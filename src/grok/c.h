#include <stdio.h>
#include <setjmp.h>
#include "grok.h"
#include "grok.tab.h"
#include "grok.flex.h"

/* Declare yylineno explicitly - it's defined in grok.flex.c but may not be in the header */
extern int yylineno;
extern int yycolumn;