#!/bin/bash

for i in "x86_64 linux musl haswell" "aarch64 linux musl" "x86_64 macos none haswell" "aarch64 macos none apple_m1"
do
    set -- $i # Convert the "tuple" into the param args $1 $2...
    echo $1 - $2 - $3
    ./linux_build_zig.sh $3 $2 $1
done