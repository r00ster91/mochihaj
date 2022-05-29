//! The Client-Server API used to interact with Matrix.
//!
//! Matrix makes no distinction between humans and bots.
//!
//! There is no full coverage of the API
//! and only a minimal subset of the API is implemented.
//! More coverage is added on demand.
//!
//! The functions extract the minimal amount of data required.
//!
//! Resources and references:
//! * https://spec.matrix.org/v1.2/
//! * https://spec.matrix.org/v1.2/client-server-api/
//! * https://matrix.org/docs/api/

const std = @import("std");
const log = std.log;
const fmt = std.fmt;
const mem = std.mem;
const json = std.json;

const http = @import("../http.zig");
const matrix = @import("../matrix.zig");
const Client = matrix.Client;
const Endpoint = @import("api/endpoint.zig").Endpoint;

/// This MUST be encoded as UTF-8.
pub const String = []const u8;
const Integer = i64;

const UserID = String;

const UserIdentifier = struct {
    type: String = "m.id.user",
    user: UserID,
};

pub const Error = struct {
    errcode: String,
    @"error": String,
};

const RateLimitError = struct {
    errcode: String,
    @"error": String,
    retry_after_ms: Integer,
};

const HomeserverInformation = struct { base_url: String };

/// Discovers and returns the base URL of the homeserver.
///
/// See also: https://spec.matrix.org/v1.2/client-server-api/#server-discovery
pub fn discoverServer(self: *Client, allocator: mem.Allocator) (error{NoHomeserverBaseURL} || anyerror)!String {
    const endpoint = Endpoint(.GET, null, union(enum) {
        @"200": struct {
            @"m.homeserver": HomeserverInformation,
        },
        @"404": struct {},
    });
    switch (try endpoint.execute(self, allocator, "/.well-known/matrix/client")) {
        .@"200" => |response| return try allocator.dupe(u8, response.@"m.homeserver".base_url),
        .@"404" => return error.NoHomeserverBaseURL,
    }
}

// revisit this and the `login` parameters
const Login = struct {
    identifier: UserIdentifier,
    password: String,
    type: enum {
        @"m.login.password",

        pub fn jsonStringify(
            self: @This(),
            _: json.StringifyOptions,
            out_stream: anytype,
        ) !void {
            try out_stream.writeAll("\"" ++ @tagName(self) ++ "\"");
        }
    },
};

/// Logs in and obtains and returns the access token.
///
/// See also:
/// * https://spec.matrix.org/v1.2/client-server-api/#get_matrixclientv3login
/// * https://spec.matrix.org/v1.2/client-server-api/#using-access-tokens
pub fn login(self: *Client, allocator: mem.Allocator, request_value: Login) (error{ InvalidRequest, LoginFailed } || anyerror)!String {
    const endpoint = Endpoint(.POST, Login, union(enum) {
        @"200": struct { access_token: String },
        @"400": Error,
        @"403": Error,
        @"429": RateLimitError,
    });
    switch (try endpoint.execute(self, allocator, "/_matrix/client/v3/login", request_value)) {
        .@"200" => |response| return try allocator.dupe(u8, response.access_token),
        .@"400" => return error.InvalidRequest,
        .@"403" => return error.LoginFailed,
        .@"429" => @panic("handle rate limits"),
    }
}

const EventFilter = struct {
    limit: ?Integer = null,
    types: ?[]const String = null,
};

const RoomEventFilter = struct {
    limit: ?Integer = null,
    types: ?[]const String = null,
};

const RoomFilter = struct {
    account_data: ?RoomEventFilter = null,
    ephemeral: ?RoomEventFilter = null,
    timeline: ?RoomEventFilter = null,
};

const Filter = struct {
    account_data: ?EventFilter = null,
    event_fields: ?[]const String = null,
    presence: ?EventFilter = null,
    room: ?RoomFilter = null,
};

/// Uploads a filter for filtering data returned by `synchronize` and returns
/// an ID to the filter to be passed to `synchronize`.
///
/// See also:
/// * https://spec.matrix.org/v1.2/client-server-api/#filtering
/// * https://spec.matrix.org/v1.2/client-server-api/#post_matrixclientv3useruseridfilter
pub fn uploadFilter(self: *Client, allocator: mem.Allocator, id: matrix.ID, filter: Filter) !String {
    const endpoint = Endpoint(
        .POST,
        Filter,
        union(enum) {
            @"200": struct { filter_id: String },
        },
    );
    const path = try fmt.allocPrint(allocator, "/_matrix/client/v3/user/{s}/filter", .{id.value});
    defer allocator.free(path);
    switch (try endpoint.execute(self, allocator, path, filter)) {
        .@"200" => |response| {
            return try allocator.dupe(u8, response.filter_id);
        },
    }
}

/// Attempts to join a room specified by an ID.
///
/// See also: https://spec.matrix.org/v1.2/client-server-api/#post_matrixclientv3roomsroomidjoin
pub fn joinRoom(self: *Client, allocator: mem.Allocator, room_id: String) (error{NoPermission} || anyerror)!void {
    const endpoint = Endpoint(
        .POST,
        struct {},
        union(enum) {
            @"200": struct {},
            @"403": Error,
            @"429": RateLimitError,
        },
    );
    const path = try fmt.allocPrint(allocator, "/_matrix/client/v3/rooms/{s}/join", .{room_id});
    defer allocator.free(path);
    switch (try endpoint.execute(self, allocator, path, .{})) {
        .@"200" => {},
        .@"403" => return error.NoPermission,
        .@"429" => @panic("handle rate limits"),
    }
}

/// Leaves a room specified by an ID.
///
/// See also: https://spec.matrix.org/v1.2/client-server-api/#post_matrixclientv3roomsroomidjoin
pub fn leaveRoom(self: *Client, allocator: mem.Allocator, room_id: String) !void {
    const endpoint = Endpoint(
        .POST,
        struct {},
        union(enum) {
            @"200": struct {},
            @"429": RateLimitError,
        },
    );
    const path = try fmt.allocPrint(allocator, "/_matrix/client/v3/rooms/{s}/leave", .{room_id});
    defer allocator.free(path);
    switch (try endpoint.execute(self, allocator, path, .{})) {
        .@"200" => {},
        .@"429" => @panic("handle rate limits"),
    }
}

/// Forgets a room specified by an ID.
///
/// See also: https://spec.matrix.org/v1.2/client-server-api/#post_matrixclientv3roomsroomidjoin
pub fn forgetRoom(self: *Client, allocator: mem.Allocator, room_id: String) (error{RoomNotLeft} || anyerror)!void {
    const endpoint = Endpoint(
        .POST,
        struct {}, // TODO: try sending no body even for POST
        union(enum) {
            @"200": struct {},
            @"400": Error,
            @"429": RateLimitError,
        },
    );
    // TODO: this could be used to handle rate limits:
    // std.builtin.SourceLocation
    // @compileLog(@src());
    const path = try fmt.allocPrint(allocator, "/_matrix/client/v3/rooms/{s}/forget", .{room_id});
    defer allocator.free(path);
    switch (try endpoint.execute(self, allocator, path, .{})) {
        .@"200" => {},
        .@"400" => return error.RoomNotLeft,
        .@"429" => @panic("handle rate limits"),
    }
}

const State = struct {
    next_batch: String,
    rooms: ?struct {
        invite: ?std.StringArrayHashMap(
            struct {
                invite_state: struct {
                    events: []struct {
                        type: String,
                    },
                },
            },
        ) = null,
        join: ?std.StringArrayHashMap(
            struct {
                timeline: struct {
                    events: []struct {
                        content: json.ObjectMap,
                        sender: ?String = null,
                    },
                },
            },
        ) = null,
    } = null,
};

/// Synchronizes the client's state with the server's state.
///
/// The `timeout` parameter is given in milliseconds and is used
/// to block/long-poll the server until new information is received.
pub fn synchronize(
    self: *Client,
    allocator: mem.Allocator,
    filter_id: ?String,
    since: ?String,
    timeout: ?u32,
) !State {
    var path = try allocator.dupe(u8, "/_matrix/client/v3/sync");
    var query_prefix: u8 = '?';

    if (filter_id) |filter_id_value| {
        const previous_path = path;
        defer allocator.free(previous_path);
        path = try fmt.allocPrint(
            allocator,
            "{s}{c}filter={s}",
            .{ path, query_prefix, filter_id_value },
        );
        query_prefix = '&';
    }

    if (since) |since_value| {
        const previous_path = path;
        defer allocator.free(previous_path);
        path = try fmt.allocPrint(
            allocator,
            "{s}{c}since={s}",
            .{ path, query_prefix, since_value },
        );
        query_prefix = '&';
    }

    if (timeout) |timeout_value| {
        const previous_path = path;
        defer allocator.free(previous_path);
        path = try fmt.allocPrint(
            allocator,
            "{s}{c}timeout={d}",
            .{ path, query_prefix, timeout_value },
        );
        query_prefix = '&';
    }

    defer allocator.free(path);

    const endpoint = Endpoint(
        .GET,
        null,
        union(enum) {
            @"200": json.ValueTree,
        },
    );
    switch (try endpoint.execute(self, allocator, path)) {
        .@"200" => |*response| {
            // TODO: defer response.deinit(); outside of this function
            const tres = @import("../lib/tres/tres.zig");
            const state = try tres.parse(
                State,
                response.root,
                allocator,
            );
            return state;
        },
    }
}

// TODO: eventually this should probably be abstracted further using a `sendEvent`
/// Sends a message to a room.
///
/// See also: https://spec.matrix.org/v1.2/client-server-api/#put_matrixclientv3roomsroomidsendeventtypetxnid
pub fn sendMessage(
    self: *Client,
    allocator: mem.Allocator,
    room_id: String,
    body: String,
    formatted_body: ?String,
    notice: bool,
) !void {
    // Individually for each access token the transaction ID has to be different for each request,
    // even after a restart. All this is solved by using monotonic time.
    const now = (try std.time.Instant.now()).timestamp;
    const transaction_id = now.tv_nsec + now.tv_sec * std.time.ns_per_s;

    const path = try fmt.allocPrint(
        allocator,
        "/_matrix/client/v3/rooms/{s}/send/m.room.message/{d}",
        .{ room_id, transaction_id },
    );
    const endpoint = Endpoint(
        .PUT,
        struct {
            body: String,
            format: ?String,
            formatted_body: ?String,
            msgtype: String,
        },
        union(enum) {
            @"200": struct {},
        },
    );
    switch (try endpoint.execute(self, allocator, path, .{
        .body = body,
        .format = if (formatted_body == null) null else "org.matrix.custom.html",
        .formatted_body = formatted_body,
        .msgtype = if (notice) "m.notice" else "m.text",
    })) {
        .@"200" => {},
    }
}
