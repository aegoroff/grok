/*!
 * \brief   The file contains application startup code
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-07-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2020
 */


#define PCRE2_CODE_UNIT_WIDTH 8

#ifndef _MSC_VER
#define EXIT_FAILURE      1

#include <errno.h>
#include <stdlib.h>

#endif

#include <locale.h>
#include "apr.h"
#include "apr_file_io.h"
#include "apr_file_info.h"

#include "lib.h"
#include "frontend.h"
#include "backend.h"
#include "encoding.h"
#include "pattern.h"
#include <apr_errno.h>
#include <apr_general.h>
#include "argtable3.h"
#include "configuration.h"
#include <dbg_helpers.h>
#include <apr_strings.h>

/*
    main_ - public members
 */

void main_compile_lib(struct arg_file* files);

void main_on_string(struct arg_file* pattern_files, const char* macro, const char* str, int info_mode);

void main_on_file(struct arg_file* pattern_files, const char* macro, const char* path, int info_mode);

wchar_t* main_char_to_wchar(const char* buffer, size_t len, bom_t encoding, apr_pool_t* p);

void main_output_line(const char* str, bom_t encoding, apr_pool_t* p);

static apr_pool_t* main_pool;

int main(int argc, const char* const argv[]) {

#ifdef _MSC_VER
#ifndef _DEBUG // only Release configuration dump generating
    SetUnhandledExceptionFilter(dbg_top_level_filter);
#endif
#endif

    setlocale(LC_ALL, ".ACP");
    setlocale(LC_NUMERIC, "C");

    const apr_status_t status = apr_app_initialize(&argc, &argv, NULL);
    if(status != APR_SUCCESS) {
        lib_printf("Couldn't initialize APR");
        return EXIT_FAILURE;
    }

    atexit(apr_terminate);

    apr_pool_create(&main_pool, NULL);
    fend_init(main_pool);

    configuration_ctx_t* configuration = (configuration_ctx_t*) apr_pcalloc(main_pool, sizeof(configuration_ctx_t));
    configuration->argc = argc;
    configuration->argv = argv;
    configuration->on_string = &main_on_string;
    configuration->on_file = &main_on_file;

    conf_configure_app(configuration);

    apr_pool_destroy(main_pool);
    return 0;
}

void main_compile_lib(struct arg_file* files) {
    patt_init(main_pool);
    if(files->count == 0) {
        patt_compile_pattern_file("*.patterns");
    } else {
        for(size_t i = 0; i < files->count; i++) {
            const char* p = files->filename[i];
            patt_compile_pattern_file(p);
        }
    }
}

void
main_on_string(struct arg_file* pattern_files, const char* const macro, const char* const str, const int info_mode) {
    main_compile_lib(pattern_files);
    pattern_t* pattern = bend_create_pattern(macro, main_pool);
    apr_pool_t* p = bend_init(main_pool);
    const BOOL r = bend_match_re(pattern, str);

    if(info_mode) {
        lib_printf("string: %s | match: %s | pattern: %s\n", str, r > 0 ? "TRUE" : "FALSE", macro);
    } else if(r) {
        main_output_line(str, bom_utf8, p);
    }

    bend_cleanup();
}

void
main_on_file(struct arg_file* pattern_files, const char* const macro, const char* const path, const int info_mode) {
    main_compile_lib(pattern_files);
    pattern_t* pattern = bend_create_pattern(macro, main_pool);
    apr_file_t* file_handle = NULL;
    apr_status_t status = APR_SUCCESS;

    if(path != NULL) {
        status = apr_file_open(&file_handle, path, APR_READ | APR_FOPEN_BUFFERED, APR_FPROT_WREAD, main_pool);
    } else {
        status = apr_file_open_stdin(&file_handle, main_pool);
    }

    if(status != APR_SUCCESS) {
        if(path == NULL) {
            lib_printf("cannot open stdin\n");
        } else {
            lib_printf("cannot open file %s\n", path);
        }
        return;
    }

    bom_t encoding = bom_unknown;
    bom_t current_encoding = encoding;

    if(path != NULL) {
        // real file
        encoding = enc_detect_bom(file_handle);
    }

    if(encoding == bom_utf32be) {
        lib_printf("unsupported file encoding %s\n", enc_get_encoding_name(encoding));
        return;
    }

    int len = 2 * 0xFFF * sizeof(char);
    char* buffer = (char*) apr_pcalloc(main_pool, len + 2 * sizeof(char));
    char* allocated_buffer = buffer;

    long long lineno = 1;
    do {
        apr_pool_t* p = bend_init(main_pool);

        // it maybe shifted by bom encoder. so wind it back
        buffer = allocated_buffer;
        status = apr_file_gets(buffer, len, file_handle);

        if(path == NULL && status != APR_EOF) {
            // stdin case. Detect encoding on each line because stdin can be concatenated from several files using cat
            size_t line_offset = 0;
            encoding = enc_detect_bom_memory(buffer, BOM_MAX_LEN, &line_offset);
            buffer += line_offset;
            if(encoding != bom_unknown) {
                current_encoding = encoding;
            } else {
                encoding = current_encoding;
            }
        }

        if(encoding == bom_utf16le && status != APR_EOF) {
            // read one more zero byte from file after trailing \n to avoid conversion to BE
            char zero;
            apr_file_getc(&zero, file_handle);
        }

        if(encoding == bom_utf16le || encoding == bom_utf16be) {
            wchar_t* wide_buffer = main_char_to_wchar(buffer, len, encoding, p);
            buffer = enc_from_unicode_to_utf8(wide_buffer, p);
        }

        const BOOL matched = bend_match_re(pattern, buffer);
        if(status != APR_EOF) {
            if(info_mode) {
                lib_printf("line: %d match: %s | pattern: %s\n", lineno++, matched ? "TRUE" : "FALSE", macro);
            } else if(matched) {
                main_output_line(buffer, encoding, p);
            }
        }

        // Extract meta information if applicable and pattern contains instructions to extract properties
        if(matched && info_mode && apr_hash_count(pattern->properties) > 0) {
            int count_not_empty_properties = 0;
            // First cycle only count not empty properties
            for(apr_hash_index_t* hi = apr_hash_first(NULL, pattern->properties); hi; hi = apr_hash_next(hi)) {
                const char* k;
                const char* v;

                apr_hash_this(hi, (const void**) &k, NULL, (void**) &v);

                if(v != NULL && strlen(v)) {
                    ++count_not_empty_properties;
                }
            }

            if(count_not_empty_properties) {
                // Second cycle - not good but without additional memory allocation
                lib_printf("\n  Meta properties found:\n");
                for(apr_hash_index_t* hi = apr_hash_first(NULL, pattern->properties); hi; hi = apr_hash_next(hi)) {
                    const char* k;
                    const char* v;

                    apr_hash_this(hi, (const void**) &k, NULL, (void**) &v);

                    if(v != NULL && strlen(v)) {
                        lib_printf("\t%s: %s\n", k, v);
                    }
                }
                lib_printf("\n\n");
            }
        }
        memset(allocated_buffer, 0, len);
        bend_cleanup();
    } while(status == APR_SUCCESS);

    status = apr_file_close(file_handle);
    if(status != APR_SUCCESS) {
        lib_printf("file %s closing error\n", path);
    }
}

wchar_t* main_char_to_wchar(const char* buffer, size_t len, bom_t encoding, apr_pool_t* p) {
    unsigned char wide_char[2];
    wchar_t wchar;
    wchar_t* wide_buffer = (wchar_t*) apr_pcalloc(p, sizeof(wchar_t) * len / 2);
    int counter = 0;

    for(int i = 0; i < len; i += 2) {
        switch(encoding) {
            case bom_utf16le: {
                wide_char[0] = buffer[i];
                wide_char[1] = buffer[i + 1];
            }
                break;
            default:
            case bom_utf16be: {
                wide_char[1] = buffer[i];
                wide_char[0] = buffer[i + 1];
            }
                break;
        }

        wchar = (uint16_t) ((uint8_t) wide_char[1] << 8 | (uint8_t) wide_char[0]);
        wide_buffer[counter] = wchar;
        ++counter;
    }
    wide_buffer[counter] = L'\0';
    return wide_buffer;
}

void main_output_line(const char* str, bom_t encoding, apr_pool_t* p) {
    const char* s = str;
#ifdef _MSC_VER
    if(encoding == bom_utf8 || enc_is_valid_utf8(str)) {
        s = enc_from_utf8_to_ansi(str, p);
    }
#endif
    lib_printf("%s", s);
}
