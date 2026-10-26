-- Run after 001_tenancy.sql for RED. For GREEN, seed
-- sync_preexisting_fixture.sql before migrations 002-004, then run this.
-- The transaction rolls back mutations; the pre-migration fixture persists.
begin;

do $$
declare
  required_column text;
  required_table text;
  pull_result text;
begin
  foreach required_column in array array['updated_at', 'deleted_at'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'customers'
        and column_name = required_column
    ) or not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'jobs'
        and column_name = required_column
    ) then
      raise exception 'missing sync column: %', required_column;
    end if;
  end loop;

  foreach required_table in array array['company_sync_state', 'sync_changes', 'sync_operation_receipts'] loop
    if to_regclass('public.' || required_table) is null then
      raise exception 'missing sync table: %', required_table;
    end if;
  end loop;

  if to_regprocedure('public.sync_push(uuid,uuid,text,uuid,uuid,bigint,text,jsonb)') is null
     or pg_get_function_result('public.sync_push(uuid,uuid,text,uuid,uuid,bigint,text,jsonb)'::regprocedure) is distinct from 'jsonb' then
    raise exception 'missing sync_push signature';
  end if;
  if to_regprocedure('public.sync_pull(uuid,bigint,integer)') is null then
    raise exception 'missing sync_pull signature';
  end if;
  select pg_get_function_result('public.sync_pull(uuid,bigint,integer)'::regprocedure) into pull_result;
  if pull_result is distinct from 'TABLE(cursor bigint, entity_kind text, entity_id uuid, version bigint, deleted_at timestamp with time zone, payload jsonb, operation_id uuid)' then
    raise exception 'wrong sync_pull return signature: %', pull_result;
  end if;

  if has_table_privilege('authenticated', 'public.sync_changes', 'SELECT')
     or has_table_privilege('authenticated', 'public.sync_operation_receipts', 'SELECT')
     or has_table_privilege('anon', 'public.sync_changes', 'SELECT')
     or has_table_privilege('anon', 'public.sync_operation_receipts', 'SELECT')
     or has_table_privilege('authenticated', 'public.customers', 'UPDATE')
     or has_table_privilege('authenticated', 'public.jobs', 'UPDATE') then
    raise exception 'direct sync table access is exposed';
  end if;
  if not has_function_privilege('authenticated', 'public.sync_push(uuid,uuid,text,uuid,uuid,bigint,text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.sync_pull(uuid,bigint,integer)', 'EXECUTE') then
    raise exception 'authenticated RPC grants missing';
  end if;
end $$;

do $$
declare
  required_column text;
begin
  foreach required_column in array array['address', 'instructions', 'quote_id'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'jobs'
        and column_name = required_column
    ) then
      raise exception 'missing job detail column: %', required_column;
    end if;
  end loop;
end $$;

do $$
begin
  if (select version from public.customers
      where id = 'c0000000-0000-4000-8000-000000000001') is distinct from 1
     or (select version from public.jobs
      where id = 'd0000000-0000-4000-8000-000000000001') is distinct from 1 then
    raise exception 'legacy source versions were not normalized to 1';
  end if;
  begin
    update public.customers set version = 0
      where id = 'c0000000-0000-4000-8000-000000000001';
    raise exception 'customer accepted a nonpositive version';
  exception when check_violation then null;
  end;
  begin
    update public.jobs set version = -1
      where id = 'd0000000-0000-4000-8000-000000000001';
    raise exception 'job accepted a nonpositive version';
  exception when check_violation then null;
  end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000004', true);
do $$
begin
  begin
    perform 1 from public.sync_pull('b0000000-0000-4000-8000-000000000001', 0, 20);
    raise exception 'non-member pull unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.sync_push('e0000000-0000-4000-8000-000000000099',
      'b0000000-0000-4000-8000-000000000001', 'customer',
      'c0000000-0000-4000-8000-000000000001',
      'f0000000-0000-4000-8000-000000000004', 1, 'upsert', '{"name":"Intrusion"}'::jsonb);
    raise exception 'non-member push unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', true);
do $$
declare
  result jsonb;
begin
  -- These records were present before 002 and must be visible to a new client.
  if (select count(*) from public.sync_pull('b0000000-0000-4000-8000-000000000001', 0, 200)) is distinct from 2 then
    raise exception 'initial pull did not include both pre-migration records';
  end if;
  if (select count(*) from public.sync_pull('b0000000-0000-4000-8000-000000000001', 0, 200)
      where cursor = 1 and entity_kind = 'customer'
        and entity_id = 'c0000000-0000-4000-8000-000000000001'
        and version = 1 and payload->>'version' = '1'
        and payload->>'name' = 'Initial customer'
        and operation_id is not null) is distinct from 1 then
    raise exception 'pre-migration customer missing from cursor-zero pull';
  end if;
  if (select count(*) from public.sync_pull('b0000000-0000-4000-8000-000000000001', 0, 200)
      where cursor = 2 and entity_kind = 'job'
        and entity_id = 'd0000000-0000-4000-8000-000000000001'
        and version = 1 and payload->>'version' = '1'
        and payload->>'title' = 'Initial job'
        and payload ? 'address'
        and payload ? 'instructions'
        and payload ? 'quote_id'
        and operation_id is not null) is distinct from 1 then
    raise exception 'pre-migration job missing from cursor-zero pull';
  end if;
  begin
    perform 1 from public.sync_pull('b0000000-0000-4000-8000-000000000002', 0, 20);
    raise exception 'member read another company';
  exception when insufficient_privilege then null;
  end;

  result := public.sync_push('e0000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001', 'customer',
    'c0000000-0000-4000-8000-000000000001',
    'f0000000-0000-4000-8000-000000000001', 1, 'upsert',
    '{"name":"Updated customer","email":"updated@example.invalid"}'::jsonb);
  if result->>'status' is distinct from 'accepted'
     or (result->>'version')::bigint is distinct from 2 then
    raise exception 'customer upsert did not advance to version 2: %', result;
  end if;

  result := public.sync_push('e0000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001', 'customer',
    'c0000000-0000-4000-8000-000000000001',
    'f0000000-0000-4000-8000-000000000001', 1, 'upsert',
    '{"name":"Updated customer","email":"updated@example.invalid"}'::jsonb);
  if result->>'status' is distinct from 'duplicate'
     or (result->>'version')::bigint is distinct from 2 then
    raise exception 'replay did not return duplicate: %', result;
  end if;

  result := public.sync_push('e0000000-0000-4000-8000-000000000002',
    'b0000000-0000-4000-8000-000000000001', 'customer',
    'c0000000-0000-4000-8000-000000000001',
    'f0000000-0000-4000-8000-000000000001', 1, 'upsert',
    '{"name":"Stale customer"}'::jsonb);
  if result->>'status' is distinct from 'conflict'
     or (result->'current'->>'version')::bigint is distinct from 2
     or result->'current'->'payload'->>'name' is distinct from 'Updated customer' then
    raise exception 'stale version did not return current record: %', result;
  end if;

  result := public.sync_push('e0000000-0000-4000-8000-000000000003',
    'b0000000-0000-4000-8000-000000000001', 'customer',
    'c0000000-0000-4000-8000-000000000001',
    'f0000000-0000-4000-8000-000000000001', 2, 'delete', '{}'::jsonb);
  if result->>'status' is distinct from 'accepted'
     or (result->>'version')::bigint is distinct from 3
     or result->>'deleted_at' is null then
    raise exception 'delete did not make version 3 tombstone: %', result;
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000003', true);
do $$
declare
  result jsonb;
begin
  begin
    perform public.sync_push('e0000000-0000-4000-8000-000000000004',
      'b0000000-0000-4000-8000-000000000001', 'customer',
      'c0000000-0000-4000-8000-000000000001',
      'f0000000-0000-4000-8000-000000000003', 3, 'upsert', '{"name":"Worker edit"}'::jsonb);
    raise exception 'worker edited a customer';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.sync_push('e0000000-0000-4000-8000-000000000005',
      'b0000000-0000-4000-8000-000000000001', 'job',
      'd0000000-0000-4000-8000-000000000001',
      'f0000000-0000-4000-8000-000000000003', 1, 'upsert',
      '{"assignee_id":"a0000000-0000-4000-8000-000000000001"}'::jsonb);
    raise exception 'worker reassigned their job';
  exception when insufficient_privilege then null;
  end;
  result := public.sync_push('e0000000-0000-4000-8000-000000000006',
    'b0000000-0000-4000-8000-000000000001', 'job',
    'd0000000-0000-4000-8000-000000000001',
    'f0000000-0000-4000-8000-000000000003', 1, 'upsert',
      '{"status":"in_progress","address":"Main street 1","instructions":"Call first","quote_id":"quote-1"}'::jsonb);
  if result->>'status' is distinct from 'accepted'
     or (result->>'version')::bigint is distinct from 2 then
    raise exception 'assigned worker job update failed: %', result;
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', true);
do $$
declare
  result jsonb;
begin
  result := public.sync_push('e0000000-0000-4000-8000-000000000007',
    'b0000000-0000-4000-8000-000000000001', 'customer',
    'c0000000-0000-4000-8000-000000000002',
    'f0000000-0000-4000-8000-000000000002', 0, 'upsert',
    '{"name":"New customer"}'::jsonb);
  if result->>'status' is distinct from 'accepted'
     or (result->>'version')::bigint is distinct from 1 then
    raise exception 'admin zero-version insert failed: %', result;
  end if;
end $$;

reset role;
do $$
begin
  if (select count(*) from public.sync_changes
      where company_id = 'b0000000-0000-4000-8000-000000000001') is distinct from 6 then
    raise exception 'replay or conflict appended a change';
  end if;
  if (select version from public.customers
      where id = 'c0000000-0000-4000-8000-000000000001') is distinct from 3
     or (select deleted_at from public.customers
      where id = 'c0000000-0000-4000-8000-000000000001') is null then
    raise exception 'customer tombstone was not persisted';
  end if;
  if (select address from public.jobs
      where id = 'd0000000-0000-4000-8000-000000000001') is distinct from 'Main street 1'
     or (select instructions from public.jobs
      where id = 'd0000000-0000-4000-8000-000000000001') is distinct from 'Call first'
     or (select quote_id from public.jobs
      where id = 'd0000000-0000-4000-8000-000000000001') is distinct from 'quote-1' then
    raise exception 'job detail fields were not persisted';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', true);
do $$
declare
  pulled_count integer;
  first_cursor bigint;
  last_cursor bigint;
begin
  select count(*), min(cursor), max(cursor) into pulled_count, first_cursor, last_cursor
  from public.sync_pull('b0000000-0000-4000-8000-000000000001', 0, 200);
  if pulled_count is distinct from 6 or first_cursor is distinct from 1
     or last_cursor is distinct from 6 then
    raise exception 'pull did not return all changes in cursor sequence';
  end if;
  if (select count(*) from public.sync_pull('b0000000-0000-4000-8000-000000000001', 2, 200)) is distinct from 4 then
    raise exception 'pull cursor did not exclude prior change';
  end if;
  if (select count(*) from public.sync_pull('b0000000-0000-4000-8000-000000000001', 0, 200)
      where cursor = 4 and entity_kind = 'customer' and version = 3
        and deleted_at is not null and payload is null) is distinct from 1 then
    raise exception 'pull tombstone is missing or exposes a payload';
  end if;
  if exists (
    select 1 from (
      select cursor, lag(cursor) over (order by ordinality) as previous_cursor
      from public.sync_pull('b0000000-0000-4000-8000-000000000001', 0, 200)
        with ordinality as changes(cursor, entity_kind, entity_id, version, deleted_at, payload, operation_id, ordinality)
    ) ordered_changes where cursor <= previous_cursor
  ) then
    raise exception 'pull cursor order is not strictly increasing';
  end if;
end $$;

rollback;
