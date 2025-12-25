const grok = @cImport({
    @cInclude("grok.tab.h");
});

const c = @cImport({
    @cInclude("stdio.h");
});

pub fn compile_file(path: [*c]const u8) !void {
    const c_file_ptr = c.fopen(path, "r");

    if (c_file_ptr == null) {
        // Handle error
        @panic("Failed to open file");
    }

    grok.yyrestart(c_file_ptr);
    grok.yyparse();
}
