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
set(APRSRC ${SRC}/${APR}/)
set(APRUSRC ${SRC}/${APR_UTIL}/)

SET(MIN_WINDOWS_VER             "Vista"
        CACHE STRING "Minimum Windows version")

set (CMAKE_C_STANDARD 99)

SET(apr_have_ipv6_10 0)
SET(apu_have_crypto_10 0)
SET(apu_have_apr_iconv_10 0) # not yet implemented
SET(apr_has_ldap_10 0)

IF(APR_HAVE_IPV6)
    SET(apr_have_ipv6_10 1)
ENDIF()

IF(APU_HAVE_CRYPTO)
    SET(apu_have_crypto_10 1)
ENDIF()

IF(APR_HAS_LDAP)
    SET(apr_has_ldap_10 1)
ENDIF()

IF("${MIN_WINDOWS_VER}" STREQUAL "")
    SET(win32_winnt_str "0x0600")
ELSEIF(${MIN_WINDOWS_VER} STREQUAL "Vista")
    SET(win32_winnt_str "0x0600")
ELSEIF(${MIN_WINDOWS_VER} STREQUAL "Windows7")
    SET(win32_winnt_str "0x0601")
ELSE()
    SET(win32_winnt_str ${MIN_WINDOWS_VER})
ENDIF()

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

add_definitions( -DPCRE2_STATIC )
add_definitions( -DPCRE2_CODE_UNIT_WIDTH=8 )
add_definitions( -DLINK_SIZE=2 )
add_definitions( -DHAVE_CONFIG_H )
add_definitions( -DAPR_DECLARE_STATIC )
add_definitions( -DAPU_DECLARE_STATIC )

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "MSVC")
add_definitions( -D__STDC_VERSION__=199901L )
endif()

CONFIGURE_FILE(${APRSRC}include/apr.hwc
        ${PROJECT_BINARY_DIR}/apr.h)

ADD_EXECUTABLE(gen_test_char ${APRSRC}tools/gen_test_char.c)
#GET_TARGET_PROPERTY(GEN_TEST_CHAR_EXE gen_test_char LOCATION)
ADD_CUSTOM_COMMAND(
        COMMENT "Generating character tables, apr_escape_test_char.h, for current locale"
        DEPENDS gen_test_char
        COMMAND gen_test_char > ${PROJECT_BINARY_DIR}/apr_escape_test_char.h
        OUTPUT ${PROJECT_BINARY_DIR}/apr_escape_test_char.h
)
ADD_CUSTOM_TARGET(
        test_char_header ALL
        DEPENDS ${PROJECT_BINARY_DIR}/apr_escape_test_char.h
)

# Generated .h files are stored in PROJECT_BINARY_DIR, not the
# source tree.
#
# BROKEN: not searching PROJECT_BINARY_DIR first, so you have to
#         manually delete apr.h in PROJECT_SOURCE_DIR/include if
#         you've generated apr.h before using a different build

SET(APR_INCLUDE_DIRECTORIES
        ${PROJECT_BINARY_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/${APRSRC}include
        ${CMAKE_CURRENT_SOURCE_DIR}/${APRSRC}include/arch/win32
        ${CMAKE_CURRENT_SOURCE_DIR}/${APRSRC}include/arch/unix
        ${CMAKE_CURRENT_SOURCE_DIR}/${APRSRC}include/private
        )

SET(APR_SYSTEM_LIBS
        ws2_32
        mswsock
        rpcrt4
        )

CONFIGURE_FILE(${APRUSRC}include/apu.hwc
        ${PROJECT_BINARY_DIR}/apu.h)
CONFIGURE_FILE(${APRUSRC}include/apr_ldap.hwc
        ${PROJECT_BINARY_DIR}/apr_ldap.h)
# "COPYONLY" just because anything else isn't implemented ;)
CONFIGURE_FILE(${APRUSRC}include/private/apu_config.hw
        ${PROJECT_BINARY_DIR}/apu_config.h
        COPYONLY)
CONFIGURE_FILE(${APRUSRC}include/private/apu_select_dbm.hw
        ${PROJECT_BINARY_DIR}/apu_select_dbm.h
        COPYONLY)
CONFIGURE_FILE(${APRUSRC}include/apu_want.hw
        ${PROJECT_BINARY_DIR}/apu_want.h
        COPYONLY)

SET(XMLLIB_INCLUDE_DIR   ${CMAKE_CURRENT_SOURCE_DIR}/${APRUSRC}xml/expat/lib)

SET(APRU_INCLUDE_DIRECTORIES
        ${CMAKE_CURRENT_SOURCE_DIR}/${APRUSRC}include
        ${CMAKE_CURRENT_SOURCE_DIR}/${APRUSRC}include/private
        )

INCLUDE_DIRECTORIES(${APR_INCLUDE_DIRECTORIES} ${XMLLIB_INCLUDE_DIR} ${APRU_INCLUDE_DIRECTORIES})

SET(APR_PUBLIC_HEADERS_STATIC
        ${APRSRC}include/apr_allocator.h
        ${APRSRC}include/apr_atomic.h
        ${APRSRC}include/apr_dso.h
        ${APRSRC}include/apr_env.h
        ${APRSRC}include/apr_errno.h
        ${APRSRC}include/apr_escape.h
        ${APRSRC}include/apr_file_info.h
        ${APRSRC}include/apr_file_io.h
        ${APRSRC}include/apr_fnmatch.h
        ${APRSRC}include/apr_general.h
        ${APRSRC}include/apr_getopt.h
        ${APRSRC}include/apr_global_mutex.h
        ${APRSRC}include/apr_hash.h
        ${APRSRC}include/apr_inherit.h
        ${APRSRC}include/apr_lib.h
        ${APRSRC}include/apr_mmap.h
        ${APRSRC}include/apr_network_io.h
        ${APRSRC}include/apr_poll.h
        ${APRSRC}include/apr_pools.h
        ${APRSRC}include/apr_portable.h
        ${APRSRC}include/apr_proc_mutex.h
        ${APRSRC}include/apr_random.h
        ${APRSRC}include/apr_ring.h
        ${APRSRC}include/apr_shm.h
        ${APRSRC}include/apr_signal.h
        ${APRSRC}include/apr_skiplist.h
        ${APRSRC}include/apr_strings.h
        ${APRSRC}include/apr_support.h
        ${APRSRC}include/apr_tables.h
        ${APRSRC}include/apr_thread_cond.h
        ${APRSRC}include/apr_thread_mutex.h
        ${APRSRC}include/apr_thread_proc.h
        ${APRSRC}include/apr_thread_rwlock.h
        ${APRSRC}include/apr_time.h
        ${APRSRC}include/apr_user.h
        ${APRSRC}include/apr_version.h
        ${APRSRC}include/apr_want.h
        )
SET(APR_PUBLIC_HEADERS_GENERATED
        ${PROJECT_BINARY_DIR}/apr.h
        )

SET(APR_SOURCES
        ${APRSRC}atomic/win32/apr_atomic.c
        ${APRSRC}dso/win32/dso.c
        ${APRSRC}encoding/apr_escape.c
        ${APRSRC}file_io/unix/copy.c
        ${APRSRC}file_io/unix/fileacc.c
        ${APRSRC}file_io/unix/filepath_util.c
        ${APRSRC}file_io/unix/fullrw.c
        ${APRSRC}file_io/unix/mktemp.c
        ${APRSRC}file_io/unix/tempdir.c
        ${APRSRC}file_io/win32/buffer.c
        ${APRSRC}file_io/win32/dir.c
        ${APRSRC}file_io/win32/filedup.c
        ${APRSRC}file_io/win32/filepath.c
        ${APRSRC}file_io/win32/filestat.c
        ${APRSRC}file_io/win32/filesys.c
        ${APRSRC}file_io/win32/flock.c
        ${APRSRC}file_io/win32/open.c
        ${APRSRC}file_io/win32/pipe.c
        ${APRSRC}file_io/win32/readwrite.c
        ${APRSRC}file_io/win32/seek.c
        ${APRSRC}locks/win32/proc_mutex.c
        ${APRSRC}locks/win32/thread_cond.c
        ${APRSRC}locks/win32/thread_mutex.c
        ${APRSRC}locks/win32/thread_rwlock.c
        ${APRSRC}memory/unix/apr_pools.c
        ${APRSRC}misc/unix/errorcodes.c
        ${APRSRC}misc/unix/getopt.c
        ${APRSRC}misc/unix/otherchild.c
        ${APRSRC}misc/unix/version.c
        ${APRSRC}misc/win32/charset.c
        ${APRSRC}misc/win32/env.c
        ${APRSRC}misc/win32/internal.c
        ${APRSRC}misc/win32/misc.c
        ${APRSRC}misc/win32/rand.c
        ${APRSRC}misc/win32/start.c
        ${APRSRC}misc/win32/utf8.c
        ${APRSRC}mmap/unix/common.c
        ${APRSRC}mmap/win32/mmap.c
        ${APRSRC}network_io/unix/inet_ntop.c
        ${APRSRC}network_io/unix/inet_pton.c
        ${APRSRC}network_io/unix/multicast.c
        ${APRSRC}network_io/unix/sockaddr.c
        ${APRSRC}network_io/unix/socket_util.c
        ${APRSRC}network_io/win32/sendrecv.c
        ${APRSRC}network_io/win32/sockets.c
        ${APRSRC}network_io/win32/sockopt.c
        ${APRSRC}passwd/apr_getpass.c
        ${APRSRC}poll/unix/poll.c
        ${APRSRC}poll/unix/pollcb.c
        ${APRSRC}poll/unix/pollset.c
        ${APRSRC}poll/unix/select.c
        ${APRSRC}random/unix/apr_random.c
        ${APRSRC}random/unix/sha2.c
        ${APRSRC}random/unix/sha2_glue.c
        ${APRSRC}shmem/win32/shm.c
        ${APRSRC}strings/apr_cpystrn.c
        ${APRSRC}strings/apr_fnmatch.c
        ${APRSRC}strings/apr_snprintf.c
        ${APRSRC}strings/apr_strings.c
        ${APRSRC}strings/apr_strnatcmp.c
        ${APRSRC}strings/apr_strtok.c
        ${APRSRC}tables/apr_hash.c
        ${APRSRC}tables/apr_skiplist.c
        ${APRSRC}tables/apr_tables.c
        ${APRSRC}threadproc/win32/proc.c
        ${APRSRC}threadproc/win32/signals.c
        ${APRSRC}threadproc/win32/thread.c
        ${APRSRC}threadproc/win32/threadpriv.c
        ${APRSRC}time/win32/time.c
        ${APRSRC}time/win32/timestr.c
        ${APRSRC}user/win32/groupinfo.c
        ${APRSRC}user/win32/userinfo.c
        )

SET(APRU_PUBLIC_HEADERS_STATIC
        ${APRUSRC}include/apr_anylock.h
        ${APRUSRC}include/apr_base64.h
        ${APRUSRC}include/apr_buckets.h
        ${APRUSRC}include/apr_crypto.h
        ${APRUSRC}include/apr_date.h
        ${APRUSRC}include/apr_dbd.h
        ${APRUSRC}include/apr_dbm.h
        ${APRUSRC}include/apr_hooks.h
        ${APRUSRC}include/apr_ldap_init.h
        ${APRUSRC}include/apr_ldap_option.h
        ${APRUSRC}include/apr_ldap_rebind.h
        ${APRUSRC}include/apr_ldap_url.h
        ${APRUSRC}include/apr_md4.h
        ${APRUSRC}include/apr_md5.h
        ${APRUSRC}include/apr_memcache.h
        ${APRUSRC}include/apr_optional.h
        ${APRUSRC}include/apr_optional_hooks.h
        ${APRUSRC}include/apr_queue.h
        ${APRUSRC}include/apr_reslist.h
        ${APRUSRC}include/apr_rmm.h
        ${APRUSRC}include/apr_sdbm.h
        ${APRUSRC}include/apr_sha1.h
        ${APRUSRC}include/apr_strmatch.h
        ${APRUSRC}include/apr_thread_pool.h
        ${APRUSRC}include/apr_uri.h
        ${APRUSRC}include/apr_uuid.h
        ${APRUSRC}include/apr_xlate.h
        ${APRUSRC}include/apr_xml.h
        ${APRUSRC}include/apu_errno.h
        ${APRUSRC}include/apu_version.h
        )

# apu_config.h and apu_select_dbm.h are private
SET(APRU_PUBLIC_HEADERS_GENERATED
        ${PROJECT_BINARY_DIR}/apu.h
        ${PROJECT_BINARY_DIR}/apr_ldap.h
        ${PROJECT_BINARY_DIR}/apu_want.h
        )

SET(APRU_SOURCES
        ${APRUSRC}buckets/apr_brigade.c
        ${APRUSRC}buckets/apr_buckets.c
        ${APRUSRC}buckets/apr_buckets_alloc.c
        ${APRUSRC}buckets/apr_buckets_eos.c
        ${APRUSRC}buckets/apr_buckets_file.c
        ${APRUSRC}buckets/apr_buckets_flush.c
        ${APRUSRC}buckets/apr_buckets_heap.c
        ${APRUSRC}buckets/apr_buckets_mmap.c
        ${APRUSRC}buckets/apr_buckets_pipe.c
        ${APRUSRC}buckets/apr_buckets_pool.c
        ${APRUSRC}buckets/apr_buckets_refcount.c
        ${APRUSRC}buckets/apr_buckets_simple.c
        ${APRUSRC}buckets/apr_buckets_socket.c
        ${APRUSRC}crypto/apr_crypto.c
        ${APRUSRC}crypto/apr_md4.c
        ${APRUSRC}crypto/apr_md5.c
        ${APRUSRC}crypto/apr_passwd.c
        ${APRUSRC}crypto/apr_sha1.c
        ${APRUSRC}crypto/crypt_blowfish.c
        ${APRUSRC}crypto/getuuid.c
        ${APRUSRC}crypto/uuid.c
        ${APRUSRC}dbd/apr_dbd.c
        ${APRUSRC}dbm/apr_dbm.c
        ${APRUSRC}dbm/apr_dbm_sdbm.c
        ${APRUSRC}dbm/sdbm/sdbm.c
        ${APRUSRC}dbm/sdbm/sdbm_hash.c
        ${APRUSRC}dbm/sdbm/sdbm_lock.c
        ${APRUSRC}dbm/sdbm/sdbm_pair.c
        ${APRUSRC}encoding/apr_base64.c
        ${APRUSRC}hooks/apr_hooks.c
        ${APRUSRC}memcache/apr_memcache.c
        ${APRUSRC}misc/apr_date.c
        ${APRUSRC}misc/apr_queue.c
        ${APRUSRC}misc/apr_reslist.c
        ${APRUSRC}misc/apr_rmm.c
        ${APRUSRC}misc/apr_thread_pool.c
        ${APRUSRC}misc/apu_dso.c
        ${APRUSRC}misc/apu_version.c
        ${APRUSRC}strmatch/apr_strmatch.c
        ${APRUSRC}uri/apr_uri.c
        ${APRUSRC}xlate/xlate.c
        ${APRUSRC}xml/apr_xml.c
        )

SET(EXPAT_SOURCES
        ${APRUSRC}xml/expat/lib/xmlrole.c
        ${APRUSRC}xml/expat/lib/xmltok.c
        ${APRUSRC}xml/expat/lib/xmlparse.c
        )


file(GLOB GROK_SOURCE_FILES "${SRC}/${GROK}/*.c")
file(GLOB LIB_SOURCE_FILES "${SRC}/${LIB}/*.c")
file(GLOB PATTERN_FILES "patterns/*.patterns")

set(PCRE_SOURCE_FILES
        ${SRC}/${PCRE}/pcre2_auto_possess.c
        ${SRC}/${PCRE}/pcre2_chartables.c
        ${SRC}/${PCRE}/pcre2_compile.c
        ${SRC}/${PCRE}/pcre2_config.c
        ${SRC}/${PCRE}/pcre2_context.c
        ${SRC}/${PCRE}/pcre2_convert.c
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

add_library(pcre STATIC ${PCRE_SOURCE_FILES})

ADD_LIBRARY(apr-1 STATIC ${APR_SOURCES} ${APR_PUBLIC_HEADERS_GENERATED})
SET(install_targets ${install_targets} apr-1)
TARGET_LINK_LIBRARIES(apr-1 ${APR_SYSTEM_LIBS})
SET_TARGET_PROPERTIES(apr-1 PROPERTIES COMPILE_DEFINITIONS "APR_DECLARE_STATIC;WINNT")
ADD_DEPENDENCIES(apr-1 test_char_header)

# static expat (not installed)
ADD_LIBRARY(libexpat STATIC ${EXPAT_SOURCES})
SET_TARGET_PROPERTIES(libexpat PROPERTIES COMPILE_DEFINITIONS "XML_STATIC;COMPILED_FROM_DSP")

ADD_LIBRARY(aprutil-1 STATIC ${APRU_SOURCES} ${APRU_PUBLIC_HEADERS_GENERATED})
SET(install_targets ${install_targets} aprutil-1)
TARGET_LINK_LIBRARIES(aprutil-1 apr-1 libexpat)
SET_TARGET_PROPERTIES(aprutil-1 PROPERTIES COMPILE_DEFINITIONS "APU_DECLARE_STATIC;APR_DECLARE_STATIC;APU_DSO_MODULE_BUILD;XML_STATIC")

add_executable(grok ${GROK_SOURCE_FILES} ${LIB_SOURCE_FILES})

target_link_libraries(grok ws2_32 rpcrt4 apr-1 aprutil-1 pcre strsafe)

install(TARGETS grok DESTINATION bin)
install(FILES ${PATTERN_FILES} DESTINATION bin)