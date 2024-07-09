const std = @import("std");

/// A mime encoded word, as defined in RFC2047
pub const Word = struct {
    /// The position in the original slice of the beginning of the mime encoded word
    pos: usize,
    /// The length of the entire mime encoding
    len: usize,

    charset: []const u8,
    encoding: u8,
    content: []const u8,

    pub const Iterator = struct {
        bytes: []const u8,
        idx: usize = 0,

        /// Returns the next mime encoded word, including the "=?" and "?=" delimiters
        /// A mime word has the form "=?<bytes>?<bytes>?<bytes>?="
        pub fn next(self: *Word.Iterator) ?Word {
            if (self.idx >= self.bytes.len) return null;
            const prefix = std.mem.indexOfPos(u8, self.bytes, self.idx, "=?") orelse {
                self.idx = self.bytes.len;
                return null;
            };
            const first_q = std.mem.indexOfScalarPos(u8, self.bytes, prefix + 2, '?') orelse {
                self.idx = self.bytes.len;
                return null;
            };
            const second_q = std.mem.indexOfScalarPos(u8, self.bytes, first_q + 1, '?') orelse {
                self.idx = self.bytes.len;
                return null;
            };
            const postfix = std.mem.indexOfPos(u8, self.bytes, second_q + 1, "?=") orelse {
                self.idx = self.bytes.len;
                return null;
            };

            self.idx = postfix + 2;
            return .{
                .pos = prefix,
                .len = postfix + 2 - prefix,
                .charset = self.bytes[prefix + 2 .. first_q],
                .encoding = self.bytes[first_q + 1],
                .content = self.bytes[second_q + 1 .. postfix],
            };
        }

        test "next" {
            var iter: Word.Iterator = .{ .bytes = "abc=?utf-8?b?Q2Fmw6k=?=def" };
            const word = iter.next();
            try std.testing.expect(word != null);
            try std.testing.expectEqual(3, word.?.pos);
            try std.testing.expectEqual(20, word.?.len);
        }
    };

    /// Decodes the word
    pub fn decode(self: Word, allocator: std.mem.Allocator) ![]const u8 {
        // TODO: support more charset encodings
        if (!std.ascii.eqlIgnoreCase(self.charset, "utf-8") and
            !std.ascii.eqlIgnoreCase(self.charset, "ansi_x3.4-1968")) return error.UnsupportedCharset;
        switch (self.encoding) {
            'B', 'b' => {
                var decoder = std.base64.standard.Decoder;
                const n = try decoder.calcSizeForSlice(self.content);
                const buf = try allocator.alloc(u8, n);
                try decoder.decode(buf, self.content);
                return buf;
            },
            'Q', 'q' => {
                var list = std.ArrayList(u8).init(allocator);
                defer list.deinit();
                var i: usize = 0;
                while (i < self.content.len) {
                    const idx = std.mem.indexOfScalarPos(u8, self.content, i, '=') orelse self.content.len;
                    try list.appendSlice(self.content[i..idx]);
                    if (idx >= self.content.len) break;
                    const b = try std.fmt.parseUnsigned(u8, self.content[idx + 1 .. idx + 3], 16);
                    try list.append(b);
                    i = idx + 3;
                }
                return allocator.dupe(u8, list.items);
            },
            else => return error.InvalidMimeWord,
        }
    }

    test "decode: base64" {
        const allocator = std.testing.allocator;
        const bytes = "=?utf-8?b?Q2Fmw6k=?=";
        var iter: Word.Iterator = .{ .bytes = bytes };
        const word = iter.next();
        try std.testing.expect(word != null);
        const decoded = try word.?.decode(allocator);
        defer allocator.free(decoded);
        try std.testing.expectEqualStrings("Café", decoded);
    }

    test "decode: quoted-printable" {
        const allocator = std.testing.allocator;
        const bytes = "=?utf-8?q?Fran=C3=A7ois-J=C3=A9r=C3=B4me?=";
        var iter: Word.Iterator = .{ .bytes = bytes };
        const word = iter.next();
        try std.testing.expect(word != null);
        const decoded = try word.?.decode(allocator);
        defer allocator.free(decoded);
        try std.testing.expectEqualStrings("François-Jérôme", decoded);
    }

    test "decode: quoted-printable ansi_x3" {
        const allocator = std.testing.allocator;
        const bytes = "=?ANSI_X3.4-1968?Q?\"The_Power_of_Perspicuity\"_with_Mind=3Fs_Eye_Madness?=";
        var iter: Word.Iterator = .{ .bytes = bytes };
        const word = iter.next();
        try std.testing.expect(word != null);
        const decoded = try word.?.decode(allocator);
        defer allocator.free(decoded);
        try std.testing.expectEqualStrings("\"The_Power_of_Perspicuity\"_with_Mind?s_Eye_Madness", decoded);
    }
};

pub const Parameter = struct {
    attribute: []const u8,
    value: []const u8,
};

/// Iterates over the parameters of a Content-Type header
pub const ParameterIterator = struct {
    src: []const u8,
    idx: usize = 0,

    pub fn next(self: *ParameterIterator) ?Parameter {
        if (self.idx >= self.src.len) return null;
        const end = std.mem.indexOfScalarPos(u8, self.src, self.idx, ';') orelse self.src.len;
        defer self.idx = end + 1;
        const trimmed = std.mem.trim(u8, self.src[self.idx..end], " \r\n\t");
        const sep = std.mem.indexOfScalar(u8, trimmed, '=') orelse return null;
        return .{
            .attribute = trimmed[0..sep],
            .value = trimmed[sep + 1 ..],
        };
    }
};
