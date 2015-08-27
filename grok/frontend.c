#include <stdio.h>
#include <stdlib.h>
#include  "frontend.h"
#include "apr.h"
#include "apr_tables.h"
#include "apr_pools.h"
#include "apr_strings.h"
#include "apr_hash.h"

#define ARRAY_INIT_SZ   256

void compose(char*, Part_t);

apr_pool_t* pool;
apr_hash_t* definition;
apr_array_header_t* composition = NULL;
char* currentDef = NULL;

void frontend_init(apr_pool_t* p) {
    pool = p;
    definition = apr_hash_make(pool);
}

void on_definition(char* def) {
    currentDef = def;
    composition = apr_array_make(pool, ARRAY_INIT_SZ, sizeof(Info_t*));
}

void on_literal(char* str) {
    compose(str, PartLiteral);
}

void on_grok(char* str) {
    compose(str, PartReference);
}

char* get_pattern(char* def) {
    apr_array_header_t* parts = apr_hash_get(definition, (const char*)def, APR_HASH_KEY_STRING);

    char* result = NULL;
    result = ((Info_t**)parts->elts)[0]->Info;
    for (int i = 1; i < parts->nelts; i++) {
        Info_t* info = ((Info_t**)parts->elts)[i];
        result = apr_pstrcat(pool, result, info->Info, NULL);
    }
    return result;
}

char* frountend_strdup(char* str) {
    return apr_pstrdup(pool, str);
}

void on_definition_end() {
    apr_array_header_t* parts = apr_array_make(pool, composition->nelts, sizeof(Info_t*));
    for (int i = 0; i < composition->nelts; i++) {
        *(Info_t**)apr_array_push(parts) = ((Info_t**)composition->elts)[i];
    }
    apr_hash_set(definition, (const char*)currentDef, APR_HASH_KEY_STRING, parts);
}

void compose(char* data, Part_t type) {
    Info_t* result = (Info_t*)apr_pcalloc(pool, sizeof(Info_t));
    result->Type = type;
    result->Info = data;
    *(Info_t**)apr_array_push(composition) = result;
}