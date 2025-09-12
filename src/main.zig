const std = @import("std");
const args = @import("args.zig");
const httpz = @import("httpz");
const channel = @import("channel.zig");
const routes = @import("routes.zig");

var server: httpz.Server(channel.Handler) = undefined;
const empty_sig: [16]c_ulong = @splat(0);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // parse cli arguments
    const config_values = args.parse_args(gpa.allocator()) catch |err| {
        if (err == args.arg_error.help) return;
        return err;
    };
    // Setup handler's context before setting websocket route
    channel.init(gpa.allocator(), config_values) catch |err| {
        std.debug.print("error initializing channel handler: {}\n", .{err});
        return err;
    };
    defer channel.deinit();
    // setup server
    server = try httpz.Server(channel.Handler).init(gpa.allocator(), .{
        .address = config_values.server.host,
        .port = config_values.server.port,
    }, channel.Handler{});
    defer server.deinit();

    // register our intent to handle SIGINT
    _ = std.c.sigaction(std.posix.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = empty_sig,
        .flags = 0,
    }, null);
    _ = std.c.sigaction(std.posix.SIG.TERM, &.{
        .handler = .{ .handler = shutdown },
        .mask = empty_sig,
        .flags = 0,
    }, null);

    // setup routes
    routes.init(config_values);
    var router = try server.router(.{});
    // a normal route
    router.get("/ws", channel.ws, .{});
    router.get("/", routes.get_home, .{});
    router.get("/static/*", routes.get_assets, .{});

    // this will block until server.stop() is called
    // which will then run the server.deinit() we setup above with `defer`
    std.log.info("starting server on address: {s}:{d}\n", .{
        config_values.server.host,
        config_values.server.port,
    });

    try server.listen();
}

export fn shutdown(_: c_int) void {
    server.stop();
}
