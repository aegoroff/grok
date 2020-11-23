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
#include <cstring>
#include <cstdint>
#include "catch.hpp"
#include "lib.h"

const size_t kBufferSize = 128;

TEST_CASE("size to string") {
    std::unique_ptr<char> buffer = std::unique_ptr<char>(new char[kBufferSize]);
    memset(buffer.get(), 0, kBufferSize);

    SECTION("1KB boundary to string") {
        const uint64_t size = 1024;
        lib_size_to_string(size, buffer.get());

        REQUIRE("1.00 Kb (1024 bytes)" == std::string(buffer.get()));
    }

    SECTION("2KB + 10 bytes to string") {
        const uint64_t size = BINARY_THOUSAND * 2 + 10;
        lib_size_to_string(size, buffer.get());

        REQUIRE("2.01 Kb (2058 bytes)" == std::string(buffer.get()));
    }

    SECTION("bytes to string") {
        const uint64_t size = 20;
        lib_size_to_string(size, buffer.get());

        REQUIRE("20 bytes" == std::string(buffer.get()));
    }

    SECTION("zero bytes to string") {
        const uint64_t size = 0;
        lib_size_to_string(size, buffer.get());

        REQUIRE("0 bytes" == std::string(buffer.get()));
    }

    SECTION("max value to string") {
        const uint64_t size = UINT64_MAX;
        lib_size_to_string(size, buffer.get());

        REQUIRE("16.00 Eb (18446744073709551615 bytes)" == std::string(buffer.get()));
    }
}