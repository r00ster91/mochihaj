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

/// An interface to allow making HTTP requests to HTTP servers.
///
/// This supports making HTTP requests in parallel.
/// It's recommended to collect HTTP requests in batches as much as possible
/// until they're actually required to be done, so that they can be done in parallel.
// TODO: "if you need the result immediately, use `fetch`"? or `immediately` or something?
pub const Client = struct {
    curl_multi_handle: *curl.CURLM,
    // TODO: later use some kind of pool to reuse handles?
    curl_easy_handles: std.ArrayList(*curl.CURL),
    curl_headers: *curl.curl_slist,
    hostname: []const u8,
    encryption: Encryption,
    body: std.ArrayList(u8),
    request_frame: *@Frame(request),
    error_string: [curl.CURL_ERROR_SIZE]u8 = undefined,

    const ContentType = enum { @"application/json" };

    pub fn init(allocator: mem.Allocator, hostname: []const u8, encryption: Encryption) !Client {
        if (curl.curl_global_init(curl.CURL_GLOBAL_SSL) != curl.CURLE_OK)
            return error.InitializationFailed;

        const curl_headers = curl_headers: {
            // We don't need Accept
            var curl_headers: [*c]curl.curl_slist = @as(
                ?[*c]curl.curl_slist,
                curl.curl_slist_append(null, "Accept:"),
            ) orelse return error.FailedSettingHeader;

            break :curl_headers curl_headers;
        };

        const client = Client{
            .curl_multi_handle = curl.curl_multi_init().?,
            .curl_easy_handles = std.ArrayList(*curl.CURL).init(allocator),
            .curl_headers = curl_headers,
            .hostname = hostname,
            .encryption = encryption,
            .body = std.ArrayList(u8).init(allocator),
            .request_frame = undefined,
        };

        // // Setup the error string
        // if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_ERRORBUFFER, &client.error_string) != curl.CURLE_OK)
        //     unreachable;

        // TODO: remove this
        // if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_VERBOSE, @as(c_int,1)) != curl.CURLE_OK)
        //     unreachable;

        return client;
    }

    fn getCurlEasyHandle(self: Client) !*curl.CURL {
        const curl_easy_handle = curl.curl_easy_init() orelse return error.InitializationFailed;

        // We want TLS 1.3 and HTTP/2
        if (curl.curl_easy_setopt(
            curl_easy_handle,
            curl.CURLOPT_SSLVERSION,
            curl.CURL_SSLVERSION_TLSv1_3,
        ) != curl.CURLE_OK)
            unreachable;
        if (curl.curl_easy_setopt(
            curl_easy_handle,
            curl.CURLOPT_HTTP_VERSION,
            curl.CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE,
        ) != curl.CURLE_OK)
            unreachable;

        // This only needs to be set once
        if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_HTTPHEADER, self.curl_headers) != curl.CURLE_OK)
            unreachable;

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
        if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_WRITEFUNCTION, write_callback) != curl.CURLE_OK)
            unreachable;

        // Setup the error string
        if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_ERRORBUFFER, &self.error_string) != curl.CURLE_OK)
            unreachable;

        return curl_easy_handle;
    }

    pub fn deinit(self: Client) void {
        for (self.curl_easy_handles.items) |curl_easy_handle| {
            if (curl.curl_multi_remove_handle(self.curl_multi_handle, curl_easy_handle) != curl.CURLE_OK)
                unreachable;
            curl.curl_easy_cleanup(curl_easy_handle);
        }
        self.curl_easy_handles.deinit();
        if (curl.curl_multi_cleanup(self.curl_multi_handle) != curl.CURLE_OK)
            unreachable;
        curl.curl_slist_free_all(self.curl_headers);
        curl.curl_global_cleanup();
        self.body.deinit();
    }

    /// Sets a request header for all following requests. `key` is case-insensitive.
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

    pub fn request(self: *Client, allocator: mem.Allocator, method: std.http.Method, path: []const u8, body: ?[]const u8) !Response { //usize { // !Response {
        const curl_easy_handle = try self.getCurlEasyHandle();

        if (body) |body_value| {
            if (@import("builtin").mode == .Debug)
                if (!method.requestHasBody())
                    std.debug.panic("{s} request must not have body", .{@tagName(method)});
            if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_POSTFIELDS, body_value.ptr) != curl.CURLE_OK)
                unreachable;
            if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_POSTFIELDSIZE, body_value.len) != curl.CURLE_OK)
                unreachable;
        }

        if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_CUSTOMREQUEST, @tagName(method).ptr) != curl.CURLE_OK)
            return error.OutOfMemory;

        const scheme = switch (self.encryption) {
            .unencrypted => "http",
            .encrypted => "https",
        };
        const url = try fmt.allocPrintZ(allocator, "{s}://{s}{s}", .{ scheme, self.hostname, path });
        defer allocator.free(url);

        if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_URL, url.ptr, curl.CURLU_PATH_AS_IS) != curl.CURLE_OK)
            return error.SettingURLFailed;

        self.body.items.len = 0;

        if (curl.curl_easy_setopt(curl_easy_handle, curl.CURLOPT_WRITEDATA, &self.body) != curl.CURLE_OK)
            unreachable;

        log.info("adding to queue: {s} request to {s}", .{ @tagName(method), url });
        if (body) |body_value| log.debug("request body: {s}", .{body_value});

        if (curl.curl_multi_add_handle(self.curl_multi_handle, curl_easy_handle) != curl.CURLE_OK)
            return error.AddingCurlEasyHandleFailed;

        const index = self.curl_easy_handles.items.len;
        try self.curl_easy_handles.append(curl_easy_handle);

        suspend {
            // Now we're suspended and wait for `awaitAll` to be called
            // before this frame is `resume`d.
            self.request_frame = @frame();
        }

        var status: std.http.Status = undefined;
        if (curl.curl_easy_getinfo(curl_easy_handle, curl.CURLINFO_RESPONSE_CODE, &status) != curl.CURLE_OK)
            unreachable;
        if (@enumToInt(status) == 0) {
            // `awaitAll` hasn't been called and this request hasn't finished yet.
            // Finish specifically this request because we need it to finish immediately.
            _ = self.curl_easy_handles.swapRemove(index);
            if (curl.curl_multi_remove_handle(self.curl_multi_handle, curl_easy_handle) != curl.CURLE_OK)
                unreachable;

            // This will invoke `write_callback`.
            const result = curl.curl_easy_perform(curl_easy_handle);
            if (result != curl.CURLE_OK) {
                log.err("{}: {s}", .{ result, self.error_string });
                return error.RequestFailed;
            }
            if (curl.curl_easy_getinfo(curl_easy_handle, curl.CURLINFO_RESPONSE_CODE, &status) != curl.CURLE_OK)
                unreachable;
            if (@enumToInt(status) == 0)
                // The request succeeded
                unreachable;
        }

        log.debug("response status: {}", .{status});
        log.debug("response body: {s}", .{self.body.items});
        return Response{ .status = status, .body = self.body.items };
    }

    pub fn awaitAll(self: Client) void {
        var polls: usize = 0;

        var transfers_running: c_int = undefined;
        var mc: curl.CURLMcode = curl.curl_multi_perform(self.curl_multi_handle, &transfers_running);
        while (transfers_running > 0) {
            mc = curl.curl_multi_perform(self.curl_multi_handle, &transfers_running);

            if (transfers_running > 0) {
                mc = curl.curl_multi_poll(self.curl_multi_handle, null, 0, 1000, null);
            }

            polls += 1;

            if (mc != 0)
                break;
        }

        log.debug("all transfers finished in {d} polls", .{polls});
    }
};

const test_hostname = "www.google.com";

test "parallel GET requests" {
    var client = try Client.init(testing.allocator, test_hostname, .encrypted);
    defer client.deinit();

    var requests = [_]@Frame(Client.request){
        async client.request(testing.allocator, .GET, "/", null),
        async client.request(testing.allocator, .GET, "/", null),
        async client.request(testing.allocator, .GET, "/", null),
        async client.request(testing.allocator, .GET, "/", null),
        async client.request(testing.allocator, .GET, "/", null),
    };

    client.awaitAll();

    for (requests) |*request| {
        resume request;
        // `nosuspend` makes sure we don't leak the synchrony to outside
        const response = try nosuspend await request;
        try testing.expect(response.status == .ok);
        try testing.expect(response.body.len != 0);
    }
}

test "POST requests" {
    var client = try Client.init(testing.allocator, test_hostname, .encrypted);
    defer client.deinit();

    var request = async client.request(testing.allocator, .POST, "/", "hello");
    client.awaitAll();
    resume request;
    const response = try nosuspend await request;

    try testing.expect(response.status == .method_not_allowed);
    try testing.expect(response.body.len != 0);
}
