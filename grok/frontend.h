/*!
 * \brief   The file contains frontend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-07-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015
 */


#include <apr_general.h>

typedef enum Part {
    PartLiteral,
    PartReference
} Part_t;

typedef struct Info {
    Part_t Type;
    char* Info;
} Info_t;

void fend_init(apr_pool_t* pool);

void fend_on_definition();
void fend_on_definition_end(char* key);

void fend_on_literal(char* str);
void fend_on_grok(char* str);
char* fend_get_pattern(char* def);

char* fend_strdup(char* str);


