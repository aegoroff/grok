/*!
 * \brief   The file contains application startup code
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-07-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#define PCRE2_CODE_UNIT_WIDTH 8
#define MAX_PATTERN_LEN_FROM_CMDLINE 4096
#define MAX_STRING_LEN 33554432 // 32 Mb

#ifndef _MSC_VER
#define EXIT_FAILURE 1

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

#endif

#ifdef __APPLE_CC__

#include <mach-o/dyld.h>
#include <sys/syslimits.h>

#endif

#include "apr.h"
#include "apr_file_info.h"
#include "apr_file_io.h"
#include <locale.h>

#include "backend.h"
#include "configuration.h"
#include "encoding.h"
#include "frontend.h"
#include "lib.h"
#include "pattern.h"
#include <apr_errno.h>
#include <apr_general.h>

#ifdef _MSC_VER

#include <dbg_helpers.h>

#endif

void grok_compile_lib(struct arg_file *files);

void grok_on_string(struct arg_file *pattern_files, const char *macro, const char *str, int info_mode);

void grok_on_file(struct arg_file *pattern_files, const char *macro, const char *path, int info_mode);

void grok_on_template_info(struct arg_file *pattern_files, const char *macro);

wchar_t *grok_char_to_wchar(const char *buffer, size_t len, bom_t encoding, apr_pool_t *p);

void grok_output_line(const char *str, bom_t encoding, apr_pool_t *p);

apr_status_t grok_open_file(const char *path, apr_file_t **file_handle);

apr_status_t grok_read_line(char **str, apr_size_t *len, apr_file_t *f);

const char *grok_get_executable_path(apr_pool_t *pool);

void grok_out_pattern(const char *name);
static int grok_print_property(void *data, const char *key, const char *value);

static apr_pool_t *main_pool;
static const char *grok_base_dir;

int main(int argc, const char *const argv[]) {

#ifdef _MSC_VER
#ifndef _DEBUG // only Release configuration dump generating
    SetUnhandledExceptionFilter(dbg_top_level_filter);
#endif
    setlocale(LC_ALL, ".ACP");
#elif defined(__APPLE_CC__)
    setlocale(LC_ALL, "en_US.UTF-8");
#else
    setlocale(LC_ALL, "C.UTF-8");
#endif
    setlocale(LC_NUMERIC, "C");

    const apr_status_t status = apr_app_initialize(&argc, &argv, NULL);
    if (status != APR_SUCCESS) {
        lib_printf("Couldn't initialize APR");
        return EXIT_FAILURE;
    }

    atexit(apr_terminate);

    apr_pool_create(&main_pool, NULL);
    fend_init(main_pool);

    const char *exe = grok_get_executable_path(main_pool);

    const char *exe_file_name;
    patt_split_path(exe, &grok_base_dir, &exe_file_name, main_pool);

    configuration_ctx_t *configuration = (configuration_ctx_t *)apr_pcalloc(main_pool, sizeof(configuration_ctx_t));
    configuration->argc = argc;
    configuration->argv = argv;
    configuration->on_string = &grok_on_string;
    configuration->on_file = &grok_on_file;
    configuration->on_template_info = &grok_on_template_info;

    conf_configure_app(configuration);

    apr_pool_destroy(main_pool);
    return 0;
}

void grok_compile_lib(struct arg_file *files) {
    patt_init(main_pool);
    if (files->count == 0) {
        // case when no specific patterns path set so use default
        // usually it's where executable file is located
        // but it's not true for linux
        char *patterns_path = NULL;

#ifdef _MSC_VER
        const char *patterns_library_path = grok_base_dir;
#elif defined(__APPLE_CC__)
        const char *patterns_library_path = grok_base_dir;
#else
        const char *patterns_library_path = "/usr/share/grok/patterns";
#endif

        apr_status_t status =
            apr_filepath_merge(&patterns_path, patterns_library_path, "*.patterns", APR_FILEPATH_NATIVE, main_pool);
        if (status != APR_SUCCESS) {
            return;
        }

        patt_compile_pattern_file(patterns_path);
    } else {
        for (size_t i = 0; i < files->count; i++) {
            const char *p = files->filename[i];
            patt_compile_pattern_file(p);
        }
    }
}

void grok_on_template_info(struct arg_file *pattern_files, const char *const macro) {
    grok_compile_lib(pattern_files);

    if (macro != NULL && macro[0] != '\0') {
        pattern_t *pattern = bend_create_pattern(macro, main_pool);
        if (pattern == NULL) {
            lib_printf("pattern %s not found\n", macro);
        } else {
            lib_printf("%s\n", pattern->regex);
        }
    } else {
        bend_init(main_pool);
        bend_enumerate_patterns(&grok_out_pattern);
        bend_cleanup();
    }
}

void grok_on_string(struct arg_file *pattern_files, const char *macro, const char *str, int info_mode) {
    grok_compile_lib(pattern_files);
    pattern_t *pattern = bend_create_pattern(macro, main_pool);
    apr_pool_t *p = bend_init(main_pool);

    prepared_t prepared = bend_prepare_re(pattern);
    match_result_t r = bend_match_re(pattern, str, &prepared, MAX_PATTERN_LEN_FROM_CMDLINE, p);
    bend_free_re(prepared);

    if (info_mode) {
        lib_printf("string: %s | match: %s | pattern: %s\n", str, r.matched ? "TRUE" : "FALSE", macro);
    } else if (r.matched) {
        grok_output_line(str, bom_utf8, p);
    }

    bend_cleanup();
}

void grok_on_file(struct arg_file *pattern_files, const char *macro, const char *path, int info_mode) {
    grok_compile_lib(pattern_files);
    pattern_t *pattern = bend_create_pattern(macro, main_pool);
    apr_file_t *file_handle = NULL;
    apr_status_t status = APR_SUCCESS;

    status = grok_open_file(path, &file_handle);

    if (status != APR_SUCCESS) {
        return;
    }

    bom_t encoding = bom_unknown;
    bom_t current_encoding = encoding;

    if (path != NULL) {
        // real file
        encoding = enc_detect_bom(file_handle);
    }

    if (encoding == bom_utf32be) {
        lib_printf("unsupported file encoding %s\n", enc_get_encoding_name(encoding));
        return;
    }

    apr_size_t len = 4096;
    char *buffer = (char *)apr_pcalloc(main_pool, len);
    char *allocated_buffer = buffer;

    long long lineno = 1;
    prepared_t prepared = bend_prepare_re(pattern);
    do {
        apr_pool_t *p = bend_init(main_pool);

        // it maybe shifted by bom encoder. so wind it back
        buffer = allocated_buffer;
        status = grok_read_line(&buffer, &len, file_handle);
        if (status == APR_EOF) {
            bend_cleanup();
            break;
        }

        // It may occur on realloc if line is too long
        if (buffer != allocated_buffer) {
            allocated_buffer = buffer;
        }

        if (path == NULL) {
            // stdin case. Detect encoding on each line because stdin can be
            // concatenated from several files using cat
            size_t line_offset = 0;
            encoding = enc_detect_bom_memory(buffer, BOM_MAX_LEN, &line_offset);
            buffer += line_offset;
            if (encoding != bom_unknown) {
                current_encoding = encoding;
            } else {
                encoding = current_encoding;
            }
        }

        if (encoding == bom_utf16le) {
            // read one more zero byte from file after trailing \n to avoid
            // conversion to BE
            char zero;
            apr_file_getc(&zero, file_handle);
        }

        if (encoding == bom_utf16le || encoding == bom_utf16be) {
            wchar_t *wide_buffer = grok_char_to_wchar(buffer, len, encoding, p);
            buffer = enc_from_unicode_to_utf8(wide_buffer, p);
        }

        match_result_t result = bend_match_re(pattern, buffer, &prepared, len, p);
        if (info_mode) {
            lib_printf("line: %d match: %s | pattern: %s\n", lineno++, result.matched ? "TRUE" : "FALSE", macro);
        } else if (result.matched) {
            grok_output_line(buffer, encoding, p);
        }
        // Extract meta information if applicable
        if (result.matched && info_mode && result.properties != NULL && apr_table_elts(result.properties)->nelts > 0) {
            lib_printf("\n  Meta properties found:\n");
            apr_table_do(grok_print_property, NULL, result.properties, NULL);
            lib_printf("\n\n");
        }
        memset(allocated_buffer, 0, len);
        bend_cleanup();
    } while (status == APR_SUCCESS);

    bend_free_re(prepared);

    status = apr_file_close(file_handle);
    if (status != APR_SUCCESS) {
        lib_printf("file %s closing error\n", path);
    }
}

static int grok_print_property(void *data, const char *key, const char *value) {
    lib_printf("\t%s: %s\n", key, value);
    return TRUE; /* TRUE:continue iteration. FALSE:stop iteration */
}

apr_status_t grok_read_line(char **str, apr_size_t *len, apr_file_t *f) {
    apr_size_t current_ix = 0;
    while (1) {
        char c;
        apr_status_t status = apr_file_getc(&c, f);
        if (status != APR_SUCCESS) {
            return status;
        }
        if (current_ix + 2 >= *len) {
            if (*len == MAX_STRING_LEN) {
                // Already allocated
                break;
            }
            apr_size_t new_len = 2 * (*len);
            if (new_len > MAX_STRING_LEN) {
                new_len = MAX_STRING_LEN;
            }
            char *new_buffer = (char *)apr_pcalloc(main_pool, new_len);
#ifdef __STDC_WANT_SECURE_LIB__
            const errno_t err = memcpy_s(new_buffer, new_len, *str, current_ix);
            if (err) {
                lib_fprintf(stderr, "memcpy_s() in grok_read_line failed: %i\n", err);
            }
#else
            memcpy(new_buffer, *str, current_ix);
#endif
            *str = new_buffer;
            *len = new_len;
        }

        (*str)[current_ix] = c;
        ++current_ix;

        if (c == '\n') {
            break;
        }
    }

    return APR_SUCCESS;
}

apr_status_t grok_open_file(const char *path, apr_file_t **file_handle) {
    apr_status_t status = APR_SUCCESS;
    if (path != NULL) {
        (status) = apr_file_open(file_handle, path, APR_READ | APR_FOPEN_BUFFERED, APR_FPROT_WREAD, main_pool);
    } else {
        (status) = apr_file_open_stdin(file_handle, main_pool);
    }

    if (status != APR_SUCCESS) {
        if (path == NULL) {
            lib_printf("cannot open stdin\n");
        } else {
            lib_printf("cannot open file %s\n", path);
        }
    }
    return status;
}

wchar_t *grok_char_to_wchar(const char *buffer, size_t len, bom_t encoding, apr_pool_t *p) {
    unsigned char wide_char[2];
    wchar_t wchar;
    wchar_t *wide_buffer = (wchar_t *)apr_pcalloc(p, sizeof(wchar_t) * len / 2);
    int counter = 0;

    for (int i = 0; i < len; i += 2) {
        switch (encoding) {
        case bom_utf16le: {
            wide_char[0] = buffer[i];
            wide_char[1] = buffer[i + 1];
        } break;
        default:
        case bom_utf16be: {
            wide_char[1] = buffer[i];
            wide_char[0] = buffer[i + 1];
        } break;
        }

        wchar = (uint16_t)((uint8_t)wide_char[1] << 8 | (uint8_t)wide_char[0]);
        wide_buffer[counter] = wchar;
        ++counter;
    }
    wide_buffer[counter] = L'\0';
    return wide_buffer;
}

void grok_output_line(const char *str, bom_t encoding, apr_pool_t *p) {
    const char *s = str;
#ifdef _MSC_VER
    if (encoding == bom_utf8 || enc_is_valid_utf8(str)) {
        s = enc_from_utf8_to_ansi(str, p);
    }
#endif
    lib_printf("%s", s);
}

const char *grok_get_executable_path(apr_pool_t *pool) {
    uint32_t size = 512;
    char *buf = (char *)apr_pcalloc(pool, size);
    int do_realloc = 1;
    do {
#ifdef __APPLE_CC__
        int result = _NSGetExecutablePath(buf, &size);
        do_realloc = result == -1;
        if (do_realloc) {
            // if the buffer is not large enough, and * bufsize is set to the
            //     size required.
            // size + 1 made buffer null terminated
            buf = (char *)apr_pcalloc(pool, size + 1);
        } else {
            char *real_path = realpath(buf, NULL);
            if (real_path != NULL) {
                size_t len = strnlen(real_path, PATH_MAX);
                buf = (char *)apr_pcalloc(pool, len + 1);
                memcpy(buf, real_path, len);
                free(real_path);
            }
        }
#else
#ifdef _MSC_VER
        // size - 1 made buffer null terminated
        DWORD result = GetModuleFileNameA(NULL, buf, size - 1);
        DWORD lastError = GetLastError();

        do_realloc = result == (size - 1) && (lastError == ERROR_INSUFFICIENT_BUFFER || lastError == ERROR_SUCCESS);
#else
        // size - 1 made buffer null terminated
        ssize_t result = readlink("/proc/self/exe", buf, size - 1);

        do_realloc = result >= (size - 1);
#endif
        if (do_realloc) {
            size *= 2;
            buf = (char *)apr_pcalloc(pool, size);
        }
#endif
    } while (do_realloc);
    return buf;
}

void grok_out_pattern(const char *name) { lib_printf("%s\n", name); }
