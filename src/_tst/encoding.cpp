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
#include "apr_test_fixture.h"

const char* kUtf8 = "\xd1\x82\xd0\xb5\xd1\x81\xd1\x82"; // тест
const char* kAnsi = "\xf2\xe5\xf1\xf2";                 // тест
const wchar_t* kUnicode = L"\x0442\x0435\x0441\x0442";  // тест

TEST_CASE("enc_is_valid_utf8") {
    SECTION("Success") {
        // Arrange

        // Act
        bool result = enc_is_valid_utf8(kUtf8);

        // Assert
        REQUIRE(result);
    }

    SECTION("Fail") {
        // Arrange

        // Act
        bool result = enc_is_valid_utf8(kAnsi);

        // Assert
        REQUIRE_FALSE(result);
    }
}

TEST_CASE_METHOD(apr_test_fixture, "encoding tests") {
    // Arrange
    apr_pool_t* method_pool;
    apr_pool_create(&method_pool, get_pool());

    SECTION("enc_from_unicode_to_utf8") {
        // Act
        char* result = enc_from_unicode_to_utf8(kUnicode, method_pool);

        // Assert
#ifdef _MSC_VER
        REQUIRE( result == std::string(kUtf8) );
        REQUIRE( enc_is_valid_utf8(result) );
#endif
    }

    SECTION("enc_from_utf8_to_unicode") {
        // Arrange
        apr_pool_create(&method_pool, get_pool());

        // Act
        const wchar_t* result = enc_from_utf8_to_unicode(kUtf8, method_pool);

        // Assert
#ifdef _MSC_VER
        REQUIRE( result == std::wstring(kUnicode) );
#endif
    }

    SECTION("enc_from_ansi_to_utf8") {
        // Act
        const char* result = enc_from_ansi_to_utf8(kAnsi, method_pool);

        // Assert
#ifdef _MSC_VER
        REQUIRE( result == std::string(kUtf8) );
#endif
    }

    SECTION("enc_from_unicode_to_ansi") {
        // Act
        const char* result = enc_from_unicode_to_ansi(kUnicode, method_pool);

        // Assert
#ifdef _MSC_VER
        REQUIRE( result == std::string(kAnsi) );
#endif
    }

    SECTION("enc_from_ansi_to_unicode") {
        // Act
        const wchar_t* result = enc_from_ansi_to_unicode(kAnsi, method_pool);

        // Assert
#ifdef _MSC_VER
        REQUIRE( result == std::wstring(kUnicode) );
#endif
    }

    apr_pool_destroy(method_pool);
}

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
