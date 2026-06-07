pub const GrokError = error{
    InvalidRegex,
    UnknownMacro,
    UnknownPatternFile,
    InvalidPatternFile,
    InvalidUtf16LineLength,
};
