pub const GrokError = error{
    InvalidRegex,
    UnknownMacro,
    CircularMacro,
    UnknownPatternFile,
    InvalidPatternFile,
    OutOfMemory,
    InvalidUtf16LineLength,
    InvalidUtf32LineLength,
    InvalidEncoding,
    InvalidUtf32,
};
