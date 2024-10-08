const std = @import("std");
const args = @import("args.zig");
const httpz = @import("httpz");
const channel = @import("channel.zig");
const routes = @import("routes.zig");

var server: httpz.ServerCtx(void, void) = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const config_values = args.parse_args(gpa.allocator()) catch |err| {
        if (err == args.arg_error.help) return;
        return err;
    };
    // Setup handler's context before setting websocket route
    var handler = channel.handler.init(gpa.allocator(), config_values) catch |err| {
        std.debug.print("error initializing channel handler: {}\n", .{err});
        return err;
    };
    defer handler.deinit() catch |err| {
        std.debug.print("handler deinit failed: {}\n", .{err});
    };
    server = try httpz.Server().init(gpa.allocator(), .{ .port = config_values.server.port });
    defer server.deinit();

    // now that our server is up, we register our intent to handle SIGINT
    try std.posix.sigaction(std.posix.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    routes.init(gpa.allocator(), config_values);
    var router = server.router();
    // a normal route
    router.get("/ws", channel.ws);
    router.get("/", routes.get_home);
    router.get("/static", routes.get_assets);

    // this will block until server.stop() is called
    // which will then run the server.deinit() we setup above with `defer`
    try server.listen();
}

fn shutdown(_: c_int) callconv(.C) void {
    server.stop();
}
