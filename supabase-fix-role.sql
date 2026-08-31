-- ============================================================
-- แก้บั๊ก: เปลี่ยน role จาก SQL Editor ไม่ได้ (trigger บล็อกไว้)
-- วิธีใช้: Supabase → SQL Editor → วางทั้งไฟล์ → Run
-- ============================================================

-- 1) แก้ trigger ให้ยอมรับคำสั่งจาก SQL Editor และ Edge Function
create or replace function public.lock_role()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() เป็น null = สั่งจาก SQL Editor / Edge Function (service role) -> อนุญาต
  -- มีค่า = สั่งจากหน้าเว็บ -> ต้องเป็นผู้จัดการ/ผู้ดูแลเท่านั้น
  if auth.uid() is not null
     and new.role is distinct from old.role
     and not public.is_manager() then
    new.role := old.role;
  end if;
  return new;
end $$;

-- 2) ตั้งบัญชีแอดมิน (แก้อีเมลให้ตรงกับของคุณถ้าไม่ใช่ชื่อนี้)
update public.profiles
   set role = 'admin'
 where email = 'bwpsaleadmin@bwp.invalid';

-- 3) ตรวจผล — ต้องเห็น role = admin
select email, name, role from public.profiles;
