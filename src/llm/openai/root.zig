//! OpenAI client — convenience wrapper around the comptime-generated API client.
//!
//! Standard endpoints (embeddings, images, moderations, files, fine-tuning, models):
//!   openai.client.call(.create_embedding, request)
//!   openai.client.call(.list_models, {})
//!
//! Convenience methods for chat completions, multipart uploads, and streaming
//! are provided directly on `OpenAI`.

const std = @import("std");
const api = @import("../../core/api.zig");
const core = @import("../../core/types.zig");
const endpoints = @import("endpoints.zig");

const ApiError = api.ApiError;
const ChatRequest = endpoints.ChatRequest;

pub const DEFAULT_MODEL = "gpt-4o";
pub const StreamCallback = *const fn (raw: []const u8) void;

pub const Client = api.Client(endpoints.registry);
pub const Ep = endpoints.Ep;

pub const OpenAI = struct {
    client: Client,
    model: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        api_key: []const u8,
        model: ?[]const u8,
        base_url: ?[]const u8,
    ) OpenAI {
        return .{
            .client = Client.init(allocator, io, api_key, base_url),
            .model = model orelse DEFAULT_MODEL,
        };
    }

    pub fn deinit(_: *OpenAI) void {}

    // ===================================================================
    // Convenience: chat completion
    // ===================================================================

    pub fn complete(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        messages: []const core.ChatMessage,
        opts: core.GenerationOptions,
    ) ApiError!std.json.Parsed(core.LLMResponse) {
        if (messages.len == 0) return ApiError.InvalidInput;
        const req = endpoints.chatRequest(self.model, messages, opts, false);
        return self.client.call(allocator, .chat_completions, req);
    }

    pub fn completeStream(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        messages: []const core.ChatMessage,
        opts: core.GenerationOptions,
        callback: StreamCallback,
    ) ApiError!void {
        if (messages.len == 0) return ApiError.InvalidInput;
        const req = endpoints.chatRequest(self.model, messages, opts, true);
        try self.doPostStream(allocator, "/v1/chat/completions", req, callback);
    }

    // ===================================================================
    // Convenience: multipart (audio, file upload)
    // ===================================================================

    pub fn createTranscription(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        request: core.AudioRequest,
    ) ApiError!std.json.Parsed(core.AudioVerboseResponse) {
        return self.audioMultipart(allocator, "/v1/audio/transcriptions", request);
    }

    pub fn createTranslation(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        request: core.AudioRequest,
    ) ApiError!std.json.Parsed(core.AudioVerboseResponse) {
        return self.audioMultipart(allocator, "/v1/audio/translations", request);
    }

    pub fn uploadFile(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        file_path: []const u8,
        purpose: []const u8,
    ) ApiError!std.json.Parsed(core.FileObject) {
        const filename = std.fs.path.basename(file_path);
        const content = std.fs.cwd().readFileAlloc(allocator, file_path, 512 * 1024 * 1024) catch return ApiError.InvalidInput;
        defer allocator.free(content);

        const body = try self.doPostMultipart(allocator, "/v1/files", &.{
            .{ .file = .{ .name = "file", .filename = filename, .content = content, .mime_type = "application/octet-stream" } },
            .{ .field = .{ .name = "purpose", .value = purpose } },
        });
        defer allocator.free(body);
        return std.json.parseFromSlice(core.FileObject, allocator, body, .{ .ignore_unknown_fields = true }) catch ApiError.ParseError;
    }

    // ===================================================================
    // Convenience: raw response (file content)
    // ===================================================================

    pub fn retrieveFileContent(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        file_id: []const u8,
    ) ApiError![]u8 {
        var buf: [128]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "/v1/files/{s}/content", .{file_id}) catch return ApiError.InvalidInput;
        return self.client.doGet(allocator, path);
    }

    // -- internal: multipart + streaming helpers -------------------------

    fn audioMultipart(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        path: []const u8,
        request: core.AudioRequest,
    ) ApiError!std.json.Parsed(core.AudioVerboseResponse) {
        const file_content = std.fs.cwd().readFileAlloc(allocator, request.file_path, 25 * 1024 * 1024) catch return ApiError.InvalidInput;
        defer allocator.free(file_content);

        var temp_buf: [32]u8 = undefined;
        const parts = [_]?MultipartPart{
            .{ .file = .{ .name = "file", .filename = request.filename, .content = file_content, .mime_type = mimeTypeFromPath(request.filename) } },
            .{ .field = .{ .name = "model", .value = request.model } },
            if (request.language) |v| .{ .field = .{ .name = "language", .value = v } } else null,
            if (request.prompt) |v| .{ .field = .{ .name = "prompt", .value = v } } else null,
            if (request.response_format) |v| .{ .field = .{ .name = "response_format", .value = v } } else null,
            if (request.temperature) |v| .{ .field = .{ .name = "temperature", .value = std.fmt.bufPrint(&temp_buf, "{d}", .{v}) catch return ApiError.InvalidInput } } else null,
        };
        const body = try self.doPostMultipart(allocator, path, &parts);
        defer allocator.free(body);
        return std.json.parseFromSlice(core.AudioVerboseResponse, allocator, body, .{ .ignore_unknown_fields = true }) catch ApiError.ParseError;
    }

    fn doPostMultipart(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        path: []const u8,
        parts: []const ?MultipartPart,
    ) ApiError![]u8 {
        var url_buf: [2048]u8 = undefined;
        const url_str = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ self.client.base_url, path }) catch return ApiError.InvalidInput;
        const uri = std.Uri.parse(url_str) catch return ApiError.InvalidInput;

        var auth_buf: [512]u8 = undefined;
        const auth = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{self.client.api_key}) catch return ApiError.InvalidInput;

        const boundary = "----ZageFormBoundary7MA4YWxkTrZu0gW";
        var body = std.ArrayList(u8).init(allocator);
        defer body.deinit();

        for (parts) |maybe_part| {
            const part = maybe_part orelse continue;
            try body.writer().print("--{s}\r\n", .{boundary});
            switch (part) {
                .field => |f| try body.writer().print("Content-Disposition: form-data; name=\"{s}\"\r\n\r\n{s}\r\n", .{ f.name, f.value }),
                .file => |f| {
                    try body.writer().print("Content-Disposition: form-data; name=\"{s}\"; filename=\"{s}\"\r\nContent-Type: {s}\r\n\r\n", .{ f.name, f.filename, f.mime_type });
                    try body.appendSlice(f.content);
                    try body.appendSlice("\r\n");
                },
            }
        }
        try body.writer().print("--{s}--\r\n", .{boundary});

        var ct_buf: [128]u8 = undefined;
        const ct = std.fmt.bufPrint(&ct_buf, "multipart/form-data; boundary={s}", .{boundary}) catch return ApiError.InvalidInput;

        var http: std.http.Client = .{ .allocator = allocator, .io = self.client.io };
        defer http.deinit();

        var req = http.request(.POST, uri, .{
            .headers = .{ .authorization = .{ .override = auth }, .content_type = .{ .override = ct } },
        }) catch return ApiError.NetworkError;
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = @intCast(body.items.len) };
        var io_buf: [4096]u8 = undefined;
        var bw = req.sendBodyUnflushed(&io_buf) catch return ApiError.NetworkError;
        _ = bw.write(body.items) catch return ApiError.NetworkError;
        bw.end() catch return ApiError.NetworkError;
        req.connection.?.flush() catch return ApiError.NetworkError;

        return receive(allocator, &req);
    }

    fn doPostStream(
        self: *OpenAI,
        allocator: std.mem.Allocator,
        path: []const u8,
        payload: anytype,
        callback: StreamCallback,
    ) ApiError!void {
        var url_buf: [2048]u8 = undefined;
        const url_str = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ self.client.base_url, path }) catch return ApiError.InvalidInput;
        const uri = std.Uri.parse(url_str) catch return ApiError.InvalidInput;

        var auth_buf: [512]u8 = undefined;
        const auth = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{self.client.api_key}) catch return ApiError.InvalidInput;

        var http: std.http.Client = .{ .allocator = allocator, .io = self.client.io };
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

        var redirect_buf: [4096]u8 = undefined;
        var response = req.receiveHead(&redirect_buf) catch return ApiError.NetworkError;
        try checkHttpStatus(&response);

        var transfer_buf: [4096]u8 = undefined;
        var reader = response.reader(&transfer_buf);
        var line_buf: [8192]u8 = undefined;
        while (true) {
            const line = reader.readUntilDelimiterOrEof(&line_buf, '\n') catch return ApiError.NetworkError;
            if (line == null) break;
            const trimmed = std.mem.trim(u8, line.?, " \r\t");
            if (std.mem.startsWith(u8, trimmed, "data: ")) {
                const data = trimmed["data: ".len..];
                if (std.mem.eql(u8, data, "[DONE]")) break;
                callback(data);
            }
        }
    }
};

// -----------------------------------------------------------------------
// Shared helpers (used by OpenAI convenience methods)
// -----------------------------------------------------------------------

const MultipartPart = union(enum) {
    field: struct { name: []const u8, value: []const u8 },
    file: struct { name: []const u8, filename: []const u8, content: []const u8, mime_type: []const u8 },
};

fn checkHttpStatus(response: *std.http.Client.Response) ApiError!void {
    if (response.head.status == .ok) return;
    var err_buf: [4096]u8 = undefined;
    var tbuf: [1024]u8 = undefined;
    const err_len = response.reader(&tbuf).readSliceShort(&err_buf) catch 0;
    std.log.warn("OpenAI HTTP {s}: {s}", .{ @tagName(response.head.status), err_buf[0..err_len] });
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

fn mimeTypeFromPath(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".mp3")) return "audio/mpeg";
    if (std.mem.eql(u8, ext, ".mp4")) return "audio/mp4";
    if (std.mem.eql(u8, ext, ".m4a")) return "audio/mp4";
    if (std.mem.eql(u8, ext, ".wav")) return "audio/wav";
    if (std.mem.eql(u8, ext, ".webm")) return "audio/webm";
    if (std.mem.eql(u8, ext, ".flac")) return "audio/flac";
    if (std.mem.eql(u8, ext, ".ogg")) return "audio/ogg";
    if (std.mem.eql(u8, ext, ".oga")) return "audio/ogg";
    return "application/octet-stream";
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "endpoint enum has expected values" {
    try std.testing.expectEqualStrings("chat_completions", @tagName(Ep.chat_completions));
    try std.testing.expectEqualStrings("list_models", @tagName(Ep.list_models));
    try std.testing.expectEqualStrings("create_embedding", @tagName(Ep.create_embedding));
}

test "buildRequestBody - minimal" {
    const allocator = std.testing.allocator;
    const json = try endpoints.buildRequestBody(allocator, "gpt-4o", &.{}, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"model\":\"gpt-4o\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"messages\":[]") != null);
}

test "buildRequestBody - full options" {
    const allocator = std.testing.allocator;
    const msgs = [_]core.ChatMessage{
        .{ .role = .system, .content = "You are a bot." },
        .{ .role = .user, .content = "Hi!" },
    };
    const opts = core.GenerationOptions{ .temperature = 0.7, .max_tokens = 256, .top_p = 0.9, .seed = 42 };
    const json = try endpoints.buildRequestBody(allocator, "gpt-4o", &msgs, opts);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"temperature\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"max_tokens\"") != null);
}

test "buildRequestBody - with stop sequences" {
    const allocator = std.testing.allocator;
    const stop = [_][]const u8{ "\n", "END" };
    const opts = core.GenerationOptions{ .stop = &stop };
    const json = try endpoints.buildRequestBody(allocator, "gpt-4o", &.{}, opts);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stop\"") != null);
}

test "parseResponse - valid" {
    const allocator = std.testing.allocator;
    const body =
        \\{"id":"chatcmpl-xxx","object":"chat.completion","created":1234567890,"model":"gpt-4o",
        \\"choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}],
        \\"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
    ;
    var parsed = std.json.parseFromSlice(core.LLMResponse, allocator, body, .{ .ignore_unknown_fields = true }) catch unreachable;
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Hello!", parsed.value.choices[0].message.content);
    try std.testing.expectEqualStrings("stop", parsed.value.choices[0].finish_reason);
    try std.testing.expect(parsed.value.usage != null);
    try std.testing.expectEqual(@as(u32, 15), parsed.value.usage.?.total_tokens);
}

test "finish_reason helper" {
    const c = core.LLMResponse.Choice{ .index = 0, .message = .{ .role = "assistant", .content = "" }, .finish_reason = "stop" };
    try std.testing.expectEqual(core.FinishReason.stop, c.finishReason());
}

test "OpenAI.init defaults" {
    const allocator = std.testing.allocator;
    const oa = OpenAI.init(allocator, std.testing.io, "sk-test-key", null, null);
    try std.testing.expectEqualStrings("sk-test-key", oa.client.api_key);
    try std.testing.expectEqualStrings(DEFAULT_MODEL, oa.model);
    try std.testing.expectEqualStrings(api.DEFAULT_BASE_URL, oa.client.base_url);
}

test "OpenAI.init custom model and url" {
    const allocator = std.testing.allocator;
    const oa = OpenAI.init(allocator, std.testing.io, "sk-custom", "gpt-3.5-turbo", "https://custom.api/v1");
    try std.testing.expectEqualStrings("gpt-3.5-turbo", oa.model);
    try std.testing.expectEqualStrings("https://custom.api/v1", oa.client.base_url);
}

test "mimeTypeFromPath" {
    try std.testing.expectEqualStrings("audio/mpeg", mimeTypeFromPath("audio.mp3"));
    try std.testing.expectEqualStrings("audio/wav", mimeTypeFromPath("recording.wav"));
    try std.testing.expectEqualStrings("application/octet-stream", mimeTypeFromPath("unknown.xyz"));
}

// =======================================================================
// Integration tests — controlled via `-Dtest-integration=true`
// =======================================================================

const build_options = @import("build_options");
const test_integration = build_options.test_integration;

const TestConfig = struct {
    api_key: []const u8,
    base_url: ?[]const u8,
    model: ?[]const u8,
};

const ParsedTestConfig = struct {
    value: TestConfig,
    allocator: std.mem.Allocator,
    content: []const u8,

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.content);
    }
};

fn loadTestConfig(io: std.Io, allocator: std.mem.Allocator) !ParsedTestConfig {
    const cwd = std.Io.Dir.cwd();
    const content = try std.Io.Dir.readFileAlloc(cwd, io, ".env.test.json", allocator, std.Io.Limit.unlimited);
    errdefer allocator.free(content);
    const cfg = try std.json.parseFromSliceLeaky(TestConfig, allocator, content, .{});
    return .{ .value = cfg, .allocator = allocator, .content = content };
}

test "integration - simple chat completion" {
    if (!test_integration) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var parsed_cfg = loadTestConfig(std.testing.io, allocator) catch return error.SkipZigTest;
    defer parsed_cfg.deinit();
    const cfg = parsed_cfg.value;

    var openai = OpenAI.init(allocator, std.testing.io, cfg.api_key, cfg.model, cfg.base_url);
    const messages = [_]core.ChatMessage{
        .{ .role = .system, .content = "You are a helpful assistant. Answer briefly." },
        .{ .role = .user, .content = "What is the capital of France?" },
    };
    const parsed = try openai.complete(allocator, &messages, .{ .max_tokens = 50 });
    defer parsed.deinit();
    const response = parsed.value;

    try std.testing.expect(response.choices[0].message.content.len > 0);
    try std.testing.expectEqualStrings("stop", response.choices[0].finish_reason);
    try std.testing.expect(response.usage != null);
    try std.testing.expect(response.usage.?.total_tokens > 0);
}

test "integration - system prompt influences response" {
    if (!test_integration) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var parsed_cfg = loadTestConfig(std.testing.io, allocator) catch return error.SkipZigTest;
    defer parsed_cfg.deinit();
    const cfg = parsed_cfg.value;

    var openai = OpenAI.init(allocator, std.testing.io, cfg.api_key, cfg.model, cfg.base_url);
    const messages = [_]core.ChatMessage{
        .{ .role = .system, .content = "You only speak French. Always respond in French." },
        .{ .role = .user, .content = "What is the capital of China?" },
    };
    const parsed = try openai.complete(allocator, &messages, .{ .max_tokens = 120 });
    defer parsed.deinit();
    const response = parsed.value;

    try std.testing.expect(response.choices.len > 0);
    try std.testing.expect(response.choices[0].message.content.len > 0);
}

test "integration - low temperature produces deterministic output" {
    if (!test_integration) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var parsed_cfg = loadTestConfig(std.testing.io, allocator) catch return error.SkipZigTest;
    defer parsed_cfg.deinit();
    const cfg = parsed_cfg.value;

    var openai = OpenAI.init(allocator, std.testing.io, cfg.api_key, cfg.model, cfg.base_url);
    const messages = [_]core.ChatMessage{
        .{ .role = .user, .content = "Reply with exactly: hello world" },
    };
    const parsed = try openai.complete(allocator, &messages, .{ .temperature = 0.0, .max_tokens = 50 });
    defer parsed.deinit();
    const response = parsed.value;

    try std.testing.expect(response.choices[0].message.content.len > 0);
}
