/*!
 * \brief   The file contains frontend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-07-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#ifndef GROK_FRONTEND_H_
#define GROK_FRONTEND_H_

#ifdef __cplusplus
extern "C" {
#endif

typedef enum part { part_literal, part_reference } part_t;

typedef struct info {
    part_t type;
    char *data;
    char *reference;
} info_t;

typedef struct macro macro_t;

extern void fend_on_definition(void);

extern void fend_on_definition_end(char *key);

extern void fend_on_literal(char *str);

extern void fend_on_grok(macro_t *str);

extern macro_t *fend_on_macro(char *name, char *prop);

extern char *fend_strdup(char *str);

#ifdef __cplusplus
}
#endif

#endif // GROK_FRONTEND_H_
