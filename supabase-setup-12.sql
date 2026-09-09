-- ============================================================
-- BWP Sales — อัปเดตข้อมูลเอกสารในลิงก์เซ็น
--
-- ปัญหาเดิม: ส่งลิงก์ให้เซ็นครั้งแรกแล้ว ถ้ากลับมาแก้ไขเอกสาร
--            คนที่เปิดลิงก์จะยังเห็นข้อมูลชุดเก่า เพราะสำเนาบนคลาวด์ไม่ถูกอัปเดต
-- แก้เป็น:   ทุกครั้งที่ฝ่ายขายกดส่งลิงก์ ระบบจะอัปเดตสำเนาให้เป็นข้อมูลล่าสุด
--            ลายเซ็นที่เซ็นไปแล้วยังอยู่ครบ ไม่ถูกล้าง
--
-- ความปลอดภัย: เฉพาะผู้ที่ล็อกอินในระบบเท่านั้น (พนักงานขาย/ผู้ดูแล)
--              ผู้ที่เปิดจากลิงก์เซ็นอย่างเดียว แก้ข้อมูลเอกสารไม่ได้
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

create or replace function public.update_doc_payload(p_id uuid, p_payload jsonb)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_at timestamptz;
begin
  update public.doc_signatures
     set payload    = p_payload,
         updated_at = now()
   where id = p_id
   returning updated_at into v_at;

  if v_at is null then raise exception 'ไม่พบเอกสารนี้'; end if;
  return v_at;
end $$;

-- Postgres ให้สิทธิ์ EXECUTE กับ PUBLIC อัตโนมัติตอนสร้างฟังก์ชัน ต้องถอนออกก่อน
revoke all on function public.update_doc_payload(uuid, jsonb) from public;
revoke all on function public.update_doc_payload(uuid, jsonb) from anon;
grant execute on function public.update_doc_payload(uuid, jsonb) to authenticated;

-- ตรวจผล — ต้องได้ false ทั้งคู่
select has_function_privilege('anon',   'public.update_doc_payload(uuid, jsonb)','EXECUTE') as "anon เรียกได้",
       has_function_privilege('public', 'public.update_doc_payload(uuid, jsonb)','EXECUTE') as "public เรียกได้";
