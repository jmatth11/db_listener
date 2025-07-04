const std = @import("std");
const pg = @import("pg");
const args = @import("args.zig");
const queries = @import("queries.zig");
const tables = @import("tables.zig");

const query_type = enum(u32) {
    PRIMARY_KEY,
    FOREIGN_KEY,
};

pub const driver_errors = error{
    unsupported_type,
};

/// Main driver of DB connections and queries.
pub const driver = struct {
    alloc: std.mem.Allocator,

    tables: std.ArrayList(tables.info),
    pool: *pg.Pool,
    listener: pg.Listener,

    pub fn init(alloc: std.mem.Allocator, conf: args.config) !driver {
        const db = try pg.Pool.init(alloc, .{
            .size = 5,
            .connect = .{
                .port = conf.pg.port,
                .host = conf.pg.host,
            },
            .auth = .{
                .username = conf.pg.username,
                .password = conf.pg.password,
                .database = conf.pg.database,
                .timeout = conf.pg.timeout,
            },
        });
        errdefer db.deinit();
        return .{
            .alloc = alloc,
            .tables = std.ArrayList(tables.info).init(alloc),
            .listener = undefined,
            .pool = db,
        };
    }

    fn single_grab_table(self: *driver, row: pg.Row) !void {
        var local_info = try tables.info.init(self.alloc, row.get([]const u8, 0));
        errdefer local_info.deinit(self.alloc);
        try self.tables.append(local_info);
    }

    fn grab_metadata(self: *driver, key_type: query_type, table: *tables.info) !void {
        const dot_idx = std.ascii.indexOfIgnoreCase(table.name, ".").?;
        const table_name = table.name[(dot_idx + 1)..];
        const schema_name = table.name[0..dot_idx];
        var query: []const u8 = undefined;
        switch (key_type) {
            query_type.PRIMARY_KEY => {
                query = try std.fmt.allocPrint(
                    self.alloc,
                    queries.primary_key_query,
                    .{ table_name, schema_name },
                );
            },
            query_type.FOREIGN_KEY => {
                query = try std.fmt.allocPrint(
                    self.alloc,
                    queries.foreign_keys_query,
                    .{ schema_name, table_name },
                );
            },
        }
        defer self.alloc.free(query);
        const result = try self.pool.query(query, .{});
        defer result.deinit();
        while (try result.next()) |row| {
            switch (key_type) {
                query_type.PRIMARY_KEY => {
                    try table.add_primary_keys(self.alloc, row.get([]const u8, 0));
                },
                query_type.FOREIGN_KEY => {
                    try table.add_foreign_keys(
                        self.alloc,
                        row.get([]u8, 0),
                        row.get([]u8, 1),
                        row.get([]u8, 2),
                    );
                },
            }
        }
    }

    fn grab_tables(self: *driver) !void {
        var results = try self.pool.query(queries.tables_query, .{});
        defer results.deinit();
        while (try results.next()) |row| {
            try self.single_grab_table(row);
        }
        var idx: usize = 0;
        while (idx < self.tables.items.len) : (idx += 1) {
            try self.grab_metadata(query_type.PRIMARY_KEY, &self.tables.items[idx]);
            try self.grab_metadata(query_type.FOREIGN_KEY, &self.tables.items[idx]);
        }
    }

    fn single_creation_query(self: *driver, table: tables.info) !void {
        const safe_name = try driver.sanitize_name(self.alloc, table.name);
        defer self.alloc.free(safe_name);

        const func_query = try std.fmt.allocPrint(self.alloc, queries.create_funcs, .{ safe_name, table.name });
        _ = try self.pool.exec(func_query, .{});
        defer self.alloc.free(func_query);

        const trigger_query = try std.fmt.allocPrint(self.alloc, queries.create_triggers, .{ safe_name, table.name, safe_name });
        _ = try self.pool.exec(trigger_query, .{});
        defer self.alloc.free(trigger_query);
    }

    fn execute_creation_queries(self: *driver) !void {
        try self.execute_deletion_queries();
        for (self.tables.items) |table| {
            try self.single_creation_query(table);
        }
    }

    fn single_delete_query(self: *driver, table: tables.info) !void {
        const safe_name = try driver.sanitize_name(self.alloc, table.name);
        defer self.alloc.free(safe_name);

        const drop_trigger_query = try std.fmt.allocPrint(self.alloc, queries.drop_triggers, .{ safe_name, table.name });
        _ = try self.pool.exec(drop_trigger_query, .{});
        defer self.alloc.free(drop_trigger_query);

        const drop_func_query = try std.fmt.allocPrint(self.alloc, queries.drop_functions, .{safe_name});
        _ = try self.pool.exec(drop_func_query, .{});
        defer self.alloc.free(drop_func_query);
    }

    fn execute_deletion_queries(self: *driver) !void {
        for (self.tables.items) |table| {
            try self.single_delete_query(table);
        }
    }

    pub fn setup_listeners(self: *driver) !void {
        try self.grab_tables();
        try self.execute_creation_queries();
        self.listener = try self.pool.newListener();
        for (self.tables.items) |table| {
            try self.listener.listen(table.name);
        }
    }

    pub fn tear_down_listeners(self: *driver) void {
        self.listener.deinit();
        self.execute_deletion_queries() catch |err| {
            std.debug.print("error executing deletion queries: {}", .{err});
        };
    }

    pub fn deinit(self: *driver) void {
        self.tear_down_listeners();
        for (0..self.tables.items.len) |table_idx| {
            self.tables.items[table_idx].deinit(self.alloc);
        }
        self.tables.deinit();
        self.pool.deinit();
    }

    fn sanitize_name(alloc: std.mem.Allocator, name: []const u8) ![]u8 {
        const result: []u8 = try alloc.alloc(u8, name.len);
        for (name, 0..) |ch, idx| {
            if (ch == '.') {
                result[idx] = '_';
            } else {
                result[idx] = ch;
            }
        }
        return result;
    }
};
