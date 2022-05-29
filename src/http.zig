//! Hypertext Transfer Protocol (HTTP).

const std = @import("std");
const log = std.log;
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;

const curl = @cImport(@cInclude("curl/curl.h"));

const Encryption = enum {
    /// HTTP.
    unencrypted,
    /// HTTPS.
    encrypted,
};

pub const Response = struct {
    status: std.http.Status,
    body: []const u8,
};

pub const Client = struct {
    curl_handle: *curl.CURL,
    curl_headers: *curl.curl_slist,
    hostname: []const u8,
    encryption: Encryption,
    body: std.ArrayList(u8),
    error_string: [curl.CURL_ERROR_SIZE]u8 = undefined,

    const ContentType = enum { @"application/json" };

    pub fn init(allocator: mem.Allocator, hostname: []const u8, encryption: Encryption) !Client {
        if (curl.curl_global_init(curl.CURL_GLOBAL_SSL) != curl.CURLE_OK)
            return error.InitializationFailed;

        const curl_handle = curl.curl_easy_init() orelse return error.InitializationFailed;

        // We want TLS 1.3 and HTTP/2
        if (curl.curl_easy_setopt(
            curl_handle,
            curl.CURLOPT_SSLVERSION,
            curl.CURL_SSLVERSION_TLSv1_3,
        ) != curl.CURLE_OK)
            unreachable;
        if (curl.curl_easy_setopt(
            curl_handle,
            curl.CURLOPT_HTTP_VERSION,
            curl.CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE,
        ) != curl.CURLE_OK)
            unreachable;

        const curl_headers = curl_headers: {
            // We don't need Accept
            var curl_headers: [*c]curl.curl_slist = @as(
                ?[*c]curl.curl_slist,
                curl.curl_slist_append(null, "Accept:"),
            ) orelse return error.FailedSettingHeader;

            // This only needs to be set once
            if (curl.curl_easy_setopt(curl_handle, curl.CURLOPT_HTTPHEADER, curl_headers) != curl.CURLE_OK)
                unreachable;

            break :curl_headers curl_headers;
        };

        const client = Client{
            .curl_handle = curl_handle,
            .curl_headers = curl_headers,
            .hostname = hostname,
            .encryption = encryption,
            .body = std.ArrayList(u8).init(allocator),
        };

        // This callback lets us read the body's content in chunks.
        // The amount of data we get in one chunk could be any amount
        // so we must not make any assumptions.
        //
        // This is not writing a body.
        const write_callback = struct {
            fn write_callback(ptr: [*]u8, size: usize, nmemb: usize, userdata: *std.ArrayList(u8)) usize {
                _ = size;

                userdata.appendSlice(ptr[0..nmemb]) catch |@"error"| {
                    switch (@"error") {
                        error.OutOfMemory => {
                            // TODO: error the current request and keep going?
                            @panic("out of memory");
                        },
                    }
                };

                return nmemb;
            }
        }.write_callback;
        if (curl.curl_easy_setopt(curl_handle, curl.CURLOPT_WRITEFUNCTION, write_callback) != curl.CURLE_OK)
            unreachable;

        // Setup the error string
        if (curl.curl_easy_setopt(curl_handle, curl.CURLOPT_ERRORBUFFER, &client.error_string) != curl.CURLE_OK)
            unreachable;

        // TODO: remove this
        // if (curl.curl_easy_setopt(curl_handle, curl.CURLOPT_VERBOSE, @as(c_int,1)) != curl.CURLE_OK)
        //     unreachable;

        return client;
    }

    pub fn deinit(self: Client) void {
        curl.curl_global_cleanup();
        curl.curl_easy_cleanup(self.curl_handle);
        curl.curl_slist_free_all(self.curl_headers);
        self.body.deinit();
    }

    /// Sets a request header. `key` is case-insensitive.
    ///
    /// Use `null` for `value` to remove the header.
    pub fn setHeader(self: *Client, allocator: mem.Allocator, key: []const u8, value: ?[]const u8) !void {
        const string = if (value) |header_value|
            try fmt.allocPrintZ(allocator, "{s}:{s}", .{ key, header_value })
        else
            try fmt.allocPrintZ(allocator, "{s}:", .{key});
        defer allocator.free(string);
        self.curl_headers = @as(
            ?*curl.curl_slist,
            curl.curl_slist_append(self.curl_headers, string),
        ) orelse return error.FailedSettingHeader;
    }

    pub fn request(self: *Client, allocator: mem.Allocator, method: std.http.Method, path: []const u8, body: ?[]const u8) !Response {
        if (body) |body_value| {
            if (@import("builtin").mode == .Debug)
                if (!method.requestHasBody())
                    std.debug.panic("{s} request must not have body", .{@tagName(method)});
            if (curl.curl_easy_setopt(self.curl_handle, curl.CURLOPT_POSTFIELDS, body_value.ptr) != curl.CURLE_OK)
                unreachable;
            if (curl.curl_easy_setopt(self.curl_handle, curl.CURLOPT_POSTFIELDSIZE, body_value.len) != curl.CURLE_OK)
                unreachable;
        }

        if (curl.curl_easy_setopt(self.curl_handle, curl.CURLOPT_CUSTOMREQUEST, @tagName(method).ptr) != curl.CURLE_OK)
            return error.OutOfMemory;

        const scheme = switch (self.encryption) {
            .unencrypted => "http",
            .encrypted => "https",
        };
        const url = try fmt.allocPrintZ(allocator, "{s}://{s}{s}", .{ scheme, self.hostname, path });
        defer allocator.free(url);

        if (curl.curl_easy_setopt(self.curl_handle, curl.CURLOPT_URL, url.ptr, curl.CURLU_PATH_AS_IS) != curl.CURLE_OK)
            return error.SettingURLFailed;

        self.body.items.len = 0;

        if (curl.curl_easy_setopt(self.curl_handle, curl.CURLOPT_WRITEDATA, &self.body) != curl.CURLE_OK)
            unreachable;

        log.info("sending {s} request to {s}", .{ @tagName(method), url });
        log.debug("request body: {s}", .{ body });

        // Here `write_callback` will be invoked
        const result = curl.curl_easy_perform(self.curl_handle);
        if (result != curl.CURLE_OK) {
            log.err("{}: {s}", .{ result, self.error_string });
            return error.RequestFailed;
        }

        var status: std.http.Status = undefined;
        if (curl.curl_easy_getinfo(self.curl_handle, curl.CURLINFO_RESPONSE_CODE, &status) != curl.CURLE_OK)
            unreachable;
        if (@enumToInt(status) == 0)
            return error.NoResponseCode;

        log.debug("response status: {}", .{status});
        log.debug("response body: {s}\n", .{self.body.items});
        return Response{ .status = status, .body = self.body.items };
    }
};

test "GET requests" {
    const hostname = "www.google.com";

    var client = try Client.init(testing.allocator, hostname, .encrypted);
    defer client.deinit();
    var response = try client.request(testing.allocator, .GET, "/", null);
    try testing.expect(response.status == .ok);
    try testing.expect(response.body.len != 0);

    response = try client.request(testing.allocator, .POST, "/", "hello");
    try testing.expect(response.status == .method_not_allowed);
    try testing.expect(response.body.len != 0);
}
