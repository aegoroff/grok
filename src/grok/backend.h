/*!
 * \brief   The file contains backend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-08-28
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2023
 */

#ifndef GROK_BACKEND_H_
#define GROK_BACKEND_H_

#include <stdbool.h>
#include <apr_hash.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pattern {
    char* regex;
    apr_hash_t* properties;
} pattern_t;

apr_pool_t* bend_init(apr_pool_t* pool);

void bend_cleanup(void);

bool bend_match_re(pattern_t* pattern, const char* subject, size_t buffer_sz);

pattern_t* bend_create_pattern(const char* macro, apr_pool_t* pool);

void bend_enumerate_patterns(void (* pfn_action)(const char* name));

#ifdef __cplusplus
}
#endif

#endif // GROK_BACKEND_H_

