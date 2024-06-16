//! An RFC5322 Internet Message
const Message = @This();

const std = @import("std");
const Header = @import("Header.zig");

/// The entire message, byte for byte
src: []const u8,
/// The header section of the message. Does not include the empty line separating the headers from
/// the body
headers: []const u8,
/// The body section of the message
body: []const u8,

pub fn init(src: []const u8) !Message {
    const sep = std.mem.indexOf(u8, src, "\r\n\r\n") orelse {
        return .{
            .src = src,
            .headers = src,
            .body = "",
        };
    };
    return .{
        .src = src,
        .headers = src[0..sep],
        .body = src[sep + 4 ..],
    };
}
