pub const GrokError = error{
    InvalidRegex,
    UnknownMacro,
    UnknownPatternFile,
    InvalidPatternFile,
    InvalidUtf16LineLength,
    InvalidUtf32LineLength,
    InvalidEncoding,
    InvalidUtf32,
};
