//! Comptime-driven API client framework.
//!
//! Pattern:
//!   1. Define endpoints as an anonymous struct of `Endpoint{...}` values.
//!   2. `EndpointEnum` derives a type-safe enum from field names.
//!   3. `Client(endpoints)` returns a concrete HTTP client with a `call()` method
//!      that accepts the derived enum — autocomplete on values, compile-error on typos.
//!
//! The client handles Bearer-token auth, JSON serialization/deserialization,
//! and basic HTTP error checking. Multipart uploads and SSE streaming are
//! out of scope — add them as external helper functions.

const std = @import("std");

pub const Method = std.http.Method;

/// Descriptor for one API endpoint. `Request`/`Response` are **type** fields.
pub const Endpoint = struct {
    method: Method,
    path: []const u8,
    Request: type,
    Response: type,
};

/// Derive an enum from the field names of a comptime-known struct literal.
pub fn EndpointEnum(comptime ep: anytype) type {
    const fields = @typeInfo(@TypeOf(ep)).@"struct".fields;
    var names: [fields.len][]const u8 = undefined;
    var values: [fields.len]u32 = undefined;
    for (fields, 0..) |f, i| {
        names[i] = f.name;
        values[i] = @intCast(i);
    }
    return @Enum(u32, .exhaustive, &names, &values);
}

pub const ApiError = error{
    NetworkError,
    HttpError,
    ParseError,
    ApiError,
    InvalidInput,
    UnexpectedResponse,
};

pub const DEFAULT_BASE_URL = "https://api.openai.com";

/// Generated HTTP client. `endpoints` is an anonymous struct of `Endpoint{…}` values.
/// The derived enum `Ep` is available as `Client.Ep`.
pub fn Client(comptime endpoints: anytype) type {
    return struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        api_key: []const u8,
        base_url: []const u8,

        const Self = @This();
        pub const Ep = EndpointEnum(endpoints);

        pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, base_url: ?[]const u8) Self {
            return .{
                .allocator = allocator,
                .io = io,
                .api_key = api_key,
                .base_url = base_url orelse DEFAULT_BASE_URL,
            };
        }

        pub fn deinit(_: *Self) void {}

        // ===============================================================
        // call — comptime dispatch on endpoint enum
        // ===============================================================

        /// Call an endpoint. GET/DELETE endpoints pass `{}` for request.
        pub fn call(
            self: *Self,
            allocator: std.mem.Allocator,
            comptime ep: Ep,
            request: anytype,
        ) ApiError!std.json.Parsed(@field(endpoints, @tagName(ep)).Response) {
            const def = comptime @field(endpoints, @tagName(ep));
            if (def.Request != void and def.Request != @TypeOf(request)) {
                @compileError("request type mismatch for " ++ @tagName(ep) ++ ": expected " ++ @typeName(def.Request) ++ ", got " ++ @typeName(@TypeOf(request)));
            }
            const body = try self.doRequest(allocator, def.method, def.path, request);
            defer allocator.free(body);
            return std.json.parseFromSlice(def.Response, allocator, body, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch ApiError.ParseError;
        }

        // ===============================================================
        // internal HTTP helpers
        // ===============================================================

        fn doRequest(self: *const Self, allocator: std.mem.Allocator, method: Method, path: []const u8, request: anytype) ApiError![]u8 {
            return switch (method) {
                .GET => self.doGet(allocator, path),
                .POST => if (@TypeOf(request) == void) self.doPostVoid(allocator, path) else self.doPost(allocator, path, request),
                .DELETE => self.doDelete(allocator, path),
                else => ApiError.InvalidInput,
            };
        }

        fn doPost(self: *const Self, allocator: std.mem.Allocator, path: []const u8, payload: anytype) ApiError![]u8 {
            var url_buf: [2048]u8 = undefined;
            const url_str = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ self.base_url, path }) catch return ApiError.InvalidInput;
            const uri = std.Uri.parse(url_str) catch return ApiError.InvalidInput;

            var auth_buf: [512]u8 = undefined;
            const auth = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{self.api_key}) catch return ApiError.InvalidInput;

            var http: std.http.Client = .{ .allocator = allocator, .io = self.io };
            defer http.deinit();

            var req = http.request(.POST, uri, .{
                .headers = .{ .authorization = .{ .override = auth }, .content_type = .{ .override = "application/json" } },
            }) catch return ApiError.NetworkError;
            defer req.deinit();

            req.transfer_encoding = .chunked;
            var io_buf: [4096]u8 = undefined;
            var bw = req.sendBodyUnflushed(&io_buf) catch return ApiError.NetworkError;
            std.json.Stringify.value(payload, .{ .emit_null_optional_fields = false }, &bw.writer) catch return ApiError.NetworkError;
            bw.end() catch return ApiError.NetworkError;
            req.connection.?.flush() catch return ApiError.NetworkError;

            return receive(allocator, &req);
        }

        fn doPostVoid(self: *const Self, allocator: std.mem.Allocator, path: []const u8) ApiError![]u8 {
            return self.doPost(allocator, path, &.{});
        }

        pub fn doGet(self: *const Self, allocator: std.mem.Allocator, path: []const u8) ApiError![]u8 {
            var url_buf: [2048]u8 = undefined;
            const url_str = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ self.base_url, path }) catch return ApiError.InvalidInput;
            const uri = std.Uri.parse(url_str) catch return ApiError.InvalidInput;

            var auth_buf: [512]u8 = undefined;
            const auth = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{self.api_key}) catch return ApiError.InvalidInput;

            var http: std.http.Client = .{ .allocator = allocator, .io = self.io };
            defer http.deinit();

            var req = http.request(.GET, uri, .{
                .headers = .{ .authorization = .{ .override = auth } },
            }) catch return ApiError.NetworkError;
            defer req.deinit();

            req.sendBodiless() catch return ApiError.NetworkError;
            return receive(allocator, &req);
        }

        fn doDelete(self: *const Self, allocator: std.mem.Allocator, path: []const u8) ApiError![]u8 {
            var url_buf: [2048]u8 = undefined;
            const url_str = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ self.base_url, path }) catch return ApiError.InvalidInput;
            const uri = std.Uri.parse(url_str) catch return ApiError.InvalidInput;

            var auth_buf: [512]u8 = undefined;
            const auth = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{self.api_key}) catch return ApiError.InvalidInput;

            var http: std.http.Client = .{ .allocator = allocator, .io = self.io };
            defer http.deinit();

            var req = http.request(.DELETE, uri, .{
                .headers = .{ .authorization = .{ .override = auth } },
            }) catch return ApiError.NetworkError;
            defer req.deinit();

            req.sendBodiless() catch return ApiError.NetworkError;
            return receive(allocator, &req);
        }
    };
}

// -----------------------------------------------------------------------
// Module-level helpers
// -----------------------------------------------------------------------

fn checkHttpStatus(response: *std.http.Client.Response) ApiError!void {
    if (response.head.status == .ok) return;
    var err_buf: [4096]u8 = undefined;
    var tbuf: [1024]u8 = undefined;
    const err_len = response.reader(&tbuf).readSliceShort(&err_buf) catch 0;
    std.log.warn("API HTTP {s}: {s}", .{ @tagName(response.head.status), err_buf[0..err_len] });
    return switch (response.head.status) {
        .unauthorized, .forbidden => ApiError.ApiError,
        .too_many_requests => ApiError.ApiError,
        .bad_request => ApiError.InvalidInput,
        else => ApiError.HttpError,
    };
}

fn receive(allocator: std.mem.Allocator, req: *std.http.Client.Request) ApiError![]u8 {
    var redirect_buf: [4096]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch return ApiError.NetworkError;
    try checkHttpStatus(&response);
    var transfer_buf: [4096]u8 = undefined;
    return response.reader(&transfer_buf).allocRemaining(allocator, @enumFromInt(64 * 1024)) catch return ApiError.NetworkError;
}
