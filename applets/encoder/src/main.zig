const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.wasm_allocator;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const stdin = std.io.getStdIn().reader();

    const buf = try allocator.alloc(u8, 4096);

    while (true) {
        const read = try stdin.readUntilDelimiterOrEof(buf, 't');

        stdout.print("{?s}!!\n", .{read}) catch {};

        if (read == null) break;
    }

    try bw.flush(); // don't forget to flush!

    return;
}
