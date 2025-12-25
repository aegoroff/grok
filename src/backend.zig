const std = @import("std");
const front = @import("frontend.zig");

pub const Pattern = struct {
    regex: []const u8,
    properties: std.ArrayList([]const u8),
};

pub fn create_pattern(allocator: std.mem.Allocator, macro: []const u8) ?Pattern {
    const m = front.get_pattern(macro).?;
    var stack = std.ArrayList(front.Info){};
    var composition = std.ArrayList(u8){};
    var result = Pattern{ .properties = std.ArrayList([]const u8){}, .regex = "" };
    for (m.items) |value| {
        stack.append(allocator, value) catch return null;
        while (stack.items.len > 0) {
            const current = stack.pop().?;
            const current_slice = std.mem.sliceTo(current.data, 0);
            if (current.part == .literal) {
                // plain literal case
                composition.appendSlice(allocator, current_slice) catch return null;
            } else {
                if (current.reference != null) {
                    // leading (?<name> immediately into composition
                    const reference = std.mem.sliceTo(current.reference, 0);
                    composition.appendSlice(allocator, "(?<") catch return null;
                    composition.appendSlice(allocator, reference) catch return null;
                    composition.appendSlice(allocator, ">") catch return null;
                    result.properties.append(allocator, reference) catch return null;

                    // trailing ) into stack bottom
                    const trail_paren = front.Info{ .data = ")", .reference = null, .part = .literal };
                    stack.append(allocator, trail_paren) catch return null;
                }
                const childs = front.get_pattern(current_slice) orelse {
                    continue;
                };
                var rev_iter = std.mem.reverseIterator(childs.items);
                while (rev_iter.next()) |child| {
                    stack.append(allocator, child) catch return null;
                }
            }
        }
    }
    result.regex = composition.items;
    return result;
}
