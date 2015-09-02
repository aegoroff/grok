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
#define COMPOSE_INIT_SZ   64

#include "../pcre/pcre2.h"
#include <apr_tables.h>
#include "lib.h"
#include "backend.h"
#include <apr_strings.h>
#include "frontend.h"
#include <apr_hash.h>


static apr_pool_t* bend_pool = NULL;
pcre2_general_context* pcre_context = NULL;

void* pcre_alloc(size_t size, void* memory_data) {
    return apr_palloc(bend_pool, size);
}

void pcre_free(void* p1, void* p2) { }

void bend_init(apr_pool_t* pool) {
    apr_pool_create(&bend_pool, pool);
    pcre_context = pcre2_general_context_create(&pcre_alloc, &pcre_free, NULL);
}

void bend_cleanup() {
    pcre2_general_context_free(pcre_context);
    apr_pool_destroy(bend_pool);
}

BOOL bend_match_re(pattern_t* pattern, const char* subject) {
    int errornumber = 0;
    size_t erroroffset = 0;

    if(pattern == NULL) {
        return FALSE;
    }

    pcre2_code* re = pcre2_compile(
        pattern->regex, /* the pattern */
        PCRE2_ZERO_TERMINATED, /* indicates pattern is zero-terminated */
        0, /* default options */
        &errornumber, /* for error number */
        &erroroffset, /* for error offset */
        NULL); /* use default compile context */

    if(re == NULL) {
        int len = 256 * sizeof(PCRE2_UCHAR);
        PCRE2_UCHAR* buffer = (PCRE2_UCHAR*)apr_pcalloc(bend_pool, len);
        pcre2_get_error_message(errornumber, buffer, len);
        lib_printf("PCRE2 compilation failed at offset %d: %s\n", (int)erroroffset, buffer);
        return FALSE;
    }
    pcre2_match_data* match_data = pcre2_match_data_create_from_pattern(re, NULL);

    int flags = PCRE2_NOTEMPTY;
    if(!strstr(subject, "^")) {
        flags |= PCRE2_NOTBOL;
    }
    if(!strstr(subject, "$")) {
        flags |= PCRE2_NOTEOL;
    }

    int rc = pcre2_match(
        re, /* the compiled pattern */
        subject, /* the subject string */
        strlen(subject), /* the length of the subject */
        0, /* start at offset 0 in the subject */
        flags,
        match_data, /* block for storing the result */
        NULL); /* use default match context */

    BOOL result = rc > 0;
    if(!result) {
        return result;
    }

    for(apr_hash_index_t* hi = apr_hash_first(NULL, pattern->properties); hi; hi = apr_hash_next(hi)) {
        const char* k;
        const char* v;

        apr_hash_this(hi, (const void**)&k, NULL, (void**)&v);
        PCRE2_SIZE len = 128 * sizeof(PCRE2_UCHAR);
        PCRE2_UCHAR* buffer = (PCRE2_UCHAR*)apr_pcalloc(bend_pool, len);
        pcre2_substring_copy_byname(match_data, k, buffer, &len);
        apr_hash_set(pattern->properties, k, APR_HASH_KEY_STRING, buffer);
    }
    return result;
}

pattern_t* bend_create_pattern(const char* macro) {
    apr_array_header_t* root_elements = fend_get_pattern(macro);

    if(root_elements == NULL) {
        return NULL;
    }

    apr_pool_t* local_pool = NULL;
    apr_pool_create(&local_pool, bend_pool);

    apr_array_header_t* stack = apr_array_make(local_pool, COMPOSE_INIT_SZ, sizeof(info_t*));
    apr_array_header_t* composition = apr_array_make(local_pool, COMPOSE_INIT_SZ, sizeof(char*));
    apr_hash_t* used_properties = apr_hash_make(bend_pool);

    for(int i = 0; i < root_elements->nelts; i++) {
        info_t* top = ((info_t**)root_elements->elts)[i];
        *(info_t**)apr_array_push(stack) = top;

        while(stack->nelts > 0) {
            info_t* current = *((info_t**)apr_array_pop(stack));
            if(current->type == part_literal) {
                // plain literal case
                *(char**)apr_array_push(composition) = current->data;
            }
            else {
                // named pattern case handling
                if(current->reference != NULL) {
                    char* reference = current->reference;
                    // duplicate properties elimnation
                    const char* result = apr_hash_get(used_properties, reference, APR_HASH_KEY_STRING);
                    if(result != NULL) {
                        reference = apr_pstrcat(local_pool, current->data, "_", reference, NULL);
                    }
                    apr_hash_set(used_properties, reference, APR_HASH_KEY_STRING, current->data);

                    // leading (?<name> immediately into composition
                    *(char**)apr_array_push(composition) = "(?<";
                    *(char**)apr_array_push(composition) = reference;
                    *(char**)apr_array_push(composition) = ">";

                    // trailing ) into stack bottom
                    info_t* trail_paren = (info_t*)apr_pcalloc(local_pool, sizeof(info_t));
                    trail_paren->type = part_literal;
                    trail_paren->data = ")";
                    *(info_t**)apr_array_push(stack) = trail_paren;
                }
                // childs in reverse order
                apr_array_header_t* childs = fend_get_pattern(current->data);
                for(int j = childs->nelts - 1; j >= 0; j--) {
                    *(info_t**)apr_array_push(stack) = ((info_t**)childs->elts)[j];
                }
            }
        }
    }
    char* regex = "";
    for(int i = 0; i < composition->nelts; i++) {
        char* part = ((char**)composition->elts)[i];
        regex = apr_pstrcat(bend_pool, regex, part, NULL);
    }
    apr_pool_destroy(local_pool);

    pattern_t* result = (pattern_t*)apr_pcalloc(bend_pool, sizeof(pattern_t));
    result->regex = regex;
    result->properties = used_properties;

    return result;
}
