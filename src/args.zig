const std = @import("std");
const clap = @import("clap");

pub const arg_error = error{
    help,
    invalid_param,
};

pub const db_info = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 5432,
    username: []const u8 = "postgres",
    password: []const u8 = "postgres",
    database: []const u8 = "postgres",
    timeout: u32 = 10_000,
};

pub const server_info = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 3000,
    web_dir: []const u8 = "web/",
};

pub const config = struct {
    pg: db_info = db_info{},
    server: server_info = server_info{},
};

pub fn parse_args(alloc: std.mem.Allocator) !config {
    var result: config = config{};
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\    --pg_host <str>     Postgres Host name.
        \\    --pg_port <u16>     Postgres Port number.
        \\    --pg_username <str> Postgres Username.
        \\    --pg_password <str> Postgres Password.
        \\    --pg_database <str> Postgres Database.
        \\    --server_host <str> Web Server Host.
        \\    --server_port <u16> Web Server Port.
        \\    --web_dir <str>     The front-end web directory.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = alloc,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // TODO validate params
    if (res.args.help != 0)
        return arg_error.help;
    if (res.args.pg_host) |val|
        result.pg.host = val;
    if (res.args.pg_port) |val|
        result.pg.port = val;
    if (res.args.pg_username) |val|
        result.pg.username = val;
    if (res.args.pg_password) |val|
        result.pg.password = val;
    if (res.args.pg_database) |val|
        result.pg.database = val;
    if (res.args.server_host) |val|
        result.server.host = val;
    if (res.args.server_port) |val|
        result.server.port = val;
    if (res.args.web_dir) |val|
        result.server.web_dir = val;
    return result;
}
