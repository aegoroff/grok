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
#include "BufferedTest.h"

BufferedTest::BufferedTest(size_t buffer_size) {
    buffer_ = std::unique_ptr<char>(new char[buffer_size]);
    memset(buffer_.get(), 0, buffer_size);
}

char* BufferedTest::GetBuffer() const {
    return buffer_.get();
}