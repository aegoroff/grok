BUILD_DIR=build-musl
APR_INCLUDE=/home/egr/code/lib/apr/include/apr-1; APR_LINK=/home/egr/code/lib/apr/lib; cmake -B ${BUILD_DIR} -G Ninja -DCMAKE_TOOLCHAIN_FILE=cmake/zig-toolchain-linux-musl.cmake
cmake --build ${BUILD_DIR}
