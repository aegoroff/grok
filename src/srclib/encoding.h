/*!
 * \brief   The file contains encoding functions interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2011-03-06
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#ifndef GROK_ENCODING_H_
#define GROK_ENCODING_H_

#ifdef __cplusplus
extern "C" {
#else
#include <stdbool.h>
#endif

#ifdef __linux__
#include <stddef.h>
#endif

#include "apr_file_io.h"
#include "apr_pools.h"

typedef enum { bom_unknown = 0, bom_utf8 = 1, bom_utf16le = 2, bom_utf16be = 3, bom_utf32be = 4 } bom_t;

#define BOM_MAX_LEN 5

#ifndef _MSC_VER

#ifndef _UINT
#define _UINT
typedef unsigned int UINT;
#endif
#endif

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
char *enc_from_utf8_to_ansi(const char *from, apr_pool_t *pool);

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
char *enc_from_ansi_to_utf8(const char *from, apr_pool_t *pool);

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
wchar_t *enc_from_ansi_to_unicode(const char *from, apr_pool_t *pool);

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
wchar_t *enc_from_utf8_to_unicode(const char *from, apr_pool_t *pool);

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
char *enc_from_unicode_to_ansi(const wchar_t *from, apr_pool_t *pool);

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
char *enc_from_unicode_to_utf8(const wchar_t *from, apr_pool_t *pool);

/**
 * Checks if the given string is a valid UTF-8 encoded string.
 *
 * This function checks if the given string is properly encoded in UTF-8.
 * It does not perform any decoding or conversion; it simply checks
 * whether the string can be decoded as UTF-8 without errors.
 *
 * @param str The input string to check for validity.
 * @return true if the string is valid UTF-8, false otherwise.
 */
bool enc_is_valid_utf8(const char *str);

/**
 * Detects the byte order mark (BOM) in a file.
 *
 * This function detects the presence and type of BOM at the beginning
 * of an APR file. If no BOM is detected, it returns `bom_unknown`.
 *
 * @param f The APR file to check for a BOM.
 * @return The type of BOM found, or `bom_unknown` if none was found.
 */
bom_t enc_detect_bom(apr_file_t *f);

/**
 * Detects the byte order mark (BOM) in a memory buffer.
 *
 * This function detects the presence and type of BOM at the specified
 * offset within the given buffer. If no BOM is detected, it returns
 * `bom_unknown`.
 *
 * @param buffer The buffer to check for a BOM.
 * @param len The length of the buffer.
 * @param offset The starting position in the buffer where the detection should start.
 * @return The type of BOM found, or `bom_unknown` if none was found.
 */
bom_t enc_detect_bom_memory(const char *buffer, size_t len, size_t *offset);

/**
 * Returns the name of the encoding corresponding to a given byte order mark (BOM).
 *
 * @param bom The type of BOM to get the corresponding encoding name for.
 * @return A string representing the name of the encoding.
 */
const char *enc_get_encoding_name(bom_t bom);

#ifdef _MSC_VER

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
char *enc_decode_utf8_ansi(const char *from, UINT from_code_page, UINT to_code_page, apr_pool_t *pool);

#endif

/*!
 * IMPORTANT: Memory allocated for result must be freed up by caller
 */
wchar_t *enc_from_code_page_to_unicode(const char *from, UINT code_page, apr_pool_t *pool);

#ifdef __cplusplus
}
#endif

#endif // GROK_ENCODING_H_
