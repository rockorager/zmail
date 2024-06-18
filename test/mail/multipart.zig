const std = @import("std");
const testing = std.testing;
const mail = @import("zmail").mail;

test "multipart" {
    const multipart_test = @embedFile("multipart.eml");
    const msg = mail.Entity.init(multipart_test);
    var iter = msg.iterator() orelse return error.UnexpectedNullEntityIterator;

    {
        const part1 = iter.next() orelse return error.UnexpectedNullEntity;
        const expected_fields = "";
        const expected_body = "Part 1\r\n";
        try testing.expectEqualStrings(expected_fields, part1.fields);
        try testing.expectEqualStrings(expected_body, part1.body);
    }
    {
        const part2 = iter.next() orelse return error.UnexpectedNullEntity;
        const expected_fields = "Content-type: text/plain; charset=US-ASCII\r\n";
        const expected_body = "A\r\nB\r\nC\r\n";
        try testing.expectEqualStrings(expected_fields, part2.fields);
        try testing.expectEqualStrings(expected_body, part2.body);
    }
}
