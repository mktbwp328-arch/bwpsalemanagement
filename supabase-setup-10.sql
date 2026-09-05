-- ============================================================
-- BWP Sales — ลบลายเซ็นเพื่อขอให้เซ็นใหม่
--
-- ใช้ตอนเซ็นผิดคน เซ็นผิดช่อง ลายเซ็นเบลอ หรือต้องแก้เอกสารแล้วขอเซ็นใหม่
-- ลบแล้วช่องนั้นจะกลับมาเป็น "ยังไม่ได้เซ็น" และส่งลิงก์เดิมให้เซ็นซ้ำได้ทันที
--
-- ความปลอดภัย: ให้สิทธิ์เฉพาะผู้ที่ล็อกอินในระบบ (พนักงานขาย/ผู้ดูแล)
--              ผู้ที่เปิดจากลิงก์เซ็นอย่างเดียวจะลบไม่ได้
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

create or replace function public.remove_doc_signature(p_id uuid, p_role text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_row public.doc_signatures; v_sigs jsonb;
begin
  select * into v_row from public.doc_signatures where id = p_id;
  if v_row is null then raise exception 'ไม่พบเอกสารนี้'; end if;

  update public.doc_signatures
     set sigs        = coalesce(sigs, '{}'::jsonb) - p_role,
         status      = 'pending',      -- เปิดให้เซ็นต่อได้อีกครั้ง
         reject_by   = null,
         reject_note = null,
         updated_at  = now()
   where id = p_id
   returning sigs into v_sigs;

  return jsonb_build_object('status','pending','sigs',v_sigs);
end $$;

revoke all on function public.remove_doc_signature(uuid,text) from anon;
grant execute on function public.remove_doc_signature(uuid,text) to authenticated;

-- ตรวจผล — ต้องเห็นชื่อฟังก์ชัน 1 บรรทัด
select proname as "ฟังก์ชันที่เพิ่มแล้ว"
  from pg_proc where proname = 'remove_doc_signature';
