const std = @import("std");

pub const GrokError = error{
    InvalidRegex,
    UnknownMacro,
    UnknownPatternFile,
    InvalidPatternFile,
};
