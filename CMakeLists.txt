cmake_minimum_required(VERSION 3.7)
project(grok)

set(SRC src)
set(GROK grok)
set(LIB srclib)
set(PCRE pcre)
set(ARGTABLE argtable)
set(APR apr)
set(APR_ICONV apr-iconv)
set(APR_UTIL apr-util)
set(LIBD LibD)
set(LIBR LibR)
set(APR_X64 "$ENV{APR_HOME14}/${APR}/x64")
set(APR_X86 "$ENV{APR_HOME14}/${APR}")
set(APR_ICONV_X64 "$ENV{APR_HOME14}/${APR_ICONV}/x64")
set(APR_ICONV_X86 "$ENV{APR_HOME14}/${APR_ICONV}")
set(APR_UTIL_X64 "$ENV{APR_HOME14}/${APR_UTIL}/x64")
set(APR_UTIL_X86 "$ENV{APR_HOME14}/${APR_UTIL}")

IF("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
    set(CMAKE_CXX_FLAGS_RELEASE  "/MP /Zc:wchar_t /Zc:inline /MT /Ox /Ob2 /Oy /Oi /Ot /GL /D NDEBUG")
    set(CMAKE_C_FLAGS_RELEASE  "/MP /Zc:wchar_t /Zc:inline /MT /Ox /Ob2 /Oy /Oi /Ot /GL /D NDEBUG")
    set(CMAKE_CXX_FLAGS_DEBUG  "/MP /Zc:wchar_t /Zc:inline /MTd /Od")
    set(CMAKE_C_FLAGS_DEBUG  "/MP /Zc:wchar_t /Zc:inline /MTd /Od")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    else()
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /LTCG")
        set(CMAKE_STATIC_LINKER_FLAGS "${CMAKE_STATIC_LINKER_FLAGS} /LTCG")
    endif()
ELSE()
    set(CMAKE_CXX_FLAGS_RELEASE  "-march=corei7-avx -Wall -Ofast -mtune=corei7-avx -mfpmath=both -save-temps -fverbose-asm")
    set(CMAKE_CXX_FLAGS_DEBUG  "-march=corei7-avx -Wall -mtune=corei7-avx -mfpmath=both -save-temps -fverbose-asm")
ENDIF()

include_directories(${SRC}/${LIB})
include_directories(${SRC}/${ARGTABLE})
include_directories(${SRC}/${PCRE})
include_directories(${SRC}/${GROK})
include_directories($ENV{APR_HOME14}/${APR}/include)
include_directories($ENV{APR_HOME14}/${APR_ICONV}/include)
include_directories($ENV{APR_HOME14}/${APR_UTIL}/include)

add_definitions( -DPCRE2_STATIC )
add_definitions( -DPCRE2_CODE_UNIT_WIDTH=8 )
add_definitions( -DLINK_SIZE=2 )
add_definitions( -DHAVE_CONFIG_H )
add_definitions( -DAPR_DECLARE_STATIC )
add_definitions( -DAPU_DECLARE_STATIC )
add_definitions( -DAPI_DECLARE_STATIC )

IF("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
add_definitions( -D__STDC_VERSION__=199901L )
ENDIF()

file(GLOB GROK_SOURCE_FILES "${SRC}/${GROK}/*.c")
file(GLOB LIB_SOURCE_FILES "${SRC}/${LIB}/*.c")
file(GLOB ARGTABLE_SOURCE_FILES "${SRC}/${ARGTABLE}/*.c")
file(GLOB PATTERN_FILES "patterns/*.patterns")

SET(PCRE_SOURCE_FILES
        ${SRC}/${PCRE}/pcre2_auto_possess.c
        ${SRC}/${PCRE}/pcre2_chartables.c
        ${SRC}/${PCRE}/pcre2_compile.c
        ${SRC}/${PCRE}/pcre2_config.c
        ${SRC}/${PCRE}/pcre2_context.c
        ${SRC}/${PCRE}/pcre2_dfa_match.c
        ${SRC}/${PCRE}/pcre2_error.c
        ${SRC}/${PCRE}/pcre2_find_bracket.c
        ${SRC}/${PCRE}/pcre2_jit_compile.c
        ${SRC}/${PCRE}/pcre2_maketables.c
        ${SRC}/${PCRE}/pcre2_match.c
        ${SRC}/${PCRE}/pcre2_match_data.c
        ${SRC}/${PCRE}/pcre2_newline.c
        ${SRC}/${PCRE}/pcre2_ord2utf.c
        ${SRC}/${PCRE}/pcre2_pattern_info.c
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

ADD_LIBRARY(argtable STATIC ${ARGTABLE_SOURCE_FILES})
ADD_LIBRARY(pcre STATIC ${PCRE_SOURCE_FILES})

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    link_directories(
            "${APR_X64}/${LIBD}"
            "${APR_ICONV_X64}/${LIBD}"
            "${APR_UTIL_X64}/${LIBD}"
    )
else()
    link_directories(
            "${APR_X64}/${LIBR}"
            "${APR_ICONV_X64}/${LIBR}"
            "${APR_UTIL_X64}/${LIBR}"
    )
endif()

ADD_EXECUTABLE(grok ${GROK_SOURCE_FILES} ${LIB_SOURCE_FILES})

TARGET_LINK_LIBRARIES(grok ws2_32 apr-1 apriconv-1 aprutil-1 pcre strsafe argtable)

install(TARGETS grok DESTINATION bin)
install(FILES ${PATTERN_FILES} DESTINATION bin)