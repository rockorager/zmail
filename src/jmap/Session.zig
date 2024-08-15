const Session = @This();

const std = @import("std");
const util = @import("util.zig");

const Account = @import("Account.zig");
const Core = @import("Core.zig");

const json = std.json;
const mem = std.mem;
const testing = std.testing;

const PrimaryAccount = struct {
    uri: []const u8,
    id: []const u8,
};

capabilities: struct {
    core: Core.Capability,
    /// The mail capability is only a bool in the session object. It's either present or not.
    mail: bool,
},

/// List of accounts. Map of account ID to account
accounts: []const Account,

/// Map of capability URI to account ID
primary_accounts: []const PrimaryAccount,

username: []const u8,
api_url: []const u8,
download_url: []const u8,
upload_url: []const u8,
event_source_url: []const u8,
state: []const u8,

pub fn jsonParse(
    allocator: mem.Allocator,
    source: anytype,
    options: json.ParseOptions,
) !Session {
    const value = try json.innerParse(json.Value, allocator, source, options);

    return jsonParseFromValue(allocator, value, options);
}

pub fn jsonParseFromValue(
    allocator: mem.Allocator,
    value: json.Value,
    options: json.ParseOptions,
) !Session {
    const root = try util.jsonAssertObject(value);
    const cap_obj = try util.jsonGetObject(root, "capabilities");
    const core_val = cap_obj.get(Core.uri) orelse return json.ParseFromValueError.MissingField;
    const core_cap = try Core.Capability.jsonParseFromValue(allocator, core_val, options);

    const mail_cap: bool = if (cap_obj.get("urn:ietf:params:jmap:mail")) |_| true else false;

    var accounts = std.ArrayList(Account).init(allocator);

    const account_obj = try util.jsonGetObject(root, "accounts");
    var account_iter = account_obj.iterator();
    while (account_iter.next()) |kv| {
        var account = try Account.jsonParseFromValue(allocator, kv.value_ptr.*, options);
        account.id = kv.key_ptr.*;
        try accounts.append(account);
    }

    var primary_accounts = std.ArrayList(PrimaryAccount).init(allocator);
    const primary_accounts_obj = try util.jsonGetObject(root, "primaryAccounts");
    var primary_accounts_iter = primary_accounts_obj.iterator();
    while (primary_accounts_iter.next()) |kv| {
        const id = try util.jsonAssertString(kv.value_ptr.*);
        try primary_accounts.append(.{
            .uri = kv.key_ptr.*,
            .id = id,
        });
    }

    return .{
        .capabilities = .{
            .core = core_cap,
            .mail = mail_cap,
        },
        .accounts = accounts.items,
        .primary_accounts = primary_accounts.items,
        .username = try util.jsonGetString(root, "username"),
        .api_url = try util.jsonGetString(root, "apiUrl"),
        .download_url = try util.jsonGetString(root, "downloadUrl"),
        .upload_url = try util.jsonGetString(root, "uploadUrl"),
        .event_source_url = try util.jsonGetString(root, "eventSourceUrl"),
        .state = try util.jsonGetString(root, "state"),
    };
}

test "Session.zig: json decode" {
    const src =
        \\{
        \\ "capabilities": {
        \\   "urn:ietf:params:jmap:core": {
        \\     "maxSizeUpload": 50000000,
        \\     "maxConcurrentUpload": 8,
        \\     "maxSizeRequest": 10000000,
        \\     "maxConcurrentRequests": 8,
        \\     "maxCallsInRequest": 32,
        \\     "maxObjectsInGet": 256,
        \\     "maxObjectsInSet": 128,
        \\     "collationAlgorithms": [
        \\       "i;ascii-numeric",
        \\       "i;ascii-casemap",
        \\       "i;unicode-casemap"
        \\     ]
        \\   },
        \\   "urn:ietf:params:jmap:mail": {},
        \\   "urn:ietf:params:jmap:contacts": {},
        \\   "https://example.com/apis/foobar": {
        \\     "maxFoosFinangled": 42
        \\   }
        \\ },
        \\ "accounts": {
        \\   "A13824": {
        \\     "name": "john@example.com",
        \\     "isPersonal": true,
        \\     "isReadOnly": false,
        \\     "accountCapabilities": {
        \\       "urn:ietf:params:jmap:mail": {
        \\         "maxMailboxesPerEmail": null,
        \\         "maxMailboxDepth": 10
        \\       }
        \\     }
        \\   },
        \\   "A97813": {
        \\     "name": "jane@example.com",
        \\     "isPersonal": false,
        \\     "isReadOnly": true,
        \\     "accountCapabilities": {
        \\       "urn:ietf:params:jmap:mail": {
        \\         "maxMailboxesPerEmail": 1,
        \\         "maxMailboxDepth": 10
        \\       }
        \\     }
        \\   }
        \\ },
        \\ "primaryAccounts": {
        \\   "urn:ietf:params:jmap:mail": "A13824",
        \\   "urn:ietf:params:jmap:contacts": "A13824"
        \\ },
        \\ "username": "john@example.com",
        \\ "apiUrl": "https://jmap.example.com/api/",
        \\ "downloadUrl": "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
        \\ "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
        \\ "eventSourceUrl": "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
        \\ "state": "75128aab4b1b"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(Session, std.testing.allocator, src, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const expected: Session = .{
        .capabilities = .{
            .core = .{
                .max_size_upload = 50_000_000,
                .max_concurrent_upload = 8,
                .max_size_request = 10_000_000,
                .max_concurrent_requests = 8,
                .max_calls_in_request = 32,
                .max_objects_in_get = 256,
                .max_objects_in_set = 128,
                .collation_algorithms = &.{
                    .ascii_numeric,
                    .ascii_casemap,
                    .unicode_casemap,
                },
            },
            .mail = true,
        },
        .accounts = &.{
            .{
                .id = "A13824",
                .name = "john@example.com",
                .is_personal = true,
                .is_read_only = false,
                .capabilities = .{},
            },
            .{
                .id = "A97813",
                .name = "jane@example.com",
                .is_personal = false,
                .is_read_only = true,
                .capabilities = .{},
            },
        },
        .primary_accounts = &.{
            .{
                .uri = "urn:ietf:params:jmap:mail",
                .id = "A13824",
            },
            .{
                .uri = "urn:ietf:params:jmap:contacts",
                .id = "A13824",
            },
        },
        .username = "john@example.com",
        .api_url = "https://jmap.example.com/api/",
        .download_url = "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
        .upload_url = "https://jmap.example.com/upload/{accountId}/",
        .event_source_url = "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
        .state = "75128aab4b1b",
    };

    try testing.expectEqualDeep(expected, parsed.value);
}
