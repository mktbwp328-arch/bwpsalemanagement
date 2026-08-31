-- ============================================================
-- BWP Sales — ระบบผู้ใช้หลายคน (ล็อกอิน + ข้อมูลบนคลาวด์ แยกตามเซล)
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (ครั้งเดียวพอ)
--
-- ⚠️ ก่อนใช้งานจริง ต้องตั้งค่าอีกจุด:
--    Authentication → Sign In / Providers → Email → ปิด "Confirm email"
--    (ถ้าไม่ปิด ผู้ใช้ต้องกดยืนยันจากอีเมลก่อนถึงจะเข้าระบบได้)
-- ============================================================

-- ---------- 1) โปรไฟล์ผู้ใช้ + สิทธิ์ ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  email      text,
  name       text,
  role       text not null default 'sales' check (role in ('sales','manager','admin')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- สร้างโปรไฟล์อัตโนมัติเมื่อสมัครสมาชิก
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email,
          coalesce(nullif(new.raw_user_meta_data->>'name',''), split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- เช็คว่าเป็นหัวหน้า/ผู้ดูแลไหม (security definer กัน RLS วนซ้ำ)
create or replace function public.is_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('manager','admin'));
$$;

-- ---------- 2) ข้อมูลงานขายของแต่ละคน ----------
create table if not exists public.user_data (
  user_id    uuid primary key references auth.users on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_data enable row level security;

-- ---------- 3) สิทธิ์การเข้าถึง ----------
-- โปรไฟล์: เห็นของตัวเอง / หัวหน้าเห็นทุกคน
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_manager());

-- แก้ชื่อตัวเองได้ (เปลี่ยน role เองไม่ได้ — กันด้วย trigger ด้านล่าง)
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create or replace function public.lock_role()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role and not public.is_manager() then
    new.role := old.role;      -- เปลี่ยนสิทธิ์ตัวเองไม่ได้
  end if;
  return new;
end $$;
drop trigger if exists profiles_lock_role on public.profiles;
create trigger profiles_lock_role before update on public.profiles
  for each row execute function public.lock_role();

-- ข้อมูลงานขาย: เจ้าของอ่าน/เขียนได้ หัวหน้าอ่านได้ทุกคน (แก้ของคนอื่นไม่ได้)
drop policy if exists user_data_read on public.user_data;
create policy user_data_read on public.user_data
  for select to authenticated
  using (user_id = auth.uid() or public.is_manager());

drop policy if exists user_data_insert on public.user_data;
create policy user_data_insert on public.user_data
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_data_update on public.user_data;
create policy user_data_update on public.user_data
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- 4) รายชื่อทีม (ให้หัวหน้าเลือกดูข้อมูลของแต่ละคน) ----------
create or replace function public.team_list()
returns table (id uuid, name text, email text, role text, updated_at timestamptz, size_kb numeric)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.role, d.updated_at,
         round((pg_column_size(d.data)/1024.0)::numeric, 1)
  from public.profiles p
  left join public.user_data d on d.user_id = p.id
  where public.is_manager()
  order by p.name;
$$;

grant execute on function public.team_list() to authenticated;
grant execute on function public.is_manager() to authenticated;

-- ============================================================
-- ตั้งคนแรกให้เป็นผู้จัดการ (แก้อีเมลให้ตรงกับที่สมัคร แล้วรันบรรทัดนี้)
--   update public.profiles set role='admin' where email='bestworld.bwp328@gmail.com';
-- ดูรายชื่อผู้ใช้ทั้งหมด:
--   select email, name, role from public.profiles order by created_at;
-- ============================================================
