const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source = "string\\\"string 2\"";

    var fbs = std.io.fixedBufferStream(source);
    var fbs_reader = fbs.reader();

    var tokenizer = Tokenizer.init(allocator, fbs_reader.any());

    while (try tokenizer.next()) |token| {
        std.debug.print("tok: {s}\n", .{token.string});
    }
}

const State = enum {
    expect_open_curly,
    expect_close_curly,
    dollar_sign,
    expect_close_bracket,
    text,
};

const Token = union(enum) {
    string: []const u8,
    whitespace: usize, // Length of whitespace in bytes
};

pub const Tokenizer = struct {
    in_reader: std.io.AnyReader,
    out_writer: std.ArrayList(u8),
    state: State = .text,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, in_reader: std.io.AnyReader) Self {
        const out_writer = std.ArrayList(u8).init(allocator);

        return .{
            .in_reader = in_reader,
            .out_writer = out_writer,
        };
    }

    pub fn next(self: *Self) !?Token {
        var token: ?Token = null;

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
                    token = Token{ .string = self.out_writer.items };
                },

                else => {
                    try self.out_writer.append(byte);
                    token = Token{ .string = self.out_writer.items };
                },
            }
        }

        return token;
    }
};
