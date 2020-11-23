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

#include "catch.hpp"
#include "encoding.h"

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
