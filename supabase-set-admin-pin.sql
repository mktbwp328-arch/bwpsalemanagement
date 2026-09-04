-- ============================================================
-- BWP Sales — ตั้ง PIN ให้บัญชีผู้ดูแลระบบ (bwpsaleadmin)
--
-- เดิม: พิมพ์ชื่อผู้ดูแลแล้วเข้าได้เลย โดยรหัสจริงฝังอยู่ในโค้ดหน้าเว็บ
--       ซึ่งใครกด F12 ก็อ่านได้ จึงเท่ากับไม่มีรหัส
-- ใหม่: ผู้ดูแลต้องใส่ PIN 6 หลักเหมือนพนักงาน และ PIN เก็บอยู่ในฐานข้อมูล
--       แบบเข้ารหัส (bcrypt) ไม่มีอยู่ในโค้ดหน้าเว็บอีกต่อไป
--
-- ⚠️ ก่อน Run: แก้ 000000 ในบรรทัดล่างให้เป็น PIN 6 หลักที่ต้องการ
--    (อย่าบันทึกไฟล์นี้พร้อม PIN จริงไว้ในโปรเจกต์ที่เปิดสาธารณะ)
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → แก้ PIN → Run
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

update auth.users
   set encrypted_password = extensions.crypt('000000', extensions.gen_salt('bf')),
       email_confirmed_at = coalesce(email_confirmed_at, now()),
       updated_at         = now()
 where email = 'bwpsaleadmin@bwp.invalid';

-- ตรวจผล: ต้องได้ 1 แถว
select email                              as "บัญชีผู้ดูแล",
       (encrypted_password is not null)   as "ตั้ง PIN แล้ว",
       email_confirmed_at                 as "ยืนยันเมื่อ"
  from auth.users
 where email = 'bwpsaleadmin@bwp.invalid';

-- ============================================================
-- ถ้าขึ้น error ว่าไม่รู้จัก extensions.crypt ให้ใช้แบบนี้แทน:
--   update auth.users
--      set encrypted_password = crypt('000000', gen_salt('bf')),
--          email_confirmed_at = coalesce(email_confirmed_at, now())
--    where email = 'bwpsaleadmin@bwp.invalid';
--
-- เปลี่ยน PIN ภายหลัง: รันไฟล์นี้ใหม่ด้วยเลขชุดใหม่ได้เลย
-- ============================================================
