const Invocation = @This();

const std = @import("std");
const util = @import("util.zig");

const json = std.json;
const mem = std.mem;
const testing = std.testing;

/// The name of the method
name: []const u8,
/// Arguments of the method
arguments: json.ObjectMap,
/// Optional id for the method
id: []const u8 = "",

pub fn jsonStringify(inv: Invocation, writer: anytype) !void {
    var tuple: [3]json.Value = undefined;
    tuple[0] = .{ .string = inv.name };
    tuple[1] = .{ .object = inv.arguments };
    tuple[2] = .{ .string = inv.id };
    try writer.write(&tuple);
}

pub fn jsonParse(
    allocator: mem.Allocator,
    source: anytype,
    options: json.ParseOptions,
) !Invocation {
    const value = try json.innerParse(json.Value, allocator, source, options);

    return jsonParseFromValue(allocator, value, options);
}

pub fn jsonParseFromValue(
    _: mem.Allocator,
    value: json.Value,
    _: json.ParseOptions,
) !Invocation {
    const arr = try util.jsonAssertArray(value);
    if (arr.items.len != 3) return json.ParseFromValueError.UnexpectedToken;
    const name = try util.jsonAssertString(arr.items[0]);
    const args = try util.jsonAssertObject(arr.items[1]);
    const id = try util.jsonAssertString(arr.items[2]);

    return .{
        .name = name,
        .arguments = args,
        .id = id,
    };
}

test "Invocation.zig: json roundtrip" {
    var map = json.ObjectMap.init(testing.allocator);
    defer map.deinit();
    try map.put("arg1", .{ .integer = 3 });
    try map.put("arg2", .{ .string = "foo" });
    const inv: Invocation = .{
        .name = "method1",
        .arguments = map,
        .id = "c1",
    };
    var out = std.ArrayList(u8).init(testing.allocator);
    defer out.deinit();
    try json.stringify(inv, .{}, out.writer());

    const parsed = try json.parseFromSlice(Invocation, testing.allocator, out.items, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings(inv.name, parsed.value.name);
    try testing.expectEqual(3, try util.jsonGetInt(parsed.value.arguments, "arg1"));
    try testing.expectEqualStrings("foo", try util.jsonGetString(parsed.value.arguments, "arg2"));
    try testing.expectEqualStrings(inv.id, parsed.value.id);
}
