cmake_minimum_required(VERSION 3.2)
project(grok)

set(SRC src)
set(GROK grok)
set(LIB srclib)
set(PCRE pcre)
set(APR apr)
set(APR_UTIL apr-util)
set(LIBD Debug)
set(LIBR Release)
set(APR_X64 "$ENV{APR_HOME16}/${APR}/x64")
set(APR_X86 "$ENV{APR_HOME16}/${APR}/x86")
set(APR_UTIL_X64 "$ENV{APR_HOME16}/${APR_UTIL}/x64")
set(APR_UTIL_X86 "$ENV{APR_HOME16}/${APR_UTIL}/x86")

set (CMAKE_C_STANDARD 99)

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    set(CMAKE_CXX_FLAGS_RELEASE  "/MP /Zc:wchar_t /Zc:inline /MT /Ox /Ob2 /Oy /Oi /Ot /GL /D NDEBUG")
    set(CMAKE_CXX_FLAGS_DEBUG  "/MP /Zc:wchar_t /Zc:inline /MTd /Od /RTC1")
    set(CMAKE_C_FLAGS_RELEASE  "/MP /Zc:wchar_t /Zc:inline /MT /Ox /Ob2 /Oy /Oi /Ot /GL /D NDEBUG")
    set(CMAKE_C_FLAGS_DEBUG  "/MP /Zc:wchar_t /Zc:inline /MTd /Od /RTC1")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    else()
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /LTCG")
        set(CMAKE_STATIC_LINKER_FLAGS "${CMAKE_STATIC_LINKER_FLAGS} /LTCG")
    endif()
else()
    set(CMAKE_CXX_FLAGS_RELEASE  "-march=corei7-avx -Wall -Ofast -mtune=corei7-avx -mfpmath=both -save-temps -fverbose-asm")
    set(CMAKE_CXX_FLAGS_DEBUG  "-march=corei7-avx -Wall -mtune=corei7-avx -mfpmath=both -save-temps -fverbose-asm")
	set(CMAKE_C_FLAGS_RELEASE  "-march=corei7-avx -Wall -Ofast -mtune=corei7-avx -mfpmath=both -save-temps -fverbose-asm")
    set(CMAKE_C_FLAGS_DEBUG  "-march=corei7-avx -Wall -mtune=corei7-avx -mfpmath=both -save-temps -fverbose-asm")
endif()

include_directories(${SRC}/${LIB})
include_directories(${SRC}/${PCRE})
include_directories(${SRC}/${GROK})
include_directories($ENV{APR_HOME16}/${APR}/include)
include_directories($ENV{APR_HOME16}/${APR_UTIL}/include)

add_definitions( -DPCRE2_STATIC )
add_definitions( -DPCRE2_CODE_UNIT_WIDTH=8 )
add_definitions( -DLINK_SIZE=2 )
add_definitions( -DHAVE_CONFIG_H )
add_definitions( -DAPR_DECLARE_STATIC )
add_definitions( -DAPU_DECLARE_STATIC )

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
add_definitions( -D__STDC_VERSION__=199901L )
endif()

file(GLOB GROK_SOURCE_FILES "${SRC}/${GROK}/*.c")
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

add_executable(grok ${GROK_SOURCE_FILES} ${LIB_SOURCE_FILES})

target_link_libraries(grok ws2_32 rpcrt4 apr-1 aprutil-1 pcre strsafe)

install(TARGETS grok DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/bin)
install(FILES ${PATTERN_FILES} DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/bin)