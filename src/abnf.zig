const std = @import("std");

pub const HTAB: u8 = 0x09;
pub const SP: u8 = 0x20;
pub const CRLF: []const u8 = "\r\n";

/// Returns true when the byte is classified as WSP
pub fn isWSP(b: u8) bool {
    return b == SP or b == HTAB;
}
