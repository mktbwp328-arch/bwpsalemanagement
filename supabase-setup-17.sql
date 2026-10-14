-- ============================================================
-- BWP Sales — ค้นผลอนุมัติใบเสนอราคาจากเลขที่เอกสาร
--
-- อาการ: ผู้บริหารเซ็นแล้ว แต่ลายเซ็นไม่เข้าใบเสนอราคา
-- สาเหตุ: กด "ส่งลิงก์ให้ผู้บริหารเซ็น" หลายครั้ง แต่ละครั้งได้ลิงก์ใหม่
--         ผู้บริหารเซ็นลิงก์เก่า แต่โปรแกรมเฝ้าดูแค่ลิงก์ล่าสุด
-- แก้:  ให้โปรแกรมค้นทุกลิงก์ของเลขที่เอกสารนั้น เจอที่เซ็นแล้วก็ดึงลายเซ็นมาใส่
--
-- เรียกได้เฉพาะคนที่เข้าระบบแล้ว (คนเปิดลิงก์เซ็นเรียกไม่ได้)
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (รันซ้ำได้)
-- ============================================================

create or replace function public.find_quote_approvals(p_doc_no text)
returns table (id uuid, status text, customer text, approver_name text,
               approver_sig text, decided_at timestamptz, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.status, a.customer, a.approver_name, a.approver_sig, a.decided_at, a.created_at
    from public.quote_approvals a
   where a.doc_no = p_doc_no
     and auth.uid() is not null
   order by (a.status <> 'pending') desc, a.decided_at desc nulls last, a.created_at desc
   limit 20;
$$;

revoke all on function public.find_quote_approvals(text) from public;
revoke all on function public.find_quote_approvals(text) from anon;
grant execute on function public.find_quote_approvals(text) to authenticated;

-- ตรวจผล: anon ต้องเรียกไม่ได้ (false ทั้งสองช่อง)
select has_function_privilege('anon',   'public.find_quote_approvals(text)','EXECUTE') as "anon เรียกได้",
       has_function_privilege('public', 'public.find_quote_approvals(text)','EXECUTE') as "public เรียกได้";
