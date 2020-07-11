GROK
======

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/1d16744e2d18482186640ce1397d8b55)](https://app.codacy.com/manual/egoroff/grok?utm_source=github.com&utm_medium=referral&utm_content=aegoroff/grok&utm_campaign=Badge_Grade_Dashboard)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Faegoroff%2Fgrok.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Faegoroff%2Fgrok?ref=badge_shield)

GROK is a tool like UNIX grep on steroids. Ofter regular expressions become huge and vague. To resolve this situation macros or grok could be applied. Grok is a peculiar regular expression's macros name. 
This term taken from logstash project. Macros looks like named reference to a regular expression that may be rather complex expression. 
This regular expression can contain references to other groks and so on. Using groks you can make complex regular expressions from simple ones.

So using GROK you have to use a macro name defined in patterns instead of complex regular expression.

**SYNTAX**:
```
grok.exe [-hi] -s <string> -m <string> [-p <file>]...

grok.exe [-hi] -f <file> -m <string> [-p <file>]...

grok.exe [-hi] -m <string> [-p <file>]...

  -h, --help                print this help and exit
  -i, --info                dont work like grep i.e. output matched string with
                            additional info
  -s, --string=<string>     string to match
  -f, --file=<file>         full path to file to read data from. If not set and
                            string option not set too data read from stdin
  -m, --macro=<string>      pattern macros to build regexp
  -p, --patterns=<file>     one or more pattern files. You can also use wildcards
                            like path\*.patterns. If not set, current directory
                            used to search all *.patterns files
``` 

## License
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Faegoroff%2Fgrok.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Faegoroff%2Fgrok?ref=badge_large)