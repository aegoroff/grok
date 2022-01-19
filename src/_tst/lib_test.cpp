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

#include <cstdio>
#include "catch.hpp"
#include "lib.h"

using namespace Catch::literals;

TEST_CASE("htoi") {
    SECTION("parse one symbol") {
        REQUIRE( lib_htoi("5", 1) == 5 );
    }

    SECTION("parse max byte value") {
        REQUIRE( lib_htoi("FF", 2) == 255 );
    }

    SECTION("setting zero data size") {
        REQUIRE( lib_htoi("FF", 0) == 0 );
    }

    SECTION("setting negative data size") {
        REQUIRE( lib_htoi("FF", -1) == 0 );
    }

    SECTION("parse two bytes") {
        REQUIRE( lib_htoi("FFEE", 4) == 65518 );
    }

    SECTION("trimming test") {
        REQUIRE( lib_htoi("  FFEE", 6) == 65518 );
    }

    SECTION("only whitespaces test") {
        REQUIRE( lib_htoi(" \t", 2) == 0 );
    }

    SECTION("only part of string that starts from whitespaces") {
        REQUIRE( lib_htoi("  FFEE", 4) == 255 );
    }

    SECTION("parsing only part of two bytes string") {
        REQUIRE( lib_htoi("FFFF", 2) == 255 );
    }

    SECTION("null string parsing") {
        REQUIRE( lib_htoi(nullptr, 2) == 0 );
    }

    SECTION("all incorrect string parsing") {
        REQUIRE( lib_htoi("RR", 2) == 0 );
    }

    SECTION("only part of string incorrect parsing") {
        REQUIRE( lib_htoi("FR", 2) == 15 );
    }
}

TEST_CASE("normalize size") {
    SECTION("zero bytes") {
        const uint64_t size = 0;

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_bytes);
        REQUIRE(result.value.size_in_bytes == size);
    }

    SECTION("Bytes") {
        const uint64_t size = 1023;

        auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_bytes);
        REQUIRE(result.value.size_in_bytes == size);
    }

    SECTION("KBytes on boundary") {
        const uint64_t size = 1024;

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_kbytes);
        REQUIRE(result.value.size == 1.0);
    }

    SECTION("KBytes") {
        uint64_t size = BINARY_THOUSAND * 2;

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_kbytes);
        REQUIRE(result.value.size == 2.0);
    }

    SECTION("MBytes") {
        uint64_t size = BINARY_THOUSAND * BINARY_THOUSAND * 2;

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_mbytes);
        REQUIRE(result.value.size == 2.0);
    }

    SECTION("GBytes") {
        const auto size = BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
                          static_cast<uint64_t>(4);

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_gbytes);
        REQUIRE(result.value.size == 4.0);
    }

    SECTION("TBytes") {
        const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
                          BINARY_THOUSAND * BINARY_THOUSAND * 2;

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_tbytes);
        REQUIRE(result.value.size == 2.0);
    }

    SECTION("PBytes") {
        const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
                          BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND * 2;

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_pbytes);
        REQUIRE(result.value.size == 2.0);
    }

    SECTION("EBytes") {
        const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
                          BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
                          BINARY_THOUSAND * 2;

        const auto result = lib_normalize_size(size);

        REQUIRE(result.unit == size_unit_ebytes);
        REQUIRE(result.value.size == 2.0);
    }

}

TEST_CASE("normalize time") {
    SECTION("Hours")  {
        const auto time = 7000.0;

        const auto result = lib_normalize_time(time);

        REQUIRE(result.hours == 1);
        REQUIRE(result.minutes == 56);
        REQUIRE(result.seconds == 40.00_a);
    }

    SECTION("HoursFractial")  {
        const auto time = 7000.51;

        const auto result = lib_normalize_time(time);

        REQUIRE(result.hours == 1);
        REQUIRE(result.minutes == 56);
        REQUIRE(result.seconds == 40.51_a);
    }

    SECTION("Minutes")  {
        const auto time = 200.0;

        const auto result = lib_normalize_time(time);

        REQUIRE(result.hours == 0);
        REQUIRE(result.minutes == 3);
        REQUIRE(result.seconds == 20.00_a);
    }

    SECTION("Seconds")  {
        const auto time = 50.0;

        const auto result = lib_normalize_time(time);

        REQUIRE(result.hours == 0);
        REQUIRE(result.minutes == 0);
        REQUIRE(result.seconds == 50.00_a);
    }

    SECTION("BigValue")  {
        const auto time = 500001.0;

        const auto result = lib_normalize_time(time);

        REQUIRE(result.days == 5);
        REQUIRE(result.hours == 18);
        REQUIRE(result.minutes == 53);
        REQUIRE(result.seconds == 21.00_a);
    }
}

TEST_CASE("count digits")  {
    SECTION("Zero")  {
        REQUIRE(lib_count_digits_in(0.0) == 1);
    }

    SECTION("One")  {
        REQUIRE(lib_count_digits_in(1.0) == 1);
    }

    SECTION("Ten")  {
        REQUIRE(lib_count_digits_in(10.0) == 2);
    }

    SECTION("N100")  {
        REQUIRE(lib_count_digits_in(100.0) == 3);
    }

    SECTION("N100F")  {
        REQUIRE(lib_count_digits_in(100.23423) == 3);
    }

    SECTION("N1000")  {
        REQUIRE(lib_count_digits_in(1000.0) == 4);
    }

    SECTION("N10000")  {
        REQUIRE(lib_count_digits_in(10000.0) == 5);
    }

    SECTION("N100000")  {
        REQUIRE(lib_count_digits_in(100000.0) == 6);
    }

    SECTION("N1000000")  {
        REQUIRE(lib_count_digits_in(1000000.0) == 7);
    }

    SECTION("N10000000")  {
        REQUIRE(lib_count_digits_in(10000000.0) == 8);
    }

    SECTION("N100000000")  {
        REQUIRE(lib_count_digits_in(100000000.0) == 9);
    }

    SECTION("N1000000000")  {
        REQUIRE(lib_count_digits_in(1000000000.0) == 10);
    }

    SECTION("N10000000000")  {
        REQUIRE(lib_count_digits_in(10000000000.0) == 11);
    }

    SECTION("N100000000000")  {
        REQUIRE(lib_count_digits_in(100000000000.0) == 12);
    }
}

SCENARIO("get file name from path") {

    GIVEN( "full platform specific path" ) {
#ifdef _WIN32
        const char* path = "c:\\path\\file.txt";
#else
        const char* path = "/path/file.txt";
#endif

        WHEN("lib_get_file_name") {
            THEN("return only file name with extension without dir part of path") {
                REQUIRE(lib_get_file_name(path) == std::string("file.txt"));
            }
        }
    }

    GIVEN( "only file name" ) {
        const char* path = "file.txt";

        WHEN("lib_get_file_name") {
            THEN("same result as input string") {
                REQUIRE(lib_get_file_name(path) == std::string(path));
            }
        }
    }

    GIVEN( "null path" ) {
        const char* path = nullptr;

        WHEN("lib_get_file_name") {
            THEN("return null and no crash occurred") {
                REQUIRE(lib_get_file_name(path) == NULL);
            }
        }
    }
}

SCENARIO("get processors count") {
    GIVEN( "a computer" ) {
        WHEN("lib_get_processor_count") {
            uint32_t proc_count = lib_get_processor_count();
            THEN("processors count must be positive") {
                REQUIRE(proc_count > 0);
            }
        }
    }
}
