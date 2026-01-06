# GROK

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/dde2c10db42548ffafaa8b1d1ceea8a9)](https://app.codacy.com/gh/aegoroff/grok/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CI Build](https://github.com/aegoroff/grok/actions/workflows/ci_build.yml/badge.svg)](https://github.com/aegoroff/grok/actions/workflows/ci_build.yml)

**GROK** is a powerful command-line tool like UNIX `grep` on steroids. It uses grok patterns (named regular expression macros) to simplify complex pattern matching tasks.

## Overview

Often, regular expressions become huge and hard to maintain. To resolve this, **grok patterns** (macros) can be applied. The term "grok" is borrowed from the Logstash project. Grok patterns are named references to regular expressions that can be rather complex. These regular expressions can contain references to other groks, allowing you to build complex patterns from simple, reusable components.

Instead of writing complex regular expressions, you can use a macro name defined in pattern files, making your pattern matching more readable and maintainable.

## Features

- 🚀 **Fast pattern matching** using PCRE2
- 📝 **Named pattern macros** for reusable regular expressions
- 🔗 **Pattern composition** - groks can reference other groks
- 📁 **Multiple input modes**: files, strings, and stdin
- 🎯 **Info mode** for detailed match information
- 🌍 **Cross-platform** support (Linux, macOS, Windows)
- 📦 **Pre-built binaries** for easy installation
- 🔍 **Built-in pattern libraries** for common use cases

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Examples](#examples)
- [Building from Source](#building-from-source)
- [Pattern Files](#pattern-files)
- [License](#license)

## Installation

### Homebrew (macOS and Linux)

Add the tap (one-time setup):
```bash
brew tap aegoroff/tap
```

Install grok:
```bash
brew install aegoroff/tap/grok
```

Update grok:
```bash
brew upgrade aegoroff/tap/grok
```

### Scoop (Windows)

```bash
scoop bucket add aegoroff https://github.com/aegoroff/scoop-bucket.git
scoop install grok
```

### AUR (Arch Linux)

Install the binary package:
```bash
yay -S grok-tool-bin
```

If the package is not found, update repository information:
```bash
yay -Syyu grok-tool-bin
```

### Manual Installation

1. Download pre-compiled binaries from the [releases page](https://github.com/aegoroff/grok/releases)
2. Extract and copy the executable to your desired location
3. **Linux**: Copy `*.patterns` files to `/usr/share/grok/patterns` (create the directory if it doesn't exist)
4. **Other platforms**: Place `*.patterns` files in the same directory as the executable

## Quick Start

List all available pattern macros:
```bash
grok macro
```

View the regular expression for a specific macro:
```bash
grok macro UNIXPATH
```

Match a string:
```bash
grok string -m EMAILADDRESS "user@example.com"
```

Search in a file:
```bash
grok file -m SYSLOGBASE /var/log/system.log
```

Pipe from stdin:
```bash
cat /var/log/system.log | grok stdin -m SYSLOGBASE
```

## Usage

### General Syntax

```bash
grok <COMMAND> [OPTIONS]
```

### Commands

| Command | Description |
|---------|-------------|
| `string` | Single string matching mode |
| `file` | File matching mode |
| `stdin` | Standard input (stdin) matching mode |
| `macro` | Macro information mode - display macro regexp or list all macros |

Run `grok <command> -h` or `grok <command> --help` for detailed help on any command.

### Common Options

- `-p, --patterns=<patterns>...` - One or more pattern files. If not set, current directory is used to search for all `*.patterns` files
- `-m, --macro=<STRING>` - Pattern macro to build regexp (required for `string`, `file`, and `stdin` commands)
- `-i, --info` - Output matched string with additional information (captured groups, etc.)
- `-h, --help` - Print help and exit

### Command Details

#### `string` - Single String Matching

Match a single string against a grok pattern.

```bash
grok string [OPTIONS] <STRING>
```

**Arguments:**
- `STRING` - String to match

**Example:**
```bash
grok string -m EMAILADDRESS "user@example.com"
```

#### `file` - File Matching

Search for patterns in a file.

```bash
grok file [OPTIONS] <PATH>
```

**Arguments:**
- `PATH` - Full path to file to read data from

**Options:**
- `-c, --count` - Print only the number of matched lines
- `-n, --line-number` - Print line numbers with matching lines

**Example:**
```bash
grok file -m SYSLOGBASE /var/log/system.log
```

#### `stdin` - Standard Input Matching

Process input from standard input (pipes, redirects, etc.).

```bash
grok stdin [OPTIONS]
```

**Example:**
```bash
cat /var/log/system.log | grok stdin -m SYSLOGBASE
```

**Options:**
- `-c, --count` - Print only the number of matched lines
- `-n, --line-number` - Print line numbers with matching lines

#### `macro` - Macro Information

Display macro information or list all available macros.

```bash
grok macro [OPTIONS] [MACRO]
```

**Arguments:**
- `MACRO` - (Optional) Macro name to expand to its real regular expression

**Examples:**
```bash
# List all available macros
grok macro

# Show the regexp for a specific macro
grok macro UNIXPATH
```
## Examples

### List Available Macros

Output all possible macro names (to pass as `-m` parameter):

```bash
grok macro
```

### View Macro Regular Expression

Output the regular expression that a macro will be expanded to:

```bash
grok macro UNIXPATH
```

**Output:**
```
(?>/(?>[\w_%!$@:.,-]+|\\.)*)+
```

### Match a String

Match an email address:

```bash
grok string -m EMAILADDRESS "user@example.com"
```

With info mode to see captured groups:

```bash
grok string -m EMAILADDRESS -i "user@example.com"
```

### Search in a File

Search for syslog entries in a log file:

```bash
grok file -m SYSLOGBASE /var/log/system.log
```

With info mode to see line numbers and captured groups:

```bash
grok file -m SYSLOGBASE -i /var/log/system.log
```

### Process from Standard Input

Same as above but reading from stdin:

```bash
cat /var/log/system.log | grok stdin -m SYSLOGBASE
```

Or with a pipe:

```bash
tail -f /var/log/system.log | grok stdin -m SYSLOGBASE
```

### Using Custom Pattern Files

Specify custom pattern files:

```bash
grok file -p /path/to/custom.patterns -m MYCUSTOMPATTERN /path/to/file.log
```

Multiple pattern files:

```bash
grok file -p patterns/custom.patterns -p patterns/webservers.patterns -m APACHELOG access.log
```

## Building from Source

### Prerequisites

- [Zig](https://ziglang.org/) compiler (latest stable version)
- `flex` (or `win_flex` on Windows)
- `bison` (or `win_bison` on Windows)
- PCRE2 library (automatically handled by Zig package manager)

### Build Steps

1. Clone the repository:
```bash
git clone https://github.com/aegoroff/grok.git
cd grok
```

2. Build the project:
```bash
zig build
```

The executable will be in `zig-out/bin/`.

3. Run tests:
```bash
zig build test
```

4. Create a release archive:
```bash
zig build archive
```

### Cross-Platform Building

The project supports cross-compilation. Use the build scripts:

```bash
# Build for all platforms
./build_all_zig.sh

# Build for Linux only
./linux_build_zig.sh
```

## Pattern Files

Grok uses pattern files (`.patterns`) that define named macros. The project includes several built-in pattern files:

- `grok.patterns` - Common patterns (numbers, strings, paths, etc.)
- `linuxsyslog.patterns` - Linux syslog patterns
- `webservers.patterns` - Web server log patterns
- `custom.patterns` - Custom patterns

Pattern files use a simple syntax:
```
MACRONAME regexp
```

Macros can reference other macros using `%{MACRONAME:fieldname}` syntax.

## License

Copyright (c) 2018-2026 Alexander Egorov

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
