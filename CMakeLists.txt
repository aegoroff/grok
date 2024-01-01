cmake_minimum_required(VERSION 3.21)
project(grok)

set(SRC src)
set(GEN generated)
set(GROK grok)
set(TST _tst)
set(LIB srclib)
set(PCRE pcre)
set(APR apr)
set(APR_UTIL apr-util)
set(LIBD Debug)
set(LIBR Release)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
enable_testing()

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    set(APR_X64 "$ENV{APR_HOME16}/${APR}/x64")
    set(APR_UTIL_X64 "$ENV{APR_HOME16}/${APR_UTIL}/x64")
else ()
    set(APR_X64 "$ENV{APR_HOME}/APR")
    set(APR_UTIL_X64 "$ENV{APR_HOME}APR-UTIL")
endif ()

set(compiler_flags)
set(debug_compiler_flags)
set(release_compiler_flags)

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    list(APPEND compiler_flags
        /MP
        /Zc:wchar_t
        /Zc:inline
        /Zc:preprocessor
        /utf-8
        /validate-charset
        /sdl
        /std:c11
        /W3
    )
    list(APPEND debug_compiler_flags
        /MTd
        /Od
        /Zi
        /RTC1
    )
    list(APPEND release_compiler_flags
        /MT
        /Ox
        /Ob2
        /Oy
        /Oi
        /Ot
        /GL
        /Qpar
        /D
        NDEBUG
    )
    foreach(compiler_flag ${compiler_flags})
        set(FLAGS "${FLAGS} ${compiler_flag}")
    endforeach()
    foreach(compiler_flag ${release_compiler_flags})
        set(RELEASE_FLAGS "${RELEASE_FLAGS} ${compiler_flag}")
    endforeach()
    foreach(compiler_flag ${debug_compiler_flags})
        set(DEBUG_FLAGS "${DEBUG_FLAGS} ${compiler_flag}")
    endforeach()
    set(CMAKE_CXX_FLAGS_RELEASE "${FLAGS} ${RELEASE_FLAGS}")
    set(CMAKE_CXX_FLAGS_DEBUG "${FLAGS} ${DEBUG_FLAGS}")
    set(CMAKE_C_FLAGS_RELEASE "${FLAGS} ${RELEASE_FLAGS} /TC")
    set(CMAKE_C_FLAGS_DEBUG "${FLAGS} ${DEBUG_FLAGS} /TC")
    if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    else ()
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /LTCG")
        set(CMAKE_STATIC_LINKER_FLAGS "${CMAKE_STATIC_LINKER_FLAGS} /LTCG")
    endif ()
else ()
    list(APPEND compiler_flags
        -Wall
        -pthread
    )
    if ("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
        list(APPEND compiler_flags
            -march=haswell
            -mtune=haswell
        )
    endif ()
    list(APPEND debug_compiler_flags
        -Og
    )
    list(APPEND release_compiler_flags
        -Ofast
        -s
    )
    if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
        list(APPEND debug_compiler_flags
            -gfull
            -glldb
        )
    else ()
        list(APPEND debug_compiler_flags
            -ggdb
        )
    endif ()
    foreach(compiler_flag ${compiler_flags})
        set(FLAGS "${FLAGS} ${compiler_flag}")
    endforeach()
    foreach(compiler_flag ${debug_compiler_flags})
        set(DEBUG_FLAGS "${DEBUG_FLAGS} ${compiler_flag}")
    endforeach()
    foreach(compiler_flag ${release_compiler_flags})
        set(RELEASE_FLAGS "${RELEASE_FLAGS} ${compiler_flag}")
    endforeach()
    set(CMAKE_CXX_FLAGS_RELEASE "${FLAGS} ${RELEASE_FLAGS} -std=c++17")
    set(CMAKE_CXX_FLAGS_DEBUG "${FLAGS} ${DEBUG_FLAGS} -std=c++17")
    set(CMAKE_C_FLAGS_RELEASE "${FLAGS} ${RELEASE_FLAGS}")
    set(CMAKE_C_FLAGS_DEBUG "${FLAGS} ${DEBUG_FLAGS}")
endif ()

include_directories(${SRC}/${LIB})
include_directories(${SRC}/${PCRE})
include_directories(${SRC}/${GROK})

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    include_directories($ENV{APR_HOME16}/${APR}/include)
    include_directories($ENV{APR_HOME16}/${APR_UTIL}/include)
elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
    if (DEFINED ENV{APR_INCLUDE})
        include_directories($ENV{APR_INCLUDE})
    else ()
        include_directories($ENV{APR_HOME}/apr/include/apr-1)
        include_directories($ENV{APR_HOME}/apr-util/include/apr-1)
    endif ()
elseif (DEFINED ENV{APR_INCLUDE})
    include_directories($ENV{APR_INCLUDE})
else ()
    include_directories($ENV{APR_HOME}/include/apr-1.0)
endif ()

add_definitions(-DPCRE2_STATIC)
add_definitions(-DPCRE2_CODE_UNIT_WIDTH=8)
add_definitions(-DLINK_SIZE=2)
add_definitions(-DHAVE_CONFIG_H)
add_definitions(-DAPR_DECLARE_STATIC)
add_definitions(-DAPU_DECLARE_STATIC)

if ("$ENV{GROK_VERSION}" STREQUAL "")
    if ("$ENV{CI_BUILD_NUMBER}" STREQUAL "")
        add_definitions(-DPRODUCT_VERSION="0.2.0")
        set(CPACK_PACKAGE_VERSION "0.2.0")
    else ()
        add_definitions(-DPRODUCT_VERSION="0.2.0-$ENV{CI_BUILD_NUMBER}")
        set(CPACK_PACKAGE_VERSION "0.2.0-$ENV{CI_BUILD_NUMBER}")
    endif ()
else ()
    add_definitions(-DPRODUCT_VERSION="$ENV{GROK_VERSION}")
    set(CPACK_PACKAGE_VERSION "$ENV{GROK_VERSION}")
endif ()

SET(GROK_SOURCE_FILES
        "${SRC}/${GROK}/backend.c"
        "${SRC}/${GROK}/configuration.c"
        "${SRC}/${GROK}/frontend.c"
        "${SRC}/${GROK}/grok.c"
        "${SRC}/${GROK}/grok.c"
        "${SRC}/${GROK}/pattern.c")

SET(TST_SOURCE_FILES
        "${SRC}/${TST}/_tst.cpp"
        "${SRC}/${TST}/encoding.cpp"
        "${SRC}/${TST}/lib_test.cpp"
        "${SRC}/${TST}/size_to_string.cpp"
        "${SRC}/${TST}/time_to_string.cpp"
        "${SRC}/${TST}/catch_amalgamated.cpp"
        "${SRC}/${TST}/trim_tests.cpp")

SET(LICENSE_FILE "LICENSE.txt")

file(GLOB LIB_SOURCE_FILES "${SRC}/${LIB}/*.c")
file(GLOB PATTERN_FILES "patterns/*.patterns")


SET(PCRE_SOURCE_FILES
        ${SRC}/${PCRE}/pcre2_auto_possess.c
        ${SRC}/${PCRE}/pcre2_chartables.c
        ${SRC}/${PCRE}/pcre2_compile.c
        ${SRC}/${PCRE}/pcre2_config.c
        ${SRC}/${PCRE}/pcre2_context.c
        ${SRC}/${PCRE}/pcre2_convert.c
        ${SRC}/${PCRE}/pcre2_dfa_match.c
        ${SRC}/${PCRE}/pcre2_error.c
        ${SRC}/${PCRE}/pcre2_extuni.c
        ${SRC}/${PCRE}/pcre2_find_bracket.c
        ${SRC}/${PCRE}/pcre2_jit_compile.c
        ${SRC}/${PCRE}/pcre2_maketables.c
        ${SRC}/${PCRE}/pcre2_match.c
        ${SRC}/${PCRE}/pcre2_match_data.c
        ${SRC}/${PCRE}/pcre2_newline.c
        ${SRC}/${PCRE}/pcre2_ord2utf.c
        ${SRC}/${PCRE}/pcre2_pattern_info.c
        ${SRC}/${PCRE}/pcre2_script_run.c
        ${SRC}/${PCRE}/pcre2_serialize.c
        ${SRC}/${PCRE}/pcre2_string_utils.c
        ${SRC}/${PCRE}/pcre2_study.c
        ${SRC}/${PCRE}/pcre2_substitute.c
        ${SRC}/${PCRE}/pcre2_substring.c
        ${SRC}/${PCRE}/pcre2_tables.c
        ${SRC}/${PCRE}/pcre2_ucd.c
        ${SRC}/${PCRE}/pcre2_ucptables.c
        ${SRC}/${PCRE}/pcre2_valid_utf.c
        ${SRC}/${PCRE}/pcre2_xclass.c
        )

add_library(pcre STATIC ${PCRE_SOURCE_FILES})

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    if (CMAKE_BUILD_TYPE STREQUAL "Debug")
        link_directories(
                "${APR_X64}/${LIBD}"
                "${APR_UTIL_X64}/${LIBD}"
        )
    else ()
        link_directories(
                "${APR_X64}/${LIBR}"
                "${APR_UTIL_X64}/${LIBR}"
        )
    endif ()
elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
    if (DEFINED ENV{APR_LINK})
        link_directories(
            "$ENV{APR_LINK}"
        )
        set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
    else ()
        link_directories(
                "$ENV{APR_HOME}/apr/lib/"
                "$ENV{APR_HOME}/apr-util/lib/"
        )
        set(CMAKE_FIND_LIBRARY_SUFFIXES .a .dylib)
    endif ()
elseif (DEFINED ENV{APR_LINK})
    link_directories(
            "$ENV{APR_LINK}"
    )
else ()
    link_directories(
            "$ENV{APR_HOME}/lib/x86_64-linux-gnu/"
    )
endif ()


if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    set(FLEX_EXE win_flex.exe)
    set(BISON_EXE win_bison.exe)
elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
    set(FLEX_EXE /usr/local/opt/flex/bin/flex)
    set(BISON_EXE /usr/local/opt/bison/bin/bison)
else ()
    set(FLEX_EXE flex)
    set(BISON_EXE bison)
endif ()

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    set(FLEX_OPT --wincompat)
endif ()

set(FLEX ${FLEX_EXE} --fast ${FLEX_OPT} --outfile="${GEN}/grok.flex.c" grok.lex)
set(BISON ${BISON_EXE} --output="${GEN}/grok.tab.c" -dy grok.y)

add_custom_target(generated_directory ALL
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}/${GROK}/${GEN}")

add_custom_target(generate_parser
        COMMAND ${FLEX}
        COMMAND ${BISON}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${SRC}/${GROK})

SET(GROK_GENERATED_FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}/${GROK}/${GEN}/grok.flex.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}/${GROK}/${GEN}/grok.tab.c")

set_source_files_properties(${GROK_GENERATED_FILES}
        PROPERTIES GENERATED TRUE)

add_library(libgrok STATIC ${GROK_GENERATED_FILES} ${LIB_SOURCE_FILES})
add_executable(grok ${GROK_SOURCE_FILES})
add_executable(_tst ${TST_SOURCE_FILES})

add_dependencies(generate_parser generated_directory)
add_dependencies(grok generate_parser)
add_dependencies(libgrok generate_parser)

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    target_link_libraries(libgrok 
        PRIVATE ws2_32 
        PRIVATE rpcrt4 
        PRIVATE apr-1 
        PRIVATE aprutil-1 
        PRIVATE pcre 
        PRIVATE strsafe)
else ()
    target_link_libraries(libgrok PRIVATE m PRIVATE libapr-1.a PRIVATE libaprutil-1.a)
endif ()
target_link_libraries(grok PRIVATE libgrok PRIVATE pcre)
target_link_libraries(_tst PRIVATE libgrok PRIVATE pcre)

add_test(NAME RunUnitTests COMMAND _tst)

install(TARGETS grok DESTINATION . COMPONENT application)
install(FILES ${PATTERN_FILES} DESTINATION . COMPONENT patterns)
install(FILES ${LICENSE_FILE} DESTINATION . COMPONENT license)

set(CPACK_INCLUDE_TOPLEVEL_DIRECTORY OFF)
set(CPACK_PACKAGE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin")
if ("${CMAKE_SYSTEM_NAME}" STREQUAL "Windows")
    set(CPACK_SYSTEM_NAME  x86_64-pc-windows-msvc)
    set(CPACK_GENERATOR     TGZ)
elseif ("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin" AND "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
    set(CPACK_SYSTEM_NAME  x86_64-apple-darwin)
    set(CPACK_GENERATOR     TGZ)
elseif ("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin" AND "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "aarch64")
    set(CPACK_SYSTEM_NAME  aarch64-apple-darwin)
    set(CPACK_GENERATOR     TGZ)
elseif ("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux" AND "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "aarch64")
    set(CPACK_SYSTEM_NAME  aarch64-unknown-linux-gnu)
    set(CPACK_GENERATOR     TGZ)
elseif ("${CMAKE_TOOLCHAIN_FILE}" MATCHES "zig-toolchain-x86_64-linux-musl")
    set(CPACK_SYSTEM_NAME  x86_64-unknown-linux-musl)
    set(CPACK_GENERATOR     TGZ)
elseif ("${CMAKE_TOOLCHAIN_FILE}" MATCHES "zig-toolchain-x86_64-linux-gnu")
    set(CPACK_SYSTEM_NAME  x86_64-unknown-linux-gnu)
    set(CPACK_GENERATOR     TGZ)
else()
    set(CPACK_SYSTEM_NAME  x86_64-unknown-linux-gnu)
    set(CPACK_GENERATOR     TGZ)
endif()

include(CPack)

cpack_add_component(application)
cpack_add_component(patterns)
cpack_add_component(license)