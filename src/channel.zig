const std = @import("std");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const db = @import("db.zig");
const args = @import("args.zig");

pub var ctx: Context = undefined;
var alloc: std.mem.Allocator = undefined;
var driver: db.driver = undefined;

/// Notification structure to send to the connected web socket client.
const notification = struct {
    /// The channel (table schema and name)
    channel: []const u8,
    /// The payload (payload from pg_notify)
    payload: []const u8,
    /// Metadata info (primary key and foreign key info)
    metadata: db.table_info,
};

/// Initialize the DB and websocket client.
pub fn init(allocator: std.mem.Allocator, conf: args.config) !void {
    alloc = allocator;
    driver = db.driver.init(alloc, conf) catch |err| {
        std.debug.print("initialize failed: {}\n", .{err});
        return err;
    };
    errdefer driver.deinit() catch |err| {
        std.debug.print("errdefer driver.deinit failed: {}\n", .{err});
    };
    driver.setup_listeners() catch |err| {
        std.debug.print("initialize failed: {}\n", .{err});
        return err;
    };
    ctx = Context{};
}

/// Deinitialize the channel internals
pub fn deinit() !void {
    try driver.deinit();
}

/// Websocket route
pub fn ws(req: *httpz.Request, res: *httpz.Response) !void {
    if (try httpz.upgradeWebsocket(ws_handler, req, res, ctx) == false) {
        res.status = 400;
        res.body = "invalid websocket handshake";
        return;
    }
    // when upgradeWebsocket succeeds, you can no longer use `res`
}

/// The main listener function to communicate DB notifications to the front-end.
fn listener(conn: *websocket.Conn) !void {
    std.log.info("listening on tables:", .{});
    var metadata_hm = std.StringHashMap(*db.table_info).init(alloc);
    defer metadata_hm.deinit();
    for (0..driver.tables.items.len) |idx| {
        const table: *db.table_info = &driver.tables.items[idx];
        std.log.info("table_name={s}", .{table.name});
        try metadata_hm.put(table.name, table);
    }
    var out_buffer: [4096 * 6]u8 = undefined;
    var fixed_alloc = std.heap.FixedBufferAllocator.init(&out_buffer);
    while (ctx.running) {
        while (driver.listener.next()) |notif| {
            fixed_alloc.reset();
            var string_writer = std.ArrayList(u8).init(fixed_alloc.allocator());
            const info = notification{
                .channel = notif.channel,
                .payload = notif.payload,
                .metadata = metadata_hm.get(notif.channel).?.*,
            };
            info.metadata.to_str();
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

/// Main context object to bridge data across threads
const Context = struct {
    running: bool = true,
};

/// Websocket handler
const ws_handler = struct {
    ctx: Context,
    conn: *websocket.Conn,
    listening_thread: std.Thread,

    // MUST have these 3 public functions
    pub fn init(conn: *websocket.Conn, ctx_t: Context) !ws_handler {
        return .{
            .conn = conn,
            .ctx = ctx_t,
            .listening_thread = try std.Thread.spawn(.{}, listener, .{conn}),
        };
    }

    pub fn handle(self: *ws_handler, message: websocket.Message) !void {
        const data = message.data;
        if (std.mem.eql(u8, data, "close")) {
            ctx.running = false;
            self.listening_thread.join();
        }
    }

    pub fn close(self: *ws_handler) void {
        ctx.running = false;
        self.listening_thread.join();
    }
};
