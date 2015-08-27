void frontend_init();
void frontend_cleanup();

void on_definition(char* def);
void on_literal(char* str);
void on_grok(char* str);
void get_pattern(char* def);

char* frountend_strdup(char* str);

void on_definition_end();
