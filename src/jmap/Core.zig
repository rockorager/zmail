const Core = @This();

const std = @import("std");
const util = @import("util.zig");

const json = std.json;
const mem = std.mem;
const testing = std.testing;

pub const uri = "urn:ietf:params:jmap:core";

/// Collation algorithm as registered in RFC 4790
pub const Collation = enum {
    ascii_numeric,
    ascii_casemap,
    unicode_casemap,
};

pub const Capability = struct {
    max_size_upload: u64,
    max_concurrent_upload: u64,
    max_size_request: u64,
    max_concurrent_requests: u64,
    max_calls_in_request: u64,
    max_objects_in_get: u64,
    max_objects_in_set: u64,
    collation_algorithms: []const Collation,

    pub fn jsonParse(
        allocator: mem.Allocator,
        source: anytype,
        options: json.ParseOptions,
    ) !Capability {
        const value = try json.innerParse(json.Value, allocator, source, options);

        return Capability.jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: mem.Allocator,
        value: json.Value,
        _: json.ParseOptions,
    ) !Capability {
        const root = try util.jsonAssertObject(value);

        const collation_vals = root.get("collationAlgorithms") orelse return json.ParseFromValueError.MissingField;
        const collation_arr = switch (collation_vals) {
            .array => |arr| arr,
            else => return json.ParseFromValueError.UnexpectedToken,
        };
        const collation_slice = try allocator.alloc(Collation, collation_arr.items.len);
        for (collation_arr.items, 0..) |item, i| {
            const str = switch (item) {
                .string => |s| s,
                else => return json.ParseFromValueError.UnexpectedToken,
            };
            if (mem.eql(u8, str, "i;ascii-numeric")) {
                collation_slice[i] = .ascii_numeric;
            } else if (mem.eql(u8, str, "i;ascii-casemap")) {
                collation_slice[i] = .ascii_casemap;
            } else if (mem.eql(u8, str, "i;unicode-casemap")) {
                collation_slice[i] = .unicode_casemap;
            }
        }

        const max_size_upload = try util.jsonGetUint(root, "maxSizeUpload");
        const max_concurrent_upload = try util.jsonGetUint(root, "maxConcurrentUpload");
        const max_size_request = try util.jsonGetUint(root, "maxSizeRequest");
        const max_concurrent_requests = try util.jsonGetUint(root, "maxConcurrentRequests");
        const max_calls_in_request = try util.jsonGetUint(root, "maxCallsInRequest");
        const max_objects_in_request = try util.jsonGetUint(root, "maxObjectsInGet");
        const max_objects_in_set = try util.jsonGetUint(root, "maxObjectsInSet");

        return .{
            .max_size_upload = max_size_upload,
            .max_concurrent_upload = max_concurrent_upload,
            .max_size_request = max_size_request,
            .max_concurrent_requests = max_concurrent_requests,
            .max_calls_in_request = max_calls_in_request,
            .max_objects_in_get = max_objects_in_request,
            .max_objects_in_set = max_objects_in_set,
            .collation_algorithms = collation_slice,
        };
    }
};

test "Core.zig: json decode" {
    const src =
        \\{
        \\  "maxSizeUpload": 50000000,
        \\  "maxConcurrentUpload": 8,
        \\  "maxSizeRequest": 10000000,
        \\  "maxConcurrentRequests": 8,
        \\  "maxCallsInRequest": 32,
        \\  "maxObjectsInGet": 256,
        \\  "maxObjectsInSet": 128,
        \\  "collationAlgorithms": [
        \\    "i;ascii-numeric",
        \\    "i;ascii-casemap",
        \\    "i;unicode-casemap"
        \\  ]
        \\}
    ;
    const value = try std.json.parseFromSlice(Capability, std.testing.allocator, src, .{ .ignore_unknown_fields = true });
    defer value.deinit();

    try testing.expectEqual(50_000_000, value.value.max_size_upload);
    try testing.expectEqual(8, value.value.max_concurrent_upload);
    try testing.expectEqual(10_000_000, value.value.max_size_request);
    try testing.expectEqual(8, value.value.max_concurrent_requests);
    try testing.expectEqual(32, value.value.max_calls_in_request);
    try testing.expectEqual(256, value.value.max_objects_in_get);
    try testing.expectEqual(128, value.value.max_objects_in_set);

    try testing.expectEqualSlices(
        Collation,
        &.{ .ascii_numeric, .ascii_casemap, .unicode_casemap },
        value.value.collation_algorithms,
    );
}
