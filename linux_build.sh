BUILD_CONF=Release
ABI=$1
OS=$2
ARCH=$3
[[ -n "${ABI}" ]] || ABI=musl
[[ -n "${OS}" ]] || OS=linux
[[ -n "${ARCH}" ]] || ARCH=x86_64
BUILD_DIR=build-${ARCH}-${OS}-${ABI}-${BUILD_CONF}
LIB_INSTALL_SRC=./external_lib/src
LIB_INSTALL_PREFIX=./external_lib/lib
CC_FLAGS="zig cc -target ${ARCH}-${OS}-${ABI}"
APR_SRC=apr-1.7.4
APR_UTIL_SRC=apr-util-1.6.3
EXPAT_SRC=expat-2.5.0

if [[ "${ARCH}" = "x86_64" ]]; then
    CFLAGS="-Ofast -march=haswell -mtune=haswell"
else
    CFLAGS="-Ofast"
fi

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

if [[ "${ARCH}" = "x86_64" ]]; then
    if [[ "${ABI}" = "musl" ]]; then
        TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-linux-musl.cmake)"
    fi
    if [[ "${ABI}" = "none" ]]; then
        TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-macos-none.cmake)"
    fi
fi
if [[ "${ARCH}" = "aarch64" ]]; then
    if [[ "${OS}" = "linux" ]]; then
        TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-aarch64-linux-gnu.cmake)"
    fi
    if [[ "${OS}" = "macos" ]]; then
        TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-aarch64-macos-none.cmake)"
    fi
fi


(cd ${LIB_INSTALL_SRC} && [[ -f "${EXPAT_SRC}.tar.gz" ]] || wget https://github.com/libexpat/libexpat/releases/download/R_2_5_0/${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xzf ${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${EXPAT_SRC} && AR="zig ar" RANLIB="zig ranlib" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" CXXFLAGS="${CFLAGS}" ./configure --host=x86_64-linux --enable-shared=no --prefix=${EXPAT_PREFIX} && make -j && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xzf ${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_SRC} && AR="zig ar" RANLIB="zig ranlib" CC="${CC_FLAGS}" CFLAGS="${CFLAGS} -Wno-implicit-function-declaration -Wno-int-conversion" ./configure ac_cv_file__dev_zero=yes apr_cv_process_shared_works=yes apr_cv_mutex_robust_shared=yes apr_cv_tcp_nodelay_with_cork=yes --host=x86_64-linux --enable-shared=no --prefix=${APR_PREFIX} && make -j && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_UTIL_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xzf ${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_UTIL_SRC} && AR="zig ar" RANLIB="zig ranlib" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --host=x86_64-linux --enable-shared=no --prefix=${APR_PREFIX} --with-apr=${APR_PREFIX} --with-expat=${EXPAT_PREFIX} && make -j && make install)

APR_INCLUDE="${EXTERNAL_PREFIX}/apr/include/apr-1" \
APR_LINK="${EXTERNAL_PREFIX}/apr/lib" \
cmake -DCMAKE_BUILD_TYPE=${BUILD_CONF} -B ${BUILD_DIR} ${TOOLCHAIN}
cmake --build ${BUILD_DIR} --verbose
ctest --test-dir ${BUILD_DIR} -VV
(cd ${BUILD_DIR} && cpack --config CPackConfig.cmake)