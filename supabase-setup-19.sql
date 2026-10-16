-- ============================================================
-- BWP Sales — ฝ่ายวิจัยแก้ไขผลการพิจารณาใบขอตัวอย่างได้ หลังเซ็นแล้ว
--
-- เดิม: เซ็นแล้วส่งซ้ำไม่ได้ (ฐานข้อมูลไม่รับลายเซ็นซ้ำในตำแหน่งเดิม)
-- ใหม่: เปิดลิงก์ฝ่ายวิจัยเดิม แก้ "ผลการพิจารณา / ข้อเสนอแนะ" ได้ ลายเซ็นเดิมคงไว้
-- ใช้ได้เฉพาะช่องฝ่ายวิจัย (rd) ของใบขอตัวอย่างที่เซ็นแล้วเท่านั้น
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (รันซ้ำได้)
-- ============================================================

create or replace function public.update_rd_note(p_id uuid, p_note text, p_name text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_row public.doc_signatures; v_sigs jsonb;
begin
  select * into v_row from public.doc_signatures where id = p_id;
  if v_row is null then raise exception 'ไม่พบเอกสารนี้'; end if;
  if v_row.doc_type <> 'sample' then raise exception 'แก้ไขได้เฉพาะใบขอตัวอย่าง'; end if;
  if not (coalesce(v_row.sigs,'{}'::jsonb) ? 'rd') then raise exception 'ฝ่ายวิจัยยังไม่ได้เซ็น'; end if;
  if length(coalesce(p_note,'')) > 5000 then raise exception 'ข้อความยาวเกินไป'; end if;

  v_sigs := jsonb_set(v_row.sigs, '{rd,note}', to_jsonb(p_note));
  v_sigs := jsonb_set(v_sigs, '{rd,edited}', to_jsonb(to_char(now() at time zone 'Asia/Bangkok','YYYY-MM-DD HH24:MI')));
  if nullif(trim(coalesce(p_name,'')),'') is not null then
    v_sigs := jsonb_set(v_sigs, '{rd,name}', to_jsonb(trim(p_name)));
  end if;

  update public.doc_signatures set sigs = v_sigs, updated_at = now() where id = p_id;
  return jsonb_build_object('status', v_row.status, 'sigs', v_sigs);
end $$;

grant execute on function public.update_rd_note(uuid, text, text) to anon, authenticated;

select proname as "ฟังก์ชันที่ติดตั้งแล้ว" from pg_proc where proname = 'update_rd_note';
