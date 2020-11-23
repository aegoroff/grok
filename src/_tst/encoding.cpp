/*!
 * \brief   The file contains unit tests
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-22
            \endverbatim
 * Copyright: (c) Alexander Egorov 2020
 */

#include <cstdio>
#include <apr_pools.h>
#include "catch.hpp"
#include "encoding.h"

const char* kUtf8 = "\xd1\x82\xd0\xb5\xd1\x81\xd1\x82"; // тест
const char* kAnsi = "\xf2\xe5\xf1\xf2";                 // тест
const wchar_t* kUnicode = L"\x0442\x0435\x0441\x0442";  // тест

TEST_CASE("enc_is_valid_utf8") {
    // Arrange

    // Act
    bool result = enc_is_valid_utf8(kAnsi);

    // Assert
    REQUIRE_FALSE(result);
}

#ifdef _MSC_VER
TEST_CASE("encoding tests") {
    // Arrange
    apr_pool_t* pool;
    apr_pool_t* method_pool;
    auto argc = 1;

    const char* const argv[] = { "1" };

    auto status = apr_app_initialize(&argc, (const char* const**)&argv, nullptr);

    if(status != APR_SUCCESS) {
        throw status;
    }
    apr_pool_create(&pool, nullptr);

    SECTION("enc_from_unicode_to_utf8") {
        // Arrange
        apr_pool_create(&method_pool, pool);

        // Act
        char* result = enc_from_unicode_to_utf8(kUnicode, method_pool);

        // Assert
        REQUIRE( result == std::string(kUtf8) );
        REQUIRE( enc_is_valid_utf8(result) );

        apr_pool_destroy(method_pool);
    }

    SECTION("enc_from_utf8_to_unicode") {
        // Arrange
        apr_pool_create(&method_pool, pool);

        // Act
        const wchar_t* result = enc_from_utf8_to_unicode(kUtf8, method_pool);

        // Assert
        REQUIRE( result == std::wstring(kUnicode) );

        apr_pool_destroy(method_pool);
    }

    apr_pool_destroy(pool);
    apr_terminate();
}
#endif

TEST_CASE("enc_detect_bom_memory") {
    SECTION("Utf8") {
        // Arrange
        const char* buffer = "\xEF\xBB\xBF\xd1\x82\xd0\xb5\xd1\x81\xd1\x82";
        size_t offset = 0;

        // Act
        bom_t result = enc_detect_bom_memory(buffer, 5, &offset);

        // Assert
        REQUIRE( result == bom_utf8 );
        REQUIRE( offset == 3 );
    }

    SECTION("Utf16le") {
        // Arrange
        const char* buffer = "\xFF\xFE\x00\x00\x00\x00\x00\xd1\x81\xd1\x82";
        size_t offset = 0;

        // Act
        bom_t result = enc_detect_bom_memory(buffer, 5, &offset);

        // Assert
        REQUIRE( result == bom_utf16le );
        REQUIRE( offset == 2 );
    }

    SECTION("Utf16be") {
        // Arrange
        const char* buffer = "\xFE\xFF\x00\x00\x00\x00\x00\xd1\x81\xd1\x82";
        size_t offset = 0;

        // Act
        bom_t result = enc_detect_bom_memory(buffer, 5, &offset);

        // Assert
        REQUIRE( result == bom_utf16be );
        REQUIRE( offset == 2 );
    }

    SECTION("Utf32be") {
        // Arrange
        const char* buffer = "\x00\x00\xFE\xFF\x00\x00\x00\xd1\x81\xd1\x82";
        size_t offset = 0;

        // Act
        bom_t result = enc_detect_bom_memory(buffer, 5, &offset);

        // Assert
        REQUIRE( result == bom_utf32be );
        REQUIRE( offset == 4 );
    }

    SECTION("No BOM") {
        // Arrange
        const char* buffer = "\xd1\x82\xd0\xb5\xd1\x81\xd1\x82";
        size_t offset = 0;

        // Act
        bom_t result = enc_detect_bom_memory(buffer, 5, &offset);

        // Assert
        REQUIRE( result == bom_unknown );
        REQUIRE( offset == 0 );
    }
}
