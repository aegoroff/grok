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

    //grok.yyrestart(c_file_ptr);
    if(grok.yyparse() > 0){
        @panic("Failed to parse file");
    }

}

pub export fn fend_on_literal(_: [*c]const u8) void {
    // Implementation of fend_on_literal function
}

pub export fn fend_on_definition() void {
    // Implementation of fend_on_definition function
}

pub export fn fend_on_definition_end(_: [*c]const u8) void {
    // Implementation of fend_on_definition_end function
}

pub export fn fend_strdup(s: [*c]const u8) [*c]const u8 {
    // Implementation of fend_strdup function
    return s;
}

pub export fn fend_on_macro(_: [*c]const u8, _: [*c]const u8) *grok.macro_t {
    // Implementation of fend_on_macro function
    return @as(?*grok.macro_t, null) orelse @as(*grok.macro_t, undefined);
}

pub export fn fend_on_grok(_: *grok.macro_t) void {
    // Implementation of fend_on_grok function
}
