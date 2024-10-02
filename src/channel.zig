const std = @import("std");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const db = @import("db.zig");
const args = @import("args.zig");

var ctx: Context = undefined;

pub const handler = struct {
    alloc: std.mem.Allocator,
    driver: db.driver,

    pub fn init(alloc: std.mem.Allocator, conf: args.config) !handler {
        var driver = db.driver.init(alloc, conf) catch |err| {
            std.debug.print("initialize failed: {}\n", .{err});
            return err;
        };
        driver.setup_listeners() catch |err| {
            std.debug.print("initialize failed: {}\n", .{err});
            return err;
        };
        ctx.alloc = alloc;
        ctx.driver = driver;
        return handler{
            .alloc = alloc,
            .driver = driver,
        };
    }
    pub fn deinit(self: *handler) !void {
        try self.driver.deinit();
    }
};

pub fn ws(req: *httpz.Request, res: *httpz.Response) !void {
    if (try httpz.upgradeWebsocket(ws_handler, req, res, ctx) == false) {
        res.status = 400;
        res.body = "invalid websocket handshake";
        return;
    }
    // when upgradeWebsocket succeeds, you can no longer use `res`
}

fn listener(ctx_t: Context) void {
    for (ctx_t.driver.tables.items) |name| {
        std.debug.print("table_name={s}\n", .{name});
    }
    var idx: usize = 0;
    while (idx < 10) {
        while (ctx_t.driver.listener.next()) |notification| {
            std.debug.print("Channel: {s}\nPayload: {s}", .{ notification.channel, notification.payload });
        }
        switch (ctx_t.driver.listener.err.?) {
            .pg => |pg| std.debug.print("{s}\n", .{pg.message}),
            .err => |err| std.debug.print("{s}\n", .{@errorName(err)}),
        }
        idx += 1;
    }
}

const Context = struct {
    alloc: std.mem.Allocator,
    driver: db.driver,
};

// MUST have these 3 public functions
const ws_handler = struct {
    ctx: Context,
    conn: *websocket.Conn,
    pub fn init(conn: *websocket.Conn, ctx_t: Context) !ws_handler {
        return .{
            .ctx = ctx_t,
            .conn = conn,
        };
    }

    pub fn handle(self: *ws_handler, message: websocket.Message) !void {
        const data = message.data;
        try self.conn.write(data); // echo the message back
    }

    pub fn close(_: *ws_handler) void {}
};
