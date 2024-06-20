const Command = @This();

const std = @import("std");

pub const Result = enum {
    not_handled,
    @"continue",
    complete,
};

ptr: *anyopaque,
writeTo_fn: *const fn (*anyopaque, std.io.AnyWriter) anyerror!void,
handleLine_fn: *const fn (*anyopaque, []const u8) anyerror!Result,

pub fn writeTo(self: Command, writer: std.io.AnyWriter) !void {
    return self.writeTo_fn(self.ptr, writer);
}

pub fn handleLine(self: Command, line: []const u8) !Result {
    return self.handleLine_fn(self.ptr, line);
}
