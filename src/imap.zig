const std = @import("std");

pub const Client = @import("imap/Client.zig");
pub const Command = @import("imap/Command.zig");
pub const commands = @import("imap/commands.zig");

pub const Error = error{
    AuthenticationFailed,
    CannotStartTLS,
    InvalidArguments,
    InvalidArgumentsOrCommandUnknown,
};

test {
    std.testing.refAllDecls(@This());
}
