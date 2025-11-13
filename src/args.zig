const std = @import("std");
const clap = @import("clap");

/// Argument Error Types
pub const arg_error = error{
    /// Error type to signal the user requesting the help menu.
    help,
    /// Generic invalid parameter for an argument.
    invalid_param,
    /// Unsupported format.
    unsupported_format,
};

/// Configuration values for Postgres database.
pub const db_info = struct {
    /// The host address
    host: []const u8 = "0.0.0.0",
    /// The port number
    port: u16 = 5432,
    /// The username to the DB
    username: []const u8 = "postgres",
    /// The password to the DB
    password: []const u8 = "postgres",
    /// The database name to connect to.
    database: []const u8 = "postgres",
    /// The timeout for connections.
    timeout: u32 = 10_000,
};

/// Configuration values for the HTTP server.
pub const server_info = struct {
    /// Server host address
    host: []const u8 = "0.0.0.0",
    /// Server port number
    port: u16 = 3000,
    /// Server front-end web folder
    web_dir: []const u8 = "web/",
};

/// Configuration structure for services.
pub const config = struct {
    /// Postgres DB
    pg: db_info = db_info{},
    /// HTTP Server
    server: server_info = server_info{},
};

fn pull_env_args(comptime T: type, key: [*:0]const u8) !?T {
    if (std.c.getenv(key)) |env_var| {
        const value = std.mem.span(env_var);
        return switch (T) {
            []const u8 => value,
            u16, u32 => try std.fmt.parseInt(T, value, 10),
            else => arg_error.unsupported_format,
        };
    }
    return null;
}

/// Parse command line arguments.
///
/// @param alloc Standard allocator.
/// @return config structure on success, error value otherwise.
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
        diag.reportToFile(.stderr(), err) catch {};
        return err;
    };
    defer res.deinit();

    // TODO validate params
    if (res.args.help != 0) {
        try clap.helpToFile(.stdout(), clap.Help, &params, .{});
        return arg_error.help;
    }
    if (res.args.pg_host) |val| {
        result.pg.host = val;
    } else if (try pull_env_args([]const u8, "PG_HOST")) |val| {
        result.pg.host = val;
    }
    if (res.args.pg_port) |val| {
        result.pg.port = val;
    } else if (try pull_env_args(u16, "PG_PORT")) |val| {
        result.pg.port = val;
    }
    if (res.args.pg_username) |val| {
        result.pg.username = val;
    } else if (try pull_env_args([]const u8, "PG_USERNAME")) |val| {
        result.pg.username = val;
    }
    if (res.args.pg_password) |val| {
        result.pg.password = val;
    } else if (try pull_env_args([]const u8, "PG_PASSWORD")) |val| {
        result.pg.password = val;
    }
    if (res.args.pg_database) |val| {
        result.pg.database = val;
    } else if (try pull_env_args([]const u8, "PG_DATABASE")) |val| {
        result.pg.database = val;
    }
    if (res.args.server_host) |val| {
        result.server.host = val;
    } else if (try pull_env_args([]const u8, "SERVER_HOST")) |val| {
        result.server.host = val;
    }
    if (res.args.server_port) |val| {
        result.server.port = val;
    } else if (try pull_env_args(u16, "SERVER_PORT")) |val| {
        result.server.port = val;
    }
    if (res.args.web_dir) |val| {
        result.server.web_dir = val;
    } else if (try pull_env_args([]const u8, "WEB_DIR")) |val| {
        result.server.web_dir = val;
    }
    return result;
}
