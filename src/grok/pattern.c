/*!
 * \brief   The file contains patterns library compilation code
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-06-14
            \endverbatim
 * Copyright: (c) Alexander Egorov 2019-2020
 */

#include <stdio.h>
#include "apr_fnmatch.h"
#include "apr_file_info.h"
#include "apr_strings.h"

#include "lib.h"
#include "generated/grok.tab.h"
#include "pattern.h"

#ifndef _MSC_VER
typedef int BOOL;
#include <errno.h>
#include <stdlib.h>
#include <libgen.h>
#endif

apr_pool_t* patt_pool = NULL;

// Forwards
extern void yyrestart(FILE* input_file);

BOOL prpatt_try_compile_as_wildcard(const char* pattern);

void prpatt_run_parsing();


void patt_init(apr_pool_t* pool) {
    patt_pool = pool;
}

void patt_compile_pattern_file(const char* p) {
    FILE* f = NULL;

#ifdef __STDC_WANT_SECURE_LIB__
    const errno_t error = fopen_s(&f, p, "r");
#else
    f = fopen(p, "r");
    int error = f == NULL;
#endif
    if(error) {
        if(!prpatt_try_compile_as_wildcard(p)) {
            perror(p);
        }
        return;
    }

    yyrestart(f);
    prpatt_run_parsing();
    fclose(f);
}

BOOL prpatt_try_compile_as_wildcard(const char* pattern) {
    const char* full_dir_path;
    const char* file_pattern;
    apr_status_t status;
    apr_dir_t* d = NULL;
    apr_finfo_t info = {0};
    char* full_path = NULL; // Full path to file
#ifdef _MSC_VER
    char* dir = (char*) apr_pcalloc(patt_pool, sizeof(char) * MAX_PATH);
    char* filename = (char*) apr_pcalloc(patt_pool, sizeof(char) * MAX_PATH);
    char* drive = (char*) apr_pcalloc(patt_pool, sizeof(char) * MAX_PATH);
    char* ext = (char*) apr_pcalloc(patt_pool, sizeof(char) * MAX_PATH);
    _splitpath_s(pattern,
                 drive, MAX_PATH, // Drive
                 dir, MAX_PATH, // Directory
                 filename, MAX_PATH, // Filename
                 ext, MAX_PATH); // Extension

    full_dir_path = apr_pstrcat(patt_pool, drive, dir, NULL);
    file_pattern = apr_pstrcat(patt_pool, filename, ext, NULL);
#else
    char* dir = apr_pstrdup(patt_pool, pattern);
    full_dir_path = dirname(dir);
    file_pattern = pattern + strlen(dir) + 1;
#endif

    status = apr_dir_open(&d, full_dir_path, patt_pool);
    if(status != APR_SUCCESS) {
        return FALSE;
    }
    for(;;) {
        status = apr_dir_read(&info, APR_FINFO_NAME | APR_FINFO_MIN, d);
        if(APR_STATUS_IS_ENOENT(status)) { // Finish reading directory
            break;
        }

        if(info.name == NULL) { // to avoid access violation
            continue;
        }

        if(status != APR_SUCCESS || info.filetype != APR_REG) {
            continue;
        }

        if(apr_fnmatch(file_pattern, info.name, APR_FNM_CASE_BLIND) != APR_SUCCESS) {
            continue;
        }

        status = apr_filepath_merge(&full_path,
                                    full_dir_path,
                                    info.name,
                                    APR_FILEPATH_NATIVE,
                                    patt_pool);

        if(status != APR_SUCCESS) {
            continue;
        }

        patt_compile_pattern_file(full_path);
    }

    status = apr_dir_close(d);
    if(status != APR_SUCCESS) {
        return FALSE;
    }

    return TRUE;
}

void prpatt_run_parsing() {
    if(yyparse()) {
        lib_printf("Parse failed\n");
    }
}