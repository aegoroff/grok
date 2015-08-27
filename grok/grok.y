%{
    #include <stdio.h>
    #include <stdlib.h>
	#include "grok.tab.h"
	#include "lib.h"
	#include "frontend.h"

	extern int yylineno;
    extern char *yytext;

	int yyerror(char *s);
	int yylex();
	int definitions = 0;
%}

%union {
	char* str;
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
%token PROPERTY
%token WS
%token <str> LITERAL
%token COMMENT
%token CRLF

%type <str> key
%type <str> grok
%type <str> literal
%type <str> definition

%%

translation_unit : lines ;

lines 
    : line
    | lines CRLF line
    ;
	
line
    : key WS groks { on_definition_end(); }
    | COMMENT
    | CRLF
    ;

key : PATTERN_DEFINITION  { on_definition($1); };

groks 
    : grok
    | groks grok
    ;

grok
	: pattern
	| literal
	;
	
pattern
	: OPEN definition CLOSE { on_grok($2); }
	;

literal 
    : LITERAL { on_literal($1); }
    ;

definition
	: PATTERN_REF { $$ = $1; }
	| PATTERN_REF semantic { $$ = $1; }
	;

semantic
	: property
    | property casting
	;
    
property
	: COLON PROPERTY
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
	CrtFprintf(stderr, "%d: %s at %s\n", yylineno, s, yytext);
	return 1;
}
