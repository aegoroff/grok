ver := "0.3.0-dev"
target := "x86_64-linux-musl"
cpu := "haswell"

build optimize = "ReleaseFast":
  mise exec zig@0.16 -- zig build  -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}

test optimize = "ReleaseFast":
  mise exec zig@0.16 -- zig build test -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}
