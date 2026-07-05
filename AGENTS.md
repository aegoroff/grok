# Rules for Grok Project

## Project Overview
- **Language**: Zig
- **Purpose**: Grok pattern matching library
- **Build System**: build.zig

## Architecture

### Data Flow

```
patterns/*.patterns
    ↓ flex/bison (grok.lex, grok.y) → src/grok/generated/
frontend.zig          — parse patterns, macro table
    ↓
regex.zig             — expand %{MACRO}, compile PCRE2
    ↓
matcher.zig           — match string / file / stdin
    ↓
printer.zig           — output (plain, -i info, -j JSONL)
```

CLI entry: `main.zig` → `configuration.zig` (yazap) dispatches to `string`, `file`, `stdin`, or `macro` commands.

### Modules

| Module | Role |
|--------|------|
| `main.zig` | CLI entry, command handlers |
| `configuration.zig` | Argument parsing (yazap), pattern file paths |
| `frontend.zig` | Load `.patterns`, C parser callbacks, macro lookup |
| `regex.zig` | Macro expansion, PCRE2 compile/match |
| `matcher.zig` | Orchestrates matching and output flags |
| `printer.zig` | Formatted output (count, line numbers, invert) |
| `encoding.zig` | BOM detection, UTF-8/16/32 decoding |
| `line_reader.zig` | Line-by-line reading with encoding support |
| `grok.zig` | Shared error types (`GrokError`) |
| `integration_test.zig` | End-to-end CLI tests |
| `fuzz.zig` | Fuzz tests for file mode |

### External Dependencies

| Package | Used in | Purpose |
|---------|---------|---------|
| `pcre2` | `regex.zig` | Regex engine |
| `yazap` | `configuration.zig` | CLI parsing |
| `fehler` | `frontend.zig` | Parser error diagnostics |
| `glob` | `frontend.zig` | Find `*.patterns` in directories |

### Where to Change What

| Task | Files |
|------|-------|
| New CLI option | `configuration.zig`, `main.zig`, `printer.zig`, `integration_test.zig` |
| Pattern syntax | `grok.lex`, `grok.y`, `frontend.zig` |
| New macro | `patterns/*.patterns` |
| Encoding / BOM | `encoding.zig`, `line_reader.zig` |
| Output format | `printer.zig` |
| Parser errors | `frontend.zig`, `grok.y` |

## Code Style Guidelines
- Follow Zig standard library conventions
- Use snake_case for functions and variables
- Use PascalCase for types and structs
- Use SCREAMING_SNAKE_CASE for constants
- Prefer explicit error handling with `!` return types
- Keep functions small and focused on single responsibility
- Add doc comments (`///`) for public APIs

## Development Rules

### Before Making Changes
1. Read existing code to understand patterns and conventions
2. Check for existing tests related to modified functionality
3. Ensure changes are compatible with existing API

### When Writing Code
1. Write idiomatic Zig code following std lib patterns
2. Handle all errors explicitly - no silent failures
3. Add tests for new functionality
4. Keep backward compatibility when possible
5. Update documentation for public APIs

### When Fixing Bugs
1. Understand root cause before fixing
2. Add regression test if missing
3. Check for similar issues in related code
4. Verify fix doesn't break existing tests

### C/Zig Boundary
- Parser/lexer: flex + bison → `src/grok/generated/`
- Zig callbacks in `frontend.zig` implement `frontend.h` interface
- Never commit or hand-edit generated files
- After changing `grok.lex` or `grok.y`, rebuild to regenerate C sources

## Build & Test Commands
```bash
# Build
mise exec zig@0.16.0 -- zig build -Dtarget=x86_64-linux-musl

# Run tests
mise exec zig@0.16.0 -- zig build test -Dtarget=x86_64-linux-musl

# Build release
mise exec zig@0.16.0 -- zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl

# Create tarball archive
mise exec zig@0.16.0 -- zig build archive -Dtarget=x86_64-linux-musl -Dversion=1.0.0

# Run fuzzing
mise exec zig@0.16.0 -- zig build test --fuzz -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
```

## File Structure
- `src/main.zig` - CLI entry point
- `src/configuration.zig` - CLI argument parsing
- `src/frontend.zig` - Pattern loading and C parser bridge
- `src/regex.zig` - Macro expansion and PCRE2 matching
- `src/matcher.zig` - Matching orchestration
- `src/printer.zig` - Output formatting
- `src/encoding.zig` - Character encoding handling
- `src/line_reader.zig` - Encoded line reading
- `src/grok.zig` - Shared error types
- `src/integration_test.zig` - End-to-end CLI tests
- `src/fuzz.zig` - Fuzz tests
- `src/grok/` - C lexer (flex) and parser (bison)
  - `c.h` - C header for Zig translation
  - `frontend.h` - C callback interface
  - `grok.lex` - Flex lexer definition
  - `grok.y` - Bison parser definition
  - `generated/` - Generated C sources (do not edit)
- `patterns/` - Built-in pattern definitions (`*.patterns`)
- `test_assets/` - Test logs and invalid pattern fixtures
- `build.zig` - Build configuration (flex, bison, pcre2, yazap, glob, fehler)

## Important Notes
- Always verify build passes before completing tasks
- Run full test suite after significant changes
- Follow existing code organization patterns
- Write code comments only in English
- Don't write trivial code comments
