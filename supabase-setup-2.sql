-- ============================================================
-- BWP Sales — ส่วนเพิ่มเติม: เอกสารที่ต้องเซ็นหลายคน (ใบขอเครดิต 4 ลายเซ็น)
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (ครั้งเดียวพอ)
-- ไฟล์นี้เพิ่มของใหม่ ไม่กระทบตาราง quote_approvals เดิม
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists public.doc_signatures (
  id         uuid primary key default gen_random_uuid(),
  doc_no     text not null,
  doc_type   text not null default 'credit',
  customer   text,
  payload    jsonb not null,                 -- ข้อมูลเอกสารทั้งใบ
  sigs       jsonb not null default '{}'::jsonb,  -- {role: {name, img, date}}
  status     text not null default 'pending'
             check (status in ('pending','complete','rejected')),
  reject_by  text,
  reject_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists doc_signatures_doc_no_idx on public.doc_signatures (doc_no);

-- ล็อกตาราง: เข้าถึงได้เฉพาะผ่านฟังก์ชันที่ต้องรู้ id เท่านั้น
alter table public.doc_signatures enable row level security;

-- 1) ฝ่ายขายสร้างเอกสารรอเซ็น → ได้ id ไปทำลิงก์
create or replace function public.create_doc_signature(
  p_payload jsonb, p_doc_no text, p_doc_type text, p_customer text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.doc_signatures (doc_no, doc_type, customer, payload)
  values (coalesce(p_doc_no,'-'), coalesce(p_doc_type,'credit'), p_customer, p_payload)
  returning id into v_id;
  return v_id;
end $$;

-- 2) เปิดลิงก์เพื่อดูเอกสาร / ฝ่ายขายเช็คสถานะ
create or replace function public.get_doc_signature(p_id uuid)
returns table (id uuid, doc_no text, doc_type text, status text, payload jsonb,
               sigs jsonb, reject_by text, reject_note text, updated_at timestamptz)
language sql security definer set search_path = public as $$
  select d.id, d.doc_no, d.doc_type, d.status, d.payload,
         d.sigs, d.reject_by, d.reject_note, d.updated_at
  from public.doc_signatures d
  where d.id = p_id;
$$;

-- 3) เซ็นทีละคนตามบทบาท (p_role เช่น sales / salesMgr / accMgr / md)
--    เซ็นทับของเดิมไม่ได้ และถ้ามีคนกดไม่อนุมัติ เอกสารจะหยุดทันที
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

  v_sigs := v_row.sigs || jsonb_build_object(p_role,
              jsonb_build_object('name', p_name, 'img', p_sig,
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

  return jsonb_build_object('status', case when v_done then 'complete' else 'pending' end, 'sigs', v_sigs);
end $$;

grant execute on function public.create_doc_signature(jsonb, text, text, text) to anon, authenticated;
grant execute on function public.get_doc_signature(uuid)                       to anon, authenticated;
grant execute on function public.add_doc_signature(uuid, text, text, text, boolean, text, text[]) to anon, authenticated;
