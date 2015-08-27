// calc.cpp : Defines the entry point for the console application.
//

#define PCRE2_CODE_UNIT_WIDTH 8

#include "targetver.h"

#include <stdio.h>
#include <locale.h>
#include "apr.h"
#include "grok.tab.h"
#include "frontend.h"
#include <apr_errno.h>
#include <apr_general.h>
#include "argtable2.h"
#include "../pcre/pcre2.h"

#define OPT_F_SHORT "p"
#define OPT_F_LONG "patterns"
#define OPT_F_DESCR "one or more pattern files"


extern void yyrestart(FILE * input_file);

void Parse();

int main(int argc, char* argv[]) {
    errno_t error = 0;
    apr_status_t status = APR_SUCCESS;
	struct arg_file* files = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, argc + 2, OPT_F_DESCR);
	struct arg_end* end = arg_end(10);
	int nerrors = 0;
	int i = 0;

	void* argtable[] = { files, end };

	setlocale(LC_ALL, ".ACP");
	setlocale(LC_NUMERIC, "C");
  
    status = apr_app_initialize(&argc, &argv, NULL);
    if (status != APR_SUCCESS) {
		CrtPrintf("Couldn't initialize APR");
        return EXIT_FAILURE;
    }

    atexit(apr_terminate);
    
    frontend_init();

	// read from stdin
	if (argc < 2) {
		Parse();
		goto cleanup;
	}

	if (arg_nullcheck(argtable) != 0) {
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

	for (; i < files->count; i++) {
		FILE* f = NULL;
		char* p = files->filename[i];
		error = fopen_s(&f, p, "r");
		if (error) {
			perror(argv[1]);
			goto cleanup;
		}
		yyrestart(f);
		Parse();
		fclose(f);
	}

cleanup:
    frontend_cleanup();
    return 0;
}

void Parse()
{
	if (!yyparse()) {
		CrtPrintf("Parse worked\n");
	}
	else {
		CrtPrintf("Parse failed\n");
	}
}

BOOL match_re(char* pattern, char* subject) {
    int errornumber = 0;
    size_t erroroffset = 0;

    pcre2_code* re = pcre2_compile(
        pattern,       /* the pattern */
        PCRE2_ZERO_TERMINATED, /* indicates pattern is zero-terminated */
        0,                     /* default options */
        &errornumber,          /* for error number */
        &erroroffset,          /* for error offset */
        NULL);                 /* use default compile context */

    if (re == NULL) {
        PCRE2_UCHAR buffer[256];
        pcre2_get_error_message(errornumber, buffer, sizeof(buffer));
        printf("PCRE2 compilation failed at offset %d: %s\n", (int)erroroffset, buffer);
        return FALSE;
    }
    pcre2_match_data* match_data = pcre2_match_data_create_from_pattern(re, NULL);

    int flags = PCRE2_NOTEMPTY;
    if (!strstr(subject, "^")) {
        flags |= PCRE2_NOTBOL;
    }
    if (!strstr(subject, "$")) {
        flags |= PCRE2_NOTEOL;
    }

    int rc = pcre2_match(
        re,                   /* the compiled pattern */
        subject,              /* the subject string */
        strlen(subject),       /* the length of the subject */
        0,                    /* start at offset 0 in the subject */
        flags,
        match_data,           /* block for storing the result */
        NULL);                /* use default match context */
    return rc >= 0;
}