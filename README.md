GROK
======

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/dde2c10db42548ffafaa8b1d1ceea8a9)](https://app.codacy.com/gh/aegoroff/grok/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CI Build](https://github.com/aegoroff/grok/actions/workflows/ci_build.yml/badge.svg)](https://github.com/aegoroff/grok/actions/workflows/ci_build.yml)
[![](https://tokei.rs/b1/github/aegoroff/grok?category=code)](https://github.com/XAMPPRocky/tokei)

GROK is a tool like UNIX grep on steroids. Ofter regular expressions become huge and vague. To resolve this situation macros or grok could be applied. Grok is a peculiar regular expression's macros name. 
This term taken from logstash project. Macros looks like named reference to a regular expression that may be rather complex expression. 
This regular expression can contain references to other groks and so on. Using groks you can make complex regular expressions from simple ones.

So using GROK you have to use a macro name defined in patterns instead of complex regular expression.

## Install the pre-compiled binary

**homebrew** (only on macOS and Linux for now):

Add my tap (do it once):
```sh
brew tap aegoroff/tap
```
And then install grok:
```sh
brew install aegoroff/tap/grok
```
Update grok if already installed:
```sh
brew upgrade aegoroff/tap/grok
```
**scoop**:

```sh
scoop bucket add aegoroff https://github.com/aegoroff/scoop-bucket.git
scoop install grok
```

**AUR (Arch Linux User Repository)**:

install binary package:
```sh
 yay -S grok-tool-bin
```
or if yay reports that package not found force updating repo info
```sh
yay -Syyu grok-tool-bin
```

**manually**:

Download the pre-compiled binaries from the [releases](https://github.com/aegoroff/grok/releases) and
copy to the desired location. On linux put *.patterns files that are next to executable to folder `/usr/share/grok/patterns`. 
Create it if not exists. On other platforms grok searches files within executable's directory.

**SYNTAX**:
```
Usage: grok [OPTIONS] <COMMAND>

Commands:
    string                           Single string matching mode
    file                             File matching mode
    stdin                            Standard input (stdin) matching mode
    macro                            Macro information mode where a macro real regexp can be displayed or to get all supported macroses

Options:
    -p, --patterns=<patterns>...     One or more pattern files. If not set, current directory used to search all *.patterns files
    -h, --help                       Print this help and exit

Run 'grok <command>` with `-h/--h' flag to get help of any command.
```
File command
```
File matching mode

Usage: grok file [OPTIONS] <ARGS>

Args:
    PATH                                          Full path to file to read data from

Options:
    -m, --macro=<STRING>                          Pattern macros to build regexp
    -i, --info                                    Dont work like grep i.e. output matched string with additional info
    -h, --help                                    Print this help and exit
```
String command
```
Single string matching mode

Usage: grok string [OPTIONS] <ARGS>

Args:
    STRING                                        String to match

Options:
    -m, --macro=<STRING>                          Pattern macros to build regexp
    -i, --info                                    Dont work like grep i.e. output matched string with additional info
    -h, --help                                    Print this help and exit
```
Stdin command
```
Standard input (stdin) matching mode

Usage: grok stdin [OPTIONS]

Options:
    -m, --macro=<STRING>                          Pattern macros to build regexp
    -i, --info                                    Dont work like grep i.e. output matched string with additional info
    -h, --help                                    Print this help and exit
```
Macro command
```
Macro information mode where a macro real regexp can be displayed or to get all supported macroses

Usage: grok macro [ARGS]

Args:
    MACRO      Macro name to expand real regular expression
```
**EXAMPLES**

Output all possible macro names (to pass as -m parameter)
```shell
grok macro
```

Output regular expression a macro will be expanded to
```shell
grok macro -m UNIXPATH
```
This will output
```
(?>/(?>[\w_%!$@:.,-]+|\\.)*)+
```

Output first log messages lines from system.log
```shell
grok file -m SYSLOGBASE /var/log/system.log
```

Same as above but input from stdin
```shell
cat /var/log/system.log | grok stdin -m SYSLOGBASE
```
