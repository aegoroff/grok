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

TEST_CASE("1SymbolByte", "[htoi]") {
    REQUIRE( lib_htoi("5", 1) == 5 );
}

TEST_CASE("2SymbolByte", "[htoi]") {
    REQUIRE( lib_htoi("FF", 2) == 255 );
}

//TEST(Htoi, ZeroSize) {
//    EXPECT_EQ(0, lib_htoi("FF", 0));
//}
//
//TEST(Htoi, NegativeSize) {
//    EXPECT_EQ(0, lib_htoi("FF", -1));
//}
//
//TEST(Htoi, 2Bytes) {
//    EXPECT_EQ(65518, lib_htoi("FFEE", 4));
//}
//
//TEST(Htoi, TrimTest) {
//    EXPECT_EQ(65518, lib_htoi("  FFEE", 6));
//}
//
//TEST(Htoi, OnlyWhiteSpaces) {
//    EXPECT_EQ(0, lib_htoi(" \t", 2));
//}
//
//TEST(Htoi, TrimTestOfPartString) {
//    EXPECT_EQ(255, lib_htoi("  FFEE", 4));
//}
//
//TEST(Htoi, 2BytesPartString) {
//    EXPECT_EQ(255, lib_htoi("FFFF", 2));
//}
//
//TEST(Htoi, NullString) {
//    EXPECT_EQ(0, lib_htoi(NULL, 2));
//}
//
//TEST(Htoi, IncorrectStringAll) {
//    EXPECT_EQ(0, lib_htoi("RR", 2));
//}
//
//TEST(Htoi, IncorrectStringPart) {
//    EXPECT_EQ(15, lib_htoi("FR", 2));
//}
//
//TEST(Trim, NullSting) {
//    ASSERT_STREQ(NULL, lib_trim(NULL, "'\""));
//}

TEST_CASE("StringWithoutSeps", "[trim]") {
    std::string input = "test'";
    auto const dst_sz = input.length() + 1;
    auto buffer = std::vector<char>(dst_sz);
    std::copy(input.begin(), input.end(), std::inserter(buffer, buffer.begin()));

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("AposString", "[trim]") {
    std::string input = "'test'";
    auto const dst_sz = input.length() + 1;
    auto buffer = std::vector<char>(dst_sz);
    std::copy(input.begin(), input.end(), std::inserter(buffer, buffer.begin()));

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

TEST_CASE("AposStringNoEnd", "[trim]") {
    std::string input = "'test";
    auto const dst_sz = input.length() + 1;
    auto buffer = std::vector<char>(dst_sz);
    std::copy(input.begin(), input.end(), std::inserter(buffer, buffer.begin()));

    REQUIRE( lib_trim(buffer.data(), "'\"") == std::string("test") );
}

//TEST(Trim, AposStringNoBegin) {
//    const char* input = "test'";
//    auto const dst_sz = strlen(input) + 1;
//    auto buffer = std::vector<char>(dst_sz);
//    strcpy_s(buffer.data(), dst_sz, input);
//
//    ASSERT_STREQ("test", lib_trim(buffer.data(), "'\""));
//}
//
//TEST(Trim, QuoteString) {
//    const char* input = "\"test\"";
//    auto const dst_sz = strlen(input) + 1;
//    auto buffer = std::vector<char>(dst_sz);
//    strcpy_s(buffer.data(), dst_sz, input);
//
//    ASSERT_STREQ("test", lib_trim(buffer.data(), "'\""));
//}
//
//TEST(Trim, OnlyWhitespacesString) {
//    const char* input = "   ";
//    auto const dst_sz = strlen(input) + 1;
//    auto buffer = std::vector<char>(dst_sz);
//    strcpy_s(buffer.data(), dst_sz, input);
//
//    ASSERT_STREQ("", lib_trim(buffer.data(), NULL));
//}
//
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
