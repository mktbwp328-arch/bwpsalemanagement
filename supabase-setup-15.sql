-- ============================================================
-- BWP Sales — เช็คสถานะลายเซ็นแบบเบา (ลดปริมาณเน็ตที่ใช้)
--
-- ปัญหาเดิม: หน้าเอกสารที่เปิดค้างไว้ จะถามคลาวด์ทุก 15 วินาที
--            แต่ละครั้งดึงข้อมูลเอกสารทั้งใบ + รูปลายเซ็นทุกคนกลับมา
--            ทั้งที่ส่วนใหญ่ไม่มีอะไรเปลี่ยน ทำให้ egress พุ่งเกินโควต้า
-- แก้เป็น:   ถามแค่ "สถานะ + ใครเซ็นแล้วบ้าง" ซึ่งเล็กมาก
--            แล้วค่อยดึงของจริงเฉพาะตอนมีลายเซ็นเพิ่มเข้ามา
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

-- 1) เอกสารที่ส่งลิงก์ให้เซ็น (ใบขอตัวอย่าง ใบขอเครดิต ฯลฯ)
create or replace function public.peek_doc_signature(p_id uuid)
returns table (status text, signed int, updated_at timestamptz)
language sql security definer set search_path = public stable as $$
  select d.status,
         (select count(*)::int from jsonb_object_keys(coalesce(d.sigs,'{}'::jsonb))),
         d.updated_at
    from public.doc_signatures d
   where d.id = p_id;
$$;

-- 2) ใบเสนอราคาที่ส่งให้ผู้บริหารอนุมัติ
create or replace function public.peek_quote_approval(p_id uuid)
returns table (status text, updated_at timestamptz)
language sql security definer set search_path = public stable as $$
  select q.status, q.decided_at
    from public.quote_approvals q
   where q.id = p_id;
$$;

-- Postgres ให้สิทธิ์ EXECUTE กับ PUBLIC อัตโนมัติตอนสร้างฟังก์ชัน ต้องถอนออกก่อน
revoke all on function public.peek_doc_signature(uuid) from public;
revoke all on function public.peek_doc_signature(uuid) from anon;
grant execute on function public.peek_doc_signature(uuid) to authenticated;

revoke all on function public.peek_quote_approval(uuid) from public;
revoke all on function public.peek_quote_approval(uuid) from anon;
grant execute on function public.peek_quote_approval(uuid) to authenticated;

-- ตรวจผล — ต้องได้ false ทั้งหมด
select has_function_privilege('anon',  'public.peek_doc_signature(uuid)','EXECUTE') as "anon เรียกได้ (เอกสาร)",
       has_function_privilege('public','public.peek_doc_signature(uuid)','EXECUTE') as "public เรียกได้ (เอกสาร)",
       has_function_privilege('anon',  'public.peek_quote_approval(uuid)','EXECUTE') as "anon เรียกได้ (อนุมัติ)",
       has_function_privilege('public','public.peek_quote_approval(uuid)','EXECUTE') as "public เรียกได้ (อนุมัติ)";
