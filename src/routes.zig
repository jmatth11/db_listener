const std = @import("std");
const httpz = @import("httpz");
const args = @import("args.zig");

var conf: args.config = undefined;
var str_buffer: [4096 * 4]u8 = undefined;
var alloc: std.heap.FixedBufferAllocator = undefined;
const index_html = "index.html";

pub fn init(config: args.config) void {
    alloc = std.heap.FixedBufferAllocator.init(@constCast(&str_buffer));
    conf = config;
}

pub fn get_home(req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("in home: from {d}", .{req.address.in.sa.addr});
    res.header("Content-Type", "text/html");
    try write_out_file(res, conf.server.web_dir, index_html);
}

pub fn get_assets(req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("in assets: {s}", .{req.url.path});
    res.header("Content-Type", "text/javascript");
    try write_out_file(res, conf.server.web_dir, req.url.path);
}

fn write_out_file(res: *httpz.Response, d: []const u8, f: []const u8) !void {
    defer alloc.reset();
    const cur_dir = std.fs.cwd();
    const path = try std.fs.path.join(alloc.allocator(), &[2][]u8{ @constCast(d), @constCast(f) });
    const bytes = cur_dir.readFileAlloc(alloc.allocator(), path, std.math.maxInt(usize)) catch {
        // this block is if we run out of memory with the fixed buffer
        // so we use heap allocation instead
        const bytes = try cur_dir.readFileAlloc(std.heap.page_allocator, path, std.math.maxInt(usize));
        defer std.heap.page_allocator.free(bytes);
        res.body = bytes;
        try res.write();
        return;
    };
    res.body = bytes;
    try res.write();
}
