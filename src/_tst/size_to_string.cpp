/*!
 * \brief   The file contains unit tests
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-22
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2025
 */

#include <cstdint>
#include <memory>
#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_string.hpp>
#include "lib.h"

using Catch::Matchers::Equals;

const size_t kBufferSize = 128;

SCENARIO("size to string") {
    std::unique_ptr<char[]> buffer = std::make_unique<char[]>(kBufferSize);
    WHEN("1024 value to string") {
        const uint64_t size = 1024;
        lib_size_to_string(size, buffer.get());

        THEN("exactly 1 KB result with bytes after it in parens") {
            REQUIRE_THAT(std::string(buffer.get()), Equals("1.00 Kb (1024 bytes)"));
        }
    }

    WHEN("2048 + 10 bytes to string") {
        const uint64_t size = BINARY_THOUSAND * 2 + 10;
        lib_size_to_string(size, buffer.get());

        THEN("tiny more then 2 KB result with bytes after it in parens") {
            REQUIRE_THAT(std::string(buffer.get()), Equals("2.01 Kb (2058 bytes)"));
        }
    }

    WHEN("bytes to string") {
        const uint64_t size = 20;
        lib_size_to_string(size, buffer.get());

        THEN("only bytes value output") {
            REQUIRE_THAT(std::string(buffer.get()), Equals("20 bytes"));
        }
    }

    WHEN("zero bytes to string") {
        const uint64_t size = 0;
        lib_size_to_string(size, buffer.get());

        THEN("0 bytes output") {
            REQUIRE_THAT(std::string(buffer.get()), Equals("0 bytes"));
        }
    }

    WHEN("max value to string") {
        const uint64_t size = UINT64_MAX;
        lib_size_to_string(size, buffer.get());

        THEN("16 EB output") {
            REQUIRE_THAT(std::string(buffer.get()), Equals("16.00 Eb (18446744073709551615 bytes)"));
        }
    }
}