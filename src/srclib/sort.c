/*!
 * \brief   The file contains sorting implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-21
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2020
 */

#include <apr_strings.h>
#include "sort.h"

int prsort_partition(apr_array_header_t* array, int start, int end) {
    char* temp;
    int marker = start;
    for(int i = start; i <= end; i++) {
        //array[end] is pivot
        if(apr_strnatcmp(((char**) array->elts)[i], ((char**) array->elts)[end]) < 0) {
            temp = ((char**) array->elts)[marker];
            ((char**) array->elts)[marker] = ((char**) array->elts)[i];
            ((char**) array->elts)[i] = temp;
            marker += 1;
        }
    }

    temp = ((char**) array->elts)[marker];
    ((char**) array->elts)[marker] = ((char**) array->elts)[end];
    ((char**) array->elts)[end] = temp;
    return marker;
}

void sort_quicksort_strings(apr_array_header_t* array, int start, int end) {
    if(start >= end) {
        return;
    }
    int pivot = prsort_partition(array, start, end);
    sort_quicksort_strings(array, start, pivot - 1);
    sort_quicksort_strings(array, pivot + 1, end);
}

