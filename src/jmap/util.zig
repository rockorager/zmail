const std = @import("std");

const json = std.json;

pub fn jsonGetInt(map: json.ObjectMap, key: []const u8) json.ParseFromValueError!i64 {
    const value = map.get(key) orelse return json.ParseFromValueError.MissingField;
    switch (value) {
        .integer => |int| return int,
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}

pub fn jsonGetUint(map: json.ObjectMap, key: []const u8) json.ParseFromValueError!u64 {
    const value = map.get(key) orelse return json.ParseFromValueError.MissingField;
    switch (value) {
        .integer => |int| return @intCast(int),
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}

pub fn jsonGetObject(map: json.ObjectMap, key: []const u8) json.ParseFromValueError!json.ObjectMap {
    const value = map.get(key) orelse return json.ParseFromValueError.MissingField;
    switch (value) {
        .object => |obj| return obj,
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}

pub fn jsonGetString(map: json.ObjectMap, key: []const u8) json.ParseFromValueError![]const u8 {
    const value = map.get(key) orelse return json.ParseFromValueError.MissingField;
    switch (value) {
        .string => |str| return str,
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}

pub fn jsonGetBool(map: json.ObjectMap, key: []const u8) json.ParseFromValueError!bool {
    const value = map.get(key) orelse return json.ParseFromValueError.MissingField;
    switch (value) {
        .bool => |v| return v,
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}

pub fn jsonAssertObject(value: json.Value) json.ParseFromValueError!json.ObjectMap {
    switch (value) {
        .object => |obj| return obj,
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}

pub fn jsonAssertString(value: json.Value) json.ParseFromValueError![]const u8 {
    switch (value) {
        .string => |str| return str,
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}

pub fn jsonAssertArray(value: json.Value) json.ParseFromValueError!std.ArrayList(json.Value) {
    switch (value) {
        .array => |arr| return arr,
        else => return json.ParseFromValueError.UnexpectedToken,
    }
}
