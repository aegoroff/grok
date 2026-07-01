/* recognize tokens and print them out */

%{
    #include "grok.tab.h"
	/* handle locations */
	int yycolumn = 1;

#ifdef _MSC_VER
#pragma warning(disable : 4996)
#endif

#define YY_USER_ACTION \
    /* Save the starting position of this token */ \
    yylloc.first_line = yylineno; \
    yylloc.first_column = yycolumn; \
    /* Update position for each character in the token */ \
    for(int i = 0; yytext[i] != '\0'; i++) { \
        if(yytext[i] == '\n') { \
            yylineno++; \
            yycolumn = 1; \
        } \
        else { \
            yycolumn++; \
        } \
    } \
    /* Set last position to the last character of the token */ \
    /* For newline tokens, last_line should be the line containing the newline */ \
    if (yytext[0] == '\n' || yytext[0] == '\r') { \
        yylloc.last_line = yylloc.first_line; \
        yylloc.last_column = yylloc.first_column; \
    } else { \
        yylloc.last_line = yylineno; \
        yylloc.last_column = yycolumn - 1; \
    }
%}

%option yylineno
%option noyywrap 
%option never-interactive

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

[ \t]+ { /* skip whitespace but update position via YY_USER_ACTION */ }

{PATTERN_DEFINITION} {
	BEGIN(INDEFINITION);
	yylval.str = fend_strdup(yytext);
	return PATTERN_DEFINITION;
}

^#[^\r\n]* { BEGIN(INCOMMENT); return COMMENT; }

<INDEFINITION>{WS}+ { BEGIN(INGROK); return WS; }

<INGROK>{CRLF} {  BEGIN(INITIAL); yycolumn = 1;  return CRLF; }

<INCOMMENT>{CRLF} {  BEGIN(INITIAL); yycolumn = 1; return CRLF; }

{CRLF} { yycolumn = 1; }

<INGROK><<EOF>> { BEGIN(INITIAL); }
<INCOMMENT><<EOF>> { BEGIN(INITIAL); }

<INGROK>{OPEN} {  BEGIN(INPATTERN); return OPEN; }

<INGROK>{LITERAL}+ { 
	yylval.str = fend_strdup(yytext);
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

<INPATTERN>{PATTERN_REF} { 
	yylval.str = fend_strdup(yytext);
	return PATTERN_REF; 
}
<INPATTERN>{PROPERTY} { 
	yylval.str = fend_strdup(yytext);
	return PROPERTY; 
}

<INPATTERN>{CASTING_PATTERN} { return CASTING_PATTERN; }

<INPATTERN>{CLOSE} { BEGIN INGROK; return CLOSE; }

%%
