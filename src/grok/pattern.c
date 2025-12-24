/*!
 * \brief   The file contains patterns library compilation code
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-06-14
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#include "apr_file_info.h"
#include "apr_fnmatch.h"
#include "apr_strings.h"
#include <stdio.h>

#include "generated/grok.tab.h"
#include "lib.h"
#include "pattern.h"

#include <stdbool.h>

#ifndef _MSC_VER

#include <errno.h>
#include <libgen.h>
#include <stdlib.h>

#ifndef __APPLE_CC__
#include <linux/limits.h>
#include <string.h>

#endif

#endif

apr_pool_t *patt_pool = NULL;

// Forwards

extern void yyrestart(FILE *input_file);

bool prpatt_try_compile_as_wildcard(const char *pattern);

void prpatt_run_parsing(const char *p);

// Implementation

// Lex wart implementation
int yywrap(void) { return 1; }

void patt_init(apr_pool_t *pool) { patt_pool = pool; }

void patt_compile_pattern_file(const char *p) {
    FILE *f = NULL;

#ifdef __STDC_WANT_SECURE_LIB__
    const errno_t error = fopen_s(&f, p, "r");
#else
    f = fopen(p, "r");
    int error = f == NULL;
#endif
    if (error) {
        if (!prpatt_try_compile_as_wildcard(p)) {
            perror(p);
        }
#ifdef __STDC_WANT_SECURE_LIB__
        if (f != NULL) {
            fclose(f);
        }
#endif
        return;
    }

    yyrestart(f);
    prpatt_run_parsing(p);
    fclose(f);
}

/// @brief Splits path specified into directory path and file name
/// @param path full path to split
/// @param d directory path
/// @param f file name
/// @param pool poot to use for operation
void patt_split_path(const char *path, const char **d, const char **f, apr_pool_t *pool) {
#ifdef _MSC_VER
    char *dir = (char *)apr_pcalloc(pool, sizeof(char) * MAX_PATH);
    char *filename = (char *)apr_pcalloc(pool, sizeof(char) * MAX_PATH);
    char *drive = (char *)apr_pcalloc(pool, sizeof(char) * MAX_PATH);
    char *ext = (char *)apr_pcalloc(pool, sizeof(char) * MAX_PATH);
    _splitpath_s(path, drive, MAX_PATH, // Drive
                 dir, MAX_PATH,         // Directory
                 filename, MAX_PATH,    // Filename
                 ext, MAX_PATH);        // Extension

    *d = apr_pstrcat(pool, drive, dir, NULL);
    *f = apr_pstrcat(pool, filename, ext, NULL);
#else
    char *dir = apr_pstrdup(pool, path);
    *d = dirname(dir);
#ifdef __APPLE_CC__
    *f = basename(dir);
#else
    *f = path + strnlen(dir, PATH_MAX) + 1;
#endif
#endif
}

bool prpatt_try_compile_as_wildcard(const char *pattern) {
    const char *full_dir_path;
    const char *file_pattern;
    apr_status_t status;
    apr_dir_t *d = NULL;
    apr_finfo_t info = {0};
    char *full_path = NULL; // Full path to file

    patt_split_path(pattern, &full_dir_path, &file_pattern, patt_pool);

    status = apr_dir_open(&d, full_dir_path, patt_pool);
    if (status != APR_SUCCESS) {
        return false;
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

        status = apr_filepath_merge(&full_path, full_dir_path, info.name, APR_FILEPATH_NATIVE, patt_pool);

        if (status != APR_SUCCESS) {
            continue;
        }

        patt_compile_pattern_file(full_path);
    }

    status = apr_dir_close(d);
    if (status != APR_SUCCESS) {
        return false;
    }

    return true;
}

void prpatt_run_parsing(const char *p) {
    if (yyparse()) {
        lib_printf("Parse '%s' failed\n", p);
    }
}
