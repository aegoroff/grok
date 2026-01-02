const std = @import("std");

pub const GrokError = error{
    InvalidRegex,
    MemoryAllocationError,
    UnknownMacro,
    UnknownPatternFile,
    InvalidPatternFile,
};
