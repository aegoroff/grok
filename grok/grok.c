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
#include "grok.tab.h"
#include "frontend.h"
#include "backend.h"
#include <apr_errno.h>
#include <apr_general.h>
#include "argtable2.h"

#define OPT_F_SHORT "p"
#define OPT_F_LONG "patterns"
#define OPT_F_DESCR "one or more pattern files"

// Forwards
extern void yyrestart(FILE* input_file);
void run_parsing();

apr_pool_t* main_pool;

int main(int argc, char* argv[]) {
    errno_t error = 0;
    apr_status_t status = APR_SUCCESS;

    struct arg_str* string = arg_str0("s", "string", NULL, "string to match");
    struct arg_str* macro = arg_str0("m", "macro", NULL, "pattern macros to build regexp");
    struct arg_file* files = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, argc + 2, OPT_F_DESCR);
    struct arg_end* end = arg_end(10);
    int nerrors = 0;
    int i = 0;

    void* argtable[] = {string, macro, files, end};

    setlocale(LC_ALL, ".ACP");
    setlocale(LC_NUMERIC, "C");

    status = apr_app_initialize(&argc, &argv, NULL);
    if(status != APR_SUCCESS) {
        CrtPrintf("Couldn't initialize APR");
        return EXIT_FAILURE;
    }

    atexit(apr_terminate);

    apr_pool_create(&main_pool, NULL);
    bend_init(main_pool);
    fend_init(main_pool);

    // read from stdin
    if(argc < 2) {
        run_parsing();
        goto cleanup;
    }

    if(arg_nullcheck(argtable) != 0) {
        arg_print_syntax(stdout, argtable, NEW_LINE NEW_LINE);
        arg_print_glossary_gnu(stdout, argtable);
        goto cleanup;
    }

    nerrors = arg_parse(argc, argv, argtable);

    if(nerrors > 0) {
        arg_print_syntax(stdout, argtable, NEW_LINE NEW_LINE);
        arg_print_glossary_gnu(stdout, argtable);
        goto cleanup;
    }

    for(; i < files->count; i++) {
        FILE* f = NULL;
        const char* p = files->filename[i];
        error = fopen_s(&f, p, "r");
        if(error) {
            perror(argv[1]);
            goto cleanup;
        }
        yyrestart(f);
        run_parsing();
        fclose(f);
    }

    if(string->count > 0 && macro->count > 0) {
        const char* pattern = bend_create_pattern(macro->sval[0]);
        BOOL r = bend_match_re(pattern, string->sval[0]);
        CrtPrintf("string: %s | match: %s | pattern: %s\n", string->sval[0], r > 0 ? "TRUE" : "FALSE", macro->sval[0]);
    }

cleanup:
    bend_cleanup();
    apr_pool_destroy(main_pool);
    return 0;
}

void run_parsing() {
    if(yyparse()) {
        CrtPrintf("Parse failed\n");
    }
}