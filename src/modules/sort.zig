const std = @import("std");
const core = @import("../main.zig");
const fg = core.fg;
const curses = @import("../shell/curses.zig");
const S = std.posix.S;

pub const exec_mode: core.ExecMode = .fork;

pub const help = core.Help{
    .description = "list files in a directory",
    .usage = "[-alUr1] [DIR]",
    .options = &.{
        .{ .flag = 'a', .description = "show hidden files" },
        .{ .flag = 'r', .description = "sort in reverse order" },
    },
};

pub fn main(arguments: []const core.Argument) core.Error {
    //  const stdout_file = std.io.getStdOut();
    // const stdout = stdout_file.writer();

    //  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //   const allocator = gpa.allocator();

    var rev_sort = false;

    var target: ?[]const u8 = null;
    for (arguments) |arg| {
        if (arg == .option) switch (arg.option[1]) {
            'r' => rev_sort = true,

            else => return .usage_error,
        };

        if (arg == .positional) {
            target = arg.positional;
        }
    }

    //    std.mem.sort(
    //        []const u8,
    //        file_list.items,
    //        @as(SortContext, .{
    //            .order = .alphabetic,
    //            .reverse = rev_sort,
    //        }),
    //        sortFn,
    //    );

    return .success;
}

const SortContext = struct {
    reverse: bool = false,
    order: Order,

    const Order = enum {
        alphabetic,
        size,
    };
};

//pub fn sortFn(ctx: SortContext, a: Entry, b: Entry) bool {
//
//    const ret = switch (ctx.order) {
//        .alphabetic => sortByAlphabet({}, a, b),
//        //.alphabetic => sortByAlphabetBytes({}, a, b),
//        .size => sortBySize({}, a, b),
//    };
//
//    if (ctx.reverse) return !ret;
//
//    return ret;
//}

/// Sorts UTF-8 strings ordered by lower to higher codepoints preferring
/// shorter strings.
pub fn sortByAlphabet(
    _: void,
    a: []const u8,
    b: []const u8,
) bool {
    var utf8_view_a = std.unicode.Utf8View.init(
        a,
    ) catch return true;

    var utf8_view_b = std.unicode.Utf8View.init(
        b,
    ) catch return false;

    var it_a = utf8_view_a.iterator();
    var it_b = utf8_view_b.iterator();

    while (true) {
        const codepoint_a = it_a.nextCodepoint() orelse return true;
        const codepoint_b = it_b.nextCodepoint() orelse return false;

        if (codepoint_a > codepoint_b) {
            return false;
        } else if (codepoint_a < codepoint_b) {
            return true;
        }
    }

    unreachable;
}

/// Sorts strings by byte values. This is smaller and simpler than the UTF-8
/// version but will not properly sort Unicode strings
fn sortByAlphabetBytes(
    _: void,
    a: []const u8,
    b: []const u8,
) bool {
    var a_idx: usize = 0;
    var b_idx: usize = 0;

    while (true) {
        const char_a = a[a_idx];
        const char_b = b[b_idx];

        if (char_a > char_b) {
            return false;
        } else if (char_a < char_b) {
            return true;
        }

        a_idx += 1;
        b_idx += 1;

        if (a_idx >= a.len) return true;
        if (b_idx >= b.len) return false;
    }

    unreachable;
}
