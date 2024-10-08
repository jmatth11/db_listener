const std = @import("std");

/// use this to get list of all tables in DB
//SELECT
//    table_schema || '.' || table_name
//FROM
//    information_schema.tables
//WHERE
//    table_type = 'BASE TABLE'
//AND
//    table_schema NOT IN ('pg_catalog', 'information_schema', 'typeorm');
//
//create or replace function f_signal_collector()returns trigger as $f$
//begin perform pg_notify('incoming_signals_feed',to_jsonb(new)::text);
//      return new;
//end $f$ language plpgsql;
//
//create trigger t_signal_collector after insert or update on table_all_signals
//for each row execute function f_signal_collector();
//
//
// DROP FUNCTION IF EXISTS <name>;
// DROP TRIGGER IF EXISTS <name> ON <table_name>;

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
