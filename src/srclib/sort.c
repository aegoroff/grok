/*
* This is an open source non-commercial project. Dear PVS-Studio, please check it.
* PVS-Studio Static Code Analyzer for C, C++ and C#: http://www.viva64.com
*/
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
    const char* temp;
    int marker = start;
    const char** items = (const char**) array->elts;
    for(int i = start; i <= end; i++) {
        //array[end] is pivot
        if(apr_strnatcmp(items[i], items[end]) < 0) {
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

void sort_quicksort_strings(apr_array_header_t* array, int start, int end) {
    if(start >= end) {
        return;
    }
    int pivot = prsort_partition(array, start, end);
    sort_quicksort_strings(array, start, pivot - 1);
    sort_quicksort_strings(array, pivot + 1, end);
}

