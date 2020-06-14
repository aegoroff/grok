/*!
 * \brief   The file contains frontend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-07-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2020
 */

#ifndef GROK_FRONTEND_H_
#define GROK_FRONTEND_H_

#include <apr_tables.h>

typedef enum part {
    part_literal,
    part_reference
} part_t;

typedef struct info {
    part_t type;
    char* data;
    char* reference;
} info_t;

typedef struct macro {
    char* name;
    char* property;
} macro_t;

void fend_init(apr_pool_t* pool);

void fend_on_definition();

void fend_on_definition_end(char* key);

void fend_on_literal(char* str);

void fend_on_grok(macro_t* str);

macro_t* fend_on_macro(char* name, char* prop);

apr_array_header_t* fend_get_pattern(const char* def);

char* fend_strdup(char* str);

#endif // GROK_FRONTEND_H_

