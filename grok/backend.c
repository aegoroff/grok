/*!
 * \brief   The file contains backend implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-08-28
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015
 */

#define PCRE2_CODE_UNIT_WIDTH 8

#include "../pcre/pcre2.h"
#include <apr_tables.h>
#include "lib.h"
#include "backend.h"
#include <apr_strings.h>
#include "frontend.h"


apr_pool_t* bend_pool = NULL;
pcre2_general_context* pcre_context = NULL;

void* pcre_alloc(size_t size, void* memory_data) {
    return apr_palloc(bend_pool, size);
}

void  pcre_free(void * p1, void * p2) {
    
}

void bend_init(apr_pool_t* pool) {
    apr_pool_create(&bend_pool, pool);
    pcre_context = pcre2_general_context_create(&pcre_alloc, &pcre_free, NULL);
}

void bend_cleanup() {
    pcre2_general_context_free(pcre_context);
    apr_pool_destroy(bend_pool);
}

BOOL bend_match_re(char* pattern, char* subject) {
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
        CrtPrintf("PCRE2 compilation failed at offset %d: %s\n", (int)erroroffset, buffer);
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

char* bend_create_pattern(const char* macro) {
    apr_array_header_t* parts = fend_get_pattern(macro);
    char* result = "";
    for (int i = 0; i < parts->nelts; i++) {
        Info_t* info = ((Info_t**)parts->elts)[i];
        result = apr_pstrcat(bend_pool, result, info->Info, NULL);
    }
    return result;
}