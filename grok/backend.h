/*!
 * \brief   The file contains backend interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-08-28
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015
 */

#ifndef GROK_BACKEND_H_
#define GROK_BACKEND_H_

void bend_init(apr_pool_t* pool);
void bend_cleanup();

BOOL bend_match_re(char* pattern, char* subject);
char* bend_create_pattern(const char* macro);

#endif // GROK_BACKEND_H_