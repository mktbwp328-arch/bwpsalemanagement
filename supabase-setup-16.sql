-- ============================================================
-- BWP Sales — ซ่อมสิทธิ์ที่เก็บไฟล์ (Storage) ในโปรเจกต์ใหม่
--
-- อาการ: ย้ายลายเซ็น/ไฟล์แนบขึ้นที่เก็บไฟล์ไม่ได้
--        "new row violates row-level security policy"
-- สาเหตุ: ตอนย้ายฐานข้อมูล กฎสิทธิ์ของที่เก็บไฟล์อาจสร้างไม่ครบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- รันซ้ำได้ ไม่กระทบไฟล์หรือข้อมูลที่มีอยู่
-- ============================================================

-- ---------- 1) ที่เก็บไฟล์ (แบบส่วนตัว) ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('attachments', 'attachments', false, 20971520)
on conflict (id) do update set public = false, file_size_limit = 20971520;

-- ---------- 2) ฟังก์ชันเช็กผู้จัดการ/ผู้ดูแล ----------
create or replace function public.is_manager()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('manager','admin'));
$$;
grant execute on function public.is_manager() to authenticated;

-- ---------- 3) กฎสิทธิ์ของไฟล์ ----------
-- ชื่อไฟล์: <user_id ของเจ้าของข้อมูล>/...  เจ้าของจัดการไฟล์ของตัวเองได้
-- ผู้จัดการ/ผู้ดูแลจัดการไฟล์ของทุกคนได้ (ใช้ตอนเปิดดูข้อมูลลูกทีม)
drop policy if exists bwp_att_read   on storage.objects;
drop policy if exists bwp_att_insert on storage.objects;
drop policy if exists bwp_att_update on storage.objects;
drop policy if exists bwp_att_delete on storage.objects;

create policy bwp_att_read on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

create policy bwp_att_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'attachments'
              and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

create policy bwp_att_update on storage.objects
  for update to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()))
  with check (bucket_id = 'attachments'
              and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

create policy bwp_att_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager()));

-- ---------- 4) ตรวจผล ----------
-- ควรเห็น 4 แถว: bwp_att_delete, bwp_att_insert, bwp_att_read, bwp_att_update
select policyname as "กฎสิทธิ์", cmd as "คำสั่ง"
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects' and policyname like 'bwp_att%'
 order by policyname;

-- บัญชีที่เป็นผู้จัดการ/ผู้ดูแล (บัญชีแอดมินต้องอยู่ในรายการนี้)
select u.email as "บัญชี", p.role as "บทบาท"
  from public.profiles p join auth.users u on u.id = p.id
 where p.role in ('manager','admin');
