%{
    #include <stdio.h>
    #include <stdlib.h>
	#include "grok.tab.h"
	#include "frontend.h"

	int yyerror(char *s);
	int yylex();
	int definitions = 0;
%}

%union {
	char* def;
	char* lit;
}

%start translation_unit

%token COMMA
%token DOT
%token ARROW
%token COLON
%token OPEN
%token CLOSE
%token PATTERN_REF
%token <def> PATTERN_DEFINITION
%token CASTING_PATTERN
%token TYPE_NAME
%token LEVEL
%token PROPERTY
%token WS
%token <lit> LITERAL
%token COMMENT
%token CRLF
%token END

%type <def> key
%type <lit> literal

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
    | END
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
	: OPEN definition CLOSE
	;

literal 
    : LITERAL { on_literal($1); }
    ;

definition
	: PATTERN_REF
	| PATTERN_REF semantic
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
