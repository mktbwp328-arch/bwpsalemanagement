-- ============================================================
-- BWP Sales — คลังรหัสสินค้าที่ใช้ร่วมกันทั้งบริษัท
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
--
-- หลักการ: รหัสสินค้าเป็นข้อมูลกลาง ไม่ใช่ของใครคนใดคนหนึ่ง
--          ใครเพิ่มรหัสใหม่ ทุกคนเห็นเหมือนกันทันที
--          พนักงานขายเพิ่มได้ แต่แก้/ลบได้เฉพาะผู้จัดการและผู้ดูแลระบบ
-- ============================================================

create table if not exists public.products (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,        -- Item Code รหัสหลัก
  code2      text default '',             -- รหัสสินค้า (รหัสรอง)
  name       text default '',
  width      text default '',
  dim_unit   text default '',
  thick      text default '',
  mat        text default '',
  core_kg    text default '',
  customer   text default '',
  note       text default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists products_code2_idx on public.products (code2);

alter table public.products enable row level security;

-- อ่านได้ทุกคนที่ล็อกอิน
drop policy if exists products_read on public.products;
create policy products_read on public.products
  for select to authenticated using (true);

-- เพิ่มรหัสใหม่ได้ทุกคนที่ล็อกอิน (บันทึกไว้ว่าใครเพิ่ม)
drop policy if exists products_insert on public.products;
create policy products_insert on public.products
  for insert to authenticated with check (true);

-- แก้ไข/ลบ เฉพาะผู้จัดการและผู้ดูแลระบบ กันพนักงานแก้ข้อมูลกลางผิด
drop policy if exists products_update on public.products;
create policy products_update on public.products
  for update to authenticated using (public.is_manager()) with check (public.is_manager());

drop policy if exists products_delete on public.products;
create policy products_delete on public.products
  for delete to authenticated using (public.is_manager());

-- อัปเดตเวลาแก้ล่าสุดอัตโนมัติ
create or replace function public.touch_product()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists products_touch on public.products;
create trigger products_touch before update on public.products
  for each row execute function public.touch_product();

-- ============================================================
-- คำสั่งที่ใช้บ่อย
--   ดูจำนวนรหัสทั้งหมด:  select count(*) from public.products;
--   ค้นหารหัส:           select code, name from public.products where code ilike '%CJK%';
--   ล้างคลังเริ่มใหม่:     delete from public.products;
-- ============================================================
