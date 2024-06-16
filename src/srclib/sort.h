/*!
 * \brief   The file contains sorting interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2024
 */

#ifndef GROK_SORT_H
#define GROK_SORT_H

#include <apr_tables.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Sorts an array of strings using quicksort algorithm.
 *
 * This function sorts the given array of strings in-place, using the quicksort
 * sorting algorithm. The start and end indices specify the portion of the
 * array to sort.
 *
 * @param array    The array of strings to be sorted.
 * @param start     The starting index of the subarray to sort (inclusive).
 * @param end       The ending index of the subarray to sort (exclusive).
 */
void sort_quicksort_strings(apr_array_header_t *array, int start, int end);

#ifdef __cplusplus
}
#endif

#endif // GROK_SORT_H
