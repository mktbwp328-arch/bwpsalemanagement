-- ============================================================
-- BWP Sales — ระบบส่งใบเสนอราคาให้ผู้บริหารเซ็นอนุมัติข้ามเครื่อง
-- วิธีใช้: เปิด Supabase → SQL Editor → New query → วางทั้งไฟล์นี้ → กด Run (ครั้งเดียวพอ)
-- ============================================================

create extension if not exists pgcrypto;

-- ตารางเก็บคำขออนุมัติ
create table if not exists public.quote_approvals (
  id            uuid primary key default gen_random_uuid(),
  doc_no        text not null,
  customer      text,
  amount        numeric,
  payload       jsonb not null,          -- ข้อมูลใบเสนอราคา + ลายเซ็นฝ่ายขาย
  status        text not null default 'pending'
                check (status in ('pending','approved','rejected')),
  approver_name text,
  approver_sig  text,                    -- ลายเซ็นผู้บริหาร (PNG base64)
  decided_at    timestamptz,
  created_at    timestamptz not null default now()
);

create index if not exists quote_approvals_doc_no_idx on public.quote_approvals (doc_no);

-- เปิด RLS แล้ว "ไม่ใส่ policy" = แอปเข้าถึงตารางตรง ๆ ไม่ได้เลย
-- ต้องเรียกผ่าน 3 ฟังก์ชันด้านล่างเท่านั้น ซึ่งต้องรู้ id (uuid) ของเอกสารนั้น
-- จึงไม่มีทางดึงรายการเอกสารทั้งหมดออกไปได้
alter table public.quote_approvals enable row level security;

-- 1) ฝ่ายขายสร้างคำขออนุมัติ → ได้ id กลับไปทำเป็นลิงก์
create or replace function public.create_quote_approval(p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.quote_approvals (doc_no, customer, amount, payload)
  values (coalesce(p_payload->>'no','-'),
          p_payload->>'customer',
          nullif(p_payload->>'amount','')::numeric,
          p_payload)
  returning id into v_id;
  return v_id;
end $$;

-- 2) ผู้บริหารเปิดลิงก์ → ดึงเอกสารมาแสดง / ฝ่ายขายใช้เช็คสถานะ
create or replace function public.get_quote_approval(p_id uuid)
returns table (id uuid, doc_no text, status text, payload jsonb,
               approver_name text, approver_sig text, decided_at timestamptz)
language sql security definer set search_path = public as $$
  select a.id, a.doc_no, a.status, a.payload, a.approver_name, a.approver_sig, a.decided_at
  from public.quote_approvals a
  where a.id = p_id;
$$;

-- 3) ผู้บริหารเซ็น/ไม่อนุมัติ (เซ็นซ้ำไม่ได้ ผลแรกเป็นผลจริง)
create or replace function public.sign_quote_approval(
  p_id uuid, p_name text, p_sig text, p_ok boolean)
returns text
language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.quote_approvals where id = p_id;
  if v_status is null then
    raise exception 'ไม่พบเอกสารนี้';
  end if;
  if v_status <> 'pending' then
    return v_status;                       -- ตัดสินไปแล้ว ไม่ทับของเดิม
  end if;
  update public.quote_approvals
     set status        = case when p_ok then 'approved' else 'rejected' end,
         approver_name = p_name,
         approver_sig  = case when p_ok then p_sig else null end,
         decided_at    = now()
   where id = p_id;
  return case when p_ok then 'approved' else 'rejected' end;
end $$;

-- ให้แอป (publishable key = role anon) เรียกได้เฉพาะ 3 ฟังก์ชันนี้
grant execute on function public.create_quote_approval(jsonb) to anon, authenticated;
grant execute on function public.get_quote_approval(uuid)     to anon, authenticated;
grant execute on function public.sign_quote_approval(uuid, text, text, boolean) to anon, authenticated;
