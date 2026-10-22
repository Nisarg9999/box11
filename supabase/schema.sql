-- Box 11 Trade Manager: run ONCE in Supabase → SQL Editor (safe to re-run).

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text, username text, full_name text,
  role text not null default 'user' check (role in ('admin','user')),
  permissions jsonb not null default '{}'::jsonb,
  disabled boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists disabled boolean not null default false;
create unique index if not exists profiles_username_key on public.profiles (lower(username));

create table if not exists public.business_data (
  key text primary key, value jsonb not null, version int not null default 0
);
insert into public.business_data (key, value) values
  ('products','[]'),('shipments','[]'),('sales','[]'),('expenses','[]'),('settings','{}')
on conflict (key) do nothing;

alter table public.profiles enable row level security;
alter table public.business_data enable row level security;   -- no policies: only the functions below can touch it

create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin' and not disabled)
$$;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using (id = auth.uid() or public.is_admin());

-- The FIRST account created becomes admin; everyone after starts as a normal user with no access.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, username, role)
  values (new.id, new.email, new.raw_user_meta_data->>'username',
          case when exists (select 1 from profiles where role = 'admin') then 'user' else 'admin' end)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.can_access(keyname text, need_edit boolean) returns boolean
language plpgsql security definer stable set search_path = public as $$
declare p profiles; tabs text[]; t text;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null or p.disabled then return false; end if;
  if p.role = 'admin' then return true; end if;
  tabs := case keyname
    when 'products'  then case when need_edit then array['products']  else array['products','shipments','sales','stock','dashboard','reports','expenses','backup'] end
    when 'shipments' then case when need_edit then array['shipments'] else array['shipments','sales','stock','dashboard','reports','expenses','backup'] end
    when 'sales'     then case when need_edit then array['sales']     else array['sales','stock','dashboard','reports','expenses','backup'] end
    when 'expenses'  then case when need_edit then array['expenses']  else array['expenses','dashboard','reports','backup'] end
    else                  case when need_edit then array['settings','customize'] else array['dashboard','products','shipments','stock','sales','expenses','reports','settings','customize','backup'] end
  end;
  foreach t in array tabs loop
    if p.permissions->>t = 'edit' or (not need_edit and p.permissions->>t = 'view') then return true; end if;
  end loop;
  return false;
end $$;

create or replace function public.get_business_data() returns jsonb
language plpgsql security definer set search_path = public as $$
declare p profiles; d jsonb := '{}'; v jsonb := '{}'; r record;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null or p.disabled then raise exception 'NOT_ALLOWED'; end if;
  for r in select key, value, version from business_data loop
    v := v || jsonb_build_object(r.key, r.version);
    d := d || jsonb_build_object(r.key, case when can_access(r.key, false) then r.value
                                             when r.key = 'settings' then '{}'::jsonb else '[]'::jsonb end);
  end loop;
  return jsonb_build_object('role', p.role, 'email', coalesce(p.username, p.email),
                            'permissions', p.permissions, 'data', d, 'versions', v);
end $$;

create or replace function public.save_business_data(patch jsonb, base_versions jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; cur int; v jsonb;
begin
  for k in select jsonb_object_keys(patch) loop
    if not exists (select 1 from business_data where key = k) or not can_access(k, true) then
      raise exception 'NOT_ALLOWED';
    end if;
    select version into cur from business_data where key = k for update;
    if cur <> coalesce((base_versions->>k)::int, 0) then raise exception 'VERSION_CONFLICT'; end if;
    update business_data set value = patch->k, version = version + 1 where key = k;
  end loop;
  select coalesce(jsonb_object_agg(key, version), '{}') into v from business_data;
  return v;
end $$;

create or replace function public.admin_set_access(target uuid, new_role text, new_perms jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'NOT_ALLOWED'; end if;
  update profiles set role = new_role, permissions = new_perms where id = target;
end $$;
