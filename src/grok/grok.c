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
#include "grok.tab.h"
#include "frontend.h"
#include "backend.h"
#include <apr_errno.h>
#include <apr_general.h>
#include "argtable2.h"
#include "configuration.h"
#include <dbg_helpers.h>

 /*
    main_ - public members
 */

// Forwards
extern void yyrestart(FILE* input_file);
void main_run_parsing();
void main_compile_lib(struct arg_file* files);
void main_on_string(struct arg_file* files, char* const macro, char* const str);
void main_on_file(struct arg_file* files, char* const macro, char* const path);

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
    bend_init(main_pool);
    fend_init(main_pool);

    configuration_ctx_t* configuration = (configuration_ctx_t*)apr_pcalloc(main_pool, sizeof(configuration_ctx_t));
    configuration->argc = argc;
    configuration->argv = argv;
    configuration->on_string = &main_on_string;
    configuration->on_file = &main_on_file;

    conf_configure_app(configuration);

    bend_cleanup();
    apr_pool_destroy(main_pool);
    return 0;
}

void main_run_parsing() {
    if(yyparse()) {
        lib_printf("Parse failed\n");
    }
}

void main_compile_lib(struct arg_file* files) {
    for(int i = 0; i < files->count; i++) {
        FILE* f = NULL;
        const char* p = files->filename[i];
        errno_t error = fopen_s(&f, p, "r");
        if(error) {
            perror(p);
            return;
        }
        yyrestart(f);
        main_run_parsing();
        fclose(f);
    }
}

void main_on_string(struct arg_file* files, char* const macro, char* const str) {
    main_compile_lib(files);
    pattern_t* pattern = bend_create_pattern(macro);
    BOOL r = bend_match_re(pattern, str);
    lib_printf("string: %s | match: %s | pattern: %s\n", str, r > 0 ? "TRUE" : "FALSE", macro);
}

void main_on_file(struct arg_file* files, char* const macro, char* const path) {
    main_compile_lib(files);
    pattern_t* pattern = bend_create_pattern(macro);
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
        status = apr_file_gets(buffer, len, file_handle);
        BOOL r = bend_match_re(pattern, buffer);
        if(status != APR_EOF) {
            lib_printf("line: %d match: %s | pattern: %s\n", lineno++, r ? "TRUE" : "FALSE", macro);
        }
        if(r) {
            lib_printf("\n");
            for(apr_hash_index_t* hi = apr_hash_first(NULL, pattern->properties); hi; hi = apr_hash_next(hi)) {
                const char* k;
                const char* v;

                apr_hash_this(hi, (const void**)&k, NULL, (void**)&v);
                lib_printf("%s: %s\n", k, v);
            }
            lib_printf("\n\n");
        }
    }
    while(status == APR_SUCCESS);

    status = apr_file_close(file_handle);
    if(status != APR_SUCCESS) {
        lib_printf("file %s closing error\n", path);
    }
}
