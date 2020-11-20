/*!
 * \brief   The file contains frontend implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-07-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2020
 */


#include <stdio.h>
#include "frontend.h"
#include "apr_tables.h"
#include "apr_pools.h"
#include "apr_strings.h"

#define ARRAY_INIT_SZ   256

/*
    fend_ - public members
    prfend_ - private members
*/

// Forwards
void prfend_add_part(char* data, char* reference, part_t type);

static apr_pool_t* fend_pool = NULL;
static apr_hash_t* fend_definition = NULL;
static apr_array_header_t* fend_composition = NULL;

void fend_init(apr_pool_t* p) {
    fend_pool = p;
    fend_definition = apr_hash_make(fend_pool);
}

void fend_on_definition() {
    fend_composition = apr_array_make(fend_pool, ARRAY_INIT_SZ, sizeof(info_t*));
}

void fend_on_definition_end(char* key) {
    apr_array_header_t* parts = apr_array_make(fend_pool, fend_composition->nelts, sizeof(info_t*));
    for(size_t i = 0; i < fend_composition->nelts; i++) {
        *(info_t**) apr_array_push(parts) = ((info_t**) fend_composition->elts)[i];
    }
    apr_hash_set(fend_definition, (const char*) key, APR_HASH_KEY_STRING, parts);
}

void fend_on_literal(char* str) {
    prfend_add_part(str, NULL, part_literal);
}

void fend_on_grok(macro_t* macro) {
    prfend_add_part(macro->name, macro->property, part_reference);
}

macro_t* fend_on_macro(char* name, char* prop) {
    macro_t* result = (macro_t*) apr_pcalloc(fend_pool, sizeof(macro_t));
    result->name = name;
    result->property = prop;
    return result;
}

void prfend_add_part(char* data, char* reference, part_t type) {
    info_t* result = (info_t*) apr_pcalloc(fend_pool, sizeof(info_t));
    result->type = type;
    result->data = data;
    result->reference = reference;
    *(info_t**) apr_array_push(fend_composition) = result;
}

apr_array_header_t* fend_get_pattern(const char* def) {
    apr_array_header_t* parts = apr_hash_get(fend_definition, def, APR_HASH_KEY_STRING);
    return parts;
}

char* fend_strdup(char* str) {
    return apr_pstrdup(fend_pool, str);
}

apr_hash_t* fend_get_patterns() {
    return fend_definition;
}
