BUILD_CONF=Release
ABI=$1
OS=$2
[[ -n "${ABI}" ]] || ABI=musl
[[ -n "${OS}" ]] || OS=linux
BUILD_DIR=build-${OS}-${ABI}-${BUILD_CONF}
LIB_INSTALL_SRC=./external_lib/src
LIB_INSTALL_PREFIX=./external_lib/lib
CC_FLAGS="zig cc -target x86_64-${OS}-${ABI}"
CFLAGS="-Ofast -march=haswell -mtune=haswell"
APR_SRC=apr-1.7.4
APR_UTIL_SRC=apr-util-1.6.3
EXPAT_SRC=expat-2.5.0

[[ -d "${LIB_INSTALL_SRC}" ]] || mkdir -p ${LIB_INSTALL_SRC}
[[ -d "${LIB_INSTALL_PREFIX}" ]] && rm -rf ${LIB_INSTALL_PREFIX}
[[ -d "${LIB_INSTALL_PREFIX}" ]] || mkdir -p ${LIB_INSTALL_PREFIX}
[[ -d "${BUILD_DIR}" ]] && rm -rf ${BUILD_DIR}
[[ -d "${LIB_INSTALL_SRC}/${EXPAT_SRC}" ]] && rm -rf ${LIB_INSTALL_SRC}/${EXPAT_SRC}
[[ -d "${LIB_INSTALL_SRC}/${APR_SRC}" ]] && rm -rf ${LIB_INSTALL_SRC}/${APR_SRC}
[[ -d "${LIB_INSTALL_SRC}/${APR_UTIL_SRC}" ]] && rm -rf ${LIB_INSTALL_SRC}/${APR_UTIL_SRC}

EXTERNAL_PREFIX=$(realpath ${LIB_INSTALL_PREFIX})
EXPAT_PREFIX=${EXTERNAL_PREFIX}/expat
APR_PREFIX=${EXTERNAL_PREFIX}/apr
echo ${EXPAT_PREFIX}
echo ${APR_PREFIX}

if [[ "${ABI}" = "musl" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-linux-musl.cmake)"
fi
if [[ "${ABI}" = "none" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-macos-none.cmake)"
fi

(cd ${LIB_INSTALL_SRC} && [[ -f "${EXPAT_SRC}.tar.gz" ]] || wget https://github.com/libexpat/libexpat/releases/download/R_2_5_0/${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xzf ${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${EXPAT_SRC} && cmake ${TOOLCHAIN} -B ${BUILD_DIR} -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=${BUILD_CONF} -DEXPAT_BUILD_TESTS=False -DCMAKE_INSTALL_PREFIX=${EXPAT_PREFIX} && cmake --build ${BUILD_DIR} && cmake --install ${BUILD_DIR})

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xzf ${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS} -Wno-implicit-function-declaration -Wno-int-conversion" ./configure ac_cv_file__dev_zero=yes apr_cv_process_shared_works=yes apr_cv_mutex_robust_shared=yes apr_cv_tcp_nodelay_with_cork=yes --host=x86_64-linux --enable-shared=no --prefix=${APR_PREFIX} && make -j && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_UTIL_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xzf ${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_UTIL_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --host=x86_64-linux --enable-shared=no --prefix=${APR_PREFIX} --with-apr=${APR_PREFIX} --with-expat=${EXPAT_PREFIX} && make -j && make install)

APR_INCLUDE="${EXTERNAL_PREFIX}/apr/include/apr-1" \
APR_LINK="${EXTERNAL_PREFIX}/apr/lib" \
cmake -DCMAKE_BUILD_TYPE=${BUILD_CONF} -B ${BUILD_DIR} ${TOOLCHAIN}
cmake --build ${BUILD_DIR}
ctest --test-dir ${BUILD_DIR} -VV
(cd ${BUILD_DIR} && cpack --config CPackConfig.cmake)