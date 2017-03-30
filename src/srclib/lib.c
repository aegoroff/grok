// This is an open source non-commercial project. Dear PVS-Studio, please check it.
// PVS-Studio Static Code Analyzer for C, C++ and C#: http://www.viva64.com
/*!
 * \brief   The file contains common solution library implementation
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2010-03-05
            \endverbatim
 * Copyright: (c) Alexander Egorov 2009-2017
 */

#include <stdarg.h>
#include <string.h>
#include <math.h>
#ifdef WIN32
#include <windows.h>
#else
#include <time.h>
#endif
#include "lib.h"

 /*
    lib_ - public members
    prdlib_ - private members
 */

#define BIG_FILE_FORMAT "%.2f %s (%llu %s)" // greater or equal 1 Kb
#define SMALL_FILE_FORMAT "%llu %s" // less then 1 Kb
#define SEC_FMT "%.3f sec"
#define MIN_FMT "%u min "
#define HOURS_FMT "%u hr "
#define DAYS_FMT "%u days "
#define YEARS_FMT "%u years "
#define SECONDS_PER_YEAR 31536000
#define SECONDS_PER_DAY 86400
#define SECONDS_PER_HOUR 3600
#define SECONDS_PER_MINUTE 60
#define INT64_BITS_COUNT 64

// forwards
static uint64_t prlib_ilog(uint64_t x);

static char* lib_sizes[] = {
    "bytes",
    "Kb",
    "Mb",
    "Gb",
    "Tb",
    "Pb",
    "Eb",
    "Zb",
    "Yb",
    "Bb",
    "GPb"
};

static double lib_span = 0.0;

#ifdef WIN32
static LARGE_INTEGER lib_freq = {0};
static LARGE_INTEGER lib_time1 = {0};
static LARGE_INTEGER lib_time2 = {0};

#else
static clock_t lib_c0 = 0;
static clock_t lib_c1 = 0;
#endif

uint32_t lib_get_processor_count(void) {
#ifdef WIN32
    SYSTEM_INFO sysinfo;
    GetSystemInfo(&sysinfo);
    return (uint32_t)sysinfo.dwNumberOfProcessors;
#else
    return (uint32_t)sysconf( _SC_NPROCESSORS_ONLN );
#endif 
}

void lib_print_size(uint64_t size) {
    lib_file_size_t normalized = lib_normalize_size(size);
    lib_printf(normalized.unit ? BIG_FILE_FORMAT : SMALL_FILE_FORMAT, //-V510
               normalized.value, lib_sizes[normalized.unit], size, lib_sizes[size_unit_bytes]);
}

void lib_size_to_string(uint64_t size, char* str) {
    lib_file_size_t normalized = lib_normalize_size(size);

    if(str == NULL) {
        return;
    }
    lib_sprintf(str, normalized.unit ? BIG_FILE_FORMAT : SMALL_FILE_FORMAT, //-V510
              normalized.value, lib_sizes[normalized.unit], size, lib_sizes[size_unit_bytes]);
}

uint32_t lib_htoi(const char* ptr, int size) {
    uint32_t value = 0;
    char ch;
    int count = 0;

    if(ptr == NULL || size <= 0) {
        return value;
    }

    ch = ptr[count];
    for(;;) {
        if(ch == ' ' || ch == '\t') {
            goto nextChar;
        }
        if(ch >= '0' && ch <= '9') {
            value = (value << 4) + (ch - '0');
        }
        else if(ch >= 'A' && ch <= 'F') {
            value = (value << 4) + (ch - 'A' + 10);
        }
        else if(ch >= 'a' && ch <= 'f') {
            value = (value << 4) + (ch - 'a' + 10);
        }
        else {
            return value;
        }
    nextChar:
        if(++count >= size) {
            return value;
        }
        ch = ptr[count];
    }
}

void lib_hex_str_2_byte_array(const char* str, uint8_t* bytes, size_t sz) {
    size_t i = 0;
    size_t to = MIN(sz, strlen(str) / BYTE_CHARS_SIZE);

    for(; i < to; i++) {
        bytes[i] = (uint8_t)lib_htoi(str + i * BYTE_CHARS_SIZE, BYTE_CHARS_SIZE);
    }
}

uint64_t prlib_ilog(uint64_t x) {
    uint64_t y;
    uint64_t n = INT64_BITS_COUNT;
    int c = INT64_BITS_COUNT / 2;

    do {
        y = x >> c;
        if(y != 0) {
            n -= c;
            x = y;
        }
        c >>= 1;
    }
    while(c != 0);
    n -= x >> (INT64_BITS_COUNT - 1);
    return (INT64_BITS_COUNT - 1) - (n - x);
}

lib_file_size_t lib_normalize_size(uint64_t size) {
    lib_file_size_t result = {0};
    result.unit = size == 0 ? size_unit_bytes : prlib_ilog(size) / prlib_ilog(BINARY_THOUSAND);
    if(result.unit == size_unit_bytes) {
        result.value.size_in_bytes = size;
    }
    else {
        result.value.size = size / pow(BINARY_THOUSAND, result.unit);
    }
    return result;
}

int lib_printf(__format_string const char* format, ...) {
    va_list params = NULL;
    int result;
    va_start(params, format);
#ifdef __STDC_WANT_SECURE_LIB__
    result = vfprintf_s(stdout, format, params);
#else
    result = vfprintf(stdout, format, params);
#endif
    va_end(params);
    return result;
}

int lib_fprintf(FILE* file, __format_string const char* format, ...) {
    va_list params = NULL;
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

int lib_sprintf(char* buffer, __format_string const char* format, ...) {
    va_list params = NULL;
    int result;
    va_start(params, format);
#ifdef __STDC_WANT_SECURE_LIB__
    int len = _vscprintf(format, params) + 1; // _vscprintf doesn't count terminating '\0'
    result = vsprintf_s(buffer, len, format, params);
#else
    result = vsprintf(buffer, format, params);
#endif
    va_end(params);
    return result;
}

lib_time_t lib_normalize_time(double seconds) {
    lib_time_t result = {0};

    result.total_seconds = seconds;
    result.years = seconds / SECONDS_PER_YEAR;
    result.days = ((uint64_t)seconds % SECONDS_PER_YEAR) / SECONDS_PER_DAY;
    result.hours = (((uint64_t)seconds % SECONDS_PER_YEAR) % SECONDS_PER_DAY) / SECONDS_PER_HOUR;
    result.minutes = ((uint64_t)seconds % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE;
    result.seconds = ((uint64_t)seconds % SECONDS_PER_HOUR) % SECONDS_PER_MINUTE;
    double tmp = result.seconds;
    result.seconds +=
            seconds -
            ((double)(result.years * SECONDS_PER_YEAR) + (double)(result.days * SECONDS_PER_DAY) + (double)(result.hours * SECONDS_PER_HOUR) + (double)(result.minutes * SECONDS_PER_MINUTE) + result.seconds);
    if(result.seconds > 60) {
        result.seconds = tmp; // HACK
    }
    return result;
}

void lib_time_to_string(lib_time_t time, char* str) {
    if(str == NULL) {
        return;
    }

    if(time.years) {
        lib_sprintf(str, YEARS_FMT DAYS_FMT HOURS_FMT MIN_FMT SEC_FMT, time.years, time.days, time.hours, time.minutes, time.seconds);
        return;
    }
    if(time.days) {
        lib_sprintf(str, DAYS_FMT HOURS_FMT MIN_FMT SEC_FMT, time.days, time.hours, time.minutes, time.seconds);
        return;
    }
    if(time.hours) {
        lib_sprintf(str, HOURS_FMT MIN_FMT SEC_FMT, time.hours, time.minutes, time.seconds);
        return;
    }
    if(time.minutes) {
        lib_sprintf(str, MIN_FMT SEC_FMT, time.minutes, time.seconds);
        return;
    }
    lib_sprintf(str, SEC_FMT, time.seconds);
}

void lib_new_line(void) {
    lib_printf(NEW_LINE);
}

void lib_start_timer(void) {
#ifdef WIN32
    QueryPerformanceFrequency(&lib_freq);
    QueryPerformanceCounter(&lib_time1);
#else
    lib_c0 = clock();
#endif
}

void lib_stop_timer(void) {
#ifdef WIN32
    QueryPerformanceCounter(&lib_time2);
    lib_span = (double)(lib_time2.QuadPart - lib_time1.QuadPart) / (double)lib_freq.QuadPart;
#else
    lib_c1 = clock();
    lib_span = (double)(lib_c1 - lib_c0) / (double)CLOCKS_PER_SEC;
#endif
}

lib_time_t lib_read_elapsed_time(void) {
    return lib_normalize_time(lib_span);
}

int lib_count_digits_in(double x) {
    int result = 0;
    long long n = x;
    do {
        ++result;
        n /= 10;
    }
    while(n > 0);
    return result;
}

const char* lib_get_file_name(const char* path) {
    if(path == NULL) {
        return path;
    }
    const char* filename = strrchr(path, '\\');

    if(filename == NULL) {
        filename = path;
    }
    else {
        filename++;
    }
    return filename;
}