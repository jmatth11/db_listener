const std = @import("std");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const db = @import("db.zig");
const args = @import("args.zig");

pub var ctx: Context = undefined;
var alloc: std.mem.Allocator = undefined;
var driver: db.driver = undefined;

const notification = struct {
    channel: []const u8,
    payload: []const u8,
};

pub fn init(allocator: std.mem.Allocator, conf: args.config) !void {
    alloc = allocator;
    driver = db.driver.init(alloc, conf) catch |err| {
        std.debug.print("initialize failed: {}\n", .{err});
        return err;
    };
    driver.setup_listeners() catch |err| {
        std.debug.print("initialize failed: {}\n", .{err});
        return err;
    };
    ctx = Context{};
}
pub fn deinit() !void {
    try driver.deinit();
}

pub fn ws(req: *httpz.Request, res: *httpz.Response) !void {
    if (try httpz.upgradeWebsocket(ws_handler, req, res, ctx) == false) {
        res.status = 400;
        res.body = "invalid websocket handshake";
        return;
    }
    // when upgradeWebsocket succeeds, you can no longer use `res`
}

fn listener(conn: *websocket.Conn) !void {
    std.log.info("listening on tables:\n", .{});
    for (driver.tables.items) |name| {
        std.log.info("table_name={s}\n", .{name});
    }
    var out_buffer: [4096 * 4]u8 = undefined;
    var fixed_alloc = std.heap.FixedBufferAllocator.init(&out_buffer);
    while (ctx.running) {
        fixed_alloc.reset();
        while (driver.listener.next()) |notif| {
            var string_writer = std.ArrayList(u8).init(fixed_alloc.allocator());
            const info = notification{
                .channel = notif.channel,
                .payload = notif.payload,
            };
            try std.json.stringify(
                info,
                .{},
                string_writer.writer(),
            );
            try conn.write(string_writer.items);
            std.log.debug("Channel: {s}\nPayload: {s}\n", .{ notif.channel, notif.payload });
        }
        switch (driver.listener.err.?) {
            .pg => |pg| std.debug.print("pg - {s}\n", .{pg.message}),
            .err => |err| {
                const named_err = @errorName(err);
                if (!std.mem.eql(u8, named_err, "WouldBlock")) {
                    std.debug.print("err - {s}\n", .{named_err});
                }
            },
        }
    }
}

const Context = struct {
    running: bool = true,
};

// MUST have these 3 public functions
const ws_handler = struct {
    ctx: Context,
    conn: *websocket.Conn,
    listening_thread: std.Thread,
    pub fn init(conn: *websocket.Conn, ctx_t: Context) !ws_handler {
        return .{
            .conn = conn,
            .ctx = ctx_t,
            .listening_thread = try std.Thread.spawn(.{}, listener, .{conn}),
        };
    }

    pub fn handle(self: *ws_handler, message: websocket.Message) !void {
        const data = message.data;
        try self.conn.write(data); // echo the message back
    }

    pub fn close(self: *ws_handler) void {
        ctx.running = false;
        self.listening_thread.join();
    }
};
