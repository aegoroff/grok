// calc.cpp : Defines the entry point for the console application.
//

#include "targetver.h"

#include <stdio.h>
#include <locale.h>
#include "apr.h"
#include "grok.tab.h"
#include "frontend.h"
#include <apr_errno.h>
#include <apr_general.h>
#include "argtable2.h"

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

int yyerror(char* s) {
	CrtFprintf(stderr, "error: %s\n", s);
    return 1;
}
