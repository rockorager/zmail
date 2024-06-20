pub const imap = @import("imap.zig");
pub const mail = @import("mail.zig");

test {
    _ = @import("imap.zig");
    _ = @import("mail.zig");
}
