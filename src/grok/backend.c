/*!
 * \brief   The file contains backend implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-08-28
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#define PCRE2_CODE_UNIT_WIDTH 8
#define COMPOSE_INIT_SZ 64

#include "backend.h"
#include "frontend.h"
#include "lib.h"
#include "sort.h"
#include <apr_hash.h>
#include <apr_strings.h>

/*
   bend_ - public members
*/

static apr_pool_t *bend_pool = NULL;
pcre2_general_context *pcre_context = NULL;

int prbend_on_each_pattern(void *rec, const void *key, apr_ssize_t klen, const void *value);

void *pcre_alloc(size_t size, void *memory_data) { return apr_palloc(bend_pool, size); }

void pcre_free(void *p1, void *p2) {}

apr_pool_t *bend_init(apr_pool_t *pool) {
    apr_pool_create(&bend_pool, pool);
    pcre_context = pcre2_general_context_create(&pcre_alloc, &pcre_free, NULL);
    return bend_pool;
}

void bend_cleanup(void) {
    pcre2_general_context_free(pcre_context);
    apr_pool_destroy(bend_pool);
}

match_result_t bend_match_re(pattern_t *pattern, const char *subject, prepared_t *prepared, size_t buffer_sz,
                             apr_pool_t *pool) {
    match_result_t result = {0};

    if (pattern == NULL) {
        return result;
    }

    pcre2_match_data *match_data = pcre2_match_data_create_from_pattern(prepared->re, pcre_context);

    int flags = PCRE2_NOTEMPTY;

    pcre2_match_context *match_ctx = pcre2_match_context_create(pcre_context);
    int rc = pcre2_match(prepared->re,                /* the compiled pattern */
                         subject,                     /* the subject string */
                         strnlen(subject, buffer_sz), /* the length of the subject */
                         0,                           /* start at offset 0 in the subject */
                         flags, match_data,           /* block for storing the result */
                         match_ctx);

    result.matched = rc > 0;
    if (result.matched && pattern->properties != NULL && pattern->properties->nelts > 0) {
        apr_table_t *properties = apr_table_make(pool, 16);
        for (size_t i = 0; i < pattern->properties->nelts; i++) {
            const char *k = ((const char **)pattern->properties->elts)[i];

            PCRE2_SIZE buffer_size_in_chars = 0;
            PCRE2_UCHAR *buffer = NULL;
            int get_string_result = pcre2_substring_get_byname(match_data, k, &buffer, &buffer_size_in_chars);
            if (get_string_result == 0) {
                apr_table_set(properties, k, buffer);
            }
        }
        result.properties = properties;
    }

    pcre2_match_data_free(match_data);
    return result;
}

prepared_t bend_prepare_re(pattern_t *pattern) {
    int errornumber = 0;
    size_t erroroffset = 0;
    prepared_t result = {0};

    if (pattern == NULL) {
        return result;
    }
    pcre2_compile_context *compile_ctx = pcre2_compile_context_create(pcre_context);

    pcre2_code *re = pcre2_compile(pattern->regex,        /* the pattern */
                                   PCRE2_ZERO_TERMINATED, /* indicates pattern is zero-terminated */
                                   0,                     /* default options */
                                   &errornumber,          /* for error number */
                                   &erroroffset,          /* for error offset */
                                   compile_ctx);

    if (re == NULL) {
        size_t error_buff_size_in_chars = 256;
        size_t len = error_buff_size_in_chars * sizeof(PCRE2_UCHAR);
        PCRE2_UCHAR *buffer = (PCRE2_UCHAR *)apr_pcalloc(bend_pool, len);
        pcre2_get_error_message(errornumber, buffer, len);
        lib_printf("PCRE2 compilation failed at offset %d: %s\n", (int)erroroffset, buffer);
    }
    result.re = re;
    return result;
}

void bend_free_re(prepared_t prepared) { pcre2_code_free(prepared.re); }

pattern_t *bend_create_pattern(const char *macro, apr_pool_t *pool) {
    apr_array_header_t *root_elements = fend_get_pattern(macro);

    if (root_elements == NULL) {
        return NULL;
    }

    apr_pool_t *local_pool = NULL;
    apr_pool_create(&local_pool, pool);

    apr_array_header_t *stack = apr_array_make(local_pool, COMPOSE_INIT_SZ, sizeof(info_t *));
    apr_array_header_t *composition = apr_array_make(local_pool, COMPOSE_INIT_SZ, sizeof(char *));
    apr_array_header_t *properties = apr_array_make(pool, 16, sizeof(char *));
    apr_hash_t *used_properties = apr_hash_make(local_pool);

    for (size_t i = 0; i < root_elements->nelts; i++) {
        info_t *top = ((info_t **)root_elements->elts)[i];
        *(info_t **)apr_array_push(stack) = top;

        while (stack->nelts > 0) {
            info_t *current = *((info_t **)apr_array_pop(stack));
            if (current->type == part_literal) {
                // plain literal case
                *(char **)apr_array_push(composition) = current->data;
            } else {
                // named pattern case handling
                if (current->reference != NULL) {
                    char *reference = current->reference;
                    // duplicate properties elimination
                    const char *result = apr_hash_get(used_properties, reference, APR_HASH_KEY_STRING);
                    if (result != NULL) {
                        reference = apr_pstrcat(local_pool, current->data, "_", reference, NULL);
                    }
                    apr_hash_set(used_properties, reference, APR_HASH_KEY_STRING, "");

                    // leading (?<name> immediately into composition
                    *(char **)apr_array_push(composition) = "(?<";
                    *(char **)apr_array_push(composition) = reference;
                    *(char **)apr_array_push(composition) = ">";
                    *(char **)apr_array_push(properties) = reference;

                    // trailing ) into stack bottom
                    info_t *trail_paren = (info_t *)apr_pcalloc(local_pool, sizeof(info_t));
                    trail_paren->type = part_literal;
                    trail_paren->data = ")";
                    *(info_t **)apr_array_push(stack) = trail_paren;
                }
                // children in reverse order
                apr_array_header_t *childs = fend_get_pattern(current->data);
                for (int j = childs->nelts - 1; j >= 0; j--) {
                    *(info_t **)apr_array_push(stack) = ((info_t **)childs->elts)[j];
                }
            }
        }
    }
    char *regex = "";
    for (size_t i = 0; i < composition->nelts; i++) {
        char *part = ((char **)composition->elts)[i];
        regex = apr_pstrcat(pool, regex, part, NULL);
    }
    apr_pool_destroy(local_pool);

    sort_quicksort_strings(properties, 0, properties->nelts - 1);
    pattern_t *result = (pattern_t *)apr_pcalloc(pool, sizeof(pattern_t));
    result->regex = regex;
    result->properties = properties;

    return result;
}

void bend_enumerate_patterns(void (*pfn_action)(const char *)) {
    apr_hash_t *ht = fend_get_patterns();
    apr_array_header_t *list = apr_array_make(bend_pool, COMPOSE_INIT_SZ, sizeof(const char *));
    apr_hash_do(&prbend_on_each_pattern, list, ht);

    sort_quicksort_strings(list, 0, list->nelts - 1);

    for (size_t i = 0; i < list->nelts; i++) {
        const char *macro = ((const char **)list->elts)[i];
        pfn_action(macro);
    }
}

int prbend_on_each_pattern(void *rec, const void *key, apr_ssize_t klen, const void *value) {
    apr_array_header_t *list = (apr_array_header_t *)rec;
    *(const char **)apr_array_push(list) = (const char *)key;
    return 1;
}
