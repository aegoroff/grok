/*!
 * \brief   The file contains common solution library interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2010-03-05
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#ifndef GROK_LIB_H_
#define GROK_LIB_H_

#include <stdio.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __STDC_WANT_SECURE_LIB__

extern int lib_fprintf(FILE *file, __format_string const char *format, ...);

#else

extern int lib_fprintf(FILE *file, const char *format, ...);

#endif

#ifdef __cplusplus
}
#endif
#endif // GROK_LIB_H_
