/*!
 * \brief   The file contains common solution library implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2010-03-05
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2026
 */

#include <string.h>

#ifdef _MSC_VER

#include <Windows.h>

#else

#ifdef __APPLE_CC__

#include <zconf.h>

#else

#endif
#endif

#include "lib.h"

#ifdef _MSC_VER

int lib_fprintf(FILE *file, __format_string const char *format, ...) {
#else

int lib_fprintf(FILE *file, const char *format, ...) {
#endif
    va_list params;
    int result;
    va_start(params, format);
#ifdef __STDC_WANT_SECURE_LIB__
    result = vfprintf_s(file, format, params);
#else
    result = vfprintf(file, format, params);
#endif
    va_end(params);
    return result;
}
