cmake_minimum_required(VERSION 3.7)
project(grok)

set(SRC src)
set(GROK grok)
set(LIB srclib)
set(PCRE srclib)
set(ARGTABLE argtable)

include_directories(${SRC}/${LIB})
include_directories(${SRC}/${ARGTABLE})
include_directories(${SRC}/${PCRE})
include_directories(${SRC}/${GROK})
include_directories($ENV{APR_HOME14}/apr/include)
include_directories($ENV{APR_HOME14}/apr-iconv/include)
include_directories($ENV{APR_HOME14}/apr-util/include)

file(GLOB GROK_SOURCE_FILES "${SRC}/${GROK}/*.c")
file(GLOB LIB_SOURCE_FILES "${SRC}/${LIB}/*.c")
file(GLOB PCRE_SOURCE_FILES "${SRC}/${PCRE}/*.c")

add_executable(grok ${GROK_SOURCE_FILES} ${LIB_SOURCE_FILES})