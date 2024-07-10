//! An email address
const Address = @This();

const std = @import("std");
const abnf = @import("../abnf.zig");

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

/// Frees allocated resources. This should be passed the same allocator that was used to parse the
/// address (from header.asAddresses, for example). The allocator is not stored as part of the
/// struct to make the struct more portable
pub fn deinit(self: Address, allocator: std.mem.Allocator) void {
    allocator.free(self.spec);
    if (self.name) |name|
        allocator.free(name);
}

pub const Iterator = struct {
    src: []const u8,
    idx: usize = 0,

    pub fn next(self: *Iterator) ?Address {
        const display_name = self.parseDisplayName();
        const spec = self.parseAddr() orelse return null;
        return .{
            .name = display_name,
            .spec = spec,
        };
    }

    /// Returns the next address. The name and spec are allocated using allocator. Call deinit on
    /// the returned Address with the allocator to free the resources
    pub fn nextAlloc(self: *Iterator, allocator: std.mem.Allocator) std.mem.Allocator.Error!?Address {
        const display_name = self.parseDisplayName();
        const spec = self.parseAddr() orelse return null;
        return .{
            .name = if (display_name) |str| try allocator.dupe(u8, str) else null,
            .spec = try allocator.dupe(u8, spec),
        };
    }

    /// Parses a display name, if one is found. Consumes any group names. If there is no display
    /// name, state is unchanged
    pub fn parseDisplayName(self: *Iterator) ?[]const u8 {
        self.trimCFWS();
        self.trimCommaSemicolon();
        if (self.idx >= self.src.len) return null;
        var start = self.idx;
        var quoted: bool = false;
        while (self.idx < self.src.len) : (self.idx += 1) {
            const b = self.src[self.idx];
            switch (b) {
                '"' => quoted = !quoted,
                '<' => {
                    if (start == self.idx) return null;
                    const trimmed = std.mem.trim(u8, self.src[start..self.idx], " ");
                    const unquoted = std.mem.trim(u8, trimmed, "\"");
                    if (unquoted.len == 0) return null;
                    return unquoted;
                },
                // handle groups
                ':', ';' => {
                    if (!quoted) start = self.idx + 1;
                },
                ',' => {
                    self.idx = start;
                    return null;
                },
                '\\' => self.idx += 1,
                else => {},
            }
        }
        // Didn't find a display-name, reset state
        self.idx = start;
        return null;
    }

    pub fn parseAddr(self: *Iterator) ?[]const u8 {
        self.trimCFWS();
        if (self.idx >= self.src.len) return null;
        const end = switch (self.src[self.idx]) {
            '<' => blk: {
                self.idx += 1;
                break :blk std.mem.indexOfScalarPos(u8, self.src, self.idx, '>') orelse self.src.len;
            },
            else => blk: {
                break :blk std.mem.indexOfAnyPos(u8, self.src, self.idx, ", ") orelse self.src.len;
            },
        };
        defer self.idx = end + 1;
        return std.mem.trimRight(u8, self.src[self.idx..end], " ");
    }

    pub fn peek(self: Iterator) ?u8 {
        if (self.idx + 1 >= self.src.len) return null;
        return self.src[self.idx + 1];
    }

    pub fn trimCFWS(self: *Iterator) void {
        if (self.idx >= self.src.len) return;
        const src = abnf.trimCFWS(self.src[self.idx..]);
        const orig_len = self.src[self.idx..].len;
        self.idx += (orig_len - src.len);
    }

    pub fn trimCommaSemicolon(self: *Iterator) void {
        if (self.idx >= self.src.len) return;
        const src = std.mem.trimLeft(u8, self.src[self.idx..], ";,");
        const orig_len = self.src[self.idx..].len;
        self.idx += (orig_len - src.len);
    }
};

test "address: addr-spec" {
    var iter: Iterator = .{ .src = "test@example.com" };
    const actual = iter.next();
    try std.testing.expectEqual(Address{ .name = null, .spec = "test@example.com" }, actual);
    try std.testing.expect(iter.next() == null);
}

test "address: addr-spec with leading CFWS" {
    var iter: Iterator = .{ .src = "   () test@example.com" };
    const actual = iter.next();
    const expected: Address = .{ .name = null, .spec = "test@example.com" };
    try std.testing.expect(actual != null);
    try std.testing.expect(actual.?.name == null);
    try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
    try std.testing.expect(iter.next() == null);
}

test "address: addr-spec with trailing CFWS" {
    var iter: Iterator = .{ .src = "test@example.com (akjld)" };
    const actual = iter.next();
    const expected: Address = .{ .name = null, .spec = "test@example.com" };
    try std.testing.expect(actual != null);
    try std.testing.expect(actual.?.name == null);
    try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
    try std.testing.expect(iter.next() == null);
}

test "address: angl-addr" {
    var iter: Iterator = .{ .src = "   () <test@example.com>" };
    const actual = iter.next();
    const expected: Address = .{ .name = null, .spec = "test@example.com" };
    try std.testing.expect(actual != null);
    try std.testing.expect(actual.?.name == null);
    try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
    try std.testing.expect(iter.next() == null);
}

test "address: name-addr" {
    var iter: Iterator = .{ .src = "Foo Bar <test@example.com>" };
    const actual = iter.next();
    const expected: Address = .{ .name = "Foo Bar", .spec = "test@example.com" };
    try std.testing.expect(actual != null);
    try std.testing.expect(actual.?.name != null);
    try std.testing.expectEqualStrings(expected.name.?, actual.?.name.?);
    try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
    try std.testing.expect(iter.next() == null);
}

test "address: quoted name-addr" {
    var iter: Iterator = .{ .src = "\"Foo Bar\" <test@example.com>" };
    const actual = iter.next();
    const expected: Address = .{ .name = "Foo Bar", .spec = "test@example.com" };
    try std.testing.expect(actual != null);
    try std.testing.expect(actual.?.name != null);
    try std.testing.expectEqualStrings(expected.name.?, actual.?.name.?);
    try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
    try std.testing.expect(iter.next() == null);
}

test "address: group" {
    var iter: Iterator = .{ .src = "Foo Bar: <test@example.com>;" };
    const actual = iter.next();
    const expected: Address = .{ .name = null, .spec = "test@example.com" };
    try std.testing.expect(actual != null);
    try std.testing.expect(actual.?.name == null);
    try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
    try std.testing.expect(iter.next() == null);
}

test "address: group with display name" {
    var iter: Iterator = .{ .src = "Foo Bar: Baz <test@example.com>;" };
    const actual = iter.next();
    const expected: Address = .{ .name = "Baz", .spec = "test@example.com" };
    try std.testing.expect(actual != null);
    try std.testing.expect(actual.?.name != null);
    try std.testing.expectEqualStrings(expected.name.?, actual.?.name.?);
    try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
    try std.testing.expect(iter.next() == null);
}

test "address: RFC5322 Appendix A.1.2" {
    // from
    {
        const input = "\"Joe Q. Public\" <john.q.public@example.com>";
        var iter: Iterator = .{ .src = input };
        const actual = iter.next();
        const expected: Address = .{ .name = "Joe Q. Public", .spec = "john.q.public@example.com" };
        try std.testing.expect(actual != null);
        try std.testing.expect(actual.?.name != null);
        try std.testing.expectEqualStrings(expected.name.?, actual.?.name.?);
        try std.testing.expectEqualStrings(expected.spec, actual.?.spec);
        try std.testing.expect(iter.next() == null);
    }
    // to
    {
        const input = "Mary Smith <mary@x.test>, jdoe@example.org, Who? <one@y.test>";
        var iter: Iterator = .{ .src = input };

        const actual1 = iter.next();
        const expected1: Address = .{ .name = "Mary Smith", .spec = "mary@x.test" };
        try std.testing.expect(actual1 != null);
        try std.testing.expect(actual1.?.name != null);
        try std.testing.expectEqualStrings(expected1.name.?, actual1.?.name.?);
        try std.testing.expectEqualStrings(expected1.spec, actual1.?.spec);

        const actual2 = iter.next();
        const expected2: Address = .{ .name = null, .spec = "jdoe@example.org" };
        try std.testing.expect(actual2 != null);
        try std.testing.expect(actual2.?.name == null);
        try std.testing.expectEqualStrings(expected2.spec, actual2.?.spec);

        const actual3 = iter.next();
        const expected3: Address = .{ .name = "Who?", .spec = "one@y.test" };
        try std.testing.expect(actual3 != null);
        try std.testing.expect(actual3.?.name != null);
        try std.testing.expectEqualStrings(expected3.name.?, actual3.?.name.?);
        try std.testing.expectEqualStrings(expected3.spec, actual3.?.spec);

        try std.testing.expect(iter.next() == null);
    }

    // cc
    {
        const input = "<boss@nil.test>, \"Giant; \"Big\" Box\" <sysservices@example.net>";
        var iter: Iterator = .{ .src = input };

        const actual1 = iter.next();
        const expected1: Address = .{ .name = null, .spec = "boss@nil.test" };
        try std.testing.expect(actual1 != null);
        try std.testing.expect(actual1.?.name == null);
        try std.testing.expectEqualStrings(expected1.spec, actual1.?.spec);

        const actual2 = iter.next();
        const expected2: Address = .{ .name = "Giant; \"Big\" Box", .spec = "sysservices@example.net" };
        try std.testing.expect(actual2 != null);
        try std.testing.expect(actual2.?.name != null);
        try std.testing.expectEqualStrings(expected2.name.?, actual2.?.name.?);
        try std.testing.expectEqualStrings(expected2.spec, actual2.?.spec);

        try std.testing.expect(iter.next() == null);
    }
}

test "address: RFC5322 Appendix A.1.3: Group Addresses" {
    // to
    {
        const input = "A Group:Ed Jones <c@a.test>,joe@where.test,John <jdoe@one.test>;";
        var iter: Iterator = .{ .src = input };

        const actual1 = iter.next();
        const expected1: Address = .{ .name = "Ed Jones", .spec = "c@a.test" };
        try std.testing.expect(actual1 != null);
        try std.testing.expect(actual1.?.name != null);
        try std.testing.expectEqualStrings(expected1.name.?, actual1.?.name.?);
        try std.testing.expectEqualStrings(expected1.spec, actual1.?.spec);

        const actual2 = iter.next();
        const expected2: Address = .{ .name = null, .spec = "joe@where.test" };
        try std.testing.expect(actual2 != null);
        try std.testing.expect(actual2.?.name == null);
        try std.testing.expectEqualStrings(expected2.spec, actual2.?.spec);

        const actual3 = iter.next();
        const expected3: Address = .{ .name = "John", .spec = "jdoe@one.test" };
        try std.testing.expect(actual3 != null);
        try std.testing.expect(actual3.?.name != null);
        try std.testing.expectEqualStrings(expected3.name.?, actual3.?.name.?);
        try std.testing.expectEqualStrings(expected3.spec, actual3.?.spec);

        try std.testing.expect(iter.next() == null);
    }

    // cc
    {
        const input = "Undisclosed recipients:;";
        var iter: Iterator = .{ .src = input };

        try std.testing.expect(iter.next() == null);
    }
}
