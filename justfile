build ver="0.3.0-dev":
  zig build  -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl --summary all -Dcpu=haswell -Dversion={{ver}}

test ver="0.3.0-dev":
  zig build test -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl --summary all -Dcpu=haswell -Dversion={{ver}}
