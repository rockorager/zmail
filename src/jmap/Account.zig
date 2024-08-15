const Account = @This();

const std = @import("std");
const util = @import("util.zig");

const json = std.json;
const mem = std.mem;

id: []const u8,
name: []const u8,
is_personal: bool,
is_read_only: bool,
capabilities: struct {},

pub fn jsonParse(
    allocator: mem.Allocator,
    source: anytype,
    options: json.ParseOptions,
) !Account {
    const value = try json.innerParse(json.Value, allocator, source, options);

    return jsonParseFromValue(allocator, value, options);
}

pub fn jsonParseFromValue(
    allocator: mem.Allocator,
    value: json.Value,
    _: json.ParseOptions,
) !Account {
    const root = try util.jsonAssertObject(value);

    const name = try util.jsonGetString(root, "name");
    const is_personal = try util.jsonGetBool(root, "isPersonal");
    const is_read_only = try util.jsonGetBool(root, "isReadOnly");

    return .{
        .id = "",
        .name = try allocator.dupe(u8, name),
        .is_personal = is_personal,
        .is_read_only = is_read_only,
        .capabilities = .{},
    };
}
