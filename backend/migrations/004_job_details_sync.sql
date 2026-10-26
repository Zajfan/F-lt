begin;

-- Task 9 extends the existing synchronized job contract without changing the
-- RPC signature. Address is nullable for old rows, while instructions keeps a
-- safe empty-string default; quote_id remains provider-neutral text.
alter table public.jobs
  add column if not exists address text,
  add column if not exists instructions text not null default '',
  add column if not exists quote_id text;

-- Rows snapshotted by 002 did not contain the new nullable/detail fields.
-- Enrich only the current snapshot for each job. Historical rows must retain
-- the details that were true at their own version.
update public.sync_changes changes
set payload = changes.payload || jsonb_build_object(
  'address', jobs.address,
  'instructions', coalesce(jobs.instructions, ''),
  'quote_id', jobs.quote_id
)
from public.jobs jobs
where changes.company_id = jobs.company_id
  and changes.entity_kind = 'job'
  and changes.entity_id = jobs.id
  and changes.deleted_at is null
  and changes.payload is not null
  and changes.version = jobs.version;

create or replace function public.sync_push(
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
      insert into public.customers (id, company_id, name, email, phone, address, version)
        values (p_entity_id, p_company_id, p_payload->>'name', p_payload->>'email',
          p_payload->>'phone', p_payload->>'address', 1)
        on conflict (id) do nothing returning * into v_customer;
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
      insert into public.jobs (
        id, company_id, customer_id, title, address, instructions, quote_id,
        assignee_id, starts_at, ends_at, status, version
      )
        values (
          p_entity_id, p_company_id, (p_payload->>'customer_id')::uuid,
          p_payload->>'title', p_payload->>'address',
          coalesce(p_payload->>'instructions', ''), p_payload->>'quote_id',
          v_assignee_id, (p_payload->>'starts_at')::timestamptz,
          (p_payload->>'ends_at')::timestamptz,
          coalesce(p_payload->>'status', 'scheduled'), 1
        )
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
        address = case when p_payload ? 'address' then p_payload->>'address' else address end,
        instructions = case when p_payload ? 'instructions' then coalesce(p_payload->>'instructions', '') else instructions end,
        quote_id = case when p_payload ? 'quote_id' then p_payload->>'quote_id' else quote_id end,
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

-- sync_pull already returns sync_changes.payload; the enriched snapshot and
-- the replacement sync_push above therefore carry the detail fields through
-- the existing tenant-filtered pull contract.
grant execute on function public.sync_push(uuid,uuid,text,uuid,uuid,bigint,text,jsonb)
  to authenticated;

commit;
