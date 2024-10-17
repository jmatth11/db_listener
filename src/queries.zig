/// postgres queries for grabbing tables and metadata info.
pub const tables_query = "SELECT table_schema || '.' || table_name FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema', 'typeorm');";
pub const foreign_keys_query =
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
pub const primary_key_query =
    \\SELECT c.column_name, c.data_type
    \\FROM information_schema.table_constraints tc
    \\JOIN information_schema.constraint_column_usage AS ccu USING (constraint_schema, constraint_name)
    \\JOIN information_schema.columns AS c ON c.table_schema = tc.constraint_schema
    \\  AND tc.table_name = c.table_name AND ccu.column_name = c.column_name
    \\WHERE constraint_type = 'PRIMARY KEY' and tc.table_name = '{s}' and c.table_schema='{s}';
;
pub const create_funcs =
    \\create or replace function {s}_fn()returns trigger as $f$
    \\begin perform pg_notify('{s}',to_jsonb(new)::text);
    \\      return new;
    \\end $f$ language plpgsql;
;
pub const create_triggers =
    \\create trigger {s}_tr after insert or update or delete on {s}
    \\for each row execute function {s}_fn();
;
pub const drop_functions = "DROP FUNCTION IF EXISTS {s}_fn;";
pub const drop_triggers = "DROP TRIGGER IF EXISTS {s}_tr ON {s};";
