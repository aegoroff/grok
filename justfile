ver := "0.4.0-dev"
target := "x86_64-linux-musl"
cpu := "haswell"

build optimize = "ReleaseFast":
  mise exec zig@0.16 -- zig build  -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}

test optimize = "ReleaseFast":
  mise exec zig@0.16 -- zig build test -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}

fuzz optimize = "ReleaseSafe":
  mise exec zig@0.16 -- zig build test --fuzz -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}}

linux:
  mise run build:zig

all optimize = "ReleaseFast": (build optimize) (test optimize)

build_all optimize = "ReleaseFast" version = "0.4.0-dev":
    #!/usr/bin/env bash
    rm -rf ./zig-out/*.tar.gz
    rm -rf ./zig-out/bin-*
    for target in \
        "x86_64-linux-musl haswell" \
        "aarch64-linux-musl generic" \
        "x86_64-macos-none haswell" \
        "aarch64-macos-none apple_m1" \
        "x86_64-windows-gnu haswell" \
        "aarch64-windows-gnu generic"
    do
        set -- $target
        ARCH_OS_ABI=$1
        CPU=$2
        echo "Building for $ARCH_OS_ABI ($CPU)..."
        mise exec zig@0.16 -- zig build archive -Doptimize={{optimize}} -Dtarget="$ARCH_OS_ABI" -Dversion="{{version}}" --summary all -Dcpu="$CPU" --prefix-exe-dir "bin-$ARCH_OS_ABI"
    done
