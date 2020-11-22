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

#include "ToStringTime.h"
#include "catch.hpp"
#include "lib.h"

const size_t kBufferSize = 64;

ToStringTime::ToStringTime() : BufferedTest(kBufferSize) {}

TEST_CASE_METHOD(ToStringTime, "time to string / big time value that more then year") {
    const auto time = 50000001.0;
    auto result = lib_normalize_time(time);
    lib_time_to_string(&result, GetBuffer());

    REQUIRE("1 years 213 days 16 hr 53 min 21.000 sec" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(ToStringTime, "time to string / big time value several days") {
    const auto time = 500001.0;
    auto result = lib_normalize_time(time);
    lib_time_to_string(&result, GetBuffer());

    REQUIRE("5 days 18 hr 53 min 21.000 sec" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(ToStringTime, "time to string / hours") {
    const auto time = 7000.0;
    auto result = lib_normalize_time(time);
    lib_time_to_string(&result, GetBuffer());

    REQUIRE("1 hr 56 min 40.000 sec" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(ToStringTime, "time to string / minutes") {
    auto time = 200.0;
    auto result = lib_normalize_time(time);
    lib_time_to_string(&result, GetBuffer());

    REQUIRE("3 min 20.000 sec" == std::string(GetBuffer()));
    REQUIRE(time == result.total_seconds);
}

TEST_CASE_METHOD(ToStringTime, "time to string / seconds") {
    const auto time = 20.0;

    auto result = lib_normalize_time(time);
    lib_time_to_string(&result, GetBuffer());

    REQUIRE("20.000 sec" == std::string(GetBuffer()));
}

TEST_CASE_METHOD(ToStringTime, "time to string / null string") {
    const auto time = 20.0;
    auto result = lib_normalize_time(time);
    lib_time_to_string(&result, nullptr);
}