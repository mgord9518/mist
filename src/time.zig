const std = @import("std");

pub fn main() void {
    const time = Timestamp{
        //.seconds = 1719283209,
        .seconds = -45812848561,
        .nanoseconds = 10069,
    };
    //   std.debug.print("UNIX: {d}\n", .{time.seconds});
    //    std.debug.print("YEAR: {d}\n", .{time.year()});
    //    std.debug.print("MONTH: {} {d}\n", .{
    //        time.month(),
    //        time.month().numeric(),
    //    });

    std.debug.print("DATE: {}\n", .{Date.fromTimestamp(time)});

    //time.dump();
}

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

            try out_stream.print(".{d:<}", .{
                new,
            });
        }
    }
};

/// This type is inspired by C stdlib's `timespec`
pub const Timestamp = struct {
    seconds: i64,
    nanoseconds: u32 = 0,

    //    pub fn year(time: *const Timestamp) isize {
    //        const secs = time.seconds - leapoch;
    //        var days = @divTrunc(secs, s_per_d);
    //        var remsecs = @rem(secs, s_per_d);
    //        if (remsecs < 0) {
    //            remsecs += s_per_d;
    //            days -= 1;
    //        }
    //
    //        var qc_cycles = @divTrunc(days, d_per_400y);
    //        var remdays = @rem(days, d_per_400y);
    //        if (remdays < 0) {
    //            remdays += d_per_400y;
    //            qc_cycles -= 1;
    //        }
    //
    //        var c_cycles = @divFloor(remdays, d_per_100y);
    //        if (c_cycles == 4) {
    //            c_cycles -= 1;
    //        }
    //        remdays -= c_cycles * d_per_100y;
    //
    //        var q_cycles = @divTrunc(remdays, d_per_4y);
    //        if (q_cycles == 25) {
    //            q_cycles -= 1;
    //        }
    //        remdays -= q_cycles * d_per_4y;
    //
    //        var remyears = @divTrunc(remdays, 365);
    //        if (remyears == 4) {
    //            remyears -= 1;
    //        }
    //        remdays -= remyears * 365;
    //
    //        const leap: i64 = if (remyears == 0 and (q_cycles != 0 or c_cycles == 0)) 1 else 0;
    //        var yday = remdays + 31 + 28 + leap;
    //        if (yday >= 365 + leap) yday -= 365 + leap;
    //
    //        const years = remyears + (4 * q_cycles) + (100 * c_cycles) + (400 * qc_cycles);
    //
    //        var m: u4 = 0;
    //        while (days_in_month[m] <= remdays) : (m += 1) {
    //            remdays -= days_in_month[m];
    //        }
    //
    //        if (m + 2 >= 12) {
    //            return years + 2001;
    //        }
    //
    //        return years + 2000;
    //    }
    //
    //    pub fn month(time: *const Timestamp) Date.Month {
    //        const secs = time.seconds - leapoch;
    //        var days = @divTrunc(secs, s_per_d);
    //        var remsecs = @rem(secs, s_per_d);
    //        if (remsecs < 0) {
    //            remsecs += s_per_d;
    //            days -= 1;
    //        }
    //
    //        var remdays = @rem(days, d_per_400y);
    //        if (remdays < 0) {
    //            remdays += d_per_400y;
    //        }
    //
    //        var c_cycles = @divFloor(remdays, d_per_100y);
    //        if (c_cycles == 4) {
    //            c_cycles -= 1;
    //        }
    //        remdays -= c_cycles * d_per_100y;
    //
    //        var q_cycles = @divTrunc(remdays, d_per_4y);
    //        if (q_cycles == 25) {
    //            q_cycles -= 1;
    //        }
    //        remdays -= q_cycles * d_per_4y;
    //
    //        var remyears = @divTrunc(remdays, 365);
    //        if (remyears == 4) {
    //            remyears -= 1;
    //        }
    //        remdays -= remyears * 365;
    //
    //        const leap: i64 = if (remyears == 0 and (q_cycles != 0 or c_cycles == 0)) 1 else 0;
    //        var yday = remdays + 31 + 28 + leap;
    //        if (yday >= 365 + leap) yday -= 365 + leap;
    //
    //        var m: u4 = 0;
    //        while (days_in_month[m] <= remdays) : (m += 1) {
    //            remdays -= days_in_month[m];
    //        }
    //
    //        var mnth = m + 2;
    //
    //        if (m >= 10) {
    //            mnth -= 12;
    //        }
    //
    //        return @enumFromInt(mnth);
    //    }
    //
    //    fn dumpe(time: *const Timestamp) void {
    //        const secs = time.seconds - leapoch;
    //        var days = @divTrunc(secs, s_per_d);
    //        var remsecs = @rem(secs, s_per_d);
    //        if (remsecs < 0) {
    //            remsecs += s_per_d;
    //            days -= 1;
    //        }
    //
    //        var wday = @rem(3 + days, 7);
    //        if (wday < 0) {
    //            wday += 7;
    //        }
    //
    //        var qc_cycles = @divTrunc(days, d_per_400y);
    //        std.debug.print("qc {d}\n", .{qc_cycles});
    //        var remdays = @rem(days, d_per_400y);
    //        if (remdays < 0) {
    //            remdays += d_per_400y;
    //            qc_cycles -= 1;
    //        }
    //        std.debug.print("qc {d}\n", .{qc_cycles});
    //
    //        var c_cycles = @divFloor(remdays, d_per_100y);
    //        std.debug.print("c {d}\n", .{c_cycles});
    //        if (c_cycles == 4) {
    //            c_cycles -= 1;
    //        }
    //        remdays -= c_cycles * d_per_100y;
    //        std.debug.print("c {d}\n", .{c_cycles});
    //
    //        var q_cycles = @divTrunc(remdays, d_per_4y);
    //        std.debug.print("q {d}\n", .{q_cycles});
    //        if (q_cycles == 25) {
    //            q_cycles -= 1;
    //        }
    //        remdays -= q_cycles * d_per_4y;
    //        std.debug.print("q {d}\n", .{q_cycles});
    //
    //        var remyears = @divTrunc(remdays, 365);
    //        if (remyears == 4) {
    //            remyears -= 1;
    //        }
    //        remdays -= remyears * 365;
    //
    //        const leap: i64 = if (remyears == 0 and (q_cycles != 0 or c_cycles == 0)) 1 else 0;
    //        var yday = remdays + 31 + 28 + leap;
    //        if (yday >= 365 + leap) yday -= 365 + leap;
    //
    //        const years = remyears + (4 * q_cycles) + (100 * c_cycles) + (400 * qc_cycles);
    //
    //        var m: u4 = 0;
    //        while (days_in_month[m] <= remdays) : (m += 1) {
    //            remdays -= days_in_month[m];
    //        }
    //
    //        // TODO INT MAX
    //        //if (years + 100)
    //
    //        std.debug.print("year: {d}\n", .{years + 2000});
    //        std.debug.print("month: {d}\n", .{m + 2});
    //        if (m + 2 >= 12) {
    //            std.debug.print("year: {d}\n", .{years + 101});
    //            std.debug.print("month: {d}\n", .{m - 10});
    //        }
    //    }
};
