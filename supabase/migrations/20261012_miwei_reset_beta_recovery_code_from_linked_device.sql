-- Allow a device already linked to the current beta account to replace a forgotten code.
-- Apply after 20260918_dinefolio_beta_profile_management.sql.
-- The app also asks for iOS device-owner authentication before calling this RPC.
create or replace function public.reset_beta_recovery_code_from_linked_device(
  p_account_id uuid,
  p_new_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_new_code !~ '^[0-9]{8}$' then
    raise exception 'Recovery code must be 8 digits';
  end if;
  if p_account_id is null
     or p_account_id is distinct from public.current_beta_account_id()
     or not exists (
       select 1 from public.beta_account_devices
       where account_id = p_account_id and device_user_id = auth.uid()
     ) then
    raise exception 'Linked account required';
  end if;

  update public.beta_accounts
  set recovery_code_hash = extensions.crypt(p_new_code, extensions.gen_salt('bf', 12))
  where id = p_account_id;
end;
$$;

-- Supabase may grant EXECUTE directly to anon through default privileges.
revoke all on function public.reset_beta_recovery_code_from_linked_device(uuid, text) from public, anon;
grant execute on function public.reset_beta_recovery_code_from_linked_device(uuid, text) to authenticated;
