-- ============================================================
-- BWP Sales — ลบลายเซ็นอนุมัติใบเสนอราคา เพื่อขอให้เซ็นใหม่
--
-- ใช้ตอนผู้บริหารเซ็นผิด ลายเซ็นเบลอ หรือแก้ใบเสนอราคาแล้วต้องขออนุมัติใหม่
-- ลบแล้วลิงก์เดิมกลับมาใช้ได้ทันที ไม่ต้องสร้างลิงก์ใหม่
--
-- ความปลอดภัย: เฉพาะผู้ที่ล็อกอินในระบบเท่านั้น (พนักงานขาย/ผู้ดูแล)
--              ผู้ที่เปิดจากลิงก์อนุมัติอย่างเดียวจะลบไม่ได้
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

create or replace function public.reset_quote_approval(p_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  update public.quote_approvals
     set status        = 'pending',
         approver_name = null,
         approver_sig  = null,
         decided_at    = null
   where id = p_id
   returning id into v_id;

  if v_id is null then raise exception 'ไม่พบเอกสารนี้'; end if;
  return 'pending';
end $$;

-- Postgres ให้สิทธิ์ EXECUTE กับ PUBLIC อัตโนมัติตอนสร้างฟังก์ชัน ต้องถอนออกก่อน
revoke all on function public.reset_quote_approval(uuid) from public;
revoke all on function public.reset_quote_approval(uuid) from anon;
grant execute on function public.reset_quote_approval(uuid) to authenticated;

-- ตรวจผล — ต้องได้ false ทั้งคู่
select has_function_privilege('anon',   'public.reset_quote_approval(uuid)','EXECUTE') as "anon เรียกได้",
       has_function_privilege('public', 'public.reset_quote_approval(uuid)','EXECUTE') as "public เรียกได้";
