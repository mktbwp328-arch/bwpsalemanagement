-- ============================================================
-- BWP Sales — ล้างข้อมูลงานขายของพนักงานทุกคน (เริ่มระบบใหม่จากศูนย์)
--
-- ลบ:   ลูกค้า · เอกสารการขายทุกชนิด · PO ลูกค้า · ใบเสร็จรับเงิน
--       รวมถึงลิงก์เซ็นเอกสารที่ค้างอยู่
-- เก็บ: คลังรหัสสินค้า (ตาราง products) · ทะเบียนพนักงาน · บัญชีผู้ใช้และ PIN
--       หัวกระดาษบริษัท · ตรารับรอง · การตั้งค่า
--
-- ⚠️ กู้คืนไม่ได้ ทำก่อนเริ่มใช้งานจริงเท่านั้น
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

-- ---------- 1) ดูก่อนว่ามีอะไรจะถูกลบบ้าง ----------
select p.name                                   as "พนักงาน",
       p.phone                                  as "เบอร์",
       jsonb_array_length(coalesce(d.data->'customers','[]'::jsonb)) as "ลูกค้า",
       jsonb_array_length(coalesce(d.data->'docs','[]'::jsonb))      as "เอกสาร",
       jsonb_array_length(coalesce(d.data->'pos','[]'::jsonb))       as "PO",
       jsonb_array_length(coalesce(d.data->'receipts','[]'::jsonb))  as "ใบเสร็จ"
  from public.user_data d
  left join public.profiles p on p.id = d.user_id
 order by p.name nulls last;

-- ---------- 2) ล้างข้อมูลงานขาย แต่เก็บหัวกระดาษและการตั้งค่าไว้ ----------
update public.user_data
   set data = jsonb_build_object(
         'customers', '[]'::jsonb,
         'docs',      '[]'::jsonb,
         'pos',       '[]'::jsonb,
         'receipts',  '[]'::jsonb,
         'logo',      coalesce(data->'logo',    'null'::jsonb),
         'cert',      coalesce(data->'cert',    'null'::jsonb),
         'company',   coalesce(data->'company', '{}'::jsonb),
         'sb',        coalesce(data->'sb',      'null'::jsonb)
       ),
       updated_at = now();

-- ---------- 3) ล้างลิงก์เซ็นเอกสารที่ค้างอยู่ ----------
delete from public.doc_signatures;
delete from public.quote_approvals;

-- ---------- 4) ตรวจผล — ทุกช่องต้องเป็น 0 และ products ต้องยังอยู่ครบ ----------
select p.name as "พนักงาน",
       jsonb_array_length(coalesce(d.data->'customers','[]'::jsonb)) as "ลูกค้า",
       jsonb_array_length(coalesce(d.data->'docs','[]'::jsonb))      as "เอกสาร",
       jsonb_array_length(coalesce(d.data->'pos','[]'::jsonb))       as "PO",
       jsonb_array_length(coalesce(d.data->'receipts','[]'::jsonb))  as "ใบเสร็จ"
  from public.user_data d
  left join public.profiles p on p.id = d.user_id
 order by p.name nulls last;

select count(*) as "รหัสสินค้าที่ยังอยู่ในคลัง" from public.products;

-- ============================================================
-- ⚠️ หลังรันเสร็จ ให้ทุกคนที่เปิดเว็บค้างไว้กด Ctrl+F5 หนึ่งครั้ง
--    ถ้าไม่รีเฟรช ข้อมูลเก่าที่ค้างในเครื่องอาจถูกบันทึกกลับขึ้นคลาวด์อีก
-- ============================================================
