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

#include "catch.hpp"
#include "lib.h"

const size_t kBufferSize = 64;

TEST_CASE("time to string") {
    std::unique_ptr<char> buffer = std::unique_ptr<char>(new char[kBufferSize]);
    memset(buffer.get(), 0, kBufferSize);

    SECTION("big time value that more then year") {
        const auto time = 50000001.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        REQUIRE("1 years 213 days 16 hr 53 min 21.000 sec" == std::string(buffer.get()));
    }

    SECTION("big time value several days") {
        const auto time = 500001.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        REQUIRE("5 days 18 hr 53 min 21.000 sec" == std::string(buffer.get()));
    }

    SECTION("hours") {
        const auto time = 7000.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        REQUIRE("1 hr 56 min 40.000 sec" == std::string(buffer.get()));
    }

    SECTION("minutes") {
        auto time = 200.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        REQUIRE("3 min 20.000 sec" == std::string(buffer.get()));
        REQUIRE(time == result.total_seconds);
    }

    SECTION("seconds") {
        const auto time = 20.0;

        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        REQUIRE("20.000 sec" == std::string(buffer.get()));
    }

    SECTION("null string") {
        const auto time = 20.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, nullptr);
    }
}