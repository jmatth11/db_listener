const std = @import("std");
const httpz = @import("httpz");
const args = @import("args.zig");

var conf: args.config = undefined;
const index_html = "index.html";

/// Initialize routes with config options.
pub fn init(config: args.config) void {
    conf = config;
}

/// Get home page
pub fn get_home(req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("in home: from {d}", .{req.address.in.sa.addr});
    try write_out_file(res, conf.server.web_dir, index_html);
}

/// Get static assets
pub fn get_assets(req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("in assets: {s}", .{req.url.path});
    try write_out_file(res, conf.server.web_dir, req.url.path);
}

fn write_out_file(res: *httpz.Response, d: []const u8, f: []const u8) !void {
    res.content_type = httpz.ContentType.forExtension(std.fs.path.extension(f));
    const cur_dir = std.fs.cwd();
    const path = try std.fs.path.join(res.arena, &[2][]const u8{ d, f });
    res.body = try cur_dir.readFileAlloc(res.arena, path, std.math.maxInt(usize));
}
