const std = @import("std");
const db = @import("db.zig");
const args = @import("args.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const config_values = args.parse_args(gpa.allocator()) catch |err| {
        if (err == args.arg_error.help) return;
        return err;
    };
    var driver = db.driver.init(std.heap.page_allocator, config_values) catch |err| {
        std.debug.print("initialize failed: {}\n", .{err});
        return err;
    };
    defer driver.deinit() catch |err| {
        std.debug.print("error deinitializing: {}\n", .{err});
    };
    driver.setup_listeners() catch |err| {
        std.debug.print("initialize failed: {}\n", .{err});
        return err;
    };
    for (driver.tables.items) |name| {
        std.debug.print("table_name={s}\n", .{name});
    }
    var idx: usize = 0;
    while (idx < 10) {
        while (driver.listener.next()) |notification| {
            std.debug.print("Channel: {s}\nPayload: {s}", .{ notification.channel, notification.payload });
        }
        switch (driver.listener.err.?) {
            .pg => |pg| std.debug.print("{s}\n", .{pg.message}),
            .err => |err| std.debug.print("{s}\n", .{@errorName(err)}),
        }
        idx += 1;
    }
}
