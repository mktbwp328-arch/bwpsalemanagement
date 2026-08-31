-- ============================================================
-- ตั้งรหัสผ่านบัญชีแอดมินให้ตรงกับค่าคงที่ที่แอปใช้
-- (หน้า Dashboard ไม่มีปุ่มตั้งรหัสตรง ๆ มีแต่ส่งอีเมลรีเซ็ต ซึ่งใช้ไม่ได้
--  เพราะ @bwp.invalid ไม่ใช่อีเมลจริง จึงต้องตั้งผ่าน SQL)
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

update auth.users
   set encrypted_password = extensions.crypt('bwp-sale-admin-2569-open-7f3ac91d',
                                             extensions.gen_salt('bf')),
       email_confirmed_at = coalesce(email_confirmed_at, now()),
       updated_at         = now()
 where email = 'bwpsaleadmin@bwp.invalid';

-- ตรวจผล: ต้องได้ 1 แถว และ confirmed ต้องไม่ว่าง
select email,
       (encrypted_password is not null) as "ตั้งรหัสแล้ว",
       email_confirmed_at as "ยืนยันเมื่อ"
  from auth.users
 where email = 'bwpsaleadmin@bwp.invalid';

-- ============================================================
-- ถ้าขึ้น error ว่าไม่รู้จัก extensions.crypt ให้ลองแบบไม่มี extensions. แทน:
--   update auth.users
--      set encrypted_password = crypt('bwp-sale-admin-2569-open-7f3ac91d', gen_salt('bf')),
--          email_confirmed_at = coalesce(email_confirmed_at, now())
--    where email = 'bwpsaleadmin@bwp.invalid';
-- ============================================================
