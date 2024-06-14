const Header = @This();

const std = @import("std");
const abnf = @import("../abnf.zig");
const mime = @import("mime.zig");

/// An email header
key: []const u8,
value: []const u8,

/// Returns true if the header value is considered "folded". Folded headers contain CRLF
/// followed by whitespace and must be "unfolded" prior to semantic analysis
pub fn isFolded(self: Header) bool {
    if (std.mem.indexOf(u8, self.value, abnf.CRLF)) |_|
        return true
    else
        return false;
}

/// Returns the size a buffer must be to hold the unfolded value of the header
pub fn unfoldedLen(self: Header) usize {
    const n = std.mem.count(u8, self.value, abnf.CRLF);
    return self.value.len -| (n * abnf.CRLF.len);
}

/// Unfolds the header. Asserts that buf is long enough to hold the unfolded value
pub fn unfold(self: Header, buf: []u8) []const u8 {
    std.debug.assert(buf.len >= self.unfoldedLen());
    var i: usize = 0; // read index
    var n: usize = 0; // bytes written

    while (i < self.value.len) {
        const idx = std.mem.indexOfPos(u8, self.value, i, abnf.CRLF) orelse self.value.len;
        const len = idx - i;
        @memcpy(buf[n .. n + len], self.value[i..idx]);
        n += len;
        i = idx + 2;
    }
    return buf[0..n];
}

pub fn format(
    self: Header,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = fmt;
    try writer.print("{s}:{s}\r\n", .{ self.key, self.value });
}

/// The raw bytes of the header value, excluding the separating ':', up to but excluding the
/// terminating CRLF
pub fn asRaw(self: Header) []const u8 {
    return self.value;
}

/// Caller owns the returned string. The following transformations occur:
/// 1. Unfolded
/// 2. Remove terminating CRLF
/// 3. Trim whitespace at beginning and end of value
/// 4. MIME-decoded
pub fn asText(self: Header, allocator: std.mem.Allocator) ![]const u8 {
    // Use an arena, we'll have possibly several allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var local = arena.allocator();

    const len = self.unfoldedLen();
    const buf = try local.alloc(u8, len);
    const unfolded = self.unfold(buf);
    const trimmed = std.mem.trim(u8, unfolded, " ");

    return allocator.dupe(u8, trimmed);
}

/// Decodes an RFC2047 encoded word.
pub fn mimeDecode(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, str, "=?")) return error.InvalidMimeEncoding;
    if (!std.mem.endsWith(u8, str, "?=")) return error.InvalidMimeEncoding;
    const word = str[2 .. str.len - 2];
    var iter = std.mem.splitScalar(u8, word, '?');
    const charset = iter.next() orelse return error.InvalidMimeEncoding;
    _ = charset; // autofix
    const encoding = iter.next() orelse return error.InvalidMimeEncoding;
    const content = iter.next() orelse return error.InvalidMimeEncoding;

    if (encoding.len != 1) return error.InvalidMimeEncoding;
    switch (encoding[0]) {
        'B', 'b' => {
            var decoder = std.base64.standard.Decoder;
            const n = try decoder.calcSizeForSlice(content);
            const buf = try allocator.alloc(u8, n);
            try decoder.decode(buf, content);
            return buf;
        }, // base64
        // 'Q', 'q' => return mime.decodeWord(allocator, content), // quoted-printable
        else => return error.InvalidMimeEncoding,
    }
}

test "asText" {
    const hdr: Header = .{ .key = "From", .value = "foo\r\n bar" };
    const text = try hdr.asText(std.testing.allocator);
    defer std.testing.allocator.free(text);
}

test "unfolding" {
    const hdr: Header = .{ .key = "From", .value = "foo\r\n bar" };
    var buf: [7]u8 = undefined;
    try std.testing.expect(hdr.isFolded());
    try std.testing.expectEqual(7, hdr.unfoldedLen());
    const unfolded = hdr.unfold(&buf);
    try std.testing.expectEqualStrings("foo bar", unfolded);
}

test "format" {
    const hdr: Header = .{ .key = "From", .value = "foo\r\n bar" };
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try hdr.format("", .{}, fbs.writer().any());
    try std.testing.expectEqualStrings("From:foo\r\n bar\r\n", buf[0..16]);
}

pub const Iterator = struct {
    src: []const u8,
    idx: usize = 0,

    /// Returns the next header. The header value will be in it's raw form, including any
    /// preceding space after the ':' field delimiter, including any folding white space, but excluding
    /// the trailing CRLF
    pub fn next(self: *Iterator) error{InvalidHeader}!?Header {
        if (self.idx >= self.src.len) return null;

        const start = self.idx;
        const sep = std.mem.indexOfScalarPos(u8, self.src, start, ':') orelse return error.InvalidHeader;
        const end = while (true) {
            const eol = std.mem.indexOfPos(u8, self.src, self.idx, abnf.CRLF) orelse {
                // Last header line
                self.idx = self.src.len;
                return .{ .key = self.src[start..sep], .value = self.src[sep + 1 ..] };
            };
            defer self.idx = eol + 2;

            // Peek to byte on next line. If it is WSP, we continue on. Otherwise it's a new field
            if (eol + 2 < self.src.len and abnf.isWSP(self.src[eol + 2]))
                continue
            else
                break eol;
        };
        defer self.idx = end + 2;
        return .{ .key = self.src[start..sep], .value = self.src[sep + 1 .. end] };
    }

    test "multiple headers" {
        var iter: Header.Iterator = .{ .src = "From:foo\r\nTo:bar" };
        var hdr = try iter.next();
        try std.testing.expect(hdr != null);
        try std.testing.expectEqualStrings("From", hdr.?.key);
        try std.testing.expectEqualStrings("foo", hdr.?.value);
        hdr = try iter.next();
        try std.testing.expect(hdr != null);
        try std.testing.expectEqualStrings("To", hdr.?.key);
        try std.testing.expectEqualStrings("bar", hdr.?.value);
        hdr = try iter.next();
        try std.testing.expect(hdr == null);
    }

    test "folding white space" {
        {
            var iter: Header.Iterator = .{ .src = "From:foo\r\n folding white space" };
            var hdr = try iter.next();
            try std.testing.expect(hdr != null);
            try std.testing.expectEqualStrings("From", hdr.?.key);
            try std.testing.expectEqualStrings("foo\r\n folding white space", hdr.?.value);
            hdr = try iter.next();
            try std.testing.expect(hdr == null);
        }
        {
            var iter: Header.Iterator = .{ .src = "From:foo\r\n\tfolding white space\r\n" };
            var hdr = try iter.next();
            try std.testing.expect(hdr != null);
            try std.testing.expectEqualStrings("From", hdr.?.key);
            try std.testing.expectEqualStrings("foo\r\n\tfolding white space", hdr.?.value);
            hdr = try iter.next();
            try std.testing.expect(hdr == null);
        }
    }
};
