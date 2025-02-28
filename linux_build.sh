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
AR_FLAGS="zig ar"
RANLIB_FLAGS="zig ranlib"
APR_SRC=apr-1.7.5
APR_UTIL_SRC=apr-util-1.6.3
EXPAT_VER=2.6.4
EXPAT_SRC=expat-${EXPAT_VER}
PCRE_SRC=pcre2-10.45
ARGTABLE3_VER=v3.2.2.f25c624
ARGTABLE3_SRC=argtable-${ARGTABLE3_VER}-amalgamation

[[ -d "${LIB_INSTALL_SRC}" ]] || mkdir -p ${LIB_INSTALL_SRC}
[[ -d "${LIB_INSTALL_PREFIX}" ]] && rm -rf ${LIB_INSTALL_PREFIX}
[[ -d "${LIB_INSTALL_PREFIX}" ]] || mkdir -p ${LIB_INSTALL_PREFIX}
rm -rf "${BUILD_DIR}"
rm -rf "${LIB_INSTALL_SRC}/${EXPAT_SRC}"
rm -rf "${LIB_INSTALL_SRC}/${APR_SRC}"
rm -rf "${LIB_INSTALL_SRC}/${APR_UTIL_SRC}"
rm -rf "${LIB_INSTALL_SRC}/${PCRE_SRC}"
rm -rf "${LIB_INSTALL_SRC}/dist"

EXTERNAL_PREFIX=$(realpath ${LIB_INSTALL_PREFIX})
EXPAT_PREFIX=${EXTERNAL_PREFIX}/expat
APR_PREFIX=${EXTERNAL_PREFIX}/apr
PCRE_PREFIX=${EXTERNAL_PREFIX}/pcre
ARGTABLE3_PREFIX=${EXTERNAL_PREFIX}/argtable3

if [[ "${ARCH}" = "x86_64" ]]; then
  CFLAGS="-Ofast -march=haswell -mtune=haswell"
  if [[ "${ABI}" = "musl" ]] && [[ "${OS}" = "linux" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-x86_64-linux-musl.cmake)"
  fi
  if [[ "${ABI}" = "gnu" ]] && [[ "${OS}" = "linux" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-x86_64-linux-gnu.cmake)"
  fi
  if [[ "${ABI}" = "none" ]] && [[ "${OS}" = "macos" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-x86_64-macos-none.cmake)"
  fi
else
  CFLAGS="-Ofast"
fi

if [[ "${ARCH}" = "aarch64" ]]; then
  if [[ "${OS}" = "linux" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-aarch64-linux-musl.cmake)"
  fi
  if [[ "${OS}" = "macos" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-aarch64-macos-none.cmake)"
  fi
fi

(cd "${LIB_INSTALL_SRC}" && ([[ -f "${EXPAT_SRC}.tar.gz" ]] || wget https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VER//./_}/${EXPAT_SRC}.tar.gz))
(cd "${LIB_INSTALL_SRC}" && tar -xzf ${EXPAT_SRC}.tar.gz)
(cd "${LIB_INSTALL_SRC}/${EXPAT_SRC}" && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" CXXFLAGS="${CFLAGS}" ./configure --host=x86_64-linux --enable-shared=no --prefix="${EXPAT_PREFIX}" && make -j $(nproc) && make install)

(cd "${LIB_INSTALL_SRC}" && ([[ -f "${ARGTABLE3_SRC}.tar.gz" ]] || wget https://github.com/argtable/argtable3/releases/download/${ARGTABLE3_VER}/${ARGTABLE3_SRC}.tar.gz))
[[ -d "${ARGTABLE3_PREFIX}" ]] || mkdir "${ARGTABLE3_PREFIX}"
(cd "${LIB_INSTALL_SRC}" && tar -xzf ${ARGTABLE3_SRC}.tar.gz && cp -v ./dist/argtable3* "${ARGTABLE3_PREFIX}/")

(cd "${LIB_INSTALL_SRC}" && ([[ -f "${APR_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_SRC}.tar.gz))
(cd "${LIB_INSTALL_SRC}" && tar -xzf ${APR_SRC}.tar.gz)
(cd "${LIB_INSTALL_SRC}/${APR_SRC}" && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS} -Wno-implicit-function-declaration -Wno-int-conversion" ./configure ac_cv_file__dev_zero=yes apr_cv_process_shared_works=yes apr_cv_mutex_robust_shared=yes apr_cv_tcp_nodelay_with_cork=yes --host=x86_64-linux --enable-shared=no --prefix="${APR_PREFIX}" && make -j $(nproc) && make install)

(cd "${LIB_INSTALL_SRC}" && ([[ -f "${APR_UTIL_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_UTIL_SRC}.tar.gz))
(cd "${LIB_INSTALL_SRC}" && tar -xzf ${APR_UTIL_SRC}.tar.gz)
(cd "${LIB_INSTALL_SRC}/${APR_UTIL_SRC}" && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --host=x86_64-linux --enable-shared=no --prefix="${APR_PREFIX}" --with-apr="${APR_PREFIX}" --with-expat="${EXPAT_PREFIX}" && make -j $(nproc) && make install)

(cd "${LIB_INSTALL_SRC}" && ([[ -f "${PCRE_SRC}.tar.gz" ]] || wget https://github.com/PCRE2Project/pcre2/releases/download/${PCRE_SRC}/${PCRE_SRC}.tar.gz))
(cd "${LIB_INSTALL_SRC}" && tar -xzf ${PCRE_SRC}.tar.gz)
(cd "${LIB_INSTALL_SRC}/${PCRE_SRC}" && AR="${AR_FLAGS}" RANLIB="${RANLIB_FLAGS}" CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" CXXFLAGS="${CFLAGS}" ./configure --host=x86_64-linux --prefix="${PCRE_PREFIX}" --enable-shared=no && make -j $(nproc) && make install)

cmake -DCMAKE_BUILD_TYPE=${BUILD_CONF} -B "${BUILD_DIR}" "${TOOLCHAIN}"
cmake --build "${BUILD_DIR}" --verbose --parallel $(nproc)

if [[ "${ARCH}" = "x86_64" ]] && [[ "${OS}" = "linux" ]]; then
  ctest --test-dir "${BUILD_DIR}" -VV
fi

(cd "${BUILD_DIR}" && cpack --config CPackConfig.cmake)
