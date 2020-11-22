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
#include "catch.hpp"
#include "lib.h"

using namespace Catch::literals;

TEST_CASE("htoi / parse one symbol") {
    REQUIRE( lib_htoi("5", 1) == 5 );
}

TEST_CASE("htoi / parse max byte value") {
    REQUIRE( lib_htoi("FF", 2) == 255 );
}

TEST_CASE("htoi / setting zero data size") {
    REQUIRE( lib_htoi("FF", 0) == 0 );
}

TEST_CASE("htoi / setting negative data size") {
    REQUIRE( lib_htoi("FF", -1) == 0 );
}

TEST_CASE("htoi / parse two bytes") {
    REQUIRE( lib_htoi("FFEE", 4) == 65518 );
}

TEST_CASE("htoi / trimming test") {
    REQUIRE( lib_htoi("  FFEE", 6) == 65518 );
}

TEST_CASE("htoi / only whitespaces test") {
    REQUIRE( lib_htoi(" \t", 2) == 0 );
}

TEST_CASE("htoi / only part of string that starts from whitespaces") {
    REQUIRE( lib_htoi("  FFEE", 4) == 255 );
}

TEST_CASE("htoi / parsing only part of two bytes string") {
    REQUIRE( lib_htoi("FFFF", 2) == 255 );
}

TEST_CASE("htoi / null string parsing") {
    REQUIRE( lib_htoi(nullptr, 2) == 0 );
}

TEST_CASE("htoi / all incorrect string parsing") {
    REQUIRE( lib_htoi("RR", 2) == 0 );
}

TEST_CASE("htoi / only part of string incorrect parsing") {
    REQUIRE( lib_htoi("FR", 2) == 15 );
}

TEST_CASE("trim / null string trimming") {
    REQUIRE( lib_trim(nullptr, "'\"") == NULL );
}

TEST_CASE("trim / string without separators") {
    const char* input = "test";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("trim / AposString") {
    const char* input = "'test'";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("trim / AposStringNoEnd") {
    const char* input = "'test";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("trim / AposStringNoBegin") {
    const char* input = "test'";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("trim / QuoteString") {
    const char* input = "\"test\"";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("trim / only whitespaces string") {
    const char* input = "   ";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), nullptr) == std::string("") );
}

TEST_CASE("normalize size / zero bytes") {
    const uint64_t size = 0;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_bytes);
    REQUIRE(result.value.size_in_bytes == size);
}

TEST_CASE("normalize size / Bytes")  {
    const uint64_t size = 1023;

    auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_bytes);
    REQUIRE(result.value.size_in_bytes == size);
}

TEST_CASE("normalize size / KBytes on boundary")  {
    const uint64_t size = 1024;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_kbytes);
    REQUIRE(result.value.size == 1.0);
}

TEST_CASE("normalize size / KBytes")  {
    uint64_t size = BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_kbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("normalize size / MBytes")  {
    uint64_t size = BINARY_THOUSAND * BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_mbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("normalize size / GBytes")  {
    const auto size = BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
                      static_cast<uint64_t>(4);

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_gbytes);
    REQUIRE(result.value.size == 4.0);
}

TEST_CASE("normalize size / TBytes")  {
    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
                      BINARY_THOUSAND * BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_tbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("normalize size / PBytes")  {
    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
                      BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_pbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("normalize size / EBytes")  {
    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
                      BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
                      BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_ebytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("normalize time / Hours")  {
    const auto time = 7000.0;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 1);
    REQUIRE(result.minutes == 56);
    REQUIRE(result.seconds == 40.00_a);
}

TEST_CASE("normalize time / HoursFractial")  {
    const auto time = 7000.51;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 1);
    REQUIRE(result.minutes == 56);
    REQUIRE(result.seconds == 40.51_a);
}

TEST_CASE("normalize time / Minutes")  {
    const auto time = 200.0;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 0);
    REQUIRE(result.minutes == 3);
    REQUIRE(result.seconds == 20.00_a);
}

TEST_CASE("normalize time / Seconds")  {
    const auto time = 50.0;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 0);
    REQUIRE(result.minutes == 0);
    REQUIRE(result.seconds == 50.00_a);
}

TEST_CASE("normalize time / BigValue")  {
    const auto time = 500001.0;

    const auto result = lib_normalize_time(time);


    REQUIRE(result.days == 5);
    REQUIRE(result.hours == 18);
    REQUIRE(result.minutes == 53);
    REQUIRE(result.seconds == 21.00_a);
}

TEST_CASE("count digits / Zero")  {
    REQUIRE(lib_count_digits_in(0.0) == 1);
}

TEST_CASE("count digits / One")  {
    REQUIRE(lib_count_digits_in(1.0) == 1);
}

TEST_CASE("count digits / Ten")  {
    REQUIRE(lib_count_digits_in(10.0) == 2);
}

TEST_CASE("count digits / N100")  {
    REQUIRE(lib_count_digits_in(100.0) == 3);
}

TEST_CASE("count digits / N100F")  {
    REQUIRE(lib_count_digits_in(100.23423) == 3);
}

TEST_CASE("count digits / N1000")  {
    REQUIRE(lib_count_digits_in(1000.0) == 4);
}

TEST_CASE("count digits / N10000")  {
    REQUIRE(lib_count_digits_in(10000.0) == 5);
}

TEST_CASE("count digits / N100000")  {
    REQUIRE(lib_count_digits_in(100000.0) == 6);
}

TEST_CASE("count digits / N1000000")  {
    REQUIRE(lib_count_digits_in(1000000.0) == 7);
}

TEST_CASE("count digits / N10000000")  {
    REQUIRE(lib_count_digits_in(10000000.0) == 8);
}

TEST_CASE("count digits / N100000000")  {
    REQUIRE(lib_count_digits_in(100000000.0) == 9);
}

TEST_CASE("count digits / N1000000000")  {
    REQUIRE(lib_count_digits_in(1000000000.0) == 10);
}

TEST_CASE("count digits / N10000000000")  {
    REQUIRE(lib_count_digits_in(10000000000.0) == 11);
}

TEST_CASE("count digits / N100000000000")  {
    REQUIRE(lib_count_digits_in(100000000000.0) == 12);
}

TEST_CASE("get file name / Full")  {
    REQUIRE( lib_get_file_name("c:\\path\\file.txt") == std::string("file.txt") );
}

TEST_CASE("get file name / OnlyFile")  {
    REQUIRE( lib_get_file_name("file.txt") == std::string("file.txt") );
}

TEST_CASE("get file name / Null")  {
    REQUIRE( lib_get_file_name(nullptr) == NULL );
}
