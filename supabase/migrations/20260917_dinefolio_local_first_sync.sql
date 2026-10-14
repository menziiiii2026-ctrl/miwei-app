-- Dinefolio: private, account-owned data. Run in Supabase SQL Editor.
create table if not exists public.dish_profiles (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  normalized_name text not null,
  display_name text not null,
  category_raw_value text not null,
  latest_record_id uuid not null,
  cover_image_path text not null,
  tasting_count integer not null,
  latest_record_at timestamptz not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table if not exists public.tasting_records (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  dish_id uuid not null references public.dish_profiles(id) on delete cascade,
  ordinal integer not null,
  plate_id text not null,
  plate_version integer not null,
  food_png_path text,
  composed_png_path text,
  recorded_at timestamptz not null,
  meal_period_raw_value text,
  recipe_url_string text,
  satisfaction double precision not null,
  health double precision not null,
  flavor double precision not null,
  freshness double precision not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

alter table public.dish_profiles enable row level security;
alter table public.tasting_records enable row level security;
grant select, insert, update on public.dish_profiles to authenticated;
grant select, insert, update on public.tasting_records to authenticated;

create policy "dinefolio dish owner" on public.dish_profiles for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "dinefolio tasting owner" on public.tasting_records for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public)
values ('dinefolio-media', 'dinefolio-media', false)
on conflict (id) do nothing;

create policy "dinefolio media owner select" on storage.objects for select to authenticated
  using (bucket_id = 'dinefolio-media' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "dinefolio media owner insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'dinefolio-media' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "dinefolio media owner update" on storage.objects for update to authenticated
  using (bucket_id = 'dinefolio-media' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "dinefolio media owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'dinefolio-media' and (storage.foldername(name))[1] = (select auth.uid()::text));
