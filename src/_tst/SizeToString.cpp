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
#include <cstdint>
#include "SizeToString.h"
#include "catch.hpp"
#include "lib.h"

const size_t kBufferSize = 128;

SizeToString::SizeToString() : BufferedTest(kBufferSize) {}

TEST_CASE_METHOD(SizeToString, "1KB to string", "[TSizeToString]") {
    const uint64_t size = 1024;
    lib_size_to_string(size, GetBuffer());

    REQUIRE("1.00 Kb (1024 bytes)" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(SizeToString, "2KB + 10 bytes to string", "[TSizeToString]") {
    const uint64_t size = BINARY_THOUSAND * 2 + 10;
    lib_size_to_string(size, GetBuffer());

    REQUIRE("2.01 Kb (2058 bytes)" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(SizeToString, "bytes to string", "[TSizeToString]") {
    const uint64_t size = 20;
    lib_size_to_string(size, GetBuffer());

    REQUIRE("20 bytes" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(SizeToString, "zero bytes to string", "[TSizeToString]") {
    const uint64_t size = 0;
    lib_size_to_string(size, GetBuffer());

    REQUIRE("0 bytes" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(SizeToString, "max value to string", "[TSizeToString]") {
    const uint64_t size = UINT64_MAX;
    lib_size_to_string(size, GetBuffer());

    REQUIRE("16.00 Eb (18446744073709551615 bytes)" == std::string(GetBuffer()));
}