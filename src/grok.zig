pub const GrokError = error{
    InvalidRegex,
    UnknownMacro,
    CircularMacro,
    UnknownPatternFile,
    InvalidPatternFile,
    InvalidUtf16LineLength,
    InvalidUtf32LineLength,
    InvalidEncoding,
    InvalidUtf32,
};
