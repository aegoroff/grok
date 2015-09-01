/*!
 * \brief   The file contains backend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-08-28
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015
 */

#ifndef GROK_BACKEND_H_
#define GROK_BACKEND_H_

#include <apr_hash.h>

//apr_hash_t*

typedef struct pattern {
    char* regex;
    apr_hash_t* properties;
} pattern_t;

void bend_init(apr_pool_t* pool);
void bend_cleanup();

BOOL bend_match_re(pattern_t* pattern, const char* subject);
pattern_t* bend_create_pattern(const char* macro);

#endif // GROK_BACKEND_H_

