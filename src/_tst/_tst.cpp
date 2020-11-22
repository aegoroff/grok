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

#define CATCH_CONFIG_MAIN

#include <cstdio>

#include "catch.hpp"
#include "lib.h"

using namespace Catch::literals;

TEST_CASE("parse one symbol", "[htoi]") {
    REQUIRE( lib_htoi("5", 1) == 5 );
}

TEST_CASE("parse max byte value", "[htoi]") {
    REQUIRE( lib_htoi("FF", 2) == 255 );
}

TEST_CASE("setting zero data size", "[htoi]") {
    REQUIRE( lib_htoi("FF", 0) == 0 );
}

TEST_CASE("setting negative data size", "[htoi]") {
    REQUIRE( lib_htoi("FF", -1) == 0 );
}

TEST_CASE("parse two bytes", "[htoi]") {
    REQUIRE( lib_htoi("FFEE", 4) == 65518 );
}

TEST_CASE("trimming test", "[htoi]") {
    REQUIRE( lib_htoi("  FFEE", 6) == 65518 );
}

TEST_CASE("only whitespaces test", "[htoi]") {
    REQUIRE( lib_htoi(" \t", 2) == 0 );
}

TEST_CASE("only part of string that starts from whitespaces", "[htoi]") {
    REQUIRE( lib_htoi("  FFEE", 4) == 255 );
}

TEST_CASE("parsing only part of two bytes string", "[htoi]") {
    REQUIRE( lib_htoi("FFFF", 2) == 255 );
}

TEST_CASE("null string parsing", "[htoi]") {
    REQUIRE( lib_htoi(nullptr, 2) == 0 );
}

TEST_CASE("all incorrect string parsing", "[htoi]") {
    REQUIRE( lib_htoi("RR", 2) == 0 );
}

TEST_CASE("only part of string incorrect parsing", "[htoi]") {
    REQUIRE( lib_htoi("FR", 2) == 15 );
}

TEST_CASE("null string trimming", "[trim]") {
    REQUIRE( lib_trim(nullptr, "'\"") == NULL );
}

TEST_CASE("string without separators", "[trim]") {
    const char* input = "test";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("AposString", "[trim]") {
    const char* input = "'test'";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("AposStringNoEnd", "[trim]") {
    const char* input = "'test";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("AposStringNoBegin", "[trim]") {
    const char* input = "test'";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("QuoteString", "[trim]") {
    const char* input = "\"test\"";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("only whitespaces string", "[trim]") {
    const char* input = "   ";

    auto const dst_sz = strlen(input);
    auto buffer = std::vector<char>(dst_sz + 1);
    buffer.insert(buffer.begin(), input, input + dst_sz );

    REQUIRE( lib_trim(buffer.data(), nullptr) == std::string("") );
}

TEST_CASE("zero bytes", "[NormalizeSize]") {
    const uint64_t size = 0;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_bytes);
    REQUIRE(result.value.size_in_bytes == size);
}

TEST_CASE("Bytes", "[NormalizeSize]")  {
    const uint64_t size = 1023;

    auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_bytes);
    REQUIRE(result.value.size_in_bytes == size);
}

TEST_CASE("KBytesBoundary", "[NormalizeSize]")  {
    const uint64_t size = 1024;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_kbytes);
    REQUIRE(result.value.size == 1.0);
}

TEST_CASE("KBytes", "[NormalizeSize]")  {
    uint64_t size = BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_kbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("MBytes", "[NormalizeSize]")  {
    uint64_t size = BINARY_THOUSAND * BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_mbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("GBytes", "[NormalizeSize]")  {
    const auto size = BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
            static_cast<uint64_t>(4);

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_gbytes);
    REQUIRE(result.value.size == 4.0);
}

TEST_CASE("TBytes", "[NormalizeSize]")  {
    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
            BINARY_THOUSAND * BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_tbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("PBytes", "[NormalizeSize]")  {
    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
            BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_pbytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("EBytes", "[NormalizeSize]")  {
    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
            BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
            BINARY_THOUSAND * 2;

    const auto result = lib_normalize_size(size);

    REQUIRE(result.unit == size_unit_ebytes);
    REQUIRE(result.value.size == 2.0);
}

TEST_CASE("Hours", "[NormalizeTime]")  {
    const auto time = 7000.0;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 1);
    REQUIRE(result.minutes == 56);
    REQUIRE(result.seconds == 40.00_a);
}

TEST_CASE("HoursFractial", "[NormalizeTime]")  {
    const auto time = 7000.51;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 1);
    REQUIRE(result.minutes == 56);
    REQUIRE(result.seconds == 40.51_a);
}

TEST_CASE("Minutes", "[NormalizeTime]")  {
    const auto time = 200.0;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 0);
    REQUIRE(result.minutes == 3);
    REQUIRE(result.seconds == 20.00_a);
}

TEST_CASE("Seconds", "[NormalizeTime]")  {
    const auto time = 50.0;

    const auto result = lib_normalize_time(time);

    REQUIRE(result.hours == 0);
    REQUIRE(result.minutes == 0);
    REQUIRE(result.seconds == 50.00_a);
}

TEST_CASE("BigValue", "[NormalizeTime]")  {
    const auto time = 500001.0;

    const auto result = lib_normalize_time(time);


    REQUIRE(result.days == 5);
    REQUIRE(result.hours == 18);
    REQUIRE(result.minutes == 53);
    REQUIRE(result.seconds == 21.00_a);
}

TEST_CASE("Zero", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(0.0) == 1);
}

TEST_CASE("One", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(1.0) == 1);
}

TEST_CASE("Ten", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(10.0) == 2);
}

TEST_CASE("N100", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(100.0) == 3);
}

TEST_CASE("N100F", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(100.23423) == 3);
}

TEST_CASE("N1000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(1000.0) == 4);
}

TEST_CASE("N10000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(10000.0) == 5);
}

TEST_CASE("N100000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(100000.0) == 6);
}

TEST_CASE("N1000000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(1000000.0) == 7);
}

TEST_CASE("N10000000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(10000000.0) == 8);
}

TEST_CASE("N100000000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(100000000.0) == 9);
}

TEST_CASE("N1000000000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(1000000000.0) == 10);
}

TEST_CASE("N10000000000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(10000000000.0) == 11);
}

TEST_CASE("N100000000000", "[CountDigits]")  {
    REQUIRE(lib_count_digits_in(100000000000.0) == 12);
}

TEST_CASE("Full", "[GetFileName]")  {
    REQUIRE( lib_get_file_name("c:\\path\\file.txt") == std::string("file.txt") );
}

TEST_CASE("OnlyFile", "[GetFileName]")  {
    REQUIRE( lib_get_file_name("file.txt") == std::string("file.txt") );
}

TEST_CASE("Null", "[GetFileName]")  {
    REQUIRE( lib_get_file_name(nullptr) == NULL );
}
