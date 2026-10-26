-- Supabase/Postgres baseline; not yet connected to the mobile client.
-- Run through a migration role, never from a mobile app service key.
begin;
create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public;

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now()
);
create table public.memberships (
  company_id uuid not null references public.companies(id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('owner','admin','worker')),
  primary key(company_id,user_id)
);
create function private.is_member(tenant uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.memberships
    where company_id = tenant and user_id = (select auth.uid()));
$$;
create function private.can_manage(tenant uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.memberships
    where company_id = tenant and user_id = (select auth.uid())
      and role in ('owner','admin'));
$$;
revoke all on function private.is_member(uuid) from public;
revoke all on function private.can_manage(uuid) from public;
grant usage on schema private to authenticated;
grant execute on function private.is_member(uuid), private.can_manage(uuid) to authenticated;

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  name text not null check(length(trim(name)) > 0),
  email text, phone text, address text,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  unique(company_id,id)
);
create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  customer_id uuid not null,
  title text not null check(length(trim(title)) > 0),
  assignee_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null check(ends_at > starts_at),
  status text not null default 'scheduled' check(status in ('scheduled','in_progress','completed')),
  version bigint not null default 1,
  foreign key(company_id,customer_id) references public.customers(company_id,id),
  foreign key(company_id,assignee_id) references public.memberships(company_id,user_id)
);
create index jobs_company_start on public.jobs(company_id,starts_at);
create index customers_company_name on public.customers(company_id,name);

alter table public.companies enable row level security;
alter table public.memberships enable row level security;
alter table public.customers enable row level security;
alter table public.jobs enable row level security;
create policy companies_read on public.companies for select to authenticated using(private.is_member(id));
create policy memberships_read on public.memberships for select to authenticated using(private.is_member(company_id));
create policy customers_read on public.customers for select to authenticated using(private.is_member(company_id));
create policy customers_insert on public.customers for insert to authenticated with check(private.can_manage(company_id));
create policy customers_update on public.customers for update to authenticated using(private.can_manage(company_id)) with check(private.can_manage(company_id));
create policy jobs_read on public.jobs for select to authenticated using(private.is_member(company_id));
create policy jobs_insert on public.jobs for insert to authenticated with check(private.can_manage(company_id));
create policy jobs_update on public.jobs for update to authenticated using(private.can_manage(company_id)) with check(private.can_manage(company_id));
-- No client policy for company creation, memberships, deletes, or worker writes.
-- Add narrowly scoped server commands for onboarding and job progression.
revoke all on public.companies,public.memberships,public.customers,public.jobs from anon,authenticated;
grant select on public.companies,public.memberships to authenticated;
grant select,insert,update on public.customers,public.jobs to authenticated;
commit;
