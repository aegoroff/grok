/*!
 * \brief   The file contains unit tests
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-22
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2022
 */

#include <cstdint>
#include "catch_amalgamated.hpp"
#include "lib.h"

const size_t kBufferSize = 128;

SCENARIO("size to string") {
    std::unique_ptr<char[]> buffer = std::make_unique<char[]>(kBufferSize);
    WHEN("1024 value to string") {
        const uint64_t size = 1024;
        lib_size_to_string(size, buffer.get());

        THEN("exactly 1 KB result with bytes after it in parens") {
            REQUIRE("1.00 Kb (1024 bytes)" == std::string(buffer.get()));
        }
    }

    WHEN("2048 + 10 bytes to string") {
        const uint64_t size = BINARY_THOUSAND * 2 + 10;
        lib_size_to_string(size, buffer.get());

        THEN("tiny more then 2 KB result with bytes after it in parens") {
            REQUIRE("2.01 Kb (2058 bytes)" == std::string(buffer.get()));
        }
    }

    WHEN("bytes to string") {
        const uint64_t size = 20;
        lib_size_to_string(size, buffer.get());

        THEN("only bytes value output") {
            REQUIRE("20 bytes" == std::string(buffer.get()));
        }
    }

    WHEN("zero bytes to string") {
        const uint64_t size = 0;
        lib_size_to_string(size, buffer.get());

        THEN("0 bytes output") {
            REQUIRE("0 bytes" == std::string(buffer.get()));
        }
    }

    WHEN("max value to string") {
        const uint64_t size = UINT64_MAX;
        lib_size_to_string(size, buffer.get());

        THEN("16 EB output") {
            REQUIRE("16.00 Eb (18446744073709551615 bytes)" == std::string(buffer.get()));
        }
    }
}