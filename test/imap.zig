const std = @import("std");
const tls = std.crypto.tls;
const imap = @import("zmail").imap;
const commands = imap.commands;

const TlsClient = struct {
    client: tls.Client,
    stream: std.net.Stream,

    fn opaqueRead(ptr: *const anyopaque, buf: []u8) !usize {
        const self: *TlsClient = @constCast(@ptrCast(@alignCast(ptr)));
        return self.client.read(self.stream, buf);
    }

    fn opaqueWrite(ptr: *const anyopaque, bytes: []const u8) !usize {
        const self: *TlsClient = @constCast(@ptrCast(@alignCast(ptr)));
        return self.client.write(self.stream, bytes);
    }

    pub fn anyReader(self: *const TlsClient) std.io.AnyReader {
        return .{
            .context = self,
            .readFn = TlsClient.opaqueRead,
        };
    }

    pub fn anyWriter(self: *const TlsClient) std.io.AnyWriter {
        return .{
            .context = self,
            .writeFn = TlsClient.opaqueWrite,
        };
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var ca_bundle = std.crypto.Certificate.Bundle{};
    try ca_bundle.rescan(allocator);
    defer ca_bundle.deinit(allocator);

    const Options = struct {
        host: []const u8,
        username: []const u8,
        password: []const u8,
    };

    var opts: Options = undefined;
    const host = "--host=";
    const username = "--username=";
    const password = "--password=";

    var args = std.process.args();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, host)) {
            opts.host = arg[host.len..];
        }
        if (std.mem.startsWith(u8, arg, username)) {
            opts.username = arg[username.len..];
        }
        if (std.mem.startsWith(u8, arg, password)) {
            opts.password = arg[password.len..];
        }
    }
    std.log.debug("{s}", .{opts.password});

    const stream = try std.net.tcpConnectToHost(allocator, opts.host, 993);
    var tls_client: TlsClient = .{
        .stream = stream,
        .client = try tls.Client.init(stream, ca_bundle, opts.host),
    };

    var client = imap.Client.init(allocator, tls_client.anyWriter(), tls_client.anyReader());
    const thread = try std.Thread.spawn(.{}, imap.Client.run, .{&client});
    thread.detach();

    var capability = commands.Capability.init(allocator, client.nextTag());
    defer capability.deinit();
    var authenticate = commands.Authenticate.init(
        allocator,
        opts.username,
        opts.password,
        .login,
        client.nextTag(),
    );
    try client.send(authenticate.command());
    try authenticate.wait();
    try client.send(capability.command());
    const caps = capability.wait();
    std.log.debug("caps: {s}", .{caps});
}
