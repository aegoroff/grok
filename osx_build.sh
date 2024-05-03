BUILD_CONF=Release
BUILD_DIR=build-${BUILD_CONF}
LIB_INSTALL_SRC=./external_lib/src
LIB_INSTALL_PREFIX=./external_lib/lib
CC_FLAGS="zig cc"
AR_FLAGS="zig ar"
RANLIB_FLAGS="zig ranlib"
CFLAGS="-Ofast -march=haswell -mtune=haswell"
APR_SRC=apr-1.7.4
APR_UTIL_SRC=apr-util-1.6.3
EXPAT_VER=2.6.2
EXPAT_SRC=expat-${EXPAT_VER}
PCRE_SRC=pcre2-10.43

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
PCRE_PREFIX=${EXTERNAL_PREFIX}/pcre
echo ${EXPAT_PREFIX}
echo ${APR_PREFIX}

(cd ${LIB_INSTALL_SRC} && [[ -f "${EXPAT_SRC}.tar.gz" ]] || curl -O -L https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VER//./_}/${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${EXPAT_SRC} && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" CXXFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=${EXPAT_PREFIX} && make -j $(sysctl -n hw.ncpu) && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_SRC}.tar.gz" ]] || curl -O -L https://dlcdn.apache.org/apr/${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_SRC} && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=${APR_PREFIX} && make -j $(sysctl -n hw.ncpu) && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_UTIL_SRC}.tar.gz" ]] || curl -O -L https://dlcdn.apache.org/apr/${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_UTIL_SRC} && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=${APR_PREFIX} --with-apr=${APR_PREFIX} --with-expat=${EXPAT_PREFIX} && make -j $(sysctl -n hw.ncpu) && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${PCRE_SRC}.tar.gz" ]] || wget https://github.com/PCRE2Project/pcre2/releases/download/${PCRE_SRC}/${PCRE_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xzf ${PCRE_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${PCRE_SRC} && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" CXXFLAGS="${CFLAGS}" ./configure --prefix=${PCRE_PREFIX} --enable-shared=no && make -j $(sysctl -n hw.ncpu) && make install)

cmake -DCMAKE_BUILD_TYPE=${BUILD_CONF} -B ${BUILD_DIR}
cmake --build ${BUILD_DIR} --parallel $(sysctl -n hw.ncpu)
ctest --test-dir ${BUILD_DIR} -VV
(cd ${BUILD_DIR} && cpack --config CPackConfig.cmake)
