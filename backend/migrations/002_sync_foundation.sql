begin;

alter table public.customers
  add column updated_at timestamptz not null default now(),
  add column deleted_at timestamptz;
alter table public.jobs
  add column updated_at timestamptz not null default now(),
  add column deleted_at timestamptz;

create function private.set_sync_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
revoke all on function private.set_sync_updated_at() from public, anon, authenticated;
create trigger customers_sync_updated_at before update on public.customers
  for each row execute function private.set_sync_updated_at();
create trigger jobs_sync_updated_at before update on public.jobs
  for each row execute function private.set_sync_updated_at();

-- 001 allowed zero and negative versions. Normalize those legacy rows to the
-- first valid server version before snapshotting, then enforce the invariant
-- on the source tables. The update trigger timestamps normalized rows.
update public.customers set version = 1 where version <= 0;
update public.jobs set version = 1 where version <= 0;
alter table public.customers
  add constraint customers_version_positive check (version > 0);
alter table public.jobs
  add constraint jobs_version_positive check (version > 0);

create table public.company_sync_state (
  company_id uuid primary key references public.companies(id),
  next_cursor bigint not null default 0 check (next_cursor >= 0)
);
create table public.sync_changes (
  company_id uuid not null references public.companies(id),
  cursor bigint not null check (cursor > 0),
  entity_kind text not null check (entity_kind in ('customer', 'job')),
  entity_id uuid not null,
  version bigint not null check (version > 0),
  deleted_at timestamptz,
  payload jsonb,
  operation_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (company_id, cursor)
);
create table public.sync_operation_receipts (
  company_id uuid not null references public.companies(id),
  operation_id uuid not null,
  device_id uuid not null,
  entity_kind text not null check (entity_kind in ('customer', 'job')),
  entity_id uuid not null,
  result text not null check (result in ('accepted', 'conflict')),
  resulting_version bigint,
  result_payload jsonb not null,
  conflict_payload jsonb,
  created_at timestamptz not null default now(),
  primary key (company_id, operation_id)
);

-- The sync_changes primary key supplies the (company_id, cursor) index.
create index sync_changes_entity_idx on public.sync_changes (company_id, entity_kind, entity_id);
create index sync_changes_created_idx on public.sync_changes (company_id, created_at);
create index sync_receipts_created_idx on public.sync_operation_receipts (company_id, created_at);

alter table public.company_sync_state enable row level security;
alter table public.sync_changes enable row level security;
alter table public.sync_operation_receipts enable row level security;
revoke all on public.company_sync_state, public.sync_changes, public.sync_operation_receipts
  from public, anon, authenticated;

-- Once a record participates in sync, all client writes must go through sync_push.
revoke insert, update, delete on public.customers, public.jobs from anon, authenticated;
drop policy customers_insert on public.customers;
drop policy customers_update on public.customers;
drop policy jobs_insert on public.jobs;
drop policy jobs_update on public.jobs;

-- The ALTER TABLE locks remain held through COMMIT, so this snapshot cannot
-- race a write. Give every pre-existing row a durable initial change and set
-- each company's next cursor past the snapshot before RPC writes become live.
-- Snapshot operation IDs are synthetic and have no client operation receipt.
with existing as (
  select c.company_id, 'customer'::text as entity_kind, c.id as entity_id,
    c.version, c.deleted_at, to_jsonb(c) as payload
  from public.customers c
  union all
  select j.company_id, 'job'::text as entity_kind, j.id as entity_id,
    j.version, j.deleted_at, to_jsonb(j) as payload
  from public.jobs j
), numbered as (
  select e.*, row_number() over (
    partition by e.company_id order by e.entity_kind, e.entity_id
  ) as cursor
  from existing e
), seeded as (
  insert into public.sync_changes (company_id, cursor, entity_kind, entity_id,
    version, deleted_at, payload, operation_id)
  select n.company_id, n.cursor, n.entity_kind, n.entity_id,
    n.version, n.deleted_at,
    case when n.deleted_at is null then n.payload else null end,
    gen_random_uuid()
  from numbered n
  returning company_id, cursor
)
insert into public.company_sync_state (company_id, next_cursor)
select company_id, max(cursor) from seeded group by company_id;

create function private.next_sync_cursor(p_company_id uuid) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_cursor bigint;
begin
  insert into public.company_sync_state (company_id) values (p_company_id)
    on conflict (company_id) do nothing;
  update public.company_sync_state
    set next_cursor = next_cursor + 1
    where company_id = p_company_id
    returning next_cursor into v_cursor;
  return v_cursor;
end $$;
revoke all on function private.next_sync_cursor(uuid) from public, anon, authenticated;

create function public.sync_push(
  p_operation_id uuid,
  p_company_id uuid,
  p_entity_kind text,
  p_entity_id uuid,
  p_device_id uuid,
  p_expected_version bigint,
  p_operation_kind text,
  p_payload jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid := auth.uid();
  v_manager boolean;
  v_customer public.customers%rowtype;
  v_job public.jobs%rowtype;
  v_receipt public.sync_operation_receipts%rowtype;
  v_current jsonb;
  v_result jsonb;
  v_payload jsonb;
  v_version bigint;
  v_deleted_at timestamptz;
  v_cursor bigint;
  v_assignee_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_company_id is null or not private.is_member(p_company_id) then
    raise exception 'company membership required' using errcode = '42501';
  end if;
  if p_operation_id is null or p_entity_id is null or p_device_id is null
     or p_expected_version is null or p_expected_version < 0
     or p_entity_kind not in ('customer', 'job')
     or p_operation_kind not in ('upsert', 'delete')
     or p_entity_kind is null or p_operation_kind is null then
    raise exception 'invalid sync operation' using errcode = '22023';
  end if;
  if p_operation_kind = 'upsert' and (p_payload is null or jsonb_typeof(p_payload) <> 'object') then
    raise exception 'upsert payload must be an object' using errcode = '22023';
  end if;

  -- A company row lock serializes receipt lookup, version checks and cursor allocation.
  insert into public.company_sync_state (company_id) values (p_company_id)
    on conflict (company_id) do nothing;
  perform 1 from public.company_sync_state where company_id = p_company_id for update;
  select * into v_receipt from public.sync_operation_receipts
    where company_id = p_company_id and operation_id = p_operation_id;
  if found then
    return jsonb_set(v_receipt.result_payload, '{status}', '"duplicate"'::jsonb);
  end if;

  v_manager := private.can_manage(p_company_id);
  if p_entity_kind = 'customer' and not v_manager then
    raise exception 'customer write requires owner or admin' using errcode = '42501';
  end if;

  if p_entity_kind = 'customer' then
    select * into v_customer from public.customers
      where company_id = p_company_id and id = p_entity_id for update;
    if found then
      v_current := jsonb_build_object('version', v_customer.version,
        'deleted_at', v_customer.deleted_at,
        'payload', case when v_customer.deleted_at is null then to_jsonb(v_customer) else null end);
    end if;
    if (p_expected_version = 0 and v_customer.id is not null)
       or (p_expected_version > 0 and
           (v_customer.id is null or v_customer.version <> p_expected_version)) then
      v_result := jsonb_build_object('status', 'conflict', 'current', v_current);
    elsif p_expected_version = 0 and p_operation_kind = 'delete' then
      v_result := jsonb_build_object('status', 'conflict', 'current', null);
    elsif p_expected_version = 0 then
      -- An ID already used by a different company cannot reveal that record.
      insert into public.customers (id, company_id, name, email, phone, address, version)
        values (p_entity_id, p_company_id, p_payload->>'name', p_payload->>'email',
          p_payload->>'phone', p_payload->>'address', 1)
        on conflict (id) do nothing
        returning * into v_customer;
      if v_customer.id is null then
        v_result := jsonb_build_object('status', 'conflict', 'current', null);
      end if;
    elsif p_operation_kind = 'delete' then
      update public.customers set deleted_at = now(), version = version + 1
        where company_id = p_company_id and id = p_entity_id returning * into v_customer;
    else
      update public.customers set
        name = case when p_payload ? 'name' then p_payload->>'name' else name end,
        email = case when p_payload ? 'email' then p_payload->>'email' else email end,
        phone = case when p_payload ? 'phone' then p_payload->>'phone' else phone end,
        address = case when p_payload ? 'address' then p_payload->>'address' else address end,
        deleted_at = null, version = version + 1
        where company_id = p_company_id and id = p_entity_id returning * into v_customer;
    end if;
    if v_result is null then
      v_version := v_customer.version;
      v_deleted_at := v_customer.deleted_at;
      v_payload := case when v_deleted_at is null then to_jsonb(v_customer) else null end;
    end if;
  else
    select * into v_job from public.jobs
      where company_id = p_company_id and id = p_entity_id for update;
    if found then
      v_current := jsonb_build_object('version', v_job.version,
        'deleted_at', v_job.deleted_at,
        'payload', case when v_job.deleted_at is null then to_jsonb(v_job) else null end);
    end if;
    v_assignee_id := case when p_payload ? 'assignee_id' then (p_payload->>'assignee_id')::uuid
                          else v_job.assignee_id end;
    if not v_manager and
       ((v_job.id is not null and v_job.assignee_id is distinct from v_user_id)
        or (p_operation_kind = 'upsert' and v_assignee_id is distinct from v_user_id)) then
      raise exception 'worker may write only assigned jobs' using errcode = '42501';
    end if;
    if (p_expected_version = 0 and v_job.id is not null)
       or (p_expected_version > 0 and
           (v_job.id is null or v_job.version <> p_expected_version)) then
      v_result := jsonb_build_object('status', 'conflict', 'current', v_current);
    elsif p_expected_version = 0 and p_operation_kind = 'delete' then
      v_result := jsonb_build_object('status', 'conflict', 'current', null);
    elsif p_expected_version = 0 then
      insert into public.jobs (id, company_id, customer_id, title, assignee_id,
        starts_at, ends_at, status, version)
        values (p_entity_id, p_company_id, (p_payload->>'customer_id')::uuid,
          p_payload->>'title', v_assignee_id,
          (p_payload->>'starts_at')::timestamptz, (p_payload->>'ends_at')::timestamptz,
          coalesce(p_payload->>'status', 'scheduled'), 1)
        on conflict (id) do nothing returning * into v_job;
      if v_job.id is null then
        v_result := jsonb_build_object('status', 'conflict', 'current', null);
      end if;
    elsif p_operation_kind = 'delete' then
      update public.jobs set deleted_at = now(), version = version + 1
        where company_id = p_company_id and id = p_entity_id returning * into v_job;
    else
      update public.jobs set
        customer_id = case when p_payload ? 'customer_id' then (p_payload->>'customer_id')::uuid else customer_id end,
        title = case when p_payload ? 'title' then p_payload->>'title' else title end,
        assignee_id = v_assignee_id,
        starts_at = case when p_payload ? 'starts_at' then (p_payload->>'starts_at')::timestamptz else starts_at end,
        ends_at = case when p_payload ? 'ends_at' then (p_payload->>'ends_at')::timestamptz else ends_at end,
        status = case when p_payload ? 'status' then p_payload->>'status' else status end,
        deleted_at = null, version = version + 1
        where company_id = p_company_id and id = p_entity_id returning * into v_job;
    end if;
    if v_result is null then
      v_version := v_job.version;
      v_deleted_at := v_job.deleted_at;
      v_payload := case when v_deleted_at is null then to_jsonb(v_job) else null end;
    end if;
  end if;

  if v_result is null then
    v_cursor := private.next_sync_cursor(p_company_id);
    insert into public.sync_changes (company_id, cursor, entity_kind, entity_id,
      version, deleted_at, payload, operation_id)
      values (p_company_id, v_cursor, p_entity_kind, p_entity_id,
        v_version, v_deleted_at, v_payload, p_operation_id);
    v_result := jsonb_build_object('status', 'accepted', 'version', v_version,
      'deleted_at', v_deleted_at, 'cursor', v_cursor);
  end if;
  insert into public.sync_operation_receipts (company_id, operation_id, device_id,
    entity_kind, entity_id, result, resulting_version, result_payload, conflict_payload)
    values (p_company_id, p_operation_id, p_device_id, p_entity_kind, p_entity_id,
      v_result->>'status', v_version, v_result,
      case when v_result->>'status' = 'conflict' then v_result->'current' else null end);
  return v_result;
end $$;

create function public.sync_pull(
  p_company_id uuid,
  p_after_cursor bigint,
  p_limit integer
) returns table (
  cursor bigint,
  entity_kind text,
  entity_id uuid,
  version bigint,
  deleted_at timestamptz,
  payload jsonb,
  operation_id uuid
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_company_id is null or not private.is_member(p_company_id) then
    raise exception 'company membership required' using errcode = '42501';
  end if;
  return query
    select c.cursor, c.entity_kind, c.entity_id, c.version, c.deleted_at,
      case when c.deleted_at is null then c.payload else null end, c.operation_id
    from public.sync_changes c
    where c.company_id = p_company_id and c.cursor > greatest(coalesce(p_after_cursor, 0), 0)
    order by c.cursor asc
    limit least(greatest(coalesce(p_limit, 200), 1), 200);
end $$;

revoke all on function public.sync_push(uuid,uuid,text,uuid,uuid,bigint,text,jsonb),
  public.sync_pull(uuid,bigint,integer) from public, anon;
grant execute on function public.sync_push(uuid,uuid,text,uuid,uuid,bigint,text,jsonb),
  public.sync_pull(uuid,bigint,integer) to authenticated;

commit;
