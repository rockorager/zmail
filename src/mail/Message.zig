//! An RFC5322 Internet Message
const Message = @This();

const std = @import("std");
const abnf = @import("../abnf.zig");
const Header = @import("Header.zig");

/// The entire message, byte for byte
src: []const u8,
/// The header section of the message. Does not include the empty line separating the headers from
/// the body
headers: []const u8,
/// The body section of the message
body: []const u8,

pub fn init(src: []const u8) !Message {
    const sep = std.mem.indexOf(u8, src, abnf.CRLF ++ abnf.CRLF) orelse {
        // No matter what, we must end with CRLF
        if (!std.mem.endsWith(u8, src, abnf.CRLF)) return error.InvalidMessageFormat;
        return .{
            .src = src,
            .headers = src,
            .body = "",
        };
    };
    return .{
        .src = src,
        .headers = src[0 .. sep + 2],
        .body = src[sep + 4 ..],
    };
}
