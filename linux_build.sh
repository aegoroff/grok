BUILD_CONF=Release
ABI=$1
[[ -n "${ABI}" ]] || ABI=musl
BUILD_DIR=build-${ABI}-${BUILD_CONF}
LIB_INSTALL_SRC=./external_lib/src
LIB_INSTALL_PREFIX=./external_lib/lib
CC_FLAGS="zig cc -target x86_64-linux-${ABI}"
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

(cd ${LIB_INSTALL_SRC} && [[ -f "${EXPAT_SRC}.tar.gz" ]] || wget https://github.com/libexpat/libexpat/releases/download/R_2_5_0/${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${EXPAT_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${EXPAT_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" CXXFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=$(realpath ../../lib/expat) && make && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${APR_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=$(realpath ../../lib/apr) && make && make install)

(cd ${LIB_INSTALL_SRC} && [[ -f "${APR_UTIL_SRC}.tar.gz" ]] || wget https://dlcdn.apache.org/apr/${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC} && tar -xvzf ${APR_UTIL_SRC}.tar.gz)
(cd ${LIB_INSTALL_SRC}/${APR_UTIL_SRC} && CC="${CC_FLAGS}" CFLAGS="${CFLAGS}" ./configure --enable-shared=no --prefix=$(realpath ../../lib/apr) --with-apr=$(realpath ../../lib/apr) --with-expat=$(realpath ../../lib/expat) && make && make install)

if [[ "${ABI}" = "musl" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=cmake/zig-toolchain-linux-musl.cmake"
fi

APR_INCLUDE="$(realpath ${LIB_INSTALL_PREFIX})/apr/include/apr-1" \
APR_LINK="$(realpath ${LIB_INSTALL_PREFIX})/apr/lib" \
cmake -DCMAKE_BUILD_TYPE=${BUILD_CONF} -B ${BUILD_DIR} ${TOOLCHAIN}
cmake --build ${BUILD_DIR}
ctest --test-dir ${BUILD_DIR} -VV
(cd ${BUILD_DIR} && cpack --config CPackConfig.cmake)