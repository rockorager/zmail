const Header = @This();

const std = @import("std");
const zeit = @import("zeit");
const abnf = @import("../abnf.zig");
const mime = @import("mime.zig");

const Address = @import("Address.zig");

const log = std.log.scoped(.zmail);

/// An email header
name: []const u8,
value: []const u8,

/// Print a formatted header. Includes the trailing \r\n
pub fn format(
    self: Header,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    _ = fmt;
    try writer.print("{s}:{s}\r\n", .{ self.name, self.value });
}

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

    var list = std.ArrayList(u8).init(local);
    var mimeIter: mime.Word.Iterator = .{ .bytes = trimmed };

    var i: usize = 0;
    while (mimeIter.next()) |word| {
        // Append up to the word
        try list.appendSlice(trimmed[i..word.pos]);
        // Decode the word
        const decoded = try word.decode(local);
        // Append  the decoded word
        try list.appendSlice(decoded);
        i = word.pos + word.len;
    } else try list.appendSlice(trimmed[i..]);
    return allocator.dupe(u8, list.items);
}

test "asText" {
    {
        const hdr: Header = .{ .name = "From", .value = "foo\r\n bar" };
        const text = try hdr.asText(std.testing.allocator);
        try std.testing.expectEqualStrings("foo bar", text);
        defer std.testing.allocator.free(text);
    }
    {
        const hdr: Header = .{ .name = "From", .value = "foo =?utf-8?b?Q2Fmw6k=?=\r\n bar" };
        const text = try hdr.asText(std.testing.allocator);
        try std.testing.expectEqualStrings("foo Café bar", text);
        defer std.testing.allocator.free(text);
    }
}

/// Parses the header as an Address list. The following transformations occur:
/// 1. Quotes around display names are removed
/// 2. Any quoted-pair in a display name is decoded
/// 3. Unfolding, as needed
/// 4. Trim whitespace at beginning and end of value
/// 5. Any group information is stripped
///
/// Caller owns the returned slice
pub fn asAddresses(_: Header, _: std.mem.Allocator) ![]Address {
    @panic("unimplemented");
}

/// Parses the header as a list of MessageIds. The following transformations occur:
/// 1. Unfolded
/// 2. Surrounding <> removed
pub fn asMessageIds(self: Header, allocator: std.mem.Allocator) ![]const []const u8 {
    var i: usize = 0;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();
    while (i < self.value.len) {
        const start = std.mem.indexOfScalarPos(u8, self.value, i, '<') orelse return error.InvalidMessageID;
        const end = std.mem.indexOfScalarPos(u8, self.value, start + 1, '>') orelse return error.InvalidMessageID;
        try list.append(self.value[start + 1 .. end]);
        i = end + 1;
    }
    return allocator.dupe([]const u8, list.items);
}

test "asMessageIds" {
    const allocator = std.testing.allocator;
    const hdr: Header = .{ .name = "Message-ID", .value = "<abc> <def>" };
    const ids = try hdr.asMessageIds(allocator);
    defer std.testing.allocator.free(ids);
    try std.testing.expectEqual(2, ids.len);
    try std.testing.expectEqualStrings("abc", ids[0]);
    try std.testing.expectEqualStrings("def", ids[1]);
}

/// Parses the header as a date.
pub fn asDate(self: Header) !zeit.Time {
    return zeit.Time.fromRFC5322(self.value);
}

test "asDate" {
    const hdr: Header = .{ .name = "Date", .value = "Tue, 1 Jul 2003 10:52:37 +0200" };
    const date = try hdr.asDate();
    try std.testing.expectEqual(2003, date.year);
    try std.testing.expectEqual(.jul, date.month);
    try std.testing.expectEqual(1, date.day);
    try std.testing.expectEqual(10, date.hour);
    try std.testing.expectEqual(52, date.minute);
    try std.testing.expectEqual(37, date.second);
    try std.testing.expectEqual(7200, date.offset);
}

test "unfolding" {
    const hdr: Header = .{ .name = "From", .value = "foo\r\n bar" };
    var buf: [7]u8 = undefined;
    try std.testing.expect(hdr.isFolded());
    try std.testing.expectEqual(7, hdr.unfoldedLen());
    const unfolded = hdr.unfold(&buf);
    try std.testing.expectEqualStrings("foo bar", unfolded);
}

test "format" {
    const hdr: Header = .{ .name = "From", .value = "foo\r\n bar" };
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
    pub fn next(self: *Iterator) ?Header {
        if (self.idx >= self.src.len) return null;

        const start = self.idx;
        const end = while (true) {
            const eol = std.mem.indexOfPos(u8, self.src, self.idx, abnf.CRLF) orelse unreachable; // We
            // always have a CRLF at the end of the header section
            // Last header line
            defer self.idx = eol + 2;

            // Peek to byte on next line. If it is WSP, we continue on. Otherwise it's a new field
            if (eol + 2 < self.src.len and abnf.isWSP(self.src[eol + 2]))
                continue
            else
                break eol;
        };
        defer self.idx = end + 2;
        const sep = std.mem.indexOfScalarPos(u8, self.src, start, ':') orelse {
            log.warn("header missing ':': {s}", .{self.src[start..end]});
            return null;
        };
        return .{ .name = self.src[start..sep], .value = self.src[sep + 1 .. end] };
    }

    test "multiple headers" {
        var iter: Header.Iterator = .{ .src = "From:foo\r\nTo:bar\r\n" };
        var hdr = iter.next();
        try std.testing.expect(hdr != null);
        try std.testing.expectEqualStrings("From", hdr.?.name);
        try std.testing.expectEqualStrings("foo", hdr.?.value);
        hdr = iter.next();
        try std.testing.expect(hdr != null);
        try std.testing.expectEqualStrings("To", hdr.?.name);
        try std.testing.expectEqualStrings("bar", hdr.?.value);
        hdr = iter.next();
        try std.testing.expect(hdr == null);
    }

    test "folding white space" {
        {
            var iter: Header.Iterator = .{ .src = "From:foo\r\n folding white space\r\n" };
            var hdr = iter.next();
            try std.testing.expect(hdr != null);
            try std.testing.expectEqualStrings("From", hdr.?.name);
            try std.testing.expectEqualStrings("foo\r\n folding white space", hdr.?.value);
            hdr = iter.next();
            try std.testing.expect(hdr == null);
        }
        {
            var iter: Header.Iterator = .{ .src = "From:foo\r\n\tfolding white space\r\n" };
            var hdr = iter.next();
            try std.testing.expect(hdr != null);
            try std.testing.expectEqualStrings("From", hdr.?.name);
            try std.testing.expectEqualStrings("foo\r\n\tfolding white space", hdr.?.value);
            hdr = iter.next();
            try std.testing.expect(hdr == null);
        }
    }
};
