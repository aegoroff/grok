#include <apr_general.h>


typedef enum Part {
    PartLiteral,
    PartReference
} Part_t;

typedef struct Info {
    Part_t Type;
    char* Info;
} Info_t;

void frontend_init(apr_pool_t* pool);

void on_definition(char* def);
void on_literal(char* str);
void on_grok(char* str);
char* get_pattern(char* def);

char* frountend_strdup(char* str);

void on_definition_end();
