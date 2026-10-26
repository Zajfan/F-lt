-- Run once on an isolated database after 001_tenancy.sql and before
-- 002_sync_foundation.sql. The contract test rolls back its own mutations;
-- this fixture remains until the test database is discarded.
begin;

insert into auth.users (id, email) values
  ('a0000000-0000-4000-8000-000000000001', 'sync-owner@example.invalid'),
  ('a0000000-0000-4000-8000-000000000002', 'sync-admin@example.invalid'),
  ('a0000000-0000-4000-8000-000000000003', 'sync-worker@example.invalid'),
  ('a0000000-0000-4000-8000-000000000004', 'sync-outsider@example.invalid');
insert into public.companies (id, name) values
  ('b0000000-0000-4000-8000-000000000001', 'Sync tenant A'),
  ('b0000000-0000-4000-8000-000000000002', 'Sync tenant B');
insert into public.memberships (company_id, user_id, role) values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'owner'),
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'admin'),
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000003', 'worker');
-- 001 permits these legacy versions; 002 must normalize them before backfill.
insert into public.customers (id, company_id, name, version) values
  ('c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'Initial customer', 0);
insert into public.jobs (id, company_id, customer_id, title, assignee_id, starts_at, ends_at, version) values
  ('d0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001',
   'c0000000-0000-4000-8000-000000000001', 'Initial job',
   'a0000000-0000-4000-8000-000000000003', '2030-01-01 09:00+00', '2030-01-01 10:00+00', -7);

commit;
