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

#include "types.h"
#include <stdio.h>

#ifndef _MSC_VER

#include <wchar.h>

#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifndef BYTE_CHARS_SIZE
#define BYTE_CHARS_SIZE 2 // byte representation string length
#endif

#define BINARY_THOUSAND 1024
#define FULL_TIME_FMT "%02u:%02u:%.3f"

#ifndef MIN
#define MIN(x, y) ((x) < (y) ? (x) : (y))
#endif

#ifndef MAX
#define MAX(x, y) ((x) > (y) ? (x) : (y))
#endif

#ifdef _MSC_VER
#define NEW_LINE "\n"
#else
#define NEW_LINE "\n"
#endif

#ifndef ARCH
#define ARCH "x64"
#endif

#define COPYRIGHT_FMT_TRAIL NEW_LINE "Copyright (C) 2019-2025 Alexander Egorov. All rights reserved." NEW_LINE NEW_LINE
#define COPYRIGHT_FMT NEW_LINE "%s " ARCH COPYRIGHT_FMT_TRAIL

#define ALLOCATION_FAIL_FMT "Failed to allocate %Iu bytes"
#define ALLOCATION_FAILURE_MESSAGE ALLOCATION_FAIL_FMT " in: %s:%d" NEW_LINE

typedef enum {
    size_unit_bytes = 0,
    size_unit_kbytes = 1,
    size_unit_mbytes = 2,
    size_unit_gbytes = 3,
    size_unit_tbytes = 4,
    size_unit_pbytes = 5,
    size_unit_ebytes = 6,
    size_unit_zbytes = 7,
    size_unit_ybytes = 8,
    size_unit_bbytes = 9,
    size_unit_gpbytes = 10
} size_unit_t;

typedef struct lib_file_size {
    size_unit_t unit;
    // Size in KBytes, MBytes etc. or zero if less then 1 KB
    double size;
    uint64_t size_in_bytes;
} lib_file_size_t;

typedef struct lib_time {
    uint32_t years;
    uint32_t days;
    uint32_t hours;
    uint32_t minutes;
    double seconds;
    double total_seconds;
} lib_time_t;

#ifdef __STDC_WANT_SECURE_LIB__

extern int lib_printf(__format_string const char *format, ...);

#else

extern int lib_printf(const char *format, ...);

#endif

#ifdef __STDC_WANT_SECURE_LIB__

extern int lib_fprintf(FILE *file, __format_string const char *format, ...);

#else

extern int lib_fprintf(FILE *file, const char *format, ...);

#endif

#ifdef __STDC_WANT_SECURE_LIB__

extern int lib_sprintf(char *buffer, __format_string const char *format, ...);

#else

extern int lib_sprintf(char *buffer, const char *format, ...);

#endif

#ifdef __STDC_WANT_SECURE_LIB__

int lib_wcsprintf(wchar_t *buffer, __format_string const wchar_t *format, ...);

#else

int lib_wcsprintf(wchar_t *buffer, const wchar_t *format, ...);

#endif

/**
* Prints the size of a given uint64_t value in various units.
*
* @param size The size to be printed.
*/
extern void lib_print_size(uint64_t size);

/**
 * Normalizes a size from bytes into a more human-readable format.
 *
 * This function takes a uint64_t size as input and returns a lib_file_size_t
 * structure that represents the same size in a more understandable unit.
 * For example, if the input size is 1024 (1 KB), this function would return
 * a lib_file_size_t with 'size_unit_kbytes' and a size of 1.0.
 *
 * @param size The size to be normalized.
 * @return A lib_file_size_t structure representing the normalized size.
 */
extern lib_file_size_t lib_normalize_size(uint64_t size);

/*!
 * Prints new line into stdout
 */
extern void lib_new_line(void);

/**
 * \brief converts time in seconds into structure that can be easly interpreted into appropriate form
 * \param seconds time in seconds
 * \return time in second converted into lib_time_t structure
 */
extern lib_time_t lib_normalize_time(double seconds);

extern void lib_start_timer(void);

extern void lib_stop_timer(void);

extern lib_time_t lib_read_elapsed_time(void);

/**
* Converts the size from bytes to a string.
*
* This function takes a uint64_t size as input and returns a character array
* representing the same size in human-readable format (e.g., 1024 KB, 512 MB).
*
* @param size The size to be converted.
* @param str The character array to store the converted size.
*/
extern void lib_size_to_string(uint64_t size, char *str);

/**
 * Converts time from lib_time_t structure into a string.
 *
 * This function takes a pointer to a lib_time_t structure as input and returns
 * a character array representing the same time in human-readable format
 * (e.g., 1 hour 30 minutes, 2 days 12 hours).
 *
 * @param time The time to be converted.
 * @param str The character array to store the converted time.
 */
extern void lib_time_to_string(const lib_time_t *time, char *str);

/// Converts a hexadecimal string to a byte array.
///
/// This function converts the input hexadecimal string into a byte array. It's
/// useful for processing data that is represented in hexadecimal format.
///
/// \param str The hexadecimal string to be converted.
/// \param bytes A pointer to the byte array where the result will be stored.
/// \param sz The size of the byte array.
extern void lib_hex_str_2_byte_array(const char *str, uint8_t *bytes, size_t sz);

/**
 * Converts a hexadecimal string to an unsigned 32-bit integer.
 *
 * This function takes a pointer to a null-terminated hexadecimal string and
 * the size of that string. It then converts the hexadecimal representation
 * into an unsigned 32-bit integer. The function does not perform any error
 * checking on the input values.
 *
 * \param ptr A pointer to a null-terminated hexadecimal string.
 * \param size The size of the hexadecimal string.
 * \return An unsigned 32-bit integer representing the value of the input
 *         hexadecimal string, or some default value if the function is not
 *         called with valid parameters.
 */
extern uint32_t lib_htoi(const char *ptr, int size);

/**
* Gets the number of processors available in the system.
*
* @return The number of processors.
*/
extern uint32_t lib_get_processor_count(void);

/**
 * \brief Counts the number of digits in a given double.
 *
 * This function is useful when you need to know how many decimal places
 * are present in a floating point number. It's often used for formatting
 * numbers in certain ways.
 *
 * \param x The double whose digit count should be determined.
 * \return The number of digits in the given double.
 */
extern int lib_count_digits_in(double x);

/**
 * \brief Retrieves the file name from a path.
 * 
 * This function is useful for extracting the file name from a path. It's often used
 * to display the file name when prompting users or logging actions.
 *
 * \param path The path containing the file name.
 * \return A pointer to the file name, or NULL if an error occurred.
 */
extern const char *lib_get_file_name(const char *path);

/**
 * Trims leading whitespace from a string.
 *
 * This function takes a character pointer and a separator character as input,
 * and returns the original string with leading separators removed.
 *
 * @param str The input string
 * @param seps A character array containing characters to be used as separators
 * @return The trimmed string
 */
extern char *lib_ltrim(char *str, const char *seps);

/**
 * Trims trailing whitespace from a string.
 *
 * This function takes a character pointer and a separator character as input,
 * and returns the original string with trailing separators removed.
 *
 * @param str The input string
 * @param seps A character array containing characters to be used as separators
 * @return The trimmed string
 */
extern char *lib_rtrim(char *str, const char *seps);

/**
 * Trims leading and trailing whitespace from a string.
 *
 * This function takes a character pointer and a separator character as input,
 * and returns the original string with both leading and trailing separators removed.
 *
 * @param str The input string
 * @param seps A character array containing characters to be used as separators
 * @return The trimmed string
 */
extern char *lib_trim(char *str, const char *seps);

#ifdef __cplusplus
}
#endif
#endif // GROK_LIB_H_
