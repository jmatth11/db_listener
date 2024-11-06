const std = @import("std");

/// metadata type info
pub const metadata_t = struct {
    const PRIMARY_KEY = "PRIMARY_KEY";
    const FOREIGN_KEY = "FOREIGN_KEY";
};

/// Structure to hold tables connected by foreign keys.
const connection_table = struct {
    table_name: []const u8,
    column_name: []const u8,

    pub fn deinit(self: *const connection_table, alloc: std.mem.Allocator) void {
        alloc.free(self.table_name);
        alloc.free(self.column_name);
    }
};

/// Structure to hold column_name that is a foreign key along with connected table info.
const column_info = struct {
    column_name: []const u8,
    connection_table: ?connection_table = null,

    pub fn deinit(self: *const column_info, alloc: std.mem.Allocator) void {
        alloc.free(self.column_name);
        if (self.connection_table) |con| {
            con.deinit(alloc);
        }
    }
};

/// Metadata structure to hold primary/foreign key info.
const metadata = struct {
    type: [*:0]const u8,
    columns: ?[]column_info = null,

    pub fn add_column(self: *metadata, alloc: std.mem.Allocator, col_name: []const u8) !void {
        if (self.columns) |col| {
            self.columns = try alloc.realloc(col, col.len + 1);
        } else {
            self.columns = try alloc.alloc(column_info, 1);
        }
        if (self.columns) |col| {
            col[col.len - 1].column_name = try alloc.dupe(u8, col_name);
        }
    }

    pub fn add_column_with_connection(
        self: *metadata,
        alloc: std.mem.Allocator,
        key: []const u8,
        con_table: []const u8,
        con_col: []const u8,
    ) !void {
        if (self.columns) |col| {
            self.columns = try alloc.realloc(col, col.len + 1);
        } else {
            self.columns = try alloc.alloc(column_info, 1);
        }
        if (self.columns) |col| {
            var cur_col = &col[col.len - 1];
            cur_col.column_name = try alloc.dupe(u8, key);
            cur_col.connection_table = connection_table{
                .column_name = try alloc.dupe(u8, con_col),
                .table_name = try alloc.dupe(u8, con_table),
            };
        }
    }

    pub fn deinit(self: *metadata, alloc: std.mem.Allocator) void {
        if (self.columns) |columns| {
            for (columns) |col| {
                col.deinit(alloc);
            }
        }
    }
};

/// Structure to hold Table info.
pub const info = struct {
    name: []const u8,
    metadatas: [2]metadata,

    pub fn init(alloc: std.mem.Allocator, name: []const u8) !info {
        return info{
            .name = try alloc.dupe(u8, name),
            .metadatas = [2]metadata{
                metadata{
                    .type = metadata_t.PRIMARY_KEY,
                },
                metadata{
                    .type = metadata_t.FOREIGN_KEY,
                },
            },
        };
    }

    pub fn add_primary_keys(self: *info, alloc: std.mem.Allocator, key: []const u8) !void {
        try self.metadatas[0].add_column(alloc, key);
    }

    pub fn add_foreign_keys(self: *info, alloc: std.mem.Allocator, key: []const u8, con_table: []const u8, con_col: []const u8) !void {
        try self.metadatas[1].add_column_with_connection(
            alloc,
            key,
            con_table,
            con_col,
        );
    }

    pub fn deinit(self: *info, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        for (0..self.metadatas.len) |idx| {
            self.metadatas[idx].deinit(alloc);
        }
    }

    /// Print out table info for debug purposes.
    pub fn to_str(self: *const info) void {
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
