%{
	#include "grok.tab.h"

	extern int yylineno;
        extern char *yytext;

	void yyerror(char *s, ...);
	void lyyerror(YYLTYPE t, char *s, ...);
	int yylex();
	int definitions = 0;
%}

%code requires
{
	#include "lib.h"
	#include "frontend.h"
}

%locations

%union {
	char* str;
	macro_t* macro;
}

%start translation_unit

%token COMMA
%token DOT
%token ARROW
%token COLON
%token OPEN
%token CLOSE
%token <str> PATTERN_REF
%token <str> PATTERN_DEFINITION
%token CASTING_PATTERN
%token TYPE_NAME
%token LEVEL
%token <str> PROPERTY
%token WS
%token <str> LITERAL
%token COMMENT
%token CRLF

%type <str> key
%type <str> grok
%type <str> literal
%type <macro> macro
%type <str> property
%type <str> semantic

%%

translation_unit : lines ;

lines 
    : line
    | lines CRLF line
    ;
	
line
    : key WS groks { fend_on_definition_end($1); }
    | COMMENT
    | CRLF
    ;

key : PATTERN_DEFINITION  { fend_on_definition(); $$ = $1; };

groks 
    : grok
    | groks grok
    ;

grok
	: pattern
	| literal
	;
	
pattern
	: OPEN macro CLOSE { fend_on_grok($2); }
	;

literal 
    : LITERAL { fend_on_literal($1); }
    ;

macro
	: PATTERN_REF { $$ = fend_on_macro($1, NULL); }
	| PATTERN_REF semantic { $$ = fend_on_macro($1, $2); }
	;

semantic
	: property { $$ = $1; }
    | property casting { $$ = $1; }
	;
    
property
	: COLON PROPERTY { $$ = $2; }
	;

casting
	: COLON type
    | COLON castings
	;
    
type
	: TYPE_NAME
	;
    
castings
	: cast
	| castings COMMA cast
	;

cast
	: CASTING_PATTERN ARROW target
	;

target
	: TYPE_NAME
	| TYPE_NAME member
	;
    
member
	: DOT LEVEL
	;

%%

void yyerror(char *s, ...) {
	va_list ap;
	va_start(ap, s);
	lyyerror(yylloc, s, ap);	
	va_end(ap);
}

void lyyerror(YYLTYPE t, char *s, ...) {
	va_list ap;
	va_start(ap, s);
	if(t.first_line)
		lib_fprintf(stderr, "%d.%d-%d.%d: error: ", t.first_line, t.first_column, t.last_line, t.last_column);
#ifdef __STDC_WANT_SECURE_LIB__
    vfprintf_s(stderr, s, ap);
#else
    vfprintf(stderr, s, ap);
#endif
	va_end(ap);
	lib_fprintf(stderr, "\n");
}