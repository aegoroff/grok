/*!
 * \brief   The file contains frontend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2025-12-24
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2026
 */

#ifndef GROK_FRONTEND_H_
#define GROK_FRONTEND_H_

#include <stdio.h>
#include <stdarg.h>

/* External lexer state for location tracking */
extern int yycolumn;

#ifdef __cplusplus
extern "C" {
#endif

typedef struct macro {
    char *name;
    char *property;
} macro_t;

extern void fend_on_definition(void);

extern void fend_on_definition_end(char *key);

extern void fend_on_literal(char *str);

extern void fend_on_grok(macro_t *str);

extern macro_t *fend_on_macro(char *name, char *prop);

extern char *fend_strdup(char *str);

extern void fend_print_error(int first_line, int first_column, int last_line, int last_column, const char *message);

#ifdef __cplusplus
}
#endif

#endif // GROK_FRONTEND_H_
