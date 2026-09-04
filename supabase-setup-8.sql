-- ============================================================
-- BWP Sales — ให้ผู้ดูแลระบบ/ผู้จัดการ แก้ไขข้อมูลของพนักงานได้
--
-- เดิม: ผู้จัดการดูข้อมูลของทุกคนได้ แต่แก้ไขได้เฉพาะของตัวเอง
-- ใหม่: ผู้จัดการและผู้ดูแลระบบ แก้ไขข้อมูลของทุกคนได้เหมือนเจ้าของบัญชี
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

-- อ่าน: ของตัวเอง หรือผู้จัดการอ่านได้ทุกคน (เหมือนเดิม)
drop policy if exists user_data_read on public.user_data;
create policy user_data_read on public.user_data
  for select to authenticated
  using (user_id = auth.uid() or public.is_manager());

-- เพิ่มแถวใหม่: ของตัวเอง หรือผู้จัดการสร้างแทนพนักงานได้
drop policy if exists user_data_insert on public.user_data;
create policy user_data_insert on public.user_data
  for insert to authenticated
  with check (user_id = auth.uid() or public.is_manager());

-- แก้ไข: ของตัวเอง หรือผู้จัดการแก้ของทุกคนได้
drop policy if exists user_data_update on public.user_data;
create policy user_data_update on public.user_data
  for update to authenticated
  using (user_id = auth.uid() or public.is_manager())
  with check (user_id = auth.uid() or public.is_manager());

-- ตรวจผล — ต้องเห็น 3 นโยบายนี้
select policyname as "นโยบาย", cmd as "คำสั่ง"
  from pg_policies
 where schemaname = 'public' and tablename = 'user_data'
 order by policyname;

-- ============================================================
-- ⚠️ ข้อควรรู้
--   ผู้จัดการที่เปิดข้อมูลของพนักงานค้างไว้ แล้วแก้พร้อมกับที่เจ้าตัวแก้
--   ระบบจะเก็บของคนที่บันทึกทีหลัง จึงควรแจ้งกันก่อนแก้ข้อมูลของคนอื่น
-- ============================================================
