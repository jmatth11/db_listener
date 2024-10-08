const std = @import("std");
const pg = @import("pg");
const args = @import("args.zig");

const tables_query = "SELECT table_schema || '.' || table_name FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema', 'typeorm');";
const create_funcs =
    \\create or replace function {s}_fn()returns trigger as $f$
    \\begin perform pg_notify('{s}',to_jsonb(new)::text);
    \\      return new;
    \\end $f$ language plpgsql;
;
const create_triggers =
    \\create trigger {s}_tr after insert or update or delete on {s}
    \\for each row execute function {s}_fn();
;
const drop_functions = "DROP FUNCTION IF EXISTS {s}_fn;";
const drop_triggers = "DROP TRIGGER IF EXISTS {s}_tr ON {s};";

pub const driver = struct {
    alloc: std.mem.Allocator,
    tables: std.ArrayList([]u8),
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
        return driver{
            .alloc = alloc,
            .tables = std.ArrayList([]u8).init(alloc),
            .listener = undefined,
            .pool = db,
        };
    }

    fn single_grab_table(self: *driver, row: pg.Row) !void {
        const name = row.get([]u8, 0);
        const name_copy = try self.alloc.alloc(u8, name.len);
        errdefer self.alloc.free(name_copy);
        @memcpy(name_copy, name);
        try self.tables.append(name_copy);
    }

    fn grab_tables(self: *driver) !void {
        var results = try self.pool.query(tables_query, .{});
        defer results.deinit();
        while (try results.next()) |row| {
            try self.single_grab_table(row);
        }
    }

    fn single_creation_query(self: *driver, table: []u8) !void {
        const safe_name = try self.sanitize_name(table);
        defer self.alloc.free(safe_name);

        const func_query = try std.fmt.allocPrint(self.alloc, create_funcs, .{ safe_name, table });
        defer self.alloc.free(func_query);
        _ = try self.pool.exec(func_query, .{});

        const trigger_query = try std.fmt.allocPrint(self.alloc, create_triggers, .{ safe_name, table, safe_name });
        defer self.alloc.free(trigger_query);
        _ = try self.pool.exec(trigger_query, .{});
    }

    fn execute_creation_queries(self: *driver) !void {
        try self.execute_deletion_queries();
        for (self.tables.items) |table| {
            try self.single_creation_query(table);
        }
    }

    fn single_delete_query(self: *driver, table: []u8) !void {
        const safe_name = try self.sanitize_name(table);
        defer self.alloc.free(safe_name);

        const drop_trigger_query = try std.fmt.allocPrint(self.alloc, drop_triggers, .{ safe_name, table });
        defer self.alloc.free(drop_trigger_query);
        _ = try self.pool.exec(drop_trigger_query, .{});

        const drop_func_query = try std.fmt.allocPrint(self.alloc, drop_functions, .{safe_name});
        defer self.alloc.free(drop_func_query);
        _ = try self.pool.exec(drop_func_query, .{});
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
            try self.listener.listen(table);
        }
    }

    pub fn tear_down_listeners(self: *driver) !void {
        self.listener.deinit();
        try self.execute_deletion_queries();
    }

    pub fn deinit(self: *driver) !void {
        try self.tear_down_listeners();
        for (self.tables.items) |item| {
            self.alloc.free(item);
        }
        self.tables.deinit();
        self.pool.deinit();
    }

    fn sanitize_name(self: *driver, name: []u8) ![]u8 {
        const result: []u8 = try self.alloc.alloc(u8, name.len);
        for (name, 0..) |ch, idx| {
            if (ch != '.') {
                result[idx] = ch;
            } else {
                result[idx] = '_';
            }
        }
        return result;
    }
};
