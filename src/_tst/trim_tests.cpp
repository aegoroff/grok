/*!
 * \brief   The file contains unit tests
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-23
            \endverbatim
 * Copyright: (c) Alexander Egorov 2020
 */

s#include <cstring>
#include "catch.hpp"
#include "lib.h"

const char* kSeps = "'\"";

class trim_test_fixture {
private:
    std::vector<char> buffer_;
public:
    trim_test_fixture() = default;

protected:
    void arrange(const char* input) {
        auto const dst_sz = strlen(input);
        buffer_ = std::vector<char>(dst_sz + 1);
        buffer_.insert(buffer_.begin(), input, input + dst_sz);
    }

    char* get_buffer() { return buffer_.data(); }
};

TEST_CASE_METHOD(trim_test_fixture, "trim") {
    SECTION("null string trimming") {
        REQUIRE(lib_trim(nullptr, "'\"") == NULL);
    }

    SECTION("string without separators") {
        arrange("test");

        // Act
        char* result = lib_trim(get_buffer(), kSeps);

        // Assert
        REQUIRE(result == std::string("test"));
    }

    SECTION("apos both ends") {
        arrange("'test'");

        // Act
        char* result = lib_trim(get_buffer(), kSeps);

        // Assert
        REQUIRE(result == std::string("test"));
    }

    SECTION("apos from begin only") {
        arrange("'test");

        // Act
        char* result = lib_trim(get_buffer(), kSeps);

        // Assert
        REQUIRE(result == std::string("test"));
    }

    SECTION("apos on end only") {
        arrange("test'");

        // Act
        char* result = lib_trim(get_buffer(), kSeps);

        // Assert
        REQUIRE(result == std::string("test"));
    }

    SECTION("quotes both ends") {
        arrange("\"test\"");

        // Act
        char* result = lib_trim(get_buffer(), kSeps);

        // Assert
        REQUIRE(result == std::string("test"));
    }

    SECTION("only whitespaces string") {
        arrange("   ");

        REQUIRE(lib_trim(get_buffer(), nullptr) == std::string(""));
    }
}