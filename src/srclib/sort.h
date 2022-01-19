/*
* This is an open source non-commercial project. Dear PVS-Studio, please check it.
* PVS-Studio Static Code Analyzer for C, C++ and C#: http://www.viva64.com
*/
/*!
 * \brief   The file contains sorting interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2022
 */

#ifndef GROK_SORT_H
#define GROK_SORT_H

#include <apr_tables.h>

#ifdef __cplusplus
extern "C" {
#endif

void sort_quicksort_strings(apr_array_header_t* array, int start, int end);

#ifdef __cplusplus
}
#endif

#endif //GROK_SORT_H
