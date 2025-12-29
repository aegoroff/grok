const std = @import("std");
const flate = std.compress.flate;

pub fn main() !void {
    const file = try std.fs.cwd().createFile("bin/archive.tar.gz", .{});
    defer file.close();

    var file_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&file_buffer);

    var flate_buffer: [flate.max_window_len]u8 = undefined;
    const options: flate.Compress.Options = .{
        .level = .default,
        .container = .gzip,
    };
    const file_interface = &file_writer.interface;
    defer file_interface.flush() catch {};
    var compressor = flate.Compress.init(file_interface, &flate_buffer, options);
    var writer = compressor.writer;
    //defer writer.flush() catch {};

    try writeTarEntry(&writer, "hello.txt", "Hello World!");

    try writer.writeAll(&[_]u8{0} ** 1024);

    try compressor.end();
}

fn writeTarEntry(writer: *std.io.Writer, name: []const u8, content: []const u8) !void {
    var header = [_]u8{0} ** 512;

    const copy_len = @min(name.len, 100); // Standard tar name limit is 100
    @memcpy(header[0..copy_len], name[0..copy_len]);

    _ = std.fmt.bufPrint(header[124..135], "{o:0>11}", .{content.len}) catch unreachable;
    header[135] = ' '; // terminator

    _ = try writer.write(&header);
    _ = try writer.write(content);

    // Pad content to 512-byte boundary
    const padding = (512 - (content.len % 512)) % 512;
    var i: usize = 0;
    while (i < padding) : (i += 1) {
        try writer.writeAll(&[_]u8{0});
    }
}
