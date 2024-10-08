const std = @import("std");
const db = @import("db.zig");

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
    var driver = try db.driver.init(std.heap.page_allocator);
    defer driver.deinit();
}
