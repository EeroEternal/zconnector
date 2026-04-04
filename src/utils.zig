const std = @import("std");

pub const DataUrl = struct {
    mime: []const u8,
    data: []const u8,
};

pub fn joinUrl(allocator: std.mem.Allocator, base_url: []const u8, path: []const u8) ![]u8 {
    const normalized_base = std.mem.trimRight(u8, base_url, "/");
    const normalized_path = std.mem.trimLeft(u8, path, "/");

    // If the path starts with v1 and base_url already contains a version like /v4,
    // we should prioritize the base_url's versioning if it looks like an API root.
    // However, the simplest fix is to check if the base_url ends with a version-like path.
    const v_index = std.mem.lastIndexOf(u8, normalized_base, "/v") orelse return std.fmt.allocPrint(allocator, "{s}/{s}", .{ normalized_base, normalized_path });
    
    // If we find /vN at the end or followed by a number
    if (v_index + 2 < normalized_base.len and std.ascii.isDigit(normalized_base[v_index + 2])) {
        // Base has /v4. If path has /v1/chat/completions, we stripped /v1 to get /chat/completions.
        // Wait, normalized_path still has /v1. Let's check.
        if (std.mem.startsWith(u8, normalized_path, "v1/")) {
             return std.fmt.allocPrint(allocator, "{s}/{s}", .{ normalized_base, normalized_path[3..] });
        }
    }

    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ normalized_base, normalized_path });
}

pub fn deinitOwnedStringMap(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8)) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    map.deinit();
}

pub fn parseDataUrl(value: []const u8) ?DataUrl {
    if (!std.mem.startsWith(u8, value, "data:")) return null;

    const comma_index = std.mem.indexOfScalar(u8, value, ',') orelse return null;
    const metadata = value[5..comma_index];

    var mime = metadata;
    if (std.mem.indexOfScalar(u8, metadata, ';')) |semicolon_index| {
        mime = metadata[0..semicolon_index];
    }

    if (mime.len == 0) {
        mime = "application/octet-stream";
    }

    return .{
        .mime = mime,
        .data = value[comma_index + 1 ..],
    };
}

pub fn buildDataUrl(allocator: std.mem.Allocator, mime: []const u8, data_base64: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "data:{s};base64,{s}", .{ mime, data_base64 });
}

pub fn encodeBase64Alloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const length = encoder.calcSize(bytes.len);
    const output = try allocator.alloc(u8, length);
    _ = encoder.encode(output, bytes);
    return output;
}

pub fn seemsLikeUrl(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "http://") or std.mem.startsWith(u8, value, "https://");
}
