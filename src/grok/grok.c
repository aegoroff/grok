// This is an open source non-commercial project. Dear PVS-Studio, please check it.
// PVS-Studio Static Code Analyzer for C, C++ and C#: http://www.viva64.com
/*!
 * \brief   The file contains compiler driver
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-07-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015
 */


#define PCRE2_CODE_UNIT_WIDTH 8

#include "targetver.h"

#include <stdio.h>
#include <locale.h>
#include "apr.h"
#include "apr_file_io.h"
#include "apr_file_info.h"
#include "apr_fnmatch.h"
#include "grok.tab.h"
#include "frontend.h"
#include "backend.h"
#include <apr_errno.h>
#include <apr_general.h>
#include "argtable2.h"
#include "configuration.h"
#include <dbg_helpers.h>
#include <apr_strings.h>

/*
    main_ - public members
 */

// Forwards
extern void yyrestart(FILE* input_file);
void main_run_parsing();
void main_compile_lib(struct arg_file* files);
void main_on_string(struct arg_file* files, char* const macro, char* const str, int grep_mode);
void main_on_file(struct arg_file* files, char* const macro, char* const path, int grep_mode);
void main_compile_pattern_file(const char* p);
BOOL main_try_compile_as_wildcard(const char* p);

static apr_pool_t* main_pool;

int main(int argc, char* argv[]) {

#ifdef _MSC_VER
#ifndef _DEBUG // only Release configuration dump generating
    SetUnhandledExceptionFilter(dbg_top_level_filter);
#endif
#endif

    setlocale(LC_ALL, ".ACP");
    setlocale(LC_NUMERIC, "C");

    apr_status_t status = apr_app_initialize(&argc, &argv, NULL);
    if(status != APR_SUCCESS) {
        lib_printf("Couldn't initialize APR");
        return EXIT_FAILURE;
    }

    atexit(apr_terminate);

    apr_pool_create(&main_pool, NULL);
    fend_init(main_pool);

    configuration_ctx_t* configuration = (configuration_ctx_t*)apr_pcalloc(main_pool, sizeof(configuration_ctx_t));
    configuration->argc = argc;
    configuration->argv = argv;
    configuration->on_string = &main_on_string;
    configuration->on_file = &main_on_file;

    conf_configure_app(configuration);

    apr_pool_destroy(main_pool);
    return 0;
}

void main_run_parsing() {
    if(yyparse()) {
        lib_printf("Parse failed\n");
    }
}

BOOL main_try_compile_as_wildcard(const char* pattern) {
    char* drive = (char*)apr_pcalloc(main_pool, sizeof(char) * MAX_PATH);
    char* dir = (char*)apr_pcalloc(main_pool, sizeof(char) * MAX_PATH);
    char* filename = (char*)apr_pcalloc(main_pool, sizeof(char) * MAX_PATH);
    char* ext = (char*)apr_pcalloc(main_pool, sizeof(char) * MAX_PATH);
    char* full_dir_path;
    char* file_pattern;
    apr_status_t status;
    apr_dir_t* d = NULL;
    apr_finfo_t info = { 0 };
    char* full_path = NULL; // Full path to file

    _splitpath_s(pattern,
                 drive, MAX_PATH, // Drive
                 dir, MAX_PATH, // Directory
                 filename, MAX_PATH, // Filename
                 ext, MAX_PATH); // Extension
            
    full_dir_path = apr_pstrcat(main_pool, drive, dir, NULL);
    file_pattern = apr_pstrcat(main_pool, filename, ext, NULL);
    status = apr_dir_open(&d, full_dir_path, main_pool);
    if (status != APR_SUCCESS) {
        return FALSE;
    }
    for (;;) {
        status = apr_dir_read(&info, APR_FINFO_NAME | APR_FINFO_MIN, d);
        if (APR_STATUS_IS_ENOENT(status)) { // Finish reading directory
            break;
        }

        if (info.name == NULL) { // to avoid access violation
            continue;
        }
        
        if (status != APR_SUCCESS || info.filetype != APR_REG) {
            continue;
        }

        if (apr_fnmatch(file_pattern, info.name, APR_FNM_CASE_BLIND) != APR_SUCCESS) {
            continue;
        }
        
        status = apr_filepath_merge(&full_path,
            full_dir_path,
            info.name,
            APR_FILEPATH_NATIVE,
            main_pool);
        
        if (status != APR_SUCCESS) {
            continue;
        }

        main_compile_pattern_file(full_path);
    }
    
    status = apr_dir_close(d);
    if (status != APR_SUCCESS) {
        return FALSE;
    }

    return TRUE;
}

void main_compile_pattern_file(const char* p) {
    FILE* f = NULL;
    const char* root;
    errno_t error = fopen_s(&f, p, "r");
    if(error) {
        if(!main_try_compile_as_wildcard(p)) {
            perror(p);
        }
        return;
    }
    yyrestart(f);
    main_run_parsing();
    fclose(f);
}

void main_compile_lib(struct arg_file* files) {
    for(size_t i = 0; i < files->count; i++) {
        const char* p = files->filename[i];
        main_compile_pattern_file(p);
    }
}

void main_on_string(struct arg_file* files, char* const macro, char* const str, int grep_mode) {
    main_compile_lib(files);
    pattern_t* pattern = bend_create_pattern(macro, main_pool);
    bend_init(main_pool);
    BOOL r = bend_match_re(pattern, str);
    lib_printf("string: %s | match: %s | pattern: %s\n", str, r > 0 ? "TRUE" : "FALSE", macro);
    bend_cleanup();
}

void main_on_file(struct arg_file* files, char* const macro, char* const path, int grep_mode) {
    main_compile_lib(files);
    pattern_t* pattern = bend_create_pattern(macro, main_pool);
    apr_file_t* file_handle = NULL;
    apr_status_t status = apr_file_open(&file_handle, path, APR_READ | APR_FOPEN_BUFFERED, APR_FPROT_WREAD, main_pool);
    if(status != APR_SUCCESS) {
        lib_printf("cannot open file %s\n", path);
        return;
    }

    int len = 0xFFF * sizeof(char);
    char* buffer = (char*)apr_pcalloc(main_pool, len);

    long long lineno = 1;
    do {
        bend_init(main_pool);
        status = apr_file_gets(buffer, len, file_handle);
        BOOL r = bend_match_re(pattern, buffer);
        if(status != APR_EOF) {
            if(grep_mode) {
                if(r) {
                    lib_printf("%s", buffer);
                }
            }
            else {
                lib_printf("line: %d match: %s | pattern: %s\n", lineno++, r ? "TRUE" : "FALSE", macro);
            }
        }
        if(r && !grep_mode) {
            lib_printf("\n");
            for(apr_hash_index_t* hi = apr_hash_first(NULL, pattern->properties); hi; hi = apr_hash_next(hi)) {
                const char* k;
                const char* v;

                apr_hash_this(hi, (const void**)&k, NULL, (void**)&v);
                lib_printf("%s: %s\n", k, v);
            }
            lib_printf("\n\n");
        }
        bend_cleanup();
    }
    while(status == APR_SUCCESS);

    status = apr_file_close(file_handle);
    if(status != APR_SUCCESS) {
        lib_printf("file %s closing error\n", path);
    }
}
