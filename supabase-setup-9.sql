-- ============================================================
-- BWP Sales — ย้ายรูปภาพและไฟล์แนบไปเก็บใน Storage
--
-- เดิม: รูปถูกแปลงเป็นตัวหนังสือยัดรวมในข้อมูลก้อนเดียว ทำให้เกิน 4.5 MB ได้ง่าย
-- ใหม่: เก็บรูปเป็นไฟล์จริงใน Storage ข้อมูลหลักเก็บแค่ที่อยู่ไฟล์ (~100 ตัวอักษร)
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

-- ---------- 1) สร้างที่เก็บไฟล์ (แบบส่วนตัว เปิดดูได้เฉพาะคนที่ล็อกอิน) ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('attachments', 'attachments', false, 20971520)   -- จำกัดไฟล์ละ 20 MB
on conflict (id) do update
  set public = false, file_size_limit = 20971520;

-- ---------- 2) สิทธิ์การเข้าถึง ----------
-- โครงสร้างชื่อไฟล์:  <user_id ของเจ้าของข้อมูล>/<ชื่อไฟล์สุ่ม>
-- โฟลเดอร์แรกคือ user_id จึงใช้ตัดสินสิทธิ์ได้เลย

drop policy if exists bwp_att_read   on storage.objects;
drop policy if exists bwp_att_insert on storage.objects;
drop policy if exists bwp_att_update on storage.objects;
drop policy if exists bwp_att_delete on storage.objects;

-- อ่าน: ไฟล์ของตัวเอง หรือผู้จัดการ/ผู้ดูแลอ่านได้ทุกคน
create policy bwp_att_read on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

-- เพิ่มไฟล์: ลงโฟลเดอร์ของตัวเอง หรือผู้จัดการเพิ่มแทนพนักงานได้
create policy bwp_att_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'attachments'
              and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

create policy bwp_att_update on storage.objects
  for update to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

create policy bwp_att_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

-- ---------- 3) ตรวจผล ----------
select id as "ที่เก็บไฟล์", public as "เปิดสาธารณะ",
       round(file_size_limit/1024.0/1024.0) as "จำกัดไฟล์ละ (MB)"
  from storage.buckets where id = 'attachments';

select policyname as "นโยบาย", cmd as "คำสั่ง"
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects' and policyname like 'bwp_att%'
 order by policyname;

-- ============================================================
-- หลังรันเสร็จ: เข้าเว็บ → เมนูผู้ใช้ → "ย้ายรูปขึ้นที่เก็บไฟล์"
-- ระบบจะย้ายรูปเดิมทั้งหมดขึ้น Storage ให้ ทำครั้งเดียวต่อบัญชี
-- ============================================================
