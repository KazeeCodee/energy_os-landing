-- Landing forms backend: newsletter, contact, trial signup metadata.

-- 1. Newsletter subscribers
create table if not exists public.newsletter_subscribers (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  source text,
  created_at timestamptz not null default now()
);

alter table public.newsletter_subscribers enable row level security;

drop policy if exists "newsletter_anon_insert" on public.newsletter_subscribers;
create policy "newsletter_anon_insert"
  on public.newsletter_subscribers
  for insert
  to anon, authenticated
  with check (true);

create index if not exists idx_newsletter_subscribers_email
  on public.newsletter_subscribers(email);

-- 2. Contact messages: extra fields used by ContactForm.astro
alter table public.contact_messages
  add column if not exists tipo_empresa text,
  add column if not exists rol text;

-- 3. User profiles: trial signup metadata
alter table public.user_profiles
  add column if not exists company text,
  add column if not exists tipo_empresa text,
  add column if not exists cuit text,
  add column if not exists industria text,
  add column if not exists demanda_kw text,
  add column if not exists telefono text,
  add column if not exists rol text;

alter table public.user_profiles
  drop constraint if exists user_profiles_cuit_check;

alter table public.user_profiles
  add constraint user_profiles_cuit_check
  check (cuit is null or cuit ~ '^[0-9]{11}$');

-- 4. Trigger: copy auth.users.raw_user_meta_data into user_profiles on signup.
--    handle_new_user issues INSERT INTO user_profiles; this BEFORE trigger
--    fires during that INSERT and pulls the metadata that auth.signUp
--    stored in options.data.
--
--    tipo_empresa (form value) maps to role (system-level enum). The job
--    role from the form lands in the separate `rol` column.
create or replace function public.apply_landing_metadata_to_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  meta jsonb;
  v_cuit text;
  v_tipo text;
  v_role text;
begin
  select coalesce(raw_user_meta_data, '{}'::jsonb) into meta
  from auth.users where id = new.user_id;

  if meta is null or meta = '{}'::jsonb then
    return new;
  end if;

  v_cuit := nullif(regexp_replace(coalesce(meta->>'cuit', ''), '[^0-9]', '', 'g'), '');
  if v_cuit is not null and length(v_cuit) <> 11 then
    v_cuit := null;
  end if;

  v_tipo := lower(coalesce(meta->>'tipo_empresa', ''));
  v_role := case v_tipo
    when 'gran_usuario'    then 'gran_consumidor'
    when 'gudi'            then 'gran_consumidor'
    when 'comercializador' then 'comercializador'
    when 'generador'       then 'generador'
    when 'distribuidor'    then 'distribuidor'
    when 'analista'        then 'analista'
    else null
  end;

  new.full_name      := coalesce(meta->>'full_name', new.full_name);
  new.role           := coalesce(v_role, new.role);
  new.rol            := coalesce(meta->>'rol', new.rol);
  new.company        := coalesce(meta->>'company', new.company);
  new.tipo_empresa   := coalesce(meta->>'tipo_empresa', new.tipo_empresa);
  new.cuit           := coalesce(v_cuit, new.cuit);
  new.industria      := coalesce(meta->>'industria', new.industria);
  new.demanda_kw     := coalesce(meta->>'demanda_kw', new.demanda_kw);
  new.telefono       := coalesce(meta->>'telefono', new.telefono);

  if (meta->>'accepts_terms')::boolean is true and new.accepted_terms_at is null then
    new.accepted_terms_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists landing_metadata_to_profile on public.user_profiles;
create trigger landing_metadata_to_profile
  before insert on public.user_profiles
  for each row execute function public.apply_landing_metadata_to_profile();
