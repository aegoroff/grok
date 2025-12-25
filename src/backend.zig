const std = @import("std");
const front = @import("frontend.zig");

pub const Pattern = struct {
    regex: []const u8,
    properties: std.ArrayList([]const u8),
};

pub fn create_pattern(allocator: std.mem.Allocator, macro: []const u8) !?Pattern {
    const m = front.get_pattern(macro).?;
    var stack = std.ArrayList(front.Info){};
    var composition = std.ArrayList(u8){};
    var used_properties = std.StringHashMap(bool).init(allocator);
    var result = Pattern{ .properties = std.ArrayList([]const u8){}, .regex = "" };
    for (m.items) |value| {
        try stack.append(allocator, value);
        while (stack.items.len > 0) {
            const current = stack.pop().?;
            const current_slice = std.mem.span(current.data);
            if (current.part == .literal) {
                // plain literal case
                try composition.appendSlice(allocator, current_slice);
            } else {
                if (current.reference != null) {
                    // leading (?<name> immediately into composition
                    var reference = std.mem.span(current.reference);
                    if (used_properties.contains(reference)) {
                        var concat = std.ArrayList(u8){};
                        try concat.appendSlice(allocator, current_slice);
                        try concat.appendSlice(allocator, "_");
                        try concat.appendSlice(allocator, reference);
                        reference = concat.items[0.. :0];
                    }
                    try used_properties.put(reference, true);

                    try composition.appendSlice(allocator, "(?<");
                    try composition.appendSlice(allocator, reference);
                    try composition.appendSlice(allocator, ">");
                    try result.properties.append(allocator, reference);

                    // trailing ) into stack bottom
                    const trail_paren = front.Info{ .data = ")", .reference = null, .part = .literal };
                    try stack.append(allocator, trail_paren);
                }
                const childs = front.get_pattern(current_slice) orelse {
                    continue;
                };
                var rev_iter = std.mem.reverseIterator(childs.items);
                while (rev_iter.next()) |child| {
                    try stack.append(allocator, child);
                }
            }
        }
    }
    result.regex = composition.items;
    return result;
}
