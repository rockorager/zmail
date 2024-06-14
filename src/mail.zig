const std = @import("std");

pub const Address = @import("mail/Address.zig");
pub const Header = @import("mail/Header.zig");
pub const Message = @import("mail/Message.zig");
pub const mime = @import("mail/mime.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
