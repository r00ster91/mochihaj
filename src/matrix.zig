const std = @import("std");
const mem = std.mem;
const log = std.log;
const json = std.json;
const testing = std.testing;

const http = @import("http2.zig");
pub const api = @import("matrix/api.zig");

/// A Matrix ID.
///
/// See also: https://spec.matrix.org/v1.2/appendices/#user-identifiers
pub const ID = struct {
    value: []const u8,

    const maximum_length = 255;

    /// Returns the username.
    pub fn getLocalpart(self: ID) []const u8 {
        var matrix_id_splitter = mem.split(u8, self.value, ":");
        const lhs = matrix_id_splitter.next().?;
        const sigil = "@";
        const localpart = mem.trimLeft(u8, lhs, sigil);
        return localpart;
    }

    /// Returns the homeserver's server name.
    /// This may include a port.
    fn getDomain(self: ID) []const u8 {
        var matrix_id_splitter = mem.split(u8, self.value, ":");
        _ = matrix_id_splitter.next().?;
        const domain = matrix_id_splitter.rest();
        return domain;
    }

    /// Minimizes the ID while keeping it unique.
    /// Use this for efficient storage.
    fn getMinimized(self: ID, id: *[maximum_length]u8) []const u8 {
        const localpart = self.getLocalpart();
        mem.copy(u8, id, localpart);

        const domain = self.getDomain();
        const removals = mem.replace(u8, domain, ".", "", id[localpart.len..]);

        return id[0 .. localpart.len + (domain.len - removals)];
    }
};

pub const Client = struct {
    http_client: http.Client,
    homeserver_url: []const u8,

    /// Initializes a Matrix client such that requests can be made to the homeserver.
    pub fn init(allocator: mem.Allocator, id: ID) !Client {
        // The hostname is the server name without a port
        const hostname = hostname: {
            const server_name = id.getDomain();
            var server_name_splitter = mem.split(u8, server_name, ":");
            break :hostname server_name_splitter.next().?;
        };

        var matrix_client = Client{
            .http_client = try http.Client.init(
                allocator,
                hostname,
                .encrypted,
            ),
            .homeserver_url = undefined,
        };

        try matrix_client.http_client.setHeader(allocator, "Content-Type", "application/json");

        var discover_server_request = async matrix_client.discoverServer(allocator);
        resume matrix_client.http_client.request_frame;
        matrix_client.homeserver_url = try nosuspend await discover_server_request;

        var homeserver_url_splitter = mem.split(u8, matrix_client.homeserver_url, "//");
        _ = homeserver_url_splitter.next().?;
        const homeserver_hostname = mem.trimRight(u8, homeserver_url_splitter.rest(), "/");

        matrix_client.http_client.hostname = homeserver_hostname;

        return matrix_client;
    }

    pub fn deinit(self: Client, allocator: mem.Allocator) void {
        self.http_client.deinit();
        allocator.free(self.homeserver_url);
    }

    pub usingnamespace api;
};

const test_id = ID{ .value = "@localpart:subdomain.domain.com" };

test "splitting IDs" {
    try testing.expectEqualStrings("localpart", test_id.getLocalpart());
    try testing.expectEqualStrings("subdomain.domain.com", test_id.getDomain());
}

test "minimizing IDs" {
    var minimized_id: [ID.maximum_length]u8 = undefined;
    try testing.expectEqualStrings("localpartsubdomaindomaincom", test_id.getMinimized(&minimized_id));
}
