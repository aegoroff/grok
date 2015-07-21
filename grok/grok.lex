/* recognize tokens for the calculator and print them out */

%option noyywrap 
%{
    #include <stdlib.h>
	#include "frontend.h"
    #include "grok.tab.h"
%}

COMMA   ","
DOT     "."
ARROW   "->"
COLON   ":"
UNDERSCORE "_"
INT   "int"
INT32   "Int32"
INT64   "Int64"
LONG   "long"
DATE_TIME   "DateTime"
LOG_LEVEL   "LogLevel"
STRING_TYPE  ([Ss]tring)
LEVEL_TRACE   "Trace"
LEVEL_DEBUG   "Debug"
LEVEL_INFO   "Info"
LEVEL_WARN   "Warn"
LEVEL_ERROR   "Error"
LEVEL_FATAL   "Fatal"

OPEN "%{"
CLOSE "}"

PATTERN_REF {UPPER_LETTER}({UPPER_LETTER}|{DIGIT}|{UNDERSCORE})*
PROPERTY ({LOWER_LETTER}|{UPPER_LETTER})({LOWER_LETTER}|{UPPER_LETTER}|{DIGIT}|{UNDERSCORE})*

PATTERN_DEFINITION {PATTERN_REF}

UPPER_LETTER [A-Z]
LOWER_LETTER [a-z]
DIGIT [0-9]

STR_ESCAPE_SEQ ("\\".)

QUOTED_STR ("'"({STR_ESCAPE_SEQ}|[^\\\r\n'])*"'"|"\""({STR_ESCAPE_SEQ}|[^\\\r\n"])*"\"")

WS [ \t\v\f]
CRLF (\r?\n)

TYPE_NAME ({INT}|{INT32}|{INT64}|{LONG}|{LOG_LEVEL}|{DATE_TIME}|{STRING_TYPE})

LEVEL ({LEVEL_TRACE}|{LEVEL_DEBUG}|{LEVEL_INFO}|{LEVEL_WARN}|{LEVEL_ERROR}|{LEVEL_FATAL})
CASTING_PATTERN ({QUOTED_STR})

LITERAL ([^%\r\n]|%[^\{]|%\{\})

%x INPATTERN
%x INDEFINITION
%x INGROK
%x INCOMMENT

%%

{PATTERN_DEFINITION} { 
	BEGIN(INDEFINITION); 
	yylval.def = frountend_strdup(yytext);
	return PATTERN_DEFINITION; 
}

^#[^\r\n]* { BEGIN(INCOMMENT); return COMMENT; }

<INDEFINITION>{WS}+ { BEGIN(INGROK); return WS; }

<INGROK>{CRLF} {  BEGIN(INITIAL);  return CRLF; }

<INCOMMENT>{CRLF} {  BEGIN(INITIAL); return CRLF; }

{CRLF} { BEGIN(INITIAL); }

<INDEFINITION><<EOF>> { BEGIN(INITIAL); return CRLF; }
<INCOMMENT><<EOF>> { BEGIN(INITIAL); return CRLF; }

<INGROK>{OPEN} {  BEGIN(INPATTERN); return OPEN; }

<INGROK>{LITERAL}+ { 
	yylval.lit = frountend_strdup(yytext);
	return LITERAL; 
}

<INPATTERN>{COMMA} { return COMMA; }

<INPATTERN>{DOT} { return DOT; }
<INPATTERN>{ARROW} { return ARROW; }
<INPATTERN>{COLON} { return COLON; }
    
<INPATTERN>{UNDERSCORE} { /* err */ }
<INPATTERN>{DIGIT} { /* err */ }
    
<INPATTERN>{INT} { return TYPE_NAME; }
<INPATTERN>{INT32} { return TYPE_NAME; }
<INPATTERN>{INT64} { return TYPE_NAME; }
<INPATTERN>{LONG} { return TYPE_NAME; }
<INPATTERN>{DATE_TIME} { return TYPE_NAME; }
<INPATTERN>{LOG_LEVEL} { return TYPE_NAME; }
<INPATTERN>{STRING_TYPE} { return TYPE_NAME; }

<INPATTERN>{LEVEL_TRACE} { return LEVEL; }
<INPATTERN>{LEVEL_DEBUG} { return LEVEL; }
<INPATTERN>{LEVEL_INFO} { return LEVEL; }
<INPATTERN>{LEVEL_WARN} { return LEVEL; }
<INPATTERN>{LEVEL_ERROR} { return LEVEL; }
<INPATTERN>{LEVEL_FATAL} { return LEVEL; }

<INPATTERN>{PATTERN_REF} { return PATTERN_REF; }
<INPATTERN>{PROPERTY} { return PROPERTY; }

<INPATTERN>{CASTING_PATTERN} { return CASTING_PATTERN; }

<INPATTERN>{CLOSE} { BEGIN INGROK; return CLOSE; }

%%
