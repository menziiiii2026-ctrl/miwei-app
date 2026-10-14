-- Dinefolio closed beta: profile, avatar, ID and recovery-code management.
-- Run AFTER 20260918_dinefolio_recoverable_beta_accounts.sql.

alter table public.beta_accounts
  add column if not exists avatar_path text;

create or replace function public.current_beta_account_profile()
returns jsonb
language sql
stable
security definer
set search_path = public, auth, extensions
as $$
  select jsonb_build_object(
    'id', a.id,
    'display_name', a.display_name,
    'avatar_path', a.avatar_path
  )
  from public.beta_accounts a
  where a.id = public.current_beta_account_id();
$$;

create or replace function public.change_beta_display_name(
  p_new_display_name text,
  p_recovery_code text
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_account_id uuid := public.current_beta_account_id();
  expected_hash text;
  normalized_name text := btrim(p_new_display_name);
begin
  if current_account_id is null then raise exception 'Account required'; end if;
  if char_length(normalized_name) < 2 or char_length(normalized_name) > 24 then
    raise exception 'Name must be 2 to 24 characters';
  end if;

  select recovery_code_hash into expected_hash
  from public.beta_accounts where id = current_account_id;
  if expected_hash is null
     or extensions.crypt(p_recovery_code, expected_hash) <> expected_hash then
    raise exception 'Invalid recovery code';
  end if;

  update public.beta_accounts
  set display_name = normalized_name
  where id = current_account_id;
  return normalized_name;
end;
$$;

create or replace function public.change_beta_recovery_code(
  p_old_code text,
  p_new_code text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  current_account_id uuid := public.current_beta_account_id();
  expected_hash text;
begin
  if current_account_id is null then raise exception 'Account required'; end if;
  if p_new_code !~ '^[0-9]{8}$' then
    raise exception 'Recovery code must be 8 digits';
  end if;

  select recovery_code_hash into expected_hash
  from public.beta_accounts where id = current_account_id;
  if expected_hash is null or crypt(p_old_code, expected_hash) <> expected_hash then
    raise exception 'Invalid recovery code';
  end if;

  update public.beta_accounts
  set recovery_code_hash = crypt(p_new_code, gen_salt('bf', 12))
  where id = current_account_id;
end;
$$;

create or replace function public.update_beta_avatar(p_avatar_path text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_account_id uuid := public.current_beta_account_id();
begin
  if current_account_id is null then raise exception 'Account required'; end if;
  if p_avatar_path is null
     or p_avatar_path not like current_account_id::text || '/profile/%' then
    raise exception 'Invalid avatar path';
  end if;

  update public.beta_accounts
  set avatar_path = p_avatar_path
  where id = current_account_id;
end;
$$;

grant execute on function public.current_beta_account_profile() to authenticated;
grant execute on function public.change_beta_display_name(text, text) to authenticated;
grant execute on function public.change_beta_recovery_code(text, text) to authenticated;
grant execute on function public.update_beta_avatar(text) to authenticated;
