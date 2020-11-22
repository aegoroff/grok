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

TEST_CASE_METHOD(ToStringTime, "big time value that more then year") {
    const auto time = 50000001.0;
    auto result = lib_normalize_time(time);
    lib_time_to_string(&result, GetBuffer());

    REQUIRE("1 years 213 days 16 hr 53 min 21.000 sec" == std::string(GetBuffer()));
}