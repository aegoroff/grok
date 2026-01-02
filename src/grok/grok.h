/*!
 * \brief   The file contains lexer C interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2025-12-25
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2026
 */

#ifndef GROK_GROK_H_
#define GROK_GROK_H_

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

extern void yyrestart(FILE *input_file);

#ifdef __cplusplus
}
#endif

#endif // GROK_GROK_H_
