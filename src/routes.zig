const std = @import("std");
const httpz = @import("httpz");
const args = @import("args.zig");

var conf: args.config = undefined;
var alloc: std.mem.Allocator = undefined;
const index_html = "index.html";
const index_js = "static/index.js";

pub fn init(allocator: std.mem.Allocator, config: args.config) void {
    alloc = allocator;
    conf = config;
}

pub fn get_home(req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    try write_out_file(res, conf.server.web_dir, index_html);
}

pub fn get_assets(req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    try write_out_file(res, conf.server.web_dir, index_js);
}

fn write_out_file(res: *httpz.Response, d: []const u8, f: []const u8) !void {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(d, &path_buffer);
    var dir = try std.fs.openDirAbsolute(path, .{});
    defer dir.close();
    const bytes = try dir.readFileAlloc(alloc, f, std.math.maxInt(usize));
    defer alloc.free(bytes);
    try res.chunk(bytes);
    try res.write();
}
