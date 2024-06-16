const std = @import("std");
const testing = std.testing;

pub const HTAB: u8 = 0x09;
pub const SP: u8 = 0x20;
pub const CRLF: []const u8 = "\r\n";

/// Returns true when the byte is classified as WSP
pub fn isWSP(b: u8) bool {
    return b == SP or b == HTAB;
}

/// Trims comments and folding whitespace from the beginning of the string
pub fn trimCFWS(src: []const u8) []const u8 {
    const State = enum {
        ground,
        cr,
        crlf,
        comment,
        comment_qp,
    };

    var state: State = .ground;

    for (src, 0..) |b, i| {
        switch (state) {
            .ground => switch (b) {
                SP, HTAB => continue,
                '\r' => state = .cr,
                '(' => state = .comment,
                else => return src[i..],
            },
            .cr => switch (b) {
                '\n' => state = .crlf,
                else => state = .ground,
            },
            .crlf => switch (b) {
                SP, HTAB => state = .ground,
                else => if (i == src.len - 1)
                    return ""
                else
                    return src[i + 1 ..],
            },
            .comment => switch (b) {
                ')' => state = .ground,
                '\\' => state = .comment_qp,
                else => continue,
            },
            .comment_qp => state = .comment,
        }
    }
    return "";
}

test "trimCFWS" {
    const expectEqualStrings = testing.expectEqualStrings;
    try expectEqualStrings("foo", trimCFWS("  \r\n (comm\\)ent)foo"));
}
