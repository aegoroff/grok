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

#ifndef GROK_BUFFEREDTEST_H
#define GROK_BUFFEREDTEST_H

#include <memory>

class BufferedTest {
    std::unique_ptr<char> buffer_;
public:
    explicit BufferedTest(size_t buffer_size);
    char* GetBuffer() const;
};

#endif //GROK_BUFFEREDTEST_H
