-- Fix closed-beta account recovery: join_beta_account verifies the 8-digit code
-- with pgcrypto.  The original function omitted the extensions schema from its
-- security-definer search path, so every legitimate login failed with 42883.

create or replace function public.join_beta_account(p_display_name text, p_recovery_code text)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
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

  if recent_attempts > 5 then
    raise exception 'Too many recovery attempts. Try again later.';
  end if;

  select id, recovery_code_hash into target_account_id, expected_hash
  from public.beta_accounts
  where display_name = btrim(p_display_name);

  if target_account_id is null
     or extensions.crypt(p_recovery_code, expected_hash) <> expected_hash then
    raise exception 'Invalid Dinefolio name or recovery code';
  end if;

  insert into public.beta_account_devices(account_id, device_user_id)
  values (target_account_id, auth.uid())
  on conflict do nothing;

  delete from public.beta_recovery_attempts where device_user_id = auth.uid();
  return target_account_id;
end;
$$;

grant execute on function public.join_beta_account(text, text) to authenticated;
