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
grok [-hi] -s <string> -m <string> [-p <file>]...

grok [-hi] -f <file> -m <string> [-p <file>]...

grok [-hi] -m <string> [-p <file>]...

grok -t[h] [-m <string>] [-p <file>]...

  -h, --help                print this help and exit
  -i, --info                dont work like grep i.e. output matched string with
                            additional info
  -s, --string=<string>     string to match
  -f, --file=<file>         full path to file to read data from. If not set and
                            string option not set too data read from stdin
  -m, --macro=<string>      pattern macros to build regexp
  -p, --patterns=<file>     one or more pattern files. You can also use
                            wildcards like path\*.patterns. If not set, current
                            directory used to search all *.patterns files
  -t, --template            show template(s) information
``` 
**EXAMPLES**

Output all possible macro names (to pass as -m parameter)
```shell
grok -t
```

Output regular expression a macro will be expanded to
```shell
grok -t -m UNIXPATH
```
This will output
```
(?>/(?>[\w_%!$@:.,-]+|\\.)*)+
```

Output first log messages lines from system.log
```shell
grok -m SYSLOGBASE -f /var/log/system.log
```

Same as above but input from stdin
```shell
cat /var/log/system.log | grok -m SYSLOGBASE
```
