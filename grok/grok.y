%{
	#include "grok.tab.h"

	extern int yylineno;
    extern char *yytext;

	int yyerror(char *s);
	int yylex();
	int definitions = 0;
%}

%code requires
{
	#include "lib.h"
	#include "frontend.h"
}


%union {
	char* str;
	Macro_t* macro;
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

int yyerror(char* s) {
	lib_fprintf(stderr, "%d: %s at %s\n", yylineno, s, yytext);
	return 1;
}
