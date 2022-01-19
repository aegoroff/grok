/*
* This is an open source non-commercial project. Dear PVS-Studio, please check it.
* PVS-Studio Static Code Analyzer for C, C++ and C#: http://www.viva64.com
*/
/*!
 * \brief   The file contains configuration module interface
 * \author  \verbatim
            Created by: Alexander Egorov
            \endverbatim
 * \date    \verbatim
            Creation date: 2015-09-01
            \endverbatim
 * Copyright: (c) Alexander Egorov 2015-2022
 */


#ifndef GROK_CONFIGURATION_H_
#define GROK_CONFIGURATION_H_

typedef struct configuration_ctx_t {
    void (*on_string)(struct arg_file* pattern_files, const char* const macro, const char* const str, int info_mode);
    void (*on_file)(struct arg_file* pattern_files, const char* const macro, const char* const path, int info_mode);
    void (*on_template_info)(struct arg_file* pattern_files, const char* const macro);
    int argc;
    const char* const* argv;
} configuration_ctx_t;

void conf_configure_app(configuration_ctx_t* ctx);

#endif // GROK_CONFIGURATION_H_

