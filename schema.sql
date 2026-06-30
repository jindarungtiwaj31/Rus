-- RMUTSB Receipt App - Supabase setup
-- Version: no-email login
-- Admin login on the web page: Username = admin, Password = 9999
-- User login on the web page: 4-digit code created by Admin

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'user')),
  display_name text not null,
  staff_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_state (
  id text primary key default 'main',
  data jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.app_state enable row level security;

drop policy if exists "authenticated can read profiles" on public.profiles;
create policy "authenticated can read profiles"
on public.profiles
for select
to authenticated
using (true);

drop policy if exists "authenticated can read app state" on public.app_state;
create policy "authenticated can read app state"
on public.app_state
for select
to authenticated
using (true);

drop policy if exists "anon can read app state" on public.app_state;
create policy "anon can read app state"
on public.app_state
for select
to anon
using (id = 'main');

drop policy if exists "authenticated can insert app state" on public.app_state;
create policy "authenticated can insert app state"
on public.app_state
for insert
to authenticated
with check (true);

drop policy if exists "authenticated can update app state" on public.app_state;
create policy "authenticated can update app state"
on public.app_state
for update
to authenticated
using (true)
with check (true);

insert into public.app_state (id, data)
values (
  'main',
  '{
    "admin": {"username": "admin", "password": "9999"},
    "users": [],
    "titles": ["นาย", "นาง", "นางสาว", "ดร.", "ผู้ช่วยศาสตราจารย์"],
    "paymentItems": ["ค่าลงทะเบียน", "ค่าธรรมเนียมการศึกษา", "ค่าบำรุงการศึกษา", "ค่าปรับ"],
    "projects": [
      {"name": "โครงการบริการวิชาการ", "active": true},
      {"name": "โครงการอบรมระยะสั้น", "active": true},
      {"name": "ศูนย์พระนครศรีอยุธยา หันตรา", "active": true},
      {"name": "ไม่ระบุโครงการ", "active": true}
    ],
    "payerBanks": ["ธนาคารกรุงไทย", "ธนาคารไทยพาณิชย์", "ธนาคารกสิกรไทย", "ธนาคารกรุงเทพ"],
    "universityBanks": [
      {"bank": "ธนาคารกรุงไทย", "accountName": "มหาวิทยาลัยเทคโนโลยีราชมงคลสุวรรณภูมิ", "accountNo": "123-4-56789-0"},
      {"bank": "ธนาคารกรุงเทพ", "accountName": "RMUTSB", "accountNo": "987-6-54321-0"}
    ],
    "books": [
      {"bookNo": "2567A", "start": 1, "end": 500, "latest": 0, "active": true, "closed": false}
    ],
    "receipts": []
  }'::jsonb
)
on conflict (id) do update
set data = app_state.data || jsonb_build_object('admin', jsonb_build_object('username', 'admin', 'password', '9999'));

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists app_state_touch_updated_at on public.app_state;
create trigger app_state_touch_updated_at
before update on public.app_state
for each row execute function public.touch_updated_at();

create or replace function public.is_fixed_admin(p_username text, p_password text)
returns boolean
language sql
stable
as $$
  select coalesce(trim(p_username), '') = 'admin' and coalesce(p_password, '') = '9999';
$$;

create or replace function public.get_app_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state jsonb;
begin
  select data into v_state
  from public.app_state
  where id = 'main';

  if v_state is null then
    raise exception 'ยังไม่ได้สร้าง app_state ใน Supabase';
  end if;

  return v_state;
end;
$$;

create or replace function public.save_app_state(p_username text, p_password text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state jsonb;
begin
  if not public.is_fixed_admin(p_username, p_password) then
    raise exception 'Username หรือ Password ไม่ถูกต้อง';
  end if;

  v_state := coalesce(p_data, '{}'::jsonb)
    || jsonb_build_object('admin', jsonb_build_object('username', 'admin', 'password', '9999'));

  insert into public.app_state (id, data)
  values ('main', v_state)
  on conflict (id) do update
  set data = excluded.data,
      updated_at = now();

  return jsonb_build_object('state', v_state);
end;
$$;

drop function if exists public.issue_receipt(text, jsonb);
create or replace function public.issue_receipt(p_user_code text, p_receipt jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state jsonb;
  v_books jsonb;
  v_book jsonb;
  v_receipts jsonb;
  v_index integer;
  v_active_index integer := null;
  v_start integer;
  v_end integer;
  v_latest integer;
  v_next integer;
  v_receipt jsonb;
  v_user_found boolean := false;
begin
  select data into v_state
  from public.app_state
  where id = 'main'
  for update;

  if v_state is null then
    raise exception 'ยังไม่ได้สร้าง app_state ใน Supabase';
  end if;

  select exists (
    select 1
    from jsonb_array_elements(coalesce(v_state->'users', '[]'::jsonb)) as u
    where u->>'code' = coalesce(trim(p_user_code), '')
  ) into v_user_found;

  if not v_user_found then
    raise exception 'ไม่พบรหัสผู้ใช้งาน';
  end if;

  v_books := coalesce(v_state->'books', '[]'::jsonb);

  if jsonb_array_length(v_books) = 0 then
    raise exception 'ยังไม่ได้กำหนดเล่มใบเสร็จ';
  end if;

  for v_index in 0..jsonb_array_length(v_books) - 1 loop
    v_book := v_books->v_index;
    if coalesce((v_book->>'active')::boolean, false)
       and not coalesce((v_book->>'closed')::boolean, false) then
      v_active_index := v_index;
      exit;
    end if;
  end loop;

  if v_active_index is null then
    raise exception 'ยังไม่มีเล่มใบเสร็จที่เปิดใช้งาน';
  end if;

  v_book := v_books->v_active_index;
  v_start := greatest(1, coalesce((v_book->>'start')::integer, 1));
  v_end := least(500, greatest(v_start, coalesce((v_book->>'end')::integer, 500)));
  v_latest := greatest(0, coalesce((v_book->>'latest')::integer, 0));
  v_next := greatest(v_start, v_latest + 1);

  if v_next > v_end or v_next > 500 then
    raise exception 'เล่มนี้ออกเลขครบแล้ว กรุณาเลือกเล่มใหม่';
  end if;

  v_books := jsonb_set(v_books, array[v_active_index::text, 'latest'], to_jsonb(v_next), false);
  v_receipt := p_receipt
    || jsonb_build_object(
      'bookNo', v_book->>'bookNo',
      'receiptNo', lpad(v_next::text, 3, '0')
    );

  v_receipts := coalesce(v_state->'receipts', '[]'::jsonb) || jsonb_build_array(v_receipt);
  v_state := jsonb_set(v_state, '{books}', v_books, true);
  v_state := jsonb_set(v_state, '{receipts}', v_receipts, true);
  v_state := jsonb_set(v_state, '{admin}', '{"username":"admin","password":"9999"}'::jsonb, true);

  update public.app_state
  set data = v_state,
      updated_at = now()
  where id = 'main';

  return jsonb_build_object('receipt', v_receipt, 'state', v_state);
end;
$$;

drop function if exists public.cancel_receipt(text, text, text, text, text);
create or replace function public.cancel_receipt(
  p_receipt_id text,
  p_reason text,
  p_actor_code text default '',
  p_admin_username text default '',
  p_admin_password text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state jsonb;
  v_receipts jsonb;
  v_receipt jsonb;
  v_index integer;
  v_found boolean := false;
  v_allowed boolean := false;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'กรุณาระบุหมายเหตุการยกเลิก';
  end if;

  select data into v_state
  from public.app_state
  where id = 'main'
  for update;

  if v_state is null then
    raise exception 'ยังไม่ได้สร้าง app_state ใน Supabase';
  end if;

  v_allowed := public.is_fixed_admin(p_admin_username, p_admin_password)
    or exists (
      select 1
      from jsonb_array_elements(coalesce(v_state->'users', '[]'::jsonb)) as u
      where u->>'code' = coalesce(trim(p_actor_code), '')
    );

  if not v_allowed then
    raise exception 'ไม่มีสิทธิ์ยกเลิกใบเสร็จ';
  end if;

  v_receipts := coalesce(v_state->'receipts', '[]'::jsonb);

  if jsonb_array_length(v_receipts) = 0 then
    raise exception 'ไม่พบใบเสร็จในระบบ';
  end if;

  for v_index in 0..jsonb_array_length(v_receipts) - 1 loop
    v_receipt := v_receipts->v_index;
    if v_receipt->>'id' = p_receipt_id then
      v_receipt := v_receipt || jsonb_build_object('status', 'ยกเลิก', 'cancelReason', p_reason);
      v_receipts := jsonb_set(v_receipts, array[v_index::text], v_receipt, false);
      v_found := true;
      exit;
    end if;
  end loop;

  if not v_found then
    raise exception 'ไม่พบใบเสร็จที่ต้องการยกเลิก';
  end if;

  v_state := jsonb_set(v_state, '{receipts}', v_receipts, true);
  v_state := jsonb_set(v_state, '{admin}', '{"username":"admin","password":"9999"}'::jsonb, true);

  update public.app_state
  set data = v_state,
      updated_at = now()
  where id = 'main';

  return jsonb_build_object('state', v_state);
end;
$$;

grant execute on function public.get_app_state() to anon, authenticated;
grant execute on function public.save_app_state(text, text, jsonb) to anon, authenticated;
grant execute on function public.issue_receipt(text, jsonb) to anon, authenticated;
grant execute on function public.cancel_receipt(text, text, text, text, text) to anon, authenticated;

do $$
begin
  alter publication supabase_realtime add table public.app_state;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
