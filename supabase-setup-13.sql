-- ============================================================
-- BWP Sales — เลขที่เอกสารกลาง ไม่ซ้ำกันทั้งทีม
--
-- ปัญหาเดิม: ข้อมูลของพนักงานขายแต่ละคนแยกกัน ต่างคนต่างเดินเลขของตัวเอง
--            ถ้าสองคนสร้างใบขอตัวอย่างวันเดียวกัน จะได้เลขเดียวกัน
-- แก้เป็น:   เก็บเลขล่าสุดไว้ที่ส่วนกลาง ใครกดสร้างก่อนได้เลขก่อน
--            เลขเดินต่อกันทั้งทีม ไม่ซ้ำ ไม่ข้าม
--
-- ความปลอดภัย: เฉพาะผู้ที่ล็อกอินในระบบเท่านั้น
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

create table if not exists public.doc_counters (
  prefix     text not null,                 -- รหัสนำหน้า เช่น RD, QUO
  yr         int  not null,                 -- ปี พ.ศ.
  n          int  not null default 0,       -- เลขล่าสุดที่จ่ายไปแล้ว
  updated_at timestamptz not null default now(),
  primary key (prefix, yr)
);

-- ล็อกตาราง: เข้าถึงได้ผ่านฟังก์ชันเท่านั้น
alter table public.doc_counters enable row level security;

-- ขอเลขถัดไป — p_min คือเลขที่เครื่องคำนวณได้เอง ใช้เป็นเลขขั้นต่ำ
-- (เผื่อในระบบมีเอกสารเก่าเลขสูงกว่าตัวนับอยู่แล้ว จะได้ไม่ย้อนกลับไปทับ)
create or replace function public.next_doc_no(p_prefix text, p_year int, p_min int default 1)
returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  insert into public.doc_counters (prefix, yr, n)
  values (upper(trim(p_prefix)), p_year, greatest(coalesce(p_min,1), 1))
  on conflict (prefix, yr) do update
    set n = greatest(public.doc_counters.n + 1, excluded.n),
        updated_at = now()
  returning n into v_n;
  return v_n;
end $$;

-- Postgres ให้สิทธิ์ EXECUTE กับ PUBLIC อัตโนมัติตอนสร้างฟังก์ชัน ต้องถอนออกก่อน
revoke all on function public.next_doc_no(text, int, int) from public;
revoke all on function public.next_doc_no(text, int, int) from anon;
grant execute on function public.next_doc_no(text, int, int) to authenticated;

-- ตรวจผล — ต้องได้ false ทั้งคู่
select has_function_privilege('anon',   'public.next_doc_no(text, int, int)','EXECUTE') as "anon เรียกได้",
       has_function_privilege('public', 'public.next_doc_no(text, int, int)','EXECUTE') as "public เรียกได้";
