const std = @import("std");
const shell = @import("../shell.zig");

const Command = shell.Command;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const test_string = "teste   bruh   | piped command PIPE| 2tes abc\"quoted  string\" end";
    var it = try SyntaxIterator.init(allocator, test_string);
    std.debug.print("{s}\n", .{test_string});

    while (try it.next()) |word| {
        switch (word) {
            .command => |command| std.debug.print("command: {s} {?s}\n", .{
                command.system.name,
                command.system.arguments,
            }),
            .separator => |separator| std.debug.print("sep   : {s}\n", .{@tagName(separator)}),
        }
    }
}

pub const SyntaxIterator = struct {
    allocator: std.mem.Allocator,

    pos: usize,
    slice: []const u8,
    args: std.ArrayList([]const u8),

    in_quotes: bool = false,

    return_next: ?Word = null,

    // Chars that interrupt a word if they aren't quoted
    special_chars: [256]bool,

    pub const Word = union(enum) {
        command: Command,
        separator: Token.Separator,
    };

    pub const Token = union(enum) {
        string: []const u8,
        separator: Separator,

        pub const Separator = enum {
            pipe,
            whitespace,
        };
    };

    pub fn init(allocator: std.mem.Allocator, slice: []const u8) !SyntaxIterator {
        var special_characters: [256]bool = undefined;

        for (special_characters, 0..) |_, idx| {
            special_characters[idx] = false;
        }

        special_characters['|'] = true;
        special_characters[' '] = true;

        return .{
            .allocator = allocator,
            .special_chars = special_characters,
            .pos = 0,
            .slice = slice,
            .args = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(it: SyntaxIterator) void {
        it.args.deinit();
    }

    pub fn next(it: *SyntaxIterator) !?Word {
        var command: ?Command = null;

        const args_off = it.args.items.len;

        if (it.return_next) |word| {
            it.return_next = null;
            return word;
        }

        while (try it.nextToken()) |token| {
            switch (token) {
                .string => |string| {
                    if (command == null) {
                        command = .{ .kind = .system, .name = string };
                    } else {
                        try it.args.append(string);
                        command.?.arguments = it.args.items[args_off..];
                    }
                },
                .separator => |sep| {
                    if (sep == .whitespace) continue;

                    it.return_next = .{ .separator = sep };
                    if (command != null) {
                        return .{ .command = command.? };
                    }
                },
            }
        }

        if (command == null) return null;
        return .{ .command = command.? };
    }

    /// All strings must be freed by the caller
    pub fn nextToken(it: *SyntaxIterator) !?Token {
        const has_whitespace = it.advanceToNextWord();
        if (has_whitespace) {
            return .{ .separator = .whitespace };
        }

        var tok_buf = std.ArrayList(u8).init(it.allocator);
        var var_buf = std.ArrayList(u8).init(it.allocator);
        defer var_buf.deinit();

        var backslash_escape = false;
        var var_state: enum {
            none,
            // $var
            normal,
            // ${var}
            bracket,
        } = .none;

        var word_pos: usize = 0;

        for (it.slice[it.pos..]) |b| {
            var byte = b;
            var should_add = false;

            switch (byte) {
                '|' => {
                    if (tok_buf.items.len == 0 and !it.in_quotes) {
                        it.pos += 1;
                        return .{ .separator = .pipe };
                    }

                    if (backslash_escape) {
                        should_add = true;
                        backslash_escape = false;
                    } else if (it.in_quotes) {
                        should_add = true;
                    }
                },
                '\\' => {
                    if (backslash_escape) {
                        should_add = true;
                    }

                    backslash_escape = !backslash_escape;
                },
                '"' => {
                    if (backslash_escape) {
                        should_add = true;
                        backslash_escape = false;
                    } else {
                        it.in_quotes = !it.in_quotes;
                    }
                },
                '~' => {
                    if (it.in_quotes) {
                        should_add = true;
                    } else if (backslash_escape) {
                        should_add = true;
                        backslash_escape = false;
                    } else {
                        tok_buf.appendSlice(
                            std.posix.getenv("HOME") orelse "",
                        ) catch unreachable;
                    }
                },
                '$' => {
                    if (backslash_escape) {
                        should_add = true;
                        backslash_escape = false;
                    } else {
                        var_state = .normal;
                    }
                },
                '{' => {
                    switch (var_state) {
                        .normal => var_state = .bracket,
                        // TODO error
                        .bracket => unreachable,
                        .none => should_add = true,
                    }
                },
                '}' => {
                    switch (var_state) {
                        .normal => unreachable,
                        .none => should_add = true,
                        // TODO error
                        .bracket => var_state = .none,
                    }

                    _ = dumpVariableString(var_buf.items, tok_buf.writer());
                    var_buf.shrinkAndFree(0);
                },
                ' ' => {
                    if (it.in_quotes) should_add = true;

                    if (var_state == .normal) {
                        var_state = .none;
                        _ = dumpVariableString(var_buf.items, tok_buf.writer());
                        var_buf.shrinkAndFree(0);
                    }
                },
                else => {
                    if (backslash_escape) {
                        backslash_escape = false;

                        byte = switch (byte) {
                            'n' => '\n',
                            't' => '\t',
                            'r' => '\r',
                            else => byte,
                        };
                    }

                    should_add = true;
                },
            }

            if (should_add) {
                if (var_state != .none) {
                    var_buf.append(byte) catch unreachable;
                } else {
                    tok_buf.append(byte) catch unreachable;
                }
            }

            // Return the current word if a pipe, etc is encountered
            if (it.special_chars[byte] and !it.in_quotes) {
                defer it.pos += word_pos;
                return .{ .string = tok_buf.toOwnedSlice() catch unreachable };
            }

            word_pos += 1;

            // Return the current word if at the end of the string
            if (it.pos + word_pos >= it.slice.len) {
                switch (var_state) {
                    .bracket => return error.ExpectedBracket,
                    .normal => {
                        _ = dumpVariableString(var_buf.items, tok_buf.writer());
                        var_buf.shrinkAndFree(0);
                    },
                    else => {},
                }

                defer it.pos += word_pos;
                return .{ .string = tok_buf.toOwnedSlice() catch unreachable };
            }
        }

        return null;
    }

    // Coerces a variable of any type into a string
    // Returns null if variable doesn't exist
    fn dumpVariableString(name: []const u8, writer: anytype) bool {
        const v = shell.variables.get(name) orelse return false;

        _ = writer.write(v) catch unreachable;

        return true;
    }

    // Returns true if any whitespace was skipped
    fn advanceToNextWord(it: *SyntaxIterator) bool {
        const start_pos = it.pos;

        for (it.slice[it.pos..]) |byte| {
            if (byte != ' ') return start_pos != it.pos;
            it.pos += 1;
        }

        return start_pos != it.pos;
    }
};
