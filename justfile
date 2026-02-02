optimize  := "ReleaseFast"
target := "x86_64-linux-musl"
cpu := "haswell"

build ver="0.4.0-dev":
  mise exec zig@master -- zig build  -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}

test ver="0.4.0-dev":
  mise exec zig@master -- zig build test -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}
