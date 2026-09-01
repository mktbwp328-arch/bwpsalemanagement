-- ============================================================
-- BWP Sales — ให้ผู้เซ็นกรอกข้อมูลเพิ่มมากับลายเซ็นได้
-- (ใบขอตัวอย่าง: ฝ่ายวิจัยและพัฒนาต้องเลือกว่าจัดทำผลิตภัณฑ์ได้หรือไม่
--  พร้อมกรอกข้อเสนอแนะ ตอนกดเซ็นจากลิงก์)
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

create or replace function public.add_doc_signature(
  p_id uuid, p_role text, p_name text, p_sig text, p_ok boolean,
  p_note text default null, p_roles_required text[] default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_row public.doc_signatures; v_sigs jsonb; r text; v_done boolean := true;
begin
  select * into v_row from public.doc_signatures where id = p_id;
  if v_row is null then raise exception 'ไม่พบเอกสารนี้'; end if;
  if v_row.status <> 'pending' then
    return jsonb_build_object('status', v_row.status, 'sigs', v_row.sigs);
  end if;
  if v_row.sigs ? p_role then
    return jsonb_build_object('status', v_row.status, 'sigs', v_row.sigs, 'already', true);
  end if;

  if not p_ok then
    update public.doc_signatures
       set status='rejected', reject_by=p_role, reject_note=coalesce(p_note, p_name), updated_at=now()
     where id = p_id
     returning sigs into v_sigs;
    return jsonb_build_object('status','rejected','sigs',v_sigs);
  end if;

  -- เก็บ note ไว้ในลายเซ็นด้วย (ของเดิมเก็บเฉพาะตอนไม่อนุมัติ)
  v_sigs := v_row.sigs || jsonb_build_object(p_role,
              jsonb_build_object('name', p_name, 'img', p_sig,
                                 'note', p_note,
                                 'date', to_char(now() at time zone 'Asia/Bangkok','YYYY-MM-DD')));

  if p_roles_required is not null then
    foreach r in array p_roles_required loop
      if not (v_sigs ? r) then v_done := false; end if;
    end loop;
  else
    v_done := false;
  end if;

  update public.doc_signatures
     set sigs = v_sigs,
         status = case when v_done then 'complete' else 'pending' end,
         updated_at = now()
   where id = p_id;

  return jsonb_build_object('status', case when v_done then 'complete' else 'pending' end,
                            'sigs', v_sigs);
end $$;

grant execute on function public.add_doc_signature(uuid,text,text,text,boolean,text,text[]) to anon, authenticated;

-- ตรวจผล — ต้องเห็นชื่อฟังก์ชันนี้ 1 บรรทัด
select proname as "ฟังก์ชันที่อัปเดตแล้ว"
  from pg_proc where proname = 'add_doc_signature';
