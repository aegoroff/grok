/*!
 * \brief   The file contains unit tests
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2020-11-23
            \endverbatim
 * Copyright: (c) Alexander Egorov 2020
 */

#ifndef GROK_APR_TEST_FIXTURE_H
#define GROK_APR_TEST_FIXTURE_H

#include <apr_pools.h>

class apr_test_fixture {
private:
    apr_pool_t* pool_;
public:
    apr_test_fixture() {
        auto argc = 1;

#ifdef _MSC_VER
        setlocale(LC_ALL, ".ACP");
#elif defined(__APPLE_CC__)
        setlocale(LC_ALL, "en_US.utf8");
#else
        setlocale(LC_ALL, "C.UTF-8");
#endif
        setlocale(LC_NUMERIC, "C");

        const char* const argv[] = {"1"};

        auto status = apr_app_initialize(&argc, (const char* const**) &argv, nullptr);

        if(status != APR_SUCCESS) {
            throw status;
        }
        apr_pool_create(&pool_, nullptr);
    }

    virtual ~apr_test_fixture() {
        apr_pool_destroy(pool_);
        apr_terminate();
    }

protected:
    apr_pool_t* get_pool() { return pool_; }
};

#endif //GROK_APR_TEST_FIXTURE_H
