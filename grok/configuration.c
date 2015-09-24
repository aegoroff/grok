/*!
 * \brief   The file contains configuration module implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-09-01
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015
 */

#include <argtable2.h>
#include "targetver.h"
#include "configuration.h"

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

 /*
    conf_ - public members
    prconf_ - private members
 */

void prconf_print_copyright(void);
void prconf_print_syntax(void* argtable, void* argtableS, void* argtableF);

void conf_configure_app(configuration_ctx_t* ctx) {
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

    struct arg_file* files = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, ctx->argc + 2, OPT_F_DESCR);
    struct arg_file* filesS = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, ctx->argc + 2, OPT_F_DESCR);
    struct arg_file* filesF = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, ctx->argc + 2, OPT_F_DESCR);

    struct arg_end* end = arg_end(10);
    struct arg_end* endF = arg_end(10);
    struct arg_end* endS = arg_end(10);

    void* argtable[] = {help, stringG, fileG, macro, files, end};
    void* argtableF[] = {helpF, file, macroF, filesF, endF};
    void* argtableS[] = {helpS, string, macroS, filesS, endS};

    if(arg_nullcheck(argtable) != 0 || arg_nullcheck(argtableF) != 0 || arg_nullcheck(argtableS) != 0) {
        prconf_print_syntax(argtable, argtableS, argtableF);
        goto cleanup;
    }

    int nerrors = arg_parse(ctx->argc, ctx->argv, argtable);
    int nerrorsF = arg_parse(ctx->argc, ctx->argv, argtableF);
    int nerrorsS = arg_parse(ctx->argc, ctx->argv, argtableS);

    if(nerrors > 0 || help->count > 0) {
        prconf_print_syntax(argtable, argtableS, argtableF);
        if(help->count == 0 && ctx->argc > 1) {
            arg_print_errors(stdout, end, PROGRAM_NAME);
        }
        goto cleanup;
    }

    if(nerrorsS == 0) {
        ctx->on_string(filesS, macroS->sval[0], string->sval[0]);
    }
    else if(nerrorsF == 0) {
        ctx->on_file(filesS, macroF->sval[0], file->filename[0]);
    }
    else {
        prconf_print_syntax(argtable, argtableS, argtableF);
        arg_print_errors(stdout, endF, PROGRAM_NAME);
        arg_print_errors(stdout, endS, PROGRAM_NAME);
    }

cleanup:
    arg_freetable(argtable, sizeof(argtable) / sizeof(argtable[0]));
    arg_freetable(argtableS, sizeof(argtableS) / sizeof(argtableS[0]));
    arg_freetable(argtableF, sizeof(argtableF) / sizeof(argtableF[0]));
}

void prconf_print_copyright(void) {
    lib_printf(COPYRIGHT_FMT, APP_NAME);
}

void prconf_print_syntax(void* argtable, void* argtableS, void* argtableF) {
    prconf_print_copyright();

    lib_printf(PROG_EXE);
    arg_print_syntax(stdout, argtableS, NEW_LINE NEW_LINE);

    lib_printf(PROG_EXE);
    arg_print_syntax(stdout, argtableF, NEW_LINE NEW_LINE);

    arg_print_glossary_gnu(stdout, argtable);
}
