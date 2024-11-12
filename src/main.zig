const std = @import("std");
const args = @import("args.zig");
const httpz = @import("httpz");
const channel = @import("channel.zig");
const routes = @import("routes.zig");

var server: httpz.ServerCtx(void, void) = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // parse cli arguments
    const config_values = args.parse_args(gpa.allocator()) catch |err| {
        if (err == args.arg_error.help) return;
        return err;
    };
    // Setup handler's context before setting websocket route
    channel.init(std.heap.page_allocator, config_values) catch |err| {
        std.debug.print("error initializing channel handler: {}\n", .{err});
        return err;
    };
    defer channel.deinit() catch |err| {
        std.debug.print("handler deinit failed: {}\n", .{err});
    };
    // setup server
    server = try httpz.Server().init(gpa.allocator(), .{
        .address = config_values.server.host,
        .port = config_values.server.port,
    });
    defer server.deinit();

    // register our intent to handle SIGINT
    try std.posix.sigaction(std.posix.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);
    try std.posix.sigaction(std.posix.SIG.TERM, &.{
        .handler = .{ .handler = shutdown },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    // setup routes
    routes.init(config_values);
    var router = server.router();
    // a normal route
    router.get("/ws", channel.ws);
    router.get("/", routes.get_home);
    router.get("/static/*", routes.get_assets);

    // this will block until server.stop() is called
    // which will then run the server.deinit() we setup above with `defer`
    std.log.info("starting server on address: {s}:{d}\n", .{
        config_values.server.host,
        config_values.server.port,
    });

    try server.listen();
}

fn shutdown(_: c_int) callconv(.C) void {
    channel.running = false;
    server.stop();
}
