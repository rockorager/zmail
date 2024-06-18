//! An RFC5322 Internet Message, or an RFC2045 MIME Entity
const Entity = @This();

const std = @import("std");
const abnf = @import("../abnf.zig");
const Header = @import("Header.zig");
const mime = @import("mime.zig");

const log = std.log.scoped(.zmail);

fields: []const u8,
body: []const u8,

/// Initialize an Entity from a source string. The entity will be split into fields and a body
pub fn init(src: []const u8) Entity {
    var offset: usize = 0;
    var iter = std.mem.splitSequence(u8, src, abnf.CRLF);
    while (iter.next()) |line| {
        // First empty line defines boundary between fields and body
        if (line.len == 0)
            return .{
                .fields = src[0..offset],
                .body = src[offset + 2 ..],
            };

        offset += line.len + abnf.CRLF.len;
    }
    return .{
        .fields = src,
        .body = "",
    };
}

/// Iterate over the headers of this entity
pub fn headerIterator(self: Entity) HeaderIterator {
    return .{ .src = self.fields };
}

/// If this is a multipart Entity, iterate over the subparts
pub fn iterator(self: Entity) ?EntityIterator {
    // Do we have a content-type header?
    const ct = self.getHeader("content-type") orelse return null;
    // Is it a multipart?
    _ = std.mem.indexOf(u8, ct.value, "multipart/") orelse return null;
    // Get the boundary
    const start = std.mem.indexOfScalar(u8, ct.value, ';') orelse {
        log.warn("multipart with no boundary parameter", .{});
        return null;
    };
    var iter: mime.ParameterIterator = .{ .src = ct.value[start + 1 ..] };
    while (iter.next()) |p| {
        if (std.ascii.eqlIgnoreCase("boundary", p.attribute)) {
            const boundary = std.mem.trim(u8, p.value, "\"");
            return .{
                .src = self.body,
                .boundary = boundary,
            };
        }
    }
    log.warn("multipart with no boundary parameter", .{});
    return null;
}

/// Returns the first occurrence of the named header. Matching is case insensitive
pub fn getHeader(self: Entity, name: []const u8) ?Header {
    var iter: HeaderIterator = .{ .src = self.fields };
    while (iter.next()) |hdr| {
        if (std.ascii.eqlIgnoreCase(name, hdr.name)) return hdr;
    }
    return null;
}

/// Iterate over header fields
pub const HeaderIterator = struct {
    src: []const u8,
    idx: usize = 0,

    /// Returns the next header. The header value will be in it's raw form, including any
    /// preceding space after the ':' field delimiter, including any folding white space, but excluding
    /// the trailing CRLF
    pub fn next(self: *HeaderIterator) ?Header {
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

    /// Returns the next instance of the named header.
    pub fn nextWithName(self: *HeaderIterator, name: []const u8) ?Header {
        while (self.next()) |hdr| {
            if (std.ascii.eqlIgnoreCase(name, hdr.name)) return hdr;
        }
        return null;
    }

    pub fn reset(self: *HeaderIterator) void {
        self.idx = 0;
    }
};

/// Iterate over the subparts of a multipart Entity
pub const EntityIterator = struct {
    src: []const u8,
    idx: usize = 0,
    /// the boundary this iterator is splitting on
    boundary: []const u8,

    /// The next entity. Note: the returned entity itself could be a multipart
    pub fn next(self: *EntityIterator) ?Entity {
        if (self.idx >= self.src.len) return null;
        // We will ignore the preamble, which occurs before the first delimiter
        var ignore = self.idx == 0;
        var start = self.idx;
        var line_iter = std.mem.splitSequence(u8, self.src[self.idx..], abnf.CRLF);
        while (line_iter.next()) |line| {
            self.idx += line.len + abnf.CRLF.len;
            // Must start with --
            if (!std.mem.startsWith(u8, line, "--")) continue;
            // Must then have boundary
            if (!std.mem.startsWith(u8, line[2..], self.boundary)) continue;
            // Are we ignoring the preamble?
            if (ignore) {
                start = self.idx;
                ignore = false;
                continue;
            }
            // the preceeding CRLF is part of the delimiter
            const end = self.idx - (abnf.CRLF.len + line.len + abnf.CRLF.len);
            return Entity.init(self.src[start..end]);
        }
        return null;
    }
};
