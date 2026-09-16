-- ============================================================
-- BWP Sales — ดูเลขที่เอกสารถัดไป (ยังไม่จอง)
--
-- ใช้ตอนเปิดฟอร์มสร้างเอกสาร เพื่อโชว์เลขจริงของทีมให้เห็นก่อน
-- ไม่กินเลข ถ้ากดยกเลิกเลขก็ไม่หาย ตัวเลขจริงจะถูกจองตอนกดสร้างเท่านั้น
--
-- ต้องรัน supabase-setup-13.sql ก่อน (ตาราง doc_counters)
-- ความปลอดภัย: เฉพาะผู้ที่ล็อกอินในระบบเท่านั้น
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

create or replace function public.peek_doc_no(p_prefix text, p_year int)
returns int
language sql security definer set search_path = public stable as $$
  select coalesce(max(n), 0)
    from public.doc_counters
   where prefix = upper(trim(p_prefix)) and yr = p_year;
$$;

-- Postgres ให้สิทธิ์ EXECUTE กับ PUBLIC อัตโนมัติตอนสร้างฟังก์ชัน ต้องถอนออกก่อน
revoke all on function public.peek_doc_no(text, int) from public;
revoke all on function public.peek_doc_no(text, int) from anon;
grant execute on function public.peek_doc_no(text, int) to authenticated;

-- ตรวจผล — ต้องได้ false ทั้งคู่
select has_function_privilege('anon',   'public.peek_doc_no(text, int)','EXECUTE') as "anon เรียกได้",
       has_function_privilege('public', 'public.peek_doc_no(text, int)','EXECUTE') as "public เรียกได้";
