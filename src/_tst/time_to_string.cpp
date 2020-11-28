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

#include <cstring>
#include "catch.hpp"
#include "lib.h"

const size_t kBufferSize = 64;

SCENARIO("time to string") {
    std::unique_ptr<char> buffer = std::unique_ptr<char>(new char[kBufferSize]);
    memset(buffer.get(), 0, kBufferSize);

    WHEN("big time value that more then year") {
        const auto time = 50000001.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        THEN("result more then year") {
            REQUIRE("1 years 213 days 16 hr 53 min 21.000 sec" == std::string(buffer.get()));
        }
    }

    WHEN("big time value several days") {
        const auto time = 500001.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        THEN("result more then 5 days") {
            REQUIRE("5 days 18 hr 53 min 21.000 sec" == std::string(buffer.get()));
        }
    }

    WHEN("hours time value") {
        const auto time = 7000.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        THEN("result more then hour") {
            REQUIRE("1 hr 56 min 40.000 sec" == std::string(buffer.get()));
        }
    }

    WHEN("minutes time value") {
        auto time = 200.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        THEN("result several minutes") {
            REQUIRE("3 min 20.000 sec" == std::string(buffer.get()));
            REQUIRE(time == result.total_seconds);
        }
    }

    WHEN("seconds time value") {
        const auto time = 20.0;

        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, buffer.get());

        THEN("result several seconds") {
            REQUIRE("20.000 sec" == std::string(buffer.get()));
        }
    }

    WHEN("null string") {
        const auto time = 20.0;
        auto result = lib_normalize_time(time);
        lib_time_to_string(&result, nullptr);

        THEN("no crash") {
        }
    }
}