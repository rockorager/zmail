const std = @import("std");
const testing = std.testing;
const mail = @import("zmail").mail;

test "headers" {
    const header_test = @embedFile("header.eml");
    const msg = mail.Entity.init(header_test);
    var headers = msg.headerIterator();
    var allocator = testing.allocator;

    // asText with folding
    {
        const hdr = headers.next() orelse return error.UnexpectedNullHeader;
        const text = try hdr.asText(allocator);
        defer allocator.free(text);
        try testing.expect(hdr.isFolded());
        try testing.expectEqualStrings("From", hdr.name);
        try testing.expectEqualStrings("foo bar", text);
    }

    // asText with folding and base64 mime word
    {
        const hdr = headers.next() orelse return error.UnexpectedNullHeader;
        const text = try hdr.asText(allocator);
        defer allocator.free(text);
        try testing.expectEqualStrings("To", hdr.name);
        try testing.expectEqualStrings("foo Café bar", text);
    }

    // asText with folding and Q mime word
    {
        const hdr = headers.next() orelse return error.UnexpectedNullHeader;
        const text = try hdr.asText(allocator);
        defer allocator.free(text);
        try testing.expectEqualStrings("Foo", hdr.name);
        try testing.expectEqualStrings("François-Jérôme", text);
    }

    // asMessageIds
    {
        const hdr = headers.next() orelse return error.UnexpectedNullHeader;
        const ids = try hdr.asMessageIds(allocator);
        defer allocator.free(ids);
        try testing.expectEqual(2, ids.len);
        try testing.expectEqualStrings("abc", ids[0]);
        try testing.expectEqualStrings("def", ids[1]);
    }

    // asDate
    {
        const hdr = headers.next() orelse return error.UnexpectedNullHeader;
        const date = try hdr.asDate();
        try testing.expectEqual(2003, date.year);
        try testing.expectEqual(.jul, date.month);
        try testing.expectEqual(1, date.day);
        try testing.expectEqual(10, date.hour);
        try testing.expectEqual(52, date.minute);
        try testing.expectEqual(37, date.second);
        try testing.expectEqual(7200, date.offset);
    }

    // End of headers
    {
        try testing.expect(headers.next() == null);
    }

    // Single part message
    {
        try testing.expect(msg.iterator() == null);
    }
}
