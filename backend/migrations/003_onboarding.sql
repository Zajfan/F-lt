begin;

alter table public.companies
  add column if not exists trade_profile text not null default 'Annat';

alter table public.companies
  drop constraint if exists companies_trade_profile_check;
alter table public.companies
  add constraint companies_trade_profile_check
  check (trade_profile in ('Tak', 'Måleri', 'El', 'Annat'));

create or replace function public.my_companies()
returns table(
  id uuid,
  name text,
  trade_profile text,
  role text
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.name, c.trade_profile, m.role
  from public.companies c
  join public.memberships m on m.company_id = c.id
  where m.user_id = (select auth.uid())
  order by c.name, c.id;
$$;

create or replace function public.create_company(
  p_name text,
  p_trade_profile text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_company public.companies%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'company name is required' using errcode = '22023';
  end if;
  if p_trade_profile is null or p_trade_profile not in ('Tak', 'Måleri', 'El', 'Annat') then
    raise exception 'invalid trade profile' using errcode = '22023';
  end if;

  insert into public.companies (name, trade_profile)
    values (trim(p_name), p_trade_profile)
    returning * into v_company;
  insert into public.memberships (company_id, user_id, role)
    values (v_company.id, v_user_id, 'owner');

  return jsonb_build_object(
    'id', v_company.id,
    'name', v_company.name,
    'trade_profile', v_company.trade_profile,
    'role', 'owner'
  );
end;
$$;

revoke all on function public.my_companies() from public, anon, authenticated;
revoke all on function public.create_company(text, text) from public, anon, authenticated;
grant execute on function public.my_companies() to authenticated;
grant execute on function public.create_company(text, text) to authenticated;

-- Direct reads remain membership-filtered by the policies from 001_tenancy.sql.
-- No authenticated insert/update/delete grant is added for onboarding tables.
revoke all on public.companies, public.memberships from public, anon, authenticated;
grant select on public.companies, public.memberships to authenticated;

commit;
