GROK
======

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/1d16744e2d18482186640ce1397d8b55)](https://app.codacy.com/manual/egoroff/grok?utm_source=github.com&utm_medium=referral&utm_content=aegoroff/grok&utm_campaign=Badge_Grade_Dashboard)
[![CI Build](https://github.com/aegoroff/grok/actions/workflows/ci_build.yml/badge.svg)](https://github.com/aegoroff/grok/actions/workflows/ci_build.yml)

GROK is a tool like UNIX grep on steroids. Ofter regular expressions become huge and vague. To resolve this situation macros or grok could be applied. Grok is a peculiar regular expression's macros name. 
This term taken from logstash project. Macros looks like named reference to a regular expression that may be rather complex expression. 
This regular expression can contain references to other groks and so on. Using groks you can make complex regular expressions from simple ones.

So using GROK you have to use a macro name defined in patterns instead of complex regular expression.

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