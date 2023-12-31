BUILD_CONF=Release
ABI=$1
[[ -n "${ABI}" ]] || ABI=none
BUILD_DIR=build-${ABI}-${BUILD_CONF}
LIB_INSTALL_SRC=./external_lib/src
LIB_INSTALL_PREFIX=./external_lib/lib
CC_FLAGS="zig cc -target x86_64-macos-${ABI}"
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

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

EXTERNAL_PREFIX=$(realpath ${LIB_INSTALL_PREFIX})
EXPAT_PREFIX=${EXTERNAL_PREFIX}/expat
APR_PREFIX=${EXTERNAL_PREFIX}/apr
echo ${EXPAT_PREFIX}
echo ${APR_PREFIX}

(cd ${LIB_INSTALL_SRC} && [[ -f "${EXPAT_SRC}.tar.gz" ]] || curl -O -L https://github.com/libexpat/libexpat/releases/download/R_2_5_0/${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${EXPAT_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" CXXFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=${EXPAT_PREFIX} && make -j && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_SRC}.tar.gz" ]] || curl -O -L https://dlcdn.apache.org/apr/${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=${APR_PREFIX} && make -j && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_UTIL_SRC}.tar.gz" ]] || curl -O -L https://dlcdn.apache.org/apr/${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_UTIL_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=${APR_PREFIX} --with-apr=${APR_PREFIX} --with-expat=${EXPAT_PREFIX} && make -j && make install)

APR_INCLUDE="${EXTERNAL_PREFIX}/apr/include/apr-1" \
APR_LINK="${EXTERNAL_PREFIX}/apr/lib" \
cmake -DCMAKE_BUILD_TYPE=${BUILD_CONF} -B ${BUILD_DIR}
cmake --build ${BUILD_DIR}
ctest --test-dir ${BUILD_DIR} -VV
(cd ${BUILD_DIR} && cpack --config CPackConfig.cmake)