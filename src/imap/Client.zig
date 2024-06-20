//! An IMAP client
const Client = @This();

const std = @import("std");
const Command = @import("Command.zig");

const log = std.log.scoped(.imap);

reader: std.io.AnyReader,
writer: std.io.AnyWriter,
in_process_commands: std.ArrayList(Command),
mutex: std.Thread.Mutex = .{},

next_tag: u16 = 0,

pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter, reader: std.io.AnyReader) Client {
    return .{
        .writer = writer,
        .reader = reader,
        .in_process_commands = std.ArrayList(Command).init(allocator),
    };
}

pub fn deinit(self: *Client) void {
    self.in_process_commands.deinit();
}

pub fn run(self: *Client) !void {
    var buf: [4096]u8 = undefined;
    var read_start: usize = 0;
    while (true) {
        const n = try self.reader.read(buf[read_start..]);
        if (n == 0) break;
        var start: usize = 0;
        const read_end = read_start + n;
        while (true) {
            const end = std.mem.indexOfPos(u8, buf[0..read_end], start, "\r\n") orelse {
                if (start < read_end) {
                    var i: usize = 0;
                    while (i < read_end - start) : (i += 1) {
                        buf[i] = buf[i + start];
                    }
                    read_start = i;
                    break;
                }
                read_start = 0;
                break;
            };
            const line = buf[start..end];
            log.debug("S: {s}", .{line});

            start = end + 2;
            self.mutex.lock();
            defer self.mutex.unlock();
            for (self.in_process_commands.items, 0..) |cmd, i| {
                const result = cmd.handleLine(line) catch |err| {
                    log.err("couldn't handle line: {}", .{err});
                    continue;
                };
                switch (result) {
                    // Try the next command
                    .not_handled => continue,
                    // Read another line
                    .@"continue" => break,
                    // Complete the command and remove from our list
                    .complete => {
                        _ = self.in_process_commands.orderedRemove(i);
                        break;
                    },
                    .quit => return,
                }
            } else std.log.err("unhandled line: {s}", .{line});
            // } else return;
        }
    }
}

pub fn nextTag(self: *Client) u16 {
    defer self.next_tag +%= 1;
    return self.next_tag;
}

pub fn send(self: *Client, cmd: Command) !void {
    self.mutex.lock();
    errdefer self.mutex.unlock();
    try self.in_process_commands.append(cmd);
    self.mutex.unlock();
    try cmd.writeTo(self.writer);
}
