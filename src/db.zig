const std = @import("std");
const pg = @import("pg");

pub const driver = struct {
    alloc: std.mem.Allocator,
    tables: ?[][]u8,
    pool: pg.Pool,

    pub fn init(alloc: std.mem.Allocator) !driver {
        return driver{
            .alloc = alloc,
            .tables = null,
            .pool = try pg.Pool.init(alloc, .{
                .size = 5,
                .connect = .{
                    .port = 5432,
                    .host = "127.0.0.1",
                },
                .auth = .{
                    .username = "postgres",
                    .password = "postgres",
                    .database = "postgres",
                    .timeout = 10_000,
                },
            }),
        };
    }

    pub fn deinit(self: *driver) void {
        if (self.tables) |tables| {
            // TODO probably need to iterate over them
            self.alloc.free(tables);
        }
        self.pool.deinit();
    }
};
