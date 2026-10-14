-- Dinefolio closed beta: a recoverable workspace shared by several devices.
-- Run AFTER 20260917_dinefolio_local_first_sync.sql in Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.beta_accounts (
  id uuid primary key default gen_random_uuid(),
  display_name text not null unique,
  recovery_code_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.beta_account_devices (
  account_id uuid not null references public.beta_accounts(id) on delete cascade,
  device_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (account_id, device_user_id)
);

create table if not exists public.beta_recovery_attempts (
  device_user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0
);

alter table public.dish_profiles add column if not exists account_id uuid references public.beta_accounts(id) on delete cascade;
alter table public.tasting_records add column if not exists account_id uuid references public.beta_accounts(id) on delete cascade;
create index if not exists dish_profiles_account_id_idx on public.dish_profiles(account_id);
create index if not exists tasting_records_account_id_idx on public.tasting_records(account_id);

alter table public.beta_accounts enable row level security;
alter table public.beta_account_devices enable row level security;
alter table public.beta_recovery_attempts enable row level security;

create policy "beta device reads own membership" on public.beta_account_devices
  for select to authenticated using ((select auth.uid()) = device_user_id);

create or replace function public.current_beta_account_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth
as $$
  select account_id
  from public.beta_account_devices
  where device_user_id = auth.uid()
  order by created_at desc
  limit 1;
$$;

create or replace function public.create_beta_account(p_display_name text, p_recovery_code text)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  new_account_id uuid;
  normalized_name text := btrim(p_display_name);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(normalized_name) < 2 or char_length(normalized_name) > 24 then
    raise exception 'Name must be 2 to 24 characters';
  end if;
  if p_recovery_code !~ '^[0-9]{8}$' then
    raise exception 'Recovery code must be 8 digits';
  end if;

  insert into public.beta_accounts(display_name, recovery_code_hash)
  values (normalized_name, crypt(p_recovery_code, gen_salt('bf', 12)))
  returning id into new_account_id;

  insert into public.beta_account_devices(account_id, device_user_id)
  values (new_account_id, auth.uid());
  return new_account_id;
end;
$$;

create or replace function public.join_beta_account(p_display_name text, p_recovery_code text)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_account_id uuid;
  expected_hash text;
  recent_attempts integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.beta_recovery_attempts(device_user_id, window_started_at, attempts)
  values (auth.uid(), now(), 1)
  on conflict (device_user_id) do update set
    attempts = case when public.beta_recovery_attempts.window_started_at < now() - interval '15 minutes'
      then 1 else public.beta_recovery_attempts.attempts + 1 end,
    window_started_at = case when public.beta_recovery_attempts.window_started_at < now() - interval '15 minutes'
      then now() else public.beta_recovery_attempts.window_started_at end
  returning attempts into recent_attempts;
  if recent_attempts > 5 then raise exception 'Too many recovery attempts. Try again later.'; end if;

  select id, recovery_code_hash into target_account_id, expected_hash
  from public.beta_accounts where display_name = btrim(p_display_name);
  if target_account_id is null or crypt(p_recovery_code, expected_hash) <> expected_hash then
    raise exception 'Invalid Dinefolio name or recovery code';
  end if;

  insert into public.beta_account_devices(account_id, device_user_id)
  values (target_account_id, auth.uid()) on conflict do nothing;
  delete from public.beta_recovery_attempts where device_user_id = auth.uid();
  return target_account_id;
end;
$$;

grant execute on function public.current_beta_account_id() to authenticated;
grant execute on function public.create_beta_account(text, text) to authenticated;
grant execute on function public.join_beta_account(text, text) to authenticated;

drop policy if exists "dinefolio dish owner" on public.dish_profiles;
drop policy if exists "dinefolio tasting owner" on public.tasting_records;
create policy "dinefolio beta account member" on public.dish_profiles for all to authenticated
  using (account_id = public.current_beta_account_id())
  with check (account_id = public.current_beta_account_id());
create policy "dinefolio beta account member" on public.tasting_records for all to authenticated
  using (account_id = public.current_beta_account_id())
  with check (account_id = public.current_beta_account_id());

drop policy if exists "dinefolio media owner select" on storage.objects;
drop policy if exists "dinefolio media owner insert" on storage.objects;
drop policy if exists "dinefolio media owner update" on storage.objects;
drop policy if exists "dinefolio media owner delete" on storage.objects;
create policy "dinefolio beta media select" on storage.objects for select to authenticated
  using (bucket_id = 'dinefolio-media' and exists (
    select 1 from public.beta_account_devices m
    where m.account_id::text = (storage.foldername(name))[1] and m.device_user_id = (select auth.uid())
  ));
create policy "dinefolio beta media insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'dinefolio-media' and exists (
    select 1 from public.beta_account_devices m
    where m.account_id::text = (storage.foldername(name))[1] and m.device_user_id = (select auth.uid())
  ));
create policy "dinefolio beta media update" on storage.objects for update to authenticated
  using (bucket_id = 'dinefolio-media' and exists (
    select 1 from public.beta_account_devices m
    where m.account_id::text = (storage.foldername(name))[1] and m.device_user_id = (select auth.uid())
  ));
create policy "dinefolio beta media delete" on storage.objects for delete to authenticated
  using (bucket_id = 'dinefolio-media' and exists (
    select 1 from public.beta_account_devices m
    where m.account_id::text = (storage.foldername(name))[1] and m.device_user_id = (select auth.uid())
  ));
