/*!
 * \brief   The file contains backend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-08-28
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2024
 */

#ifndef GROK_BACKEND_H_
#define GROK_BACKEND_H_

#include <apr_tables.h>
#include <pcre2.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pattern {
    char *regex;
    apr_array_header_t *properties;
} pattern_t;

typedef struct match_result {
    bool matched;
    apr_table_t *properties;
} match_result_t;

typedef struct prepared {
    pcre2_code *re;
} prepared_t;

apr_pool_t *bend_init(apr_pool_t *pool);

void bend_cleanup(void);

match_result_t bend_match_re(pattern_t *pattern, const char *subject, prepared_t *prepared, size_t buffer_sz,
                             apr_pool_t *pool);

prepared_t bend_prepare_re(pattern_t *pattern);

void bend_free_re(prepared_t prepared);

pattern_t *bend_create_pattern(const char *macro, apr_pool_t *pool);

void bend_enumerate_patterns(void (*pfn_action)(const char *name));

#ifdef __cplusplus
}
#endif

#endif // GROK_BACKEND_H_
