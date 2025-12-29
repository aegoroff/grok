#!/bin/bash

rm -rf ./zig-out/*.tar.gz
for i in "x86_64 linux musl 0.3.0 haswell" "aarch64 linux musl 0.3.0" "x86_64 macos none 0.3.0 haswell" "aarch64 macos none 0.3.0 apple_m1" "x86_64 windows gnu 0.3.0 haswell"
do
    set -- $i # Convert the "tuple" into the param args $1 $2...
    echo "$1" - "$2" - "$3" - "$4" - "$5"
    ./linux_build_zig.sh "$3" "$2" "$1" "$4" "$5"
done
