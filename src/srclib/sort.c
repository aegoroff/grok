/*!
 * \brief   The file contains sorting implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#include "sort.h"
#include <apr_strings.h>

int prsort_partition(apr_array_header_t *array, int start, int end) {
    const char *temp;
    int marker = start;
    const char **items = (const char **)array->elts;
    for (int i = start; i <= end; i++) {
        // array[end] is pivot point
        if (apr_strnatcmp(items[i], items[end]) < 0) {
            temp = items[marker];
            items[marker] = items[i];
            items[i] = temp;
            marker += 1;
        }
    }

    temp = items[marker];
    items[marker] = items[end];
    items[end] = temp;
    return marker;
}

void sort_quicksort_strings(apr_array_header_t *array, int start, int end) {
    if (start >= end) {
        return;
    }
    int pivot = prsort_partition(array, start, end);
    sort_quicksort_strings(array, start, pivot - 1);
    sort_quicksort_strings(array, pivot + 1, end);
}
