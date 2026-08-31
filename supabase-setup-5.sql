-- ============================================================
-- BWP Sales — ทะเบียนพนักงาน + เข้าระบบด้วยเบอร์ + PIN
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
--
-- หลักการ: เบอร์ที่ไม่มีในทะเบียนพนักงาน จะสมัคร/ตั้ง PIN ไม่ได้เลย
--          บังคับที่ฐานข้อมูล ไม่ใช่แค่ที่หน้าเว็บ จึงหลบเลี่ยงไม่ได้
-- ============================================================

-- ---------- 1) ทะเบียนพนักงาน ----------
create table if not exists public.employees (
  id         uuid primary key default gen_random_uuid(),
  phone      text not null unique,          -- เบอร์ตัวเลขล้วน ใช้เข้าระบบ
  name       text,
  position   text,
  role       text not null default 'sales' check (role in ('sales','manager','admin')),
  active     boolean not null default true,
  note       text,
  created_at timestamptz not null default now()
);
alter table public.employees enable row level security;

-- เฉพาะผู้จัดการ/ผู้ดูแลเท่านั้นที่ดูและแก้ทะเบียนได้
drop policy if exists employees_all on public.employees;
create policy employees_all on public.employees
  for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- ---------- 2) ด่านตรวจตอนสมัคร/ตั้ง PIN ----------
-- บัญชีผู้ดูแลระบบที่ยกเว้นด่านนี้ (สร้างจาก Dashboard)
create or replace function public.is_system_account(p_local text)
returns boolean language sql immutable as $$
  select p_local in ('bwpsaleadmin');
$$;

create or replace function public.check_employee_signup()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_local text; v_ok boolean;
begin
  v_local := split_part(new.email, '@', 1);

  if public.is_system_account(v_local) then
    return new;                                   -- บัญชีผู้ดูแล ผ่านได้
  end if;

  select exists(select 1 from public.employees
                 where phone = v_local and active) into v_ok;
  if not v_ok then
    raise exception 'เบอร์นี้ไม่มีในทะเบียนพนักงาน กรุณาติดต่อผู้ดูแลระบบ'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_signup_check on auth.users;
create trigger on_auth_user_signup_check
  before insert on auth.users
  for each row execute function public.check_employee_signup();

-- ---------- 3) สร้างโปรไฟล์โดยดึงชื่อ/สิทธิ์จากทะเบียนพนักงาน ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_local text; v_emp public.employees%rowtype;
begin
  v_local := split_part(new.email, '@', 1);
  select * into v_emp from public.employees where phone = v_local;

  insert into public.profiles (id, email, name, phone, role)
  values (new.id, new.email,
          coalesce(nullif(new.raw_user_meta_data->>'name',''), v_emp.name, v_local),
          v_local,
          case when public.is_system_account(v_local) then 'admin'
               else coalesce(v_emp.role, 'sales') end)
  on conflict (id) do nothing;
  return new;
end $$;

-- ---------- 4) ให้แอดมินเห็นว่าใครตั้ง PIN แล้วบ้าง ----------
drop function if exists public.employee_list();
create or replace function public.employee_list()
returns table (id uuid, phone text, name text, position text, role text,
               active boolean, note text, has_pin boolean, last_saved timestamptz)
language sql stable security definer set search_path = public as $$
  select e.id, e.phone, e.name, e.position, e.role, e.active, e.note,
         (p.id is not null) as has_pin,
         d.updated_at
  from public.employees e
  left join public.profiles p on p.phone = e.phone
  left join public.user_data d on d.user_id = p.id
  where public.is_manager()
  order by e.active desc, e.name nulls last, e.phone;
$$;
grant execute on function public.employee_list() to authenticated;

-- ---------- 5) เติมทะเบียนจากบัญชีที่มีอยู่แล้ว (ถ้ามี) ----------
insert into public.employees (phone, name, role)
select p.phone, p.name, p.role
from public.profiles p
where p.phone is not null
  and not public.is_system_account(p.phone)
  and not exists (select 1 from public.employees e where e.phone = p.phone)
on conflict (phone) do nothing;

-- ============================================================
-- ⚠️ ต้องตั้งค่าใน Supabase อีก 1 จุด ไม่งั้นพนักงานตั้ง PIN ไม่ได้:
--    Authentication → Sign In / Providers → Email → ปิด "Confirm email" → Save
--
-- คำสั่งที่ใช้บ่อย
--   ดูทะเบียนพนักงาน:      select phone, name, position, role, active from public.employees;
--   ปิดใช้งานพนักงาน:      update public.employees set active=false where phone='0812345678';
--   ให้พนักงานตั้ง PIN ใหม่: delete from auth.users where email='0812345678@bwp.invalid';
--                          (ทะเบียนยังอยู่ พนักงานเข้าเว็บแล้วตั้ง PIN ใหม่ได้เลย)
-- ============================================================
