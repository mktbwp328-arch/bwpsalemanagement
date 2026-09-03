-- ============================================================
-- BWP Sales — ลบบัญชีพนักงานออกจากระบบ
--
-- ตัวอย่างนี้ลบเบอร์ 0859735367 (บัญชีทดสอบ)
-- ถ้าจะลบคนอื่น ให้แก้เบอร์ในบรรทัดที่มี v_phone ทั้ง 2 จุด
--
-- ⚠️ ลบแล้วกู้คืนไม่ได้ — ข้อมูลงานขายของบัญชีนี้จะหายไปด้วย
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

-- ---------- 1) ดูก่อนว่าจะลบอะไรบ้าง ----------
select p.phone                                as "เบอร์",
       p.name                                 as "ชื่อ",
       p.role                                 as "สิทธิ์",
       jsonb_array_length(coalesce(d.data->'customers','[]'::jsonb)) as "ลูกค้า",
       jsonb_array_length(coalesce(d.data->'docs','[]'::jsonb))      as "เอกสาร",
       jsonb_array_length(coalesce(d.data->'pos','[]'::jsonb))       as "PO",
       jsonb_array_length(coalesce(d.data->'receipts','[]'::jsonb))  as "ใบเสร็จ"
  from public.profiles p
  left join public.user_data d on d.user_id = p.id
 where p.phone = '0859735367';

-- ---------- 2) ลบบัญชีเข้าระบบ (โปรไฟล์และข้อมูลงานขายลบตามอัตโนมัติ) ----------
delete from auth.users where email = '0859735367@bwp.invalid';

-- ---------- 3) ลบออกจากทะเบียนพนักงาน ----------
-- (ถ้าอยากเก็บชื่อไว้ในทะเบียนแต่ห้ามเข้าระบบ ให้ใช้บรรทัด update แทน)
delete from public.employees where phone = '0859735367';
-- update public.employees set active = false where phone = '0859735367';

-- ---------- 4) ตรวจผล — ทั้ง 2 ตารางต้องไม่เหลือเบอร์นี้ ----------
select count(*) as "เหลือในบัญชีเข้าระบบ" from auth.users  where email = '0859735367@bwp.invalid';
select count(*) as "เหลือในทะเบียนพนักงาน" from public.employees where phone = '0859735367';

select phone as "เบอร์", name as "ชื่อ", role as "สิทธิ์" from public.profiles order by name nulls last;
