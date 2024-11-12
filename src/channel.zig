const std = @import("std");
const httpz = @import("httpz");
const websocket = httpz.websocket;
const db = @import("db.zig");
const args = @import("args.zig");
const tables = @import("tables.zig");
const assert = std.debug.assert;

const conn_type = std.AutoHashMap(u32, *websocket.Conn);
pub var running: bool = true;
var thread_ctx: ThreadContext = undefined;
var alloc: std.mem.Allocator = undefined;
var driver: db.driver = undefined;
var main_thread: std.Thread = undefined;

/// Notification structure to send to the connected web socket client.
const notification = struct {
    /// The channel (table schema and name)
    channel: []const u8,
    /// The payload (payload from pg_notify)
    payload: []const u8,
    /// Metadata info (primary key and foreign key info)
    metadata: tables.info,
};

const ThreadContext = struct {
    connections: conn_type,
};

/// Main context object to bridge data across threads
const WSContext = struct {
    address: u32,
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
    thread_ctx = ThreadContext{
        .connections = conn_type.init(alloc),
    };
    errdefer thread_ctx.connections.deinit();
    main_thread = try std.Thread.spawn(.{}, listener, .{&thread_ctx});
}

/// Deinitialize the channel internals
pub fn deinit() !void {
    try driver.deinit();
    running = false;
    main_thread.join();
    // TODO maybe iterate through hashmap and close connections that were left open?
    thread_ctx.connections.deinit();
}

/// Websocket route
pub fn ws(req: *httpz.Request, res: *httpz.Response) !void {
    const local_ctx = WSContext{
        .address = req.address.in.sa.addr,
    };
    if (try httpz.upgradeWebsocket(ws_handler, req, res, local_ctx) == false) {
        res.status = 400;
        res.body = "invalid websocket handshake";
        return;
    }
    // when upgradeWebsocket succeeds, you can no longer use `res`
}

/// Function to send payload to client
fn send_notification(
    allocator: std.mem.Allocator,
    ctx: *ThreadContext,
    table_map: std.StringHashMap(*tables.info),
    channel: []const u8,
    payload: []const u8,
) !void {
    var string_writer = std.ArrayList(u8).init(allocator);
    defer string_writer.deinit();
    const md_optional = table_map.get(channel);
    assert(md_optional != null);
    const info = notification{
        .channel = channel,
        .payload = payload,
        .metadata = md_optional.?.*,
    };
    info.metadata.to_str();
    try std.json.stringify(
        info,
        .{},
        string_writer.writer(),
    );
    // TODO need to make thread safe
    var iter = ctx.connections.valueIterator();
    while (iter.next()) |conn| {
        try conn.*.write(string_writer.items);
    }
    std.log.debug("Channel: {s}\nPayload: {s}\n", .{ channel, payload });
}

/// The main listener function to communicate DB notifications to the front-end.
fn listener(ctx: *ThreadContext) !void {
    std.log.info("listening on tables:", .{});
    var metadata_hm = std.StringHashMap(*tables.info).init(alloc);
    defer metadata_hm.deinit();
    for (0..driver.tables.items.len) |idx| {
        const table: *tables.info = &driver.tables.items[idx];
        std.log.info("table_name={s}", .{table.name});
        try metadata_hm.put(table.name, table);
    }
    var out_buffer: [4096 * 6]u8 = undefined;
    var fixed_alloc = std.heap.FixedBufferAllocator.init(&out_buffer);
    while (running) {
        while (driver.listener.next()) |notif| {
            fixed_alloc.reset();
            try send_notification(
                fixed_alloc.allocator(),
                ctx,
                metadata_hm,
                notif.channel,
                notif.payload,
            );
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

/// Websocket handler
const ws_handler = struct {
    ctx: WSContext,
    conn: *websocket.Conn,

    // MUST have these 3 public functions
    pub fn init(conn: *websocket.Conn, ctx_t: WSContext) !ws_handler {
        if (thread_ctx.connections.get(ctx_t.address)) |thread| {
            thread.close();
        }
        try thread_ctx.connections.put(ctx_t.address, conn);
        return .{
            .conn = conn,
            .ctx = ctx_t,
        };
    }

    pub fn handle(self: *ws_handler, message: websocket.Message) !void {
        const data = message.data;
        if (std.mem.eql(u8, data, "close")) {
            self.conn.close();
        }
    }

    pub fn close(self: *ws_handler) void {
        _ = thread_ctx.connections.remove(self.ctx.address);
    }
};
