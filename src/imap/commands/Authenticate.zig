const Authenticate = @This();

const std = @import("std");
const Command = @import("../Command.zig");
const Result = Command.Result;
const base64 = std.base64.standard;

const log = std.log.scoped(.imap);

const name = "AUTHENTICATE";

pub const Mechanism = enum {
    plain,
    login,
    oauth,
    xoauth2,
};

mutex: std.Thread.Mutex = .{},
cond: std.Thread.Condition = .{},
done: bool = false,
ok: bool = false,

allocator: std.mem.Allocator,
/// the base64 encoded auth string
username: []const u8,
password: []const u8,
mechanism: Mechanism,

writer: ?std.io.AnyWriter = null,

/// Get the next tag from the client
tag: u16,

pub fn init(
    allocator: std.mem.Allocator,
    username: []const u8,
    password: []const u8,
    mechanism: Mechanism,
    tag: u16,
) Authenticate {
    return .{
        .tag = tag,
        .allocator = allocator,
        .username = username,
        .password = password,
        .mechanism = mechanism,
    };
}

/// Waits for the command to finish and returns the capability string. The string is space
/// separated, users of the library are encouraged to inspect the list however they please
pub fn wait(self: *Authenticate) !void {
    while (!self.done) {
        self.cond.wait(&self.mutex);
    }
    if (self.ok)
        return
    else
        return error.AuthenticationFailed;
}

pub fn command(self: *Authenticate) Command {
    return .{
        .ptr = self,
        .writeTo_fn = writeTo,
        .handleLine_fn = handleLine,
    };
}

fn writeTo(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
    const self: *Authenticate = @ptrCast(@alignCast(ptr));
    self.writer = writer;
    self.mutex.lock();
    switch (self.mechanism) {
        .plain => {
            const str = try std.fmt.allocPrint(self.allocator, "\x00{s}\x00{s}", .{ self.username, self.password });
            const n = base64.Encoder.calcSize(str.len);
            const auth_str_enc = try self.allocator.alloc(u8, n);
            const result = base64.Encoder.encode(auth_str_enc, str);
            try writer.print("{x} {s} PLAIN {s}\r\n", .{ self.tag, name, result });
        },
        .login => {
            const n = base64.Encoder.calcSize(self.username.len);
            const auth_str_enc = try self.allocator.alloc(u8, n);
            defer self.allocator.free(auth_str_enc);
            const result = base64.Encoder.encode(auth_str_enc, self.username);
            try writer.print("{x} {s} LOGIN {s}\r\n", .{ self.tag, name, result });
        },
        .oauth => {
            const auth_str = try std.fmt.allocPrint(
                self.allocator,
                "n,a={s},\x01auth=Bearer {s}\x01\x01",
                .{ self.username, self.password },
            );
            defer self.allocator.free(auth_str);
            const n = base64.Encoder.calcSize(auth_str.len);
            const auth_str_enc = try self.allocator.alloc(u8, n);
            defer self.allocator.free(auth_str_enc);
            const result = base64.Encoder.encode(auth_str_enc, auth_str);
            try writer.print("{x} {s} OAUTH {s}\r\n", .{ self.tag, name, result });
        },
        .xoauth2 => {
            const auth_str = try std.fmt.allocPrint(
                self.allocator,
                "user={s}\x01auth=Bearer {s}\x01\x01",
                .{ self.username, self.password },
            );
            defer self.allocator.free(auth_str);
            const n = base64.Encoder.calcSize(auth_str.len);
            const auth_str_enc = try self.allocator.alloc(u8, n);
            defer self.allocator.free(auth_str_enc);
            const result = base64.Encoder.encode(auth_str_enc, auth_str);
            try writer.print("{x} {s} XOAUTH2 {s}\r\n", .{ self.tag, name, result });
        },
    }
}

fn handleLine(ptr: *anyopaque, line: []const u8) !Result {
    if (line.len == 0) return .not_handled;
    const self: *Authenticate = @ptrCast(@alignCast(ptr));
    switch (self.mechanism) {
        .plain => {
            if (!std.ascii.isAlphanumeric(line[0]))
                return .not_handled;
            var iter = std.mem.splitScalar(u8, line, ' ');
            const tag_str = iter.next() orelse return .not_handled;
            const tag = try std.fmt.parseUnsigned(u16, tag_str, 16);
            if (tag != self.tag)
                return .not_handled;
            const result = iter.next() orelse return .not_handled;
            self.ok = std.ascii.eqlIgnoreCase(result, "ok");
        },
        .login => {
            if (line[0] == '+') {
                const n = base64.Encoder.calcSize(self.password.len);
                const auth_str_enc = try self.allocator.alloc(u8, n);
                defer self.allocator.free(auth_str_enc);
                const result = base64.Encoder.encode(auth_str_enc, self.password);
                try self.writer.?.print("{s}\r\n", .{result});
                return .@"continue";
            }
            if (!std.ascii.isAlphanumeric(line[0]))
                return .not_handled;
            var iter = std.mem.splitScalar(u8, line, ' ');
            const tag_str = iter.next() orelse return .not_handled;
            const tag = try std.fmt.parseUnsigned(u16, tag_str, 16);
            if (tag != self.tag)
                return .not_handled;
            const result = iter.next() orelse return .not_handled;
            self.ok = std.ascii.eqlIgnoreCase(result, "ok");
        },
        .oauth,
        .xoauth2,
        => {
            if (line[0] == '+') {
                try self.writer.?.writeAll("\r\n");
                return .@"continue";
            }
            if (!std.ascii.isAlphanumeric(line[0]))
                return .not_handled;
            var iter = std.mem.splitScalar(u8, line, ' ');
            const tag_str = iter.next() orelse return .not_handled;
            const tag = try std.fmt.parseUnsigned(u16, tag_str, 16);
            if (tag != self.tag)
                return .not_handled;
            const result = iter.next() orelse return .not_handled;
            self.ok = std.ascii.eqlIgnoreCase(result, "ok");
        },
    }
    self.done = true;
    self.cond.signal();

    return .complete;
}
