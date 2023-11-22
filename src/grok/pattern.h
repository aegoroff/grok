/*!
 * \brief   The file contains patterns library compilation interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-06-14
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2023
 */

#ifndef GROK_PATTERN_H
#define GROK_PATTERN_H

#include "apr_pools.h"

#ifdef __cplusplus
extern "C" {
#endif

void patt_init(apr_pool_t *pool);

void patt_compile_pattern_file(const char *p);

/// @brief Splits path specified into directory path and file name
/// @param path full path to split
/// @param d directory path
/// @param f file name
/// @param pool poot to use for operation
void patt_split_path(const char *path, const char **dir, const char **file, apr_pool_t *pool);

#ifdef __cplusplus
}
#endif

#endif // GROK_PATTERN_H
