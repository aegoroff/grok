ABI=$1
OS=$2
ARCH=$3
VERSION=$4
CPU=$5
[[ -n "${ABI}" ]] || ABI=musl
[[ -n "${OS}" ]] || OS=linux
[[ -n "${ARCH}" ]] || ARCH=x86_64
[[ -n "${VERSION}" ]] || VERSION="0.3.0-dev"

BUILD_DIR=build-${ARCH}-${OS}-${ABI}
ZIG_PREFIX_DIR=bin-${ARCH}-${OS}-${ABI}
ZIG_OUT_DIR=zig-out/${ZIG_PREFIX_DIR}
OPTIMIZE=ReleaseFast

DCPU=""
[[ -n "${CPU}" ]] && DCPU="-Dcpu=${CPU}"

zig build -Doptimize=${OPTIMIZE} ${DCPU} -Dtarget=${ARCH}-${OS}-${ABI} -Dversion="${VERSION}" --summary all --prefix-exe-dir ${ZIG_PREFIX_DIR}

if [[ "${ARCH}" = "x86_64" ]] && [[ "${OS}" = "linux" ]]; then
  zig build test -Doptimize=${OPTIMIZE} ${DCPU} -Dtarget=${ARCH}-${OS}-${ABI} --summary all -- -s
fi

if [[ "${ARCH}" = "x86_64" ]]; then
  if [[ "${ABI}" = "musl" ]] && [[ "${OS}" = "linux" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-x86_64-linux-musl.cmake)"
  fi
  if [[ "${ABI}" = "gnu" ]] && [[ "${OS}" = "linux" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-x86_64-linux-gnu.cmake)"
  fi
  if [[ "${ABI}" = "none" ]] && [[ "${OS}" = "macos" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-x86_64-macos-none.cmake)"
  fi
  if [[ "${ABI}" = "gnu" ]] && [[ "${OS}" = "windows" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-x86_64-windows-gnu.cmake)"
  fi
fi

if [[ "${ARCH}" = "aarch64" ]]; then
  if [[ "${OS}" = "linux" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-aarch64-linux-musl.cmake)"
  fi
  if [[ "${OS}" = "macos" ]]; then
    TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=$(realpath cmake/zig-toolchain-aarch64-macos-none.cmake)"
  fi
fi

cmake -B "${BUILD_DIR}" "${TOOLCHAIN}"
(cd "${BUILD_DIR}" && cpack --config CPackConfig.cmake)
