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

#define OPT_F_SHORT "p"
#define OPT_F_LONG "patterns"
#define OPT_F_DESCR "one or more pattern files"

#define OPT_HELP_SHORT "h"
#define OPT_HELP_LONG "help"
#define OPT_HELP_DESCR "print this help and exit"

#define OPT_MACRO_SHORT "m"
#define OPT_MACRO_LONG "macro"
#define OPT_MACRO_DESCR "pattern macros to build regexp"

#define OPT_STR_SHORT "s"
#define OPT_STR_LONG "string"
#define OPT_STR_DESCR "string to match"

#define OPT_FILE_SHORT "f"
#define OPT_FILE_LONG "file"
#define OPT_FILE_DESCR "full path to file to read data from"

// Forwards
extern void yyrestart(FILE* input_file);
void run_parsing();
void print_copyright();
void print_syntax(void* argtable, void* argtableS, void* argtableF);
void compile_lib(struct arg_file* files);

apr_pool_t* main_pool;

int main(int argc, char* argv[]) {
    errno_t error = 0;
    apr_status_t status = APR_SUCCESS;

    struct arg_lit* help = arg_lit0(OPT_HELP_SHORT, OPT_HELP_LONG, OPT_HELP_DESCR);
    struct arg_lit* helpF = arg_lit0(OPT_HELP_SHORT, OPT_HELP_LONG, OPT_HELP_DESCR);
    struct arg_lit* helpS = arg_lit0(OPT_HELP_SHORT, OPT_HELP_LONG, OPT_HELP_DESCR);
    
    struct arg_str* string = arg_str1(OPT_STR_SHORT, OPT_STR_LONG, NULL, OPT_STR_DESCR);
    struct arg_str* stringG = arg_str0(OPT_STR_SHORT, OPT_STR_LONG, NULL, OPT_STR_DESCR);
    struct arg_file* file = arg_file1(OPT_FILE_SHORT, OPT_FILE_LONG, NULL, OPT_FILE_DESCR);
    struct arg_file* fileG = arg_file0(OPT_FILE_SHORT, OPT_FILE_LONG, NULL, OPT_FILE_DESCR);

    struct arg_str* macro = arg_str1(OPT_MACRO_SHORT, OPT_MACRO_LONG, NULL, OPT_MACRO_DESCR);
    struct arg_str* macroS = arg_str1(OPT_MACRO_SHORT, OPT_MACRO_LONG, NULL, OPT_MACRO_DESCR);
    struct arg_str* macroF = arg_str1(OPT_MACRO_SHORT, OPT_MACRO_LONG, NULL, OPT_MACRO_DESCR);
    
    struct arg_file* files = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, argc + 2, OPT_F_DESCR);
    struct arg_file* filesS = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, argc + 2, OPT_F_DESCR);
    struct arg_file* filesF = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, argc + 2, OPT_F_DESCR);
    
    struct arg_end* end = arg_end(10);
    struct arg_end* endF = arg_end(10);
    struct arg_end* endS = arg_end(10);

    void* argtable[] = { help, stringG, fileG, macro, files, end };
    void* argtableF[] = { helpF, file, macroF, filesF, endF };
    void* argtableS[] = { helpS, string, macroS, filesS, endS };

    setlocale(LC_ALL, ".ACP");
    setlocale(LC_NUMERIC, "C");

    status = apr_app_initialize(&argc, &argv, NULL);
    if(status != APR_SUCCESS) {
        lib_printf("Couldn't initialize APR");
        return EXIT_FAILURE;
    }

    atexit(apr_terminate);

    apr_pool_create(&main_pool, NULL);
    bend_init(main_pool);
    fend_init(main_pool);
    
    if(arg_nullcheck(argtable) != 0 || arg_nullcheck(argtableF) != 0 || arg_nullcheck(argtableS) != 0) {
        print_syntax(argtable, argtableS, argtableF);
        goto cleanup;
    }

    int nerrors = arg_parse(argc, argv, argtable);
    int nerrorsF = arg_parse(argc, argv, argtableF);
    int nerrorsS = arg_parse(argc, argv, argtableS);

    if(nerrors > 0 || help->count > 0) {
        print_syntax(argtable, argtableS, argtableF);
        if (help->count == 0 && argc > 1) {
            arg_print_errors(stdout, end, PROGRAM_NAME);
        }
        goto cleanup;
    }

    if(nerrorsS == 0) {
        compile_lib(filesS);
        pattern_t* pattern = bend_create_pattern(macroS->sval[0]);
        BOOL r = bend_match_re(pattern, string->sval[0]);
        lib_printf("string: %s | match: %s | pattern: %s\n", string->sval[0], r > 0 ? "TRUE" : "FALSE", macroS->sval[0]);
    } 
    else if(nerrorsF == 0) {
        compile_lib(filesF);
        pattern_t* pattern = bend_create_pattern(macroF->sval[0]);
        apr_file_t* file_handle = NULL;
        status = apr_file_open(&file_handle, file->filename[0], APR_READ | APR_FOPEN_BUFFERED, APR_FPROT_WREAD, main_pool);

        int len = 0xFFF * sizeof(char);
        char* buffer = (char*)apr_pcalloc(main_pool, len);

        status = apr_file_gets(buffer, len, file_handle);

        status = apr_file_close(file_handle);
        BOOL r = bend_match_re(pattern, buffer);
        lib_printf("file: %s | match: %s | pattern: %s\n", file->filename[0], r ? "TRUE" : "FALSE", macroF->sval[0]);
        if(r) {
            lib_printf("\n\n");
            for (apr_hash_index_t* hi = apr_hash_first(NULL, pattern->properties); hi; hi = apr_hash_next(hi)) {
                const char *k;
                const char *v;

                apr_hash_this(hi, (const void**)&k, NULL, (void**)&v);
                lib_printf("%s: %s\n", k, v);
            }
        }
    }
    else {
        print_syntax(argtable, argtableS, argtableF);
        arg_print_errors(stdout, endF, PROGRAM_NAME);
        arg_print_errors(stdout, endS, PROGRAM_NAME);
    }

cleanup:
    bend_cleanup();
    arg_freetable(argtable, sizeof(argtable) / sizeof(argtable[0]));
    arg_freetable(argtableS, sizeof(argtableS) / sizeof(argtableS[0]));
    arg_freetable(argtableF, sizeof(argtableF) / sizeof(argtableF[0]));
    apr_pool_destroy(main_pool);
    return 0;
}

void run_parsing() {
    if(yyparse()) {
        lib_printf("Parse failed\n");
    }
}

void print_copyright(void) {
    lib_printf(COPYRIGHT_FMT, APP_NAME);
}

void print_syntax(void* argtable, void* argtableS, void* argtableF) {
    print_copyright();

    lib_printf(PROG_EXE);
    arg_print_syntax(stdout, argtableS, NEW_LINE NEW_LINE);

    lib_printf(PROG_EXE);
    arg_print_syntax(stdout, argtableF, NEW_LINE NEW_LINE);
    
    arg_print_glossary_gnu(stdout, argtable);
}

void compile_lib(struct arg_file* files) {
    for (int i = 0; i < files->count; i++) {
        FILE* f = NULL;
        const char* p = files->filename[i];
        errno_t error = fopen_s(&f, p, "r");
        if (error) {
            perror(p);
            return;
        }
        yyrestart(f);
        run_parsing();
        fclose(f);
    }
}