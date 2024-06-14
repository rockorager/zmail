//! An email address
const Address = @This();

const std = @import("std");

/// display name
name: ?[]const u8,

/// local@domain
spec: []const u8,
