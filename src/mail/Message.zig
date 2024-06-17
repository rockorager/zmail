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

pub fn headerIterator(self: Message) Header.Iterator {
    return .{ .src = self.headers };
}

/// A MIME entity
pub const Part = struct {
    headers: []const u8,
    body: []const u8,

    parent: ?*Part,
    children: ?[]*Part,

    pub fn isMultipart(self: Part) bool {
        var iter: Header.Iterator = .{ .src = self.headers };
        while (iter.next()) |hdr| {
            if (std.ascii.eqlIgnoreCase("Content-Type", hdr.name)) {
                if (std.mem.indexOf(u8, hdr.value, "multipart/")) |_|
                    return true
                else
                    return false;
            }
        }
        return false;
    }
};
