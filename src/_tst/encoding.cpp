/*!
 * \brief   The file contains unit tests
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-22
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2024
 */

#include <cstdio>
#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_string.hpp>
#include "apr_test_fixture.h"
#include "encoding.h"

using Catch::Matchers::Equals;

const char* kUtf8 = "\xd1\x82\xd0\xb5\xd1\x81\xd1\x82"; // тест
const char* kAnsi = "\xf2\xe5\xf1\xf2";                 // тест
const wchar_t* kUnicode = L"\x0442\x0435\x0441\x0442";  // тест

SCENARIO("utf8 encoding validation") {
    WHEN("input is UTF-8") {
        bool result = enc_is_valid_utf8(kUtf8);

        THEN("result must be true") {
            REQUIRE(result);
        }
    }

    WHEN("input is ANSI") {
        bool result = enc_is_valid_utf8(kAnsi);

        THEN("result must be false") {
            REQUIRE_FALSE(result);
        }
    }
}

TEST_CASE_METHOD(apr_test_fixture, "encoding tests") {

    SECTION("enc_from_unicode_to_utf8") {
        // Act
        char* result = enc_from_unicode_to_utf8(kUnicode, get_pool());

        // Assert
        REQUIRE_THAT(std::string(result), Equals(kUtf8));
        REQUIRE( enc_is_valid_utf8(result) );
    }

    SECTION("enc_from_utf8_to_unicode") {
        // Act
        const wchar_t* result = enc_from_utf8_to_unicode(kUtf8, get_pool());

        // Assert
        REQUIRE( result == std::wstring(kUnicode) );
    }

    SECTION("enc_from_ansi_to_utf8") {
        // Act
        const char* result = enc_from_ansi_to_utf8(kAnsi, get_pool());

        // Assert
#ifdef _MSC_VER
        REQUIRE( (GetACP() != 1251 || result == std::string(kUtf8)) );
#else
        REQUIRE( result == NULL);
#endif
    }

    SECTION("enc_from_unicode_to_ansi") {
        // Act
        const char* result = enc_from_unicode_to_ansi(kUnicode, get_pool());

        // Assert
#ifdef _MSC_VER
        REQUIRE( (GetACP() != 1251 || result == std::string(kAnsi)) );
#else
        REQUIRE( result != NULL);
#endif
    }

    SECTION("enc_from_ansi_to_unicode") {
        // Act
        const wchar_t* result = enc_from_ansi_to_unicode(kAnsi, get_pool());

        // Assert
#ifdef _MSC_VER
        REQUIRE( (GetACP() != 1251 || result == std::wstring(kUnicode)) );
#else
        REQUIRE( result == NULL);
#endif
    }
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

SCENARIO("get encoding names test") {
    GIVEN( "bom_utf8 bom" ) {
        bom_t bom = bom_utf8;

        WHEN("enc_get_encoding_name") {
            auto result = enc_get_encoding_name(bom);

            THEN("UTF-8") {
                REQUIRE_THAT(std::string(result), Equals("UTF-8"));
            }
        }
    }

    GIVEN( "bom_utf16le bom" ) {
        bom_t bom = bom_utf16le;

        WHEN("enc_get_encoding_name") {
            auto result = enc_get_encoding_name(bom);

            THEN("UTF-16 (LE)") {
                REQUIRE_THAT(std::string(result), Equals("UTF-16 (LE)"));
            }
        }
    }

    GIVEN( "bom_utf16be bom" ) {
        bom_t bom = bom_utf16be;

        WHEN("enc_get_encoding_name") {
            auto result = enc_get_encoding_name(bom);

            THEN("UTF-16 (BE)") {
                REQUIRE_THAT(std::string(result), Equals("UTF-16 (BE)"));
            }
        }
    }

    GIVEN( "bom_utf32be bom" ) {
        bom_t bom = bom_utf32be;

        WHEN("enc_get_encoding_name") {
            auto result = enc_get_encoding_name(bom);

            THEN("UTF-32 (BE)") {
                REQUIRE_THAT(std::string(result), Equals("UTF-32 (BE)"));
            }
        }
    }

    GIVEN( "bom_unknown bom" ) {
        bom_t bom = bom_unknown;

        WHEN("enc_get_encoding_name") {
            auto result = enc_get_encoding_name(bom);

            THEN("Unknown") {
                REQUIRE_THAT(std::string(result), Equals("Unknown"));
            }
        }
    }

    GIVEN( "invalid bom" ) {
        auto bom = (bom_t)-1;

        WHEN("enc_get_encoding_name") {
            auto result = enc_get_encoding_name(bom);

            THEN("nullptr") {
                REQUIRE(result == nullptr);
            }
        }
    }
}