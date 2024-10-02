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
    std.log.info("in home: from {d}\n", .{req.address.in.sa.addr});
    res.header("Content-Type", "text/html");
    try write_out_file(res, conf.server.web_dir, index_html);
}

pub fn get_assets(req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("in assets: {s}\n", .{req.url.path});
    res.header("Content-Type", "text/javascript");
    try write_out_file(res, conf.server.web_dir, req.url.path);
}

fn write_out_file(res: *httpz.Response, d: []const u8, f: []const u8) !void {
    const cur_dir = std.fs.cwd();
    const path = try std.fs.path.join(alloc, &[2][]u8{ @constCast(d), @constCast(f) });
    defer alloc.free(path);
    const bytes = try cur_dir.readFileAlloc(alloc, path, std.math.maxInt(usize));
    defer alloc.free(bytes);
    res.body = bytes;
    try res.write();
}
