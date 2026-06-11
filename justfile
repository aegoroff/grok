ver := "0.4.0-dev"
target := "x86_64-linux-musl"
cpu := "haswell"

build optimize = "ReleaseFast":
  mise exec zig@0.15.2 -- zig build  -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}

test optimize = "ReleaseFast":
  mise exec zig@0.15.2 -- zig build test -Doptimize={{optimize}} -Dtarget={{target}} --summary all -Dcpu={{cpu}} -Dversion={{ver}}

linux:
  mise run build:zig

all optimize = "ReleaseFast": (build optimize) (test optimize)
