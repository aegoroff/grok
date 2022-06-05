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

#include "catch_amalgamated.hpp"
#include "lib.h"

const size_t kBufferSize = 64;

SCENARIO("time to string") {
    std::unique_ptr<char[]> buffer = std::make_unique<char[]>(kBufferSize);

    GIVEN( "50 000 001.0 seconds value" ) {
        const auto time = 50000001.0;

        WHEN("normalize it and convert to string") {
            auto result = lib_normalize_time(time);
            lib_time_to_string(&result, buffer.get());

            THEN("result more then year") {
                REQUIRE("1 years 213 days 16 hr 53 min 21.000 sec" == std::string(buffer.get()));
            }
        }
    }

    GIVEN( "500 001.0 seconds value" ) {
        const auto time = 500001.0;

        WHEN("normalize it and convert to string") {
            auto result = lib_normalize_time(time);
            lib_time_to_string(&result, buffer.get());

            THEN("result more then 5 days") {
                REQUIRE("5 days 18 hr 53 min 21.000 sec" == std::string(buffer.get()));
            }
        }
    }

    GIVEN( "7000.0 seconds value" ) {
        const auto time = 7000.0;

        WHEN("normalize it and convert to string") {
            auto result = lib_normalize_time(time);
            lib_time_to_string(&result, buffer.get());

            THEN("result more then hour") {
                REQUIRE("1 hr 56 min 40.000 sec" == std::string(buffer.get()));
            }
        }
    }

    GIVEN( "200.0 seconds value" ) {
        auto time = 200.0;

        WHEN("normalize it and convert to string") {
            auto result = lib_normalize_time(time);
            lib_time_to_string(&result, buffer.get());

            THEN("result several minutes") {
                REQUIRE("3 min 20.000 sec" == std::string(buffer.get()));
                REQUIRE(time == result.total_seconds);
            }
        }
    }

    GIVEN( "20.0 seconds value" ) {
        const auto time = 20.0;

        WHEN("normalize it and convert to string") {
            auto result = lib_normalize_time(time);
            lib_time_to_string(&result, buffer.get());

            THEN("result same seconds as input") {
                REQUIRE("20.000 sec" == std::string(buffer.get()));
            }
        }

        WHEN("normalize it and try to convert it to null string") {
            auto result = lib_normalize_time(time);
            lib_time_to_string(&result, nullptr);

            THEN("no crash") {
            }
        }
    }
}