const Capability = @This();

const std = @import("std");
const imap = @import("../../imap.zig");
const Command = @import("../Command.zig");
const CommandResult = Command.Result;
const Result = Command.HandleResult;

const log = std.log.scoped(.imap);

const name = "CAPABILITY";

mutex: std.Thread.Mutex = .{},
cond: std.Thread.Condition = .{},
cap_string: std.ArrayList(u8),
result: ?CommandResult = null,

/// Get the next tag from the client
tag: u16,

pub fn init(allocator: std.mem.Allocator, tag: u16) Capability {
    return .{
        .tag = tag,
        .cap_string = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Capability) void {
    self.cap_string.deinit();
}

/// Waits for the command to finish and returns the capability string. The string is space
/// separated, users of the library are encouraged to inspect the list however they please
pub fn wait(self: *Capability) ![]const u8 {
    while (self.result == null) {
        self.cond.wait(&self.mutex);
    }
    switch (self.result.?) {
        .ok => return self.cap_string.items,
        .bad => return error.InvalidArguments,
        else => return error.InvalidArguments,
    }
}

pub fn command(self: *Capability) Command {
    return .{
        .ptr = self,
        .writeTo_fn = writeTo,
        .handleLine_fn = handleLine,
    };
}

fn writeTo(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
    const self = toSelf(*Capability, ptr);
    try writer.print("{x} {s}\r\n", .{ self.tag, name });
    self.mutex.lock();
}

fn handleLine(ptr: *anyopaque, line: []const u8) !Result {
    if (line.len == 0) return .not_handled;
    const self = toSelf(*Capability, ptr);

    var iter = std.mem.splitScalar(u8, line, ' ');
    const tag = iter.next() orelse return .not_handled;

    if (tag.len == 1 and tag[0] == '*') {
        const resp_name = iter.next() orelse return .not_handled;
        if (!std.ascii.eqlIgnoreCase(resp_name, name)) return .not_handled;
        while (iter.next()) |cap| {
            try self.cap_string.appendSlice(cap);
            try self.cap_string.append(' ');
        }
        return .@"continue";
    }

    const tag_parsed = try std.fmt.parseUnsigned(u8, tag, 16);

    if (tag_parsed == self.tag) {
        defer self.cond.signal();
        const result = iter.next() orelse return .not_handled;
        self.result = try CommandResult.fromString(result);
        switch (self.result.?) {
            .ok => {},
            else => log.warn("{s}: {s}", .{ name, line }),
        }
        return .complete;
    }

    return .not_handled;
}

fn toSelf(T: type, ptr: *anyopaque) T {
    return @ptrCast(@alignCast(ptr));
}
