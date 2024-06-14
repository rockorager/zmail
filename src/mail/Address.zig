//! An email address
const Address = @This();

const std = @import("std");

/// display name
name: ?[]const u8,

/// local@domain
spec: []const u8,

pub fn format(
    self: Address,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = fmt;
    if (self.name) |name|
        try writer.print("{s} <{s}>", .{ name, self.spec })
    else
        try writer.writeAll(self.spec);
}

pub const Group = struct {
    display_name: []const u8,
    addresses: []const Address,
};
