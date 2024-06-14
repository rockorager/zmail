const std = @import("std");
const grammar = @import("grammar.zig");

/// An email address
pub const Address = struct {
    /// display name
    name: ?[]const u8,
    /// local@domain
    spec: []const u8,
};

/// An email header
pub const Header = struct {
    key: []const u8,
    value: []const u8,

    /// Returns true if the header value is considered "folded". Folded headers contain CRLF
    /// followed by whitespace and must be "unfolded" prior to semantic analysis
    pub fn isFolded(self: Header) bool {
        if (std.mem.indexOf(u8, self.value, grammar.CRLF)) |_|
            return true
        else
            return false;
    }

    /// Returns the size a buffer must be to hold the unfolded value of the header
    pub fn unfoldedLen(self: Header) usize {
        const n = std.mem.count(u8, self.value, grammar.CRLF);
        return self.value.len -| (n * grammar.CRLF.len);
    }

    /// Unfolds the header. Asserts that buf is long enough to hold the unfolded value
    pub fn unfold(self: Header, buf: []u8) []const u8 {
        std.debug.assert(buf.len >= self.unfoldedLen());
        var i: usize = 0; // read index
        var n: usize = 0; // bytes written

        while (i < self.value.len) {
            const idx = std.mem.indexOfPos(u8, self.value, i, grammar.CRLF) orelse self.value.len;
            const len = idx - i;
            @memcpy(buf[n .. n + len], self.value[i..idx]);
            n += len;
            i = idx + 2;
        }
        return buf[0..n];
    }

    /// Writes the header to the writer. Includes a CRLF after the header
    pub fn writeTo(self: Header, writer: std.io.AnyWriter) !void {
        try writer.writeAll(self.key);
        try writer.writeByte(':');
        try writer.writeAll(self.value);
        try writer.writeAll(grammar.CRLF);
    }

    test "unfolding" {
        const hdr: Header = .{ .key = "From", .value = "foo\r\n bar" };
        var buf: [7]u8 = undefined;
        try std.testing.expect(hdr.isFolded());
        try std.testing.expectEqual(7, hdr.unfoldedLen());
        const unfolded = hdr.unfold(&buf);
        try std.testing.expectEqualStrings("foo bar", unfolded);
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
                const eol = std.mem.indexOfPos(u8, self.src, self.idx, grammar.CRLF) orelse {
                    // Last header line
                    self.idx = self.src.len;
                    return .{ .key = self.src[start..sep], .value = self.src[sep + 1 ..] };
                };
                defer self.idx = eol + 2;

                // Peek to byte on next line. If it is WSP, we continue on. Otherwise it's a new field
                if (eol + 2 < self.src.len and grammar.isWSP(self.src[eol + 2]))
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
};

pub const Message = struct {
    src: []const u8,

    headers: []const u8,
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
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
