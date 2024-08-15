const Request = @This();

const std = @import("std");

const Invocation = @import("Invocation.zig");

const json = std.json;
const testing = std.testing;

/// The capability URIs this request uses
using: []const []const u8,

/// The method calls of this request
method_calls: std.ArrayList(Invocation),

created_ids: ?[]const []const u8 = null,

pub fn jsonStringify(self: Request, writer: anytype) !void {
    try writer.beginObject();
    try writer.objectField("using");
    try writer.write(self.using);
    try writer.objectField("methodCalls");
    try writer.write(self.method_calls.items);
    if (self.created_ids) |created_ids| {
        try writer.objectField("createdIds");
        try writer.beginObject();
        for (created_ids) |id| {
            try writer.objectField(id);
            try writer.write("");
        }
        try writer.endObject();
    }
    try writer.endObject();
}
