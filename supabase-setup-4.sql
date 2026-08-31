-- ============================================================
-- BWP Sales — ส่วนเพิ่มเติม: เก็บเบอร์โทรของพนักงาน (ใช้เข้าระบบ)
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (ครั้งเดียวพอ)
-- ============================================================

-- เก็บเบอร์โทรไว้ในโปรไฟล์ (เบอร์เดียวกับที่ใช้ล็อกอิน)
alter table public.profiles add column if not exists phone text;

-- เติมเบอร์ให้บัญชีที่มีอยู่แล้ว (ดึงจากส่วนหน้า @ ถ้าเป็นตัวเลขล้วน)
update public.profiles
   set phone = split_part(email, '@', 1)
 where phone is null
   and split_part(email, '@', 1) ~ '^0[0-9]{8,9}$';

-- ให้หน้ารายชื่อทีมแสดงเบอร์ด้วย
create or replace function public.team_list()
returns table (id uuid, name text, email text, phone text, role text,
               updated_at timestamptz, size_kb numeric)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.phone, p.role, d.updated_at,
         round((pg_column_size(d.data)/1024.0)::numeric, 1)
  from public.profiles p
  left join public.user_data d on d.user_id = p.id
  where public.is_manager()
  order by p.name;
$$;

grant execute on function public.team_list() to authenticated;

-- ============================================================
-- ดูรายชื่อพนักงานทั้งหมด (เบอร์ที่ใช้เข้าระบบ)
--   select coalesce(phone, split_part(email,'@',1)) as "เบอร์เข้าระบบ",
--          name as "ชื่อ", role as "สิทธิ์", created_at as "สร้างเมื่อ"
--   from public.profiles order by created_at;
-- ============================================================
