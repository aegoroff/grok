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

extern FILE* yyin;

#define OPT_F_SHORT "F"
#define OPT_F_LONG "query"
#define OPT_F_DESCR "one or more query files"


int main(int argc, char* argv[]) {
    errno_t error = 0;
    apr_status_t status = APR_SUCCESS;
	struct arg_file* files = arg_filen(OPT_F_SHORT, OPT_F_LONG, NULL, 1, argc + 2, OPT_F_DESCR);

	setlocale(LC_ALL, ".ACP");
	setlocale(LC_NUMERIC, "C");
  
    status = apr_app_initialize(&argc, &argv, NULL);
    if (status != APR_SUCCESS) {
        printf("Couldn't initialize APR");
        return EXIT_FAILURE;
    }

    atexit(apr_terminate);
    
    frontend_init();

    if(argc > 1) {
        error = fopen_s(&yyin, argv[1], "r");
        if(error) {
            perror(argv[1]);
            goto cleanup;
        }
    }


    if(!yyparse()) {
        printf("Parse worked\n");
    }
    else {
        printf("Parse failed\n");
    }

cleanup:
    frontend_cleanup();
    return 0;
}

int yyerror(char* s) {
    fprintf(stderr, "error: %s\n", s);
    return 1;
}
