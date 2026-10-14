-- Existing beta projects already ran the profile-management migration.  Keep
-- ID changes able to verify the 8-digit password by exposing pgcrypto to this
-- security-definer function; no account or product data is changed here.

create or replace function public.change_beta_display_name(
  p_new_display_name text,
  p_recovery_code text
)
returns text
language plpgsql
security definer
set search_path = public, auth, extensions
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

grant execute on function public.change_beta_display_name(text, text) to authenticated;
