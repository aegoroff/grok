cmake_minimum_required(VERSION 3.11)
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

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC" OR "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    set(APR_X64 "$ENV{APR_HOME16}/${APR}/x64")
    set(APR_UTIL_X64 "$ENV{APR_HOME16}/${APR_UTIL}/x64")
else()
    set(APR_X64 "$ENV{APR_HOME}/APR")
    set(APR_UTIL_X64 "$ENV{APR_HOME}APR-UTIL")
endif()

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    set(CMAKE_CXX_FLAGS_RELEASE  "/MP /Zc:wchar_t /Zc:inline /Zc:preprocessor /MT /Ox /Ob2 /Oy /Oi /Ot /GL /Qpar /W3 /utf-8 /validate-charset /sdl /std:c11 /D NDEBUG")
    set(CMAKE_CXX_FLAGS_DEBUG  "/MP /Zc:wchar_t /Zc:inline /Zc:preprocessor /MTd /Od /Zi /W3 /utf-8 /validate-charset /sdl /std:c11 /RTC1")
    set(CMAKE_C_FLAGS_RELEASE  "/MP /Zc:wchar_t /Zc:inline /Zc:preprocessor /MT /Ox /Ob2 /Oy /Oi /Ot /GL /Qpar /W3 /utf-8 /validate-charset /std:c11 /TC /sdl /D NDEBUG")
    set(CMAKE_C_FLAGS_DEBUG  "/MP /Zc:wchar_t /Zc:inline /Zc:preprocessor /MTd /Od /Zi /W3 /utf-8 /validate-charset /std:c11 /TC /sdl /RTC1")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    else()
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /LTCG")
        set(CMAKE_STATIC_LINKER_FLAGS "${CMAKE_STATIC_LINKER_FLAGS} /LTCG")
    endif()
elseif("${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    set(CMAKE_CXX_FLAGS_RELEASE  "/Zc:wchar_t /Zc:inline /MT /Ox /Ob2 /Oy /Oi /Ot /D NDEBUG")
    set(CMAKE_CXX_FLAGS_DEBUG  "/Zc:wchar_t /Zc:inline /MTd /Od /Zi /RTC1")
    set(CMAKE_C_FLAGS_RELEASE  "/Zc:wchar_t /Zc:inline /MT /Ox /Ob2 /Oy /Oi /Ot /D NDEBUG")
    set(CMAKE_C_FLAGS_DEBUG  "/Zc:wchar_t /Zc:inline /MTd /Od /Zi /RTC1")
elseif("${CMAKE_CXX_COMPILER_ID}" STREQUAL "AppleClang")
    set(CMAKE_CXX_FLAGS_RELEASE  "-march=haswell -Wall -Ofast -mtune=haswell -pthread -std=c++17")
    set(CMAKE_CXX_FLAGS_DEBUG  "-march=haswell -Wall -Og -mtune=haswell -pthread -gfull -glldb -std=c++17")
    set(CMAKE_C_FLAGS_RELEASE  "-march=haswell -Wall -Ofast -mtune=haswell -pthread -std=c11")
    set(CMAKE_C_FLAGS_DEBUG  "-march=haswell -Wall -Og -mtune=haswell -pthread -gfull -glldb -std=c11")
else()
    set(CMAKE_CXX_FLAGS_RELEASE  "-march=haswell -Wall -Ofast -mtune=haswell -mfpmath=both -pthread -std=c++11")
    set(CMAKE_CXX_FLAGS_DEBUG  "-march=haswell -Wall -Og -ggdb -mtune=haswell -mfpmath=both -pthread -std=c++11")
	set(CMAKE_C_FLAGS_RELEASE  "-march=haswell -Wall -Ofast -mtune=haswell -mfpmath=both -pthread -std=c11")
    set(CMAKE_C_FLAGS_DEBUG  "-march=haswell -Wall -Og -ggdb -mtune=haswell -mfpmath=both -pthread -std=c11")
endif()

include_directories(${SRC}/${LIB})
include_directories(${SRC}/${PCRE})
include_directories(${SRC}/${GROK})

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC" OR "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    include_directories($ENV{APR_HOME16}/${APR}/include)
    include_directories($ENV{APR_HOME16}/${APR_UTIL}/include)
else()
    include_directories($ENV{APR_HOME}/include/apr-1.0)
#    include_directories($ENV{APR_HOME}/include/apr-1)
endif()

add_definitions( -DPCRE2_STATIC )
add_definitions( -DPCRE2_CODE_UNIT_WIDTH=8 )
add_definitions( -DLINK_SIZE=2 )
add_definitions( -DHAVE_CONFIG_H )
add_definitions( -DAPR_DECLARE_STATIC )
add_definitions( -DAPU_DECLARE_STATIC )

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
        "${SRC}/${TST}/trim_tests.cpp")

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
        ${SRC}/${PCRE}/pcre2_valid_utf.c
        ${SRC}/${PCRE}/pcre2_xclass.c
        )

add_library(pcre STATIC ${PCRE_SOURCE_FILES})

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC" OR "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        link_directories(
                "${APR_X64}/${LIBD}"
                "${APR_UTIL_X64}/${LIBD}"
        )
    else()
        link_directories(
                "${APR_X64}/${LIBR}"
                "${APR_UTIL_X64}/${LIBR}"
        )
    endif()
else()
#    link_directories(
#                "$ENV{APR_HOME}/apr/lib/"
#                "$ENV{APR_HOME}/apr-util/lib/"
#    )
    link_directories(
                "$ENV{APR_HOME}/lib/x86_64-linux-gnu/"
    )
endif()


if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC" OR "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    set(FLEX win_flex.exe --fast --wincompat --outfile="${GEN}/grok.flex.c" grok.lex)
    set(BISON win_bison.exe --output="${GEN}/grok.tab.c" -dy grok.y)
else()
    set(FLEX flex --fast --outfile="${GEN}/grok.flex.c" grok.lex)
    set(BISON bison --output="${GEN}/grok.tab.c" -dy grok.y)
endif()

add_custom_target(generate_parser
        COMMAND ${FLEX}
        COMMAND ${BISON}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${SRC}/${GROK})

file(GLOB GROK_GENERATED_FILES
        CONFIGURE_DEPENDS *.c
        "${SRC}/${GROK}/${GEN}/*.c"
        )

add_executable(grok ${GROK_SOURCE_FILES} ${GROK_GENERATED_FILES} ${LIB_SOURCE_FILES})
add_library(libgrok ${GROK_GENERATED_FILES} ${LIB_SOURCE_FILES})
add_executable(_tst ${TST_SOURCE_FILES} ${LIB_SOURCE_FILES})

add_dependencies(grok generate_parser)
add_dependencies(libgrok generate_parser)

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC" OR "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
    target_link_libraries(grok ws2_32 rpcrt4 apr-1 aprutil-1 pcre strsafe)
    target_link_libraries(libgrok ws2_32 rpcrt4 apr-1 aprutil-1 pcre strsafe)
    target_link_libraries(_tst ws2_32 rpcrt4 apr-1 aprutil-1 pcre strsafe)
else()
    target_link_libraries(grok m libapr-1.a libaprutil-1.a pcre)
    target_link_libraries(_tst m libapr-1.a libaprutil-1.a pcre)
    target_link_libraries(libgrok m libapr-1.a libaprutil-1.a pcre)
endif()

install(TARGETS grok DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/bin)
install(FILES ${PATTERN_FILES} DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/bin)