const std = @import("std");
const pg = @import("pg");
const args = @import("args.zig");

/// postgres queries for grabbing tables and metadata info.
const tables_query = "SELECT table_schema || '.' || table_name FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema', 'typeorm');";
const foreign_keys_query =
    \\SELECT
    \\	kcu.column_name,
    \\    ccu.table_schema || '.' || ccu.table_name AS f_table_name,
    \\    ccu.column_name AS f_column_name
    \\FROM information_schema.table_constraints AS tc
    \\JOIN information_schema.key_column_usage AS kcu
    \\    ON tc.constraint_name = kcu.constraint_name
    \\    AND tc.table_schema = kcu.table_schema
    \\JOIN information_schema.constraint_column_usage AS ccu
    \\    ON ccu.constraint_name = tc.constraint_name
    \\WHERE tc.constraint_type = 'FOREIGN KEY'
    \\    AND tc.table_schema='{s}'
    \\    AND tc.table_name='{s}';
;
const primary_key_query =
    \\SELECT c.column_name, c.data_type
    \\FROM information_schema.table_constraints tc
    \\JOIN information_schema.constraint_column_usage AS ccu USING (constraint_schema, constraint_name)
    \\JOIN information_schema.columns AS c ON c.table_schema = tc.constraint_schema
    \\  AND tc.table_name = c.table_name AND ccu.column_name = c.column_name
    \\WHERE constraint_type = 'PRIMARY KEY' and tc.table_name = '{s}' and c.table_schema='{s}';
;
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

/// metadata type info
pub const metadata_t = struct {
    const PRIMARY_KEY = "PRIMARY_KEY";
    const FOREIGN_KEY = "FOREIGN_KEY";
};

/// Structure to hold tables connected by foreign keys.
pub const connection_table = struct {
    table_name: []u8,
    column_name: []u8,
};

/// Structure to hold column_name that is a foreign key along with connected table info.
pub const column_info = struct {
    column_name: []u8,
    connection_table: ?connection_table = null,
};

/// Metadata structure to hold primary/foreign key info.
pub const metadata = struct {
    type: [*:0]const u8,
    columns: ?[]column_info,
};

/// Structure to hold Table info.
pub const table_info = struct {
    name: []u8,
    metadatas: [2]metadata,

    /// Print out table info for debug purposes.
    pub fn to_str(self: *const table_info) void {
        std.debug.print("name: {s}\n", .{self.name});
        std.debug.print("metadatas:\n", .{});
        for (self.metadatas) |md| {
            std.debug.print("  type: {s}\n", .{md.type});
            std.debug.print("  columns:\n", .{});
            if (md.columns) |columns| {
                for (columns) |col| {
                    std.debug.print("    column_name: {s}\n", .{col.column_name});
                    std.debug.print("    connection_table:\n", .{});
                    if (col.connection_table) |ct| {
                        std.debug.print("      table_name: {s}\n", .{ct.table_name});
                        std.debug.print("      column_name: {s}\n", .{ct.column_name});
                    }
                }
            }
        }
    }
};

/// Main driver of DB connections and queries.
pub const driver = struct {
    str_buffer: [4096 * 2]u8,
    tsa: std.heap.ThreadSafeAllocator,
    fpa: std.heap.FixedBufferAllocator,
    alloc: std.mem.Allocator,

    tables: std.ArrayList(table_info),
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
        var driver_obj = driver{
            .alloc = alloc,
            .tables = std.ArrayList(table_info).init(alloc),
            .listener = undefined,
            .pool = db,
            .fpa = undefined,
            .tsa = undefined,
            .str_buffer = undefined,
        };
        driver_obj.fpa = std.heap.FixedBufferAllocator.init(@constCast(&driver_obj.str_buffer));
        driver_obj.tsa.child_allocator = driver_obj.fpa.allocator();
        return driver_obj;
    }

    fn make_str_copy(self: *driver, row: pg.Row, idx: usize) ![]u8 {
        const value = row.get([]u8, idx);
        const result = try self.alloc.alloc(u8, value.len);
        @memcpy(result, value);
        return result;
    }

    fn single_grab_table(self: *driver, row: pg.Row) !void {
        const local_info = table_info{
            .name = try self.make_str_copy(row, 0),
            .metadatas = undefined,
        };
        errdefer self.alloc.free(local_info.name);
        try self.tables.append(local_info);
    }

    fn grab_primary_keys(self: *driver, table: table_info) !metadata {
        const dot_idx = std.ascii.indexOfIgnoreCase(table.name, ".").?;
        const table_name = table.name[(dot_idx + 1)..];
        const schema_name = table.name[0..dot_idx];
        const query = try std.fmt.allocPrint(
            self.tsa.allocator(),
            primary_key_query,
            .{ table_name, schema_name },
        );
        defer self.tsa.child_allocator.free(query);
        const result = try self.pool.query(query, .{});
        defer result.deinit();
        var idx: usize = 0;
        var md: metadata = metadata{
            .type = metadata_t.PRIMARY_KEY,
            .columns = null,
        };
        while (try result.next()) |row| {
            if (idx == 0) {
                md.columns = try self.alloc.alloc(column_info, 1);
            } else {
                md.columns = try self.alloc.realloc(md.columns.?, idx + 1);
            }
            md.columns.?[idx].column_name = try self.make_str_copy(row, 0);
            md.columns.?[idx].connection_table = null;
            idx += 1;
        }
        return md;
    }

    fn grab_foreign_keys(self: *driver, table: table_info) !metadata {
        const dot_idx = std.ascii.indexOfIgnoreCase(table.name, ".").?;
        const table_name = table.name[(dot_idx + 1)..];
        const schema_name = table.name[0..dot_idx];
        const query = try std.fmt.allocPrint(
            self.tsa.allocator(),
            foreign_keys_query,
            .{ schema_name, table_name },
        );
        defer self.tsa.child_allocator.free(query);
        const result = try self.pool.query(query, .{});
        defer result.deinit();
        var idx: usize = 0;
        var md: metadata = metadata{
            .type = metadata_t.FOREIGN_KEY,
            .columns = null,
        };
        while (try result.next()) |row| {
            if (idx == 0) {
                md.columns = try self.alloc.alloc(column_info, 1);
            } else {
                md.columns = try self.alloc.realloc(md.columns.?, idx + 1);
            }
            md.columns.?[idx].column_name = try self.make_str_copy(row, 0);
            md.columns.?[idx].connection_table = connection_table{
                .table_name = try self.make_str_copy(row, 1),
                .column_name = try self.make_str_copy(row, 2),
            };
            idx += 1;
        }
        return md;
    }

    fn grab_tables(self: *driver) !void {
        var results = try self.pool.query(tables_query, .{});
        defer results.deinit();
        while (try results.next()) |row| {
            try self.single_grab_table(row);
        }
        for (self.tables.items, 0..) |table, idx| {
            self.tables.items[idx].metadatas[0] = try self.grab_primary_keys(table);
            self.tables.items[idx].metadatas[1] = try self.grab_foreign_keys(table);
        }
    }

    fn single_creation_query(self: *driver, table: table_info) !void {
        const safe_name = try driver.sanitize_name(self.tsa.allocator(), table.name);
        defer self.tsa.child_allocator.free(safe_name);

        const func_query = try std.fmt.allocPrint(self.tsa.allocator(), create_funcs, .{ safe_name, table.name });
        _ = try self.pool.exec(func_query, .{});
        defer self.tsa.child_allocator.free(func_query);

        const trigger_query = try std.fmt.allocPrint(self.tsa.allocator(), create_triggers, .{ safe_name, table.name, safe_name });
        _ = try self.pool.exec(trigger_query, .{});
        defer self.tsa.child_allocator.free(trigger_query);
    }

    fn execute_creation_queries(self: *driver) !void {
        try self.execute_deletion_queries();
        for (self.tables.items) |table| {
            try self.single_creation_query(table);
        }
    }

    fn single_delete_query(self: *driver, table: table_info) !void {
        const safe_name = try driver.sanitize_name(self.tsa.allocator(), table.name);
        defer self.tsa.child_allocator.free(safe_name);

        const drop_trigger_query = try std.fmt.allocPrint(self.tsa.allocator(), drop_triggers, .{ safe_name, table.name });
        _ = try self.pool.exec(drop_trigger_query, .{});
        defer self.tsa.child_allocator.free(drop_trigger_query);

        const drop_func_query = try std.fmt.allocPrint(self.tsa.allocator(), drop_functions, .{safe_name});
        _ = try self.pool.exec(drop_func_query, .{});
        defer self.tsa.child_allocator.free(drop_func_query);
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

    pub fn tear_down_listeners(self: *driver) !void {
        self.listener.deinit();
        try self.execute_deletion_queries();
    }

    pub fn deinit(self: *driver) !void {
        // this feels ugly. maybe pull this stuff out into their structure's deinit method's
        try self.tear_down_listeners();
        for (0..self.tables.items.len) |table_idx| {
            const table = self.tables.items[table_idx];
            self.alloc.free(table.name);
            for (0..table.metadatas.len) |md_idx| {
                const md = table.metadatas[md_idx];
                if (md.columns) |columns| {
                    for (0..columns.len) |col_idx| {
                        const col = columns[col_idx];
                        self.alloc.free(col.column_name);
                        if (col.connection_table) |ct| {
                            self.alloc.free(ct.column_name);
                            self.alloc.free(ct.table_name);
                        }
                    }
                    self.alloc.free(md.columns.?);
                }
            }
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
