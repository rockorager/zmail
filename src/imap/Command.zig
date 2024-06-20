const Command = @This();

const std = @import("std");

pub const HandleResult = enum {
    not_handled,
    @"continue",
    complete,
    /// Only sent by the logout command
    quit,
};

pub const Result = enum {
    ok,
    no,
    bad,

    pub fn fromString(str: []const u8) !Result {
        switch (str.len) {
            2 => {
                if (std.ascii.eqlIgnoreCase(str, "ok")) return .ok;
                if (std.ascii.eqlIgnoreCase(str, "no")) return .no;
                return error.InvalidResult;
            },
            3 => {
                if (std.ascii.eqlIgnoreCase(str, "bad")) return .bad;
                return error.InvalidResult;
            },
            else => return error.InvalidResult,
        }
    }
};

ptr: *anyopaque,
writeTo_fn: *const fn (*anyopaque, std.io.AnyWriter) anyerror!void,
handleLine_fn: *const fn (*anyopaque, []const u8) anyerror!HandleResult,

pub fn writeTo(self: Command, writer: std.io.AnyWriter) !void {
    return self.writeTo_fn(self.ptr, writer);
}

pub fn handleLine(self: Command, line: []const u8) !HandleResult {
    return self.handleLine_fn(self.ptr, line);
}
