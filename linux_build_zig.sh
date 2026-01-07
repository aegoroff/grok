#!/bin/bash

ABI=$1
OS=$2
ARCH=$3
VERSION=$4
CPU=$5
[[ -n "${ABI}" ]] || ABI=musl
[[ -n "${OS}" ]] || OS=linux
[[ -n "${ARCH}" ]] || ARCH=x86_64
[[ -n "${VERSION}" ]] || VERSION="0.3.0-dev"

ZIG_PREFIX_DIR=bin-${ARCH}-${OS}-${ABI}
OPTIMIZE=ReleaseFast

DCPU=""
[[ -n "${CPU}" ]] && DCPU="-Dcpu=${CPU}"

if [[ "${ARCH}" = "x86_64" ]] && [[ "${OS}" = "linux" ]]; then
  zig build test -Doptimize=${OPTIMIZE} "${DCPU}" -Dtarget="${ARCH}"-"${OS}"-"${ABI}" -Dversion="${VERSION}" --summary all
fi

zig build archive -Doptimize=${OPTIMIZE} "${DCPU}" -Dtarget="${ARCH}"-"${OS}"-"${ABI}" -Dversion="${VERSION}" --summary all --prefix-exe-dir "${ZIG_PREFIX_DIR}"
