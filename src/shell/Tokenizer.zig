const std = @import("std");
const expect = std.testing.expect;

const Tokenizer = @This();

in_reader: std.io.AnyReader,
out_writer: std.ArrayList(u8),

const Self = @This();

pub fn init(allocator: std.mem.Allocator, in_reader: std.io.AnyReader) Self {
    const out_writer = std.ArrayList(u8).init(allocator);

    return .{
        .in_reader = in_reader,
        .out_writer = out_writer,
    };
}

pub fn deinit(self: *Self) void {
    self.out_writer.deinit();
    self.* = undefined;
}

pub fn next(self: *Self) !?[]const u8 {
    self.out_writer.shrinkAndFree(0);

    var token: ?[]const u8 = null;
    var in_double_quotes = false;

    while (true) {
        const byte = self.in_reader.readByte() catch |err| {
            if (err == error.EndOfStream) break;

            return err;
        };

        switch (byte) {
            '\\' => {
                const next_byte = self.in_reader.readByte() catch |err| {
                    if (err == error.EndOfStream) break;

                    return err;
                };

                const write = switch (next_byte) {
                    '"' => '"',
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    'x' => blk: {
                        var buf: [2]u8 = undefined;
                        try self.in_reader.readNoEof(&buf);

                        break :blk try std.fmt.parseInt(u8, &buf, 16);
                    },

                    else => return error.InvalidEscapeChar,
                };

                try self.out_writer.append(write);
                token = self.out_writer.items;
            },
            ' ', '\n', '\t' => |whitespace| {
                if (in_double_quotes) {
                    try self.out_writer.append(whitespace);
                    token = self.out_writer.items;
                } else if (token == null) {
                    return self.next();
                } else {
                    return token;
                }
            },
            '"' => in_double_quotes = !in_double_quotes,

            else => {
                try self.out_writer.append(byte);
                token = self.out_writer.items;
            },
        }
    }

    return token;
}

test "tokenize" {
    const source =
        \\ string \"string 2" quoted "with_quoted final
    ;

    var fbs = std.io.fixedBufferStream(source);
    var fbs_reader = fbs.reader();

    var tokenizer = Tokenizer.init(std.testing.allocator, fbs_reader.any());
    defer tokenizer.deinit();

    try expect(std.mem.eql(u8, (try tokenizer.next()).?, "string"));
    try expect(std.mem.eql(u8, (try tokenizer.next()).?, "\"string"));
    try expect(std.mem.eql(u8, (try tokenizer.next()).?, "2 quoted with_quoted"));
    try expect(std.mem.eql(u8, (try tokenizer.next()).?, "final"));

    while (try tokenizer.next()) |token| {
        std.debug.print("tok: {s}\n", .{token});
    }
}
