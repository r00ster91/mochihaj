const std = @import("std");
const log = std.log;
const json = std.json;
const mem = std.mem;

const api = @import("../api.zig");
const http = @import("../../http.zig");
const Client = @import("../../matrix.zig").Client;

pub fn Endpoint(method: std.http.Method, comptime OptionalRequestValue: ?type, comptime Responses: type) type {
    const parseResponse = struct {
        fn parseResponse(allocator: std.mem.Allocator, response: http.Response) (error{Other} || anyerror)!Responses {
            inline for (@typeInfo(Responses).Union.fields) |*field| {
                const response_status = comptime try std.meta.intToEnum(
                    std.http.Status,
                    try std.fmt.parseUnsigned(std.meta.Tag(std.http.Status), field.name, 10),
                );
                if (response.status == response_status) {
                    const value = if (field.field_type == json.ValueTree) value: {
                        // This is used for objects that contain keys
                        // we don't know at compile time
                        // TODO: https://github.com/ziglang/zig/issues/11712
                        var parser = std.json.Parser.init(allocator, false);
                        defer parser.deinit();
                        break :value try parser.parse(response.body);
                    } else value: {
                        var response_tokens = json.TokenStream.init(response.body);
                        break :value try json.parse(field.field_type, &response_tokens, .{
                            .allocator = allocator,
                            .ignore_unknown_fields = true,
                        });
                    };
                    return @unionInit(Responses, field.name, value);
                }
            } else {
                var response_tokens = json.TokenStream.init(response.body);
                const @"error" = try json.parse(api.Error, &response_tokens, .{
                    .allocator = allocator,
                    .ignore_unknown_fields = true,
                });
                log.err("{s}: {s}", .{ @"error".errcode, @"error".@"error" });
                return error.Other;
            }
        }
    }.parseResponse;

    if (OptionalRequestValue) |RequestValue| {
        return struct {
            pub fn execute(
                client: *Client,
                allocator: mem.Allocator,
                path: []const u8,
                request_value: RequestValue,
            ) (error{Other} || anyerror)!Responses {
                const request_body = try json.stringifyAlloc(
                    allocator,
                    request_value,
                    .{ .emit_null_optional_fields = false },
                );
                // TODO: this possibly causes a segfault!
                // defer allocator.free(request_body);
                const response = try client.http_client.request(
                    allocator,
                    method,
                    path,
                    request_body,
                );
                return parseResponse(allocator, response);
            }
        };
    } else {
        return struct {
            pub fn execute(
                client: *Client,
                allocator: mem.Allocator,
                path: []const u8,
            ) (error{Other} || anyerror)!Responses {
                const response = try client.http_client.request(
                    allocator,
                    method,
                    path,
                    null,
                );
                return parseResponse(allocator, response);
            }
        };
    }
}
