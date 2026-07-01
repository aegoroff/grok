%{
	#include "grok.tab.h"

	extern int yylineno;
	extern char *yytext;

	void yyerror(char *s, ...);
	void lyyerror(YYLTYPE t, char *s, ...);
	int yylex();
	int definitions = 0;

	/* Initialize location tracking */
	YYLTYPE yylloc_default = {1, 1, 1, 1};
%}

%code requires
{
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

translation_unit : lines opt_trailing_crlf ;

lines
    : line
    | lines CRLF line
    ;

opt_trailing_crlf
    : CRLF
    |
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

int yyerror_flag = 0;

void yyerror(char *format, ...) {
	if (yyerror_flag) return;  // Already reported
	yyerror_flag = 1;

	va_list ap;
	va_start(ap, format);
	lyyerror(yylloc, format, ap);
	va_end(ap);
}

void lyyerror(YYLTYPE t, char *format, ...) {
    va_list params;
    va_start(params, format);

    char buf[4096];
    int result;

#ifdef __STDC_WANT_SECURE_LIB__
    result = vsnprintf_s(buf, sizeof(buf), (size_t)-1, format, params);
#else
    result = vsnprintf(buf, sizeof(buf), format, params);
#endif
	va_end(params);

	if (result >= 0) {
		fend_print_error(t.first_line, t.first_column, t.last_line, t.last_column, buf);
    } else {
		fend_print_error(t.first_line, t.first_column, t.last_line, t.last_column, "");
	}
}