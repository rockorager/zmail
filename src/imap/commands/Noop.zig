const Noop = @This();

const std = @import("std");
const imap = @import("../../imap.zig");
const Command = @import("../Command.zig");
const HandleResult = Command.HandleResult;
const Result = Command.Result;

const log = std.log.scoped(.imap);

const name = "NOOP";

mutex: std.Thread.Mutex = .{},
cond: std.Thread.Condition = .{},
result: ?Result = null,

/// Get the next tag from the client
tag: u16,

/// Waits for the command to finish and returns the capability string. The string is space
/// separated, users of the library are encouraged to inspect the list however they please
pub fn wait(self: *Noop) imap.Error!void {
    while (self.result == null) {
        self.cond.wait(&self.mutex);
    }
    switch (self.result.?) {
        .ok => return,
        .no => return error.InvalidArgumentsOrCommandUnknown,
        .bad => return error.InvalidArgumentsOrCommandUnknown,
    }
}

pub fn command(self: *Noop) Command {
    return .{
        .ptr = self,
        .writeTo_fn = writeTo,
        .handleLine_fn = handleLine,
    };
}

fn writeTo(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
    const self: *Noop = @ptrCast(@alignCast(ptr));
    try writer.print("{x} {s}\r\n", .{ self.tag, name });
    self.mutex.lock();
}

fn handleLine(ptr: *anyopaque, line: []const u8) !HandleResult {
    if (line.len == 0) return .not_handled;
    const self: *Noop = @ptrCast(@alignCast(ptr));

    var iter = std.mem.splitScalar(u8, line, ' ');
    const tag = iter.next() orelse return .not_handled;

    if (tag[0] == '*') return .not_handled;

    if (!std.ascii.isAlphanumeric(tag[0])) return .not_handled;

    const tag_parsed = try std.fmt.parseUnsigned(u8, tag, 16);
    if (tag_parsed != self.tag) return .not_handled;

    defer self.cond.signal();
    const result = iter.next() orelse return .not_handled;

    self.result = try Result.fromString(result);
    switch (self.result.?) {
        .ok => {},
        else => log.warn("{s}: {s}", .{ name, line }),
    }
    return .complete;
}
