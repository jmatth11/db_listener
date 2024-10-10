const std = @import("std");
const httpz = @import("httpz");
const args = @import("args.zig");

var conf: args.config = undefined;
const index_html = "index.html";

pub fn init(config: args.config) void {
    conf = config;
}

pub fn get_home(req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("in home: from {d}", .{req.address.in.sa.addr});
    try write_out_file(res, conf.server.web_dir, index_html);
}

pub fn get_assets(req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("in assets: {s}", .{req.url.path});
    try write_out_file(res, conf.server.web_dir, req.url.path);
}

fn write_out_file(res: *httpz.Response, d: []const u8, f: []const u8) !void {
    set_content_type(res, std.fs.path.extension(f));
    const cur_dir = std.fs.cwd();
    const path = try std.fs.path.join(res.arena, &[2][]u8{ @constCast(d), @constCast(f) });
    res.body = try cur_dir.readFileAlloc(res.arena, path, std.math.maxInt(usize));
}

fn set_content_type(res: *httpz.Response, ext: []const u8) void {
    if (std.mem.eql(u8, ext, ".js")) {
        res.content_type = .JS;
    }
    if (std.mem.eql(u8, ext, ".css")) {
        res.content_type = .CSS;
    }
    if (std.mem.eql(u8, ext, ".html")) {
        res.content_type = .HTML;
    }
}
