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

//TEST(NormalizeSize, ZeroBytes) {
//    const uint64_t size = 0;
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_bytes);
//    EXPECT_EQ(result.value.size_in_bytes, size);
//}
//
//TEST(NormalizeSize, Bytes) {
//    const uint64_t size = 1023;
//
//    auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_bytes);
//    EXPECT_EQ(result.value.size_in_bytes, size);
//}
//
//TEST(NormalizeSize, KBytesBoundary) {
//    const uint64_t size = 1024;
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_kbytes);
//    EXPECT_EQ(result.value.size, 1.0);
//}
//
//TEST(NormalizeSize, KBytes) {
//    uint64_t size = BINARY_THOUSAND * 2;
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_kbytes);
//    EXPECT_EQ(result.value.size, 2.0);
//}
//
//TEST(NormalizeSize, MBytes) {
//    uint64_t size = BINARY_THOUSAND * BINARY_THOUSAND * 2;
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_mbytes);
//    EXPECT_EQ(result.value.size, 2.0);
//}
//
//TEST(NormalizeSize, GBytes) {
//    const auto size = BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
//            static_cast<uint64_t>(4);
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_gbytes);
//    EXPECT_EQ(result.value.size, 4.0);
//}
//
//TEST(NormalizeSize, TBytes) {
//    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
//            BINARY_THOUSAND * BINARY_THOUSAND * 2;
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_tbytes);
//    EXPECT_EQ(result.value.size, 2.0);
//}
//
//TEST(NormalizeSize, PBytes) {
//    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
//            BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND * 2;
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(result.unit, size_unit_pbytes);
//    EXPECT_EQ(result.value.size, 2.0);
//}
//
//TEST(NormalizeSize, EBytes) {
//    const auto size = static_cast<uint64_t>(BINARY_THOUSAND) * BINARY_THOUSAND *
//            BINARY_THOUSAND * BINARY_THOUSAND * BINARY_THOUSAND *
//            BINARY_THOUSAND * 2;
//
//    const auto result = lib_normalize_size(size);
//
//    EXPECT_EQ(size_unit_ebytes, result.unit);
//    EXPECT_EQ(2.0, result.value.size);
//}
//
//TEST(NormalizeTime, Hours) {
//    const auto time = 7000.0;
//
//    const auto result = lib_normalize_time(time);
//
//    EXPECT_EQ(1, result.hours);
//    EXPECT_EQ(56, result.minutes);
//    EXPECT_FLOAT_EQ(40.00, result.seconds);
//}
//
//TEST(NormalizeTime, HoursFractial) {
//    const auto time = 7000.51;
//
//    const auto result = lib_normalize_time(time);
//
//    EXPECT_EQ(1, result.hours);
//    EXPECT_EQ(56, result.minutes);
//    EXPECT_FLOAT_EQ(40.51, result.seconds);
//}
//
//TEST(NormalizeTime, Minutes) {
//    const auto time = 200.0;
//
//    const auto result = lib_normalize_time(time);
//
//    EXPECT_EQ(0, result.hours);
//    EXPECT_EQ(3, result.minutes);
//    EXPECT_FLOAT_EQ(20.00, result.seconds);
//}
//
//TEST(NormalizeTime, Seconds) {
//    const auto time = 50.0;
//
//    const auto result = lib_normalize_time(time);
//
//    EXPECT_EQ(0, result.hours);
//    EXPECT_EQ(0, result.minutes);
//    EXPECT_FLOAT_EQ(50.00, result.seconds);
//}
//
//TEST(NormalizeTime, BigValue) {
//    const auto time = 500001.0;
//
//    const auto result = lib_normalize_time(time);
//
//    EXPECT_EQ(5, result.days);
//    EXPECT_EQ(18, result.hours);
//    EXPECT_EQ(53, result.minutes);
//    EXPECT_FLOAT_EQ(21.00, result.seconds);
//}
//
//TEST(CountDigits, Zero) {
//    EXPECT_EQ(1, lib_count_digits_in(0.0));
//}
//
//TEST(CountDigits, One) {
//    EXPECT_EQ(1, lib_count_digits_in(1.0));
//}
//
//TEST(CountDigits, Ten) {
//    EXPECT_EQ(2, lib_count_digits_in(10.0));
//}
//
//TEST(CountDigits, N100) {
//    EXPECT_EQ(3, lib_count_digits_in(100.0));
//}
//
//TEST(CountDigits, N100F) {
//    EXPECT_EQ(3, lib_count_digits_in(100.23423));
//}
//
//TEST(CountDigits, N1000) {
//    EXPECT_EQ(4, lib_count_digits_in(1000.0));
//}
//
//TEST(CountDigits, N10000) {
//    EXPECT_EQ(5, lib_count_digits_in(10000.0));
//}
//
//TEST(CountDigits, N100000) {
//    EXPECT_EQ(6, lib_count_digits_in(100000.0));
//}
//
//TEST(CountDigits, N1000000) {
//    EXPECT_EQ(7, lib_count_digits_in(1000000.0));
//}
//
//TEST(CountDigits, N10000000) {
//    EXPECT_EQ(8, lib_count_digits_in(10000000.0));
//}
//
//TEST(CountDigits, N100000000) {
//    EXPECT_EQ(9, lib_count_digits_in(100000000.0));
//}
//
//TEST(CountDigits, N1000000000) {
//    EXPECT_EQ(10, lib_count_digits_in(1000000000.0));
//}
//
//TEST(CountDigits, N10000000000) {
//    EXPECT_EQ(11, lib_count_digits_in(10000000000.0));
//}
//
//TEST(CountDigits, N100000000000) {
//    EXPECT_EQ(12, lib_count_digits_in(100000000000.0));
//}
//
//TEST(GetFileName, Full) {
//    ASSERT_STREQ("file.txt", lib_get_file_name("c:\\path\\file.txt"));
//}
//
//TEST(GetFileName, OnlyFile) {
//    ASSERT_STREQ("file.txt", lib_get_file_name("file.txt"));
//}
//
//TEST(GetFileName, Null) {
//    ASSERT_STREQ(NULL, lib_get_file_name(NULL));
//}
