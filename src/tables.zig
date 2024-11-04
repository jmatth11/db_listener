const std = @import("std");

/// metadata type info
pub const metadata_t = struct {
    const PRIMARY_KEY = "PRIMARY_KEY";
    const FOREIGN_KEY = "FOREIGN_KEY";
};

/// Structure to hold tables connected by foreign keys.
pub const connection_table = struct {
    alloc: std.mem.Allocator,
    table_name: []u8,
    column_name: []u8,
};

/// Structure to hold column_name that is a foreign key along with connected table info.
pub const column_info = struct {
    alloc: std.mem.Allocator,
    column_name: []u8,
    connection_table: ?connection_table = null,
};

/// Metadata structure to hold primary/foreign key info.
pub const metadata = struct {
    alloc: std.mem.Allocator,
    type: [*:0]const u8,
    columns: ?[]column_info,
};

/// Structure to hold Table info.
pub const info = struct {
    alloc: std.mem.Allocator,
    name: []u8,
    metadatas: [2]metadata,

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
