#include <stdio.h>
#include <stdlib.h>
#include  "frontend.h"
#include "apr.h"
#include "apr_general.h"
#include "apr_tables.h"
#include "apr_pools.h"
#include "apr_strings.h"
#include "apr_hash.h"

#define ARRAY_INIT_SZ           32

apr_pool_t* pool;
apr_hash_t* definition;
apr_array_header_t* composition = NULL;
char* currentDef = NULL;

void frontend_init() {
    apr_pool_create(&pool, NULL);
    definition = apr_hash_make(pool);
}

void frontend_cleanup() {
    apr_pool_destroy(pool);
}

void on_definition(char* def) {
    currentDef = def;
    composition = apr_array_make(pool, ARRAY_INIT_SZ, sizeof(const char*));
}

void on_literal(char* str) {
    *(const char**)apr_array_push(composition) = str;
}

char* frountend_strdup(char* str) {
    return apr_pstrdup(pool, str);
}

void on_definition_end() {
    int i = 1;
    char* result = NULL;
    result = ((const char**)composition->elts)[0];
    for (; i < composition->nelts; i++) {
        const char *s = ((const char**)composition->elts)[i];
        result = apr_pstrcat(pool, result, s, NULL);
    }
    apr_hash_set(definition, (const char*)currentDef, APR_HASH_KEY_STRING, result);
}