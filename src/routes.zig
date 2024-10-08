const std = @import("std");
const httpz = @import("httpz");
const args = @import("args.zig");

var conf: args.config = undefined;
var alloc: std.mem.Allocator = undefined;

pub fn init(allocator: std.mem.Allocator, config: args.config) void {
    alloc = allocator;
    conf = config;
}

pub fn get_home(req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    _ = res;
}

pub fn get_assets(req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    _ = res;
}
