-- ============================================================
-- BWP Sales — กู้เอกสารจากคลาวด์ (สำหรับผู้ดูแลเท่านั้น)
--
-- เอกสารทุกใบที่เคย "ส่งลิงก์ให้เซ็น" หรือ "ส่งให้ผู้บริหารอนุมัติ"
-- มีสำเนาเต็มใบเก็บไว้บนคลาวด์ ฟังก์ชันนี้ให้ผู้ดูแลดึงรายการทั้งหมด
-- เพื่อกู้กลับเข้าบัญชีของพนักงาน (ใช้ตอนข้อมูลในบัญชีหาย)
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (รันซ้ำได้)
-- ============================================================

create or replace function public.recovery_list_docs()
returns table (src text, id uuid, doc_no text, doc_type text, status text, payload jsonb, sigs jsonb,
               approver_name text, approver_sig text, decided_at timestamptz,
               created_at timestamptz, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select 'sig', d.id, d.doc_no, d.doc_type, d.status, d.payload, d.sigs,
         null::text, null::text, null::timestamptz, d.created_at, d.updated_at
    from public.doc_signatures d
   where public.is_manager()
  union all
  select 'quote', q.id, q.doc_no, 'quotation', q.status, q.payload, null::jsonb,
         q.approver_name, q.approver_sig, q.decided_at, q.created_at, coalesce(q.decided_at, q.created_at)
    from public.quote_approvals q
   where public.is_manager()
  order by 11 desc;
$$;

revoke all on function public.recovery_list_docs() from public;
revoke all on function public.recovery_list_docs() from anon;
grant execute on function public.recovery_list_docs() to authenticated;

-- ตรวจผล: false ทั้งสองช่อง (คนนอกเรียกไม่ได้)
select has_function_privilege('anon',   'public.recovery_list_docs()','EXECUTE') as "anon เรียกได้",
       has_function_privilege('public', 'public.recovery_list_docs()','EXECUTE') as "public เรียกได้";
