const std = @import("std");

pub fn main() !void {
    const source = "\\x20\\x20\\n\\thi $[HOME]";

    var stdout = std.io.getStdOut();

    var fbs = std.io.fixedBufferStream(source);
    var fbs_reader = fbs.reader();

    var it = StringSubstitutionIterator.init(fbs_reader.any(), stdout.writer().any());

    try it.process();
}

const State = enum {
    expect_open_curly,
    expect_close_curly,
    dollar_sign,
    expect_close_bracket,
    text,
};

pub const StringSubstitutionIterator = struct {
    in_reader: std.io.AnyReader,
    out_writer: std.io.AnyWriter,
    state: State = .text,

    const Self = @This();

    pub fn init(in_reader: std.io.AnyReader, out_writer: std.io.AnyWriter) Self {
        return .{
            .in_reader = in_reader,
            .out_writer = out_writer,
        };
    }

    fn handleEscapable(self: *Self) !void {
        const byte = self.in_reader.readByte() catch |err| {
            if (err == error.EndOfStream) return error.ExpectedEscapedChar;
            return err;
        };

        const write = switch (byte) {
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

        try self.out_writer.writeByte(write);
    }

    fn handleOpenBracket(self: *Self) !void {
        return switch (self.state) {
            .dollar_sign => {
                try self.dumpEnvironmentVariable();
            },

            else => return error.UnexpectedOpenBracket,
        };
    }

    pub fn process(self: *Self) !void {
        while (true) {
            const byte = self.in_reader.readByte() catch |err| {
                if (err == error.EndOfStream) return;

                return err;
            };

            switch (byte) {
                '$' => switch (self.state) {
                    .text => self.state = .dollar_sign,
                    else => return error.UnexpectedSymbol,
                },
                '[' => try self.handleOpenBracket(),
                '{' => try self.handleOpenBracket(),
                '\\' => try self.handleEscapable(),
                else => try self.out_writer.writeByte(byte),
            }
        }
    }

    // Must be called when `self.state` is expecting an open curly.
    // Next bytes from `self.in_reader` until `}` constitute the variable
    // name, which is then pulled from the variable map and dumped to
    // `self.out_writer`
    fn dumpEnvironmentVariable(self: *Self) !void {
        std.debug.assert(self.state == .dollar_sign);

        self.state = .text;

        var buf: [256]u8 = undefined;
        var variable_name_buf = std.io.fixedBufferStream(&buf);

        // Dump variable contents to writer
        self.in_reader.streamUntilDelimiter(
            variable_name_buf.writer(),
            ']',
            null,
        ) catch |err| {
            if (err == error.EndOfStream) return error.ExpectedCloseCurly;
            return err;
        };

        const variable_name = variable_name_buf.buffer[0..variable_name_buf.pos];

        if (std.posix.getenv(variable_name)) |variable| {
            try self.out_writer.print(
                "env var val: !{s}!",
                .{variable},
            );
        } else {
            return error.EnvironmentVariableNotFound;
        }
    }

    fn dumpLocalVariable(self: *Self) !void {
        std.debug.assert(self.state == .dollar_sign);

        self.state = .text;

        var buf: [256]u8 = undefined;
        var variable_name_buf = std.io.fixedBufferStream(&buf);

        // Dump variable contents to writer
        self.in_reader.streamUntilDelimiter(
            variable_name_buf.writer(),
            ']',
            null,
        ) catch |err| {
            if (err == error.EndOfStream) return error.ExpectedCloseCurly;
            return err;
        };

        const variable_name = variable_name_buf.buffer[0..variable_name_buf.pos];

        if (std.posix.getenv(variable_name)) |variable| {
            try self.out_writer.print(
                "env var val: !{s}!",
                .{variable},
            );
        } else {
            return error.EnvironmentVariableNotFound;
        }
    }
};
