const std = @import("std");
const builtin = @import("builtin");

/// Calendar (Gregorian) date
pub const Date = struct {
    nanoseconds: u32,
    seconds: u6,
    minutes: u6,
    hours: u5,
    day: u5,
    weekday: Weekday,
    month: Month,
    year: isize,

    const s_per_d = (60 * 60 * 24);
    const d_per_400y = 365 * 400 + 97;
    const d_per_100y = 365 * 100 + 24;
    const d_per_4y = 365 * 4 + 1;

    // 2000-03-01 (mod 400 year, immediately after Feb 29th)
    const leapoch = (946684800 + (s_per_d * (31 + 29)));

    const days_in_month = [12]u5{ 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 29 };

    pub const Weekday = enum(u3) {
        sunday = 0,
        monday = 1,
        tuesday = 2,
        wednesday = 3,
        thursday = 4,
        friday = 5,
        saturday = 6,
    };

    pub const Month = enum(u4) {
        january = 1,
        february = 2,
        march = 3,
        april = 4,
        may = 5,
        june = 6,
        july = 7,
        august = 8,
        september = 9,
        october = 10,
        november = 11,
        december = 12,

        pub fn numeric(m: Month) u4 {
            return @intFromEnum(m);
        }
    };

    pub fn nowUtc() Date {
        return Date.fromTimestamp(Timestamp.nowUtc());
    }

    pub fn nowLocal() Date {
        return Date.fromTimestamp(Timestamp.nowLocal());
    }

    pub fn fromUnix(seconds: i64) Date {
        return fromTimestamp(.{ .seconds = seconds });
    }

    pub fn fromUnixMillis(milliseconds: i64) Date {
        return fromTimestamp(.{
            .seconds = milliseconds / 1000,
            .nanoseconds = (milliseconds % 1000) * 1_000_000,
        });
    }

    // Ported from Musl libc
    // <https://git.musl-libc.org/cgit/musl/tree/src/time/__secs_to_tm.c?h=v0.9.15>
    pub fn fromTimestamp(timestamp: Timestamp) Date {
        const secs = timestamp.seconds - leapoch;
        var days = @divTrunc(secs, s_per_d);
        var remsecs = @rem(secs, s_per_d);
        if (remsecs < 0) {
            remsecs += s_per_d;
            days -= 1;
        }

        var qc_cycles = @divTrunc(days, d_per_400y);
        var remdays = @rem(days, d_per_400y);
        if (remdays < 0) {
            remdays += d_per_400y;
            qc_cycles -= 1;
        }

        var c_cycles = @divFloor(remdays, d_per_100y);
        if (c_cycles == 4) {
            c_cycles -= 1;
        }
        remdays -= c_cycles * d_per_100y;

        var q_cycles = @divTrunc(remdays, d_per_4y);
        if (q_cycles == 25) {
            q_cycles -= 1;
        }
        remdays -= q_cycles * d_per_4y;

        var remyears = @divTrunc(remdays, 365);
        if (remyears == 4) {
            remyears -= 1;
        }
        remdays -= remyears * 365;

        const leap: i64 = if (remyears == 0 and (q_cycles != 0 or c_cycles == 0)) 1 else 0;
        var yday = remdays + 31 + 28 + leap;
        if (yday >= 365 + leap) yday -= 365 + leap;

        var years = remyears + (4 * q_cycles) + (100 * c_cycles) + (400 * qc_cycles);

        var m: u4 = 0;
        while (days_in_month[m] <= remdays) : (m += 1) {
            remdays -= days_in_month[m];
        }

        var mnth = m + 2;

        if (m >= 10) {
            years += 1;
            mnth -= 12;
        }

        return .{
            .nanoseconds = timestamp.nanoseconds,
            .seconds = @intCast(@mod(remsecs, 60)),
            .minutes = @intCast(@mod(@divTrunc(remsecs, 60), 60)),
            .hours = @intCast(@divTrunc(remsecs, 60 * 60)),
            .weekday = @enumFromInt(@mod(days + 3, 7)),
            .day = @intCast(remdays + 1),
            .month = @enumFromInt(mnth + 1),
            .year = years + 2000,
        };
    }

    pub fn format(
        date: Date,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        if (date.year < 0) {
            try out_stream.print("{d:0>4}", .{
                date.year,
            });
        } else {
            try out_stream.print("{d:0>4}", .{
                @as(usize, @intCast(date.year)),
            });
        }

        try out_stream.print("-{d:0>2}-{d:0>2}", .{
            date.month.numeric(),
            date.day,
        });

        if (date.hours > 0 or date.minutes > 0 or date.seconds > 0) {
            try out_stream.print("T{d:0>2}:{d:0>2}:{d:0>2}", .{
                date.hours,
                date.minutes,
                date.seconds,
            });
        }

        if (date.nanoseconds > 0) {
            // Remove following zeroes
            var new = date.nanoseconds;
            while (new / 10 * 10 == new) {
                new /= 10;
            }

            try out_stream.print(".{d}", .{
                new,
            });
        }
    }
};

/// This type is inspired by C stdlib's `timespec`
pub const Timestamp = struct {
    seconds: i64,

    // Must be between 0 and 1,000,000,000
    nanoseconds: u30 = 0,

    pub fn nowUtc() Timestamp {
        const unix_nanoseconds = std.time.nanoTimestamp();

        return .{
            .seconds = @intCast(@divTrunc(
                unix_nanoseconds,
                std.time.ns_per_s,
            )),
            .nanoseconds = @intCast(@mod(
                unix_nanoseconds,
                std.time.ns_per_s,
            )),
        };
    }

    pub fn nowLocal() Timestamp {
        return switch (builtin.os.tag) {
            .linux => nowLocalLinuxImpl(),

            else => @compileError("`nowLocal` not yet implemented for OS"),
        };
    }

    fn nowLocalLinuxImpl() Timestamp {
        const Container = struct {
            // If `localtime` is called, these will be populated for caching
            var local_tz: ?std.tz.Tz = null;
            var latest_transition_idx: usize = 0;
        };

        if (Container.local_tz == null) {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();

            const cwd = std.fs.cwd();

            var tz_file = cwd.openFile(
                "/etc/localtime",
                .{},
            ) catch return nowUtc();
            defer tz_file.close();

            Container.local_tz = std.tz.Tz.parse(
                allocator,
                tz_file.reader(),
            ) catch return nowUtc();
        }

        const utc_time = Timestamp.nowUtc();

        var latest_transition: ?std.tz.Transition = null;
        for (Container.local_tz.?.transitions[Container.latest_transition_idx..], 0..) |trans, idx| {
            if (trans.ts >= utc_time.seconds) {
                Container.latest_transition_idx += idx - 1;
                break;
            }

            latest_transition = trans;
        }

        return .{
            .seconds = utc_time.seconds + latest_transition.?.timetype.offset,
            .nanoseconds = utc_time.nanoseconds,
        };
    }
};
