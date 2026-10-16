-- ============================================================
-- BWP Sales — ทะเบียนลูกค้ากลาง (ใช้ร่วมกันทั้งทีม)
--
-- ข้อมูลพื้นฐานของลูกค้า (ชื่อ ที่อยู่ เลขผู้เสียภาษี ผู้ติดต่อ เบอร์ อีเมล เครดิต)
-- ใช้ร่วมกันทุกคน ใครเพิ่ม/แก้ ทุกคนเห็นตาม
-- ส่วนสถานะการขาย บันทึกการติดต่อ รูป และไฟล์ ยังเป็นของแต่ละคนเหมือนเดิม
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run (รันซ้ำได้)
-- ============================================================

create table if not exists public.customers_shared (
  name_key        text primary key,          -- ชื่อแบบตัดช่องว่าง/คำนำหน้า ใช้จับคู่ลูกค้ารายเดียวกัน
  name            text not null,
  contact         text default '',
  contact_pos     text default '',
  phone           text default '',
  email           text default '',
  address         text default '',
  ship_to         text default '',
  tax_id          text default '',
  biz             text default '',
  website         text default '',
  credit_term     text default '',
  credit_limit    numeric default 0,
  updated_by      uuid references auth.users(id) on delete set null,
  updated_by_name text default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists customers_shared_updated_idx on public.customers_shared (updated_at);

alter table public.customers_shared enable row level security;

-- ทุกคนในทีม (เข้าระบบแล้ว) ดู เพิ่ม และแก้ไขได้ · ลบได้เฉพาะผู้จัดการ/ผู้ดูแล
drop policy if exists customers_shared_read   on public.customers_shared;
drop policy if exists customers_shared_insert on public.customers_shared;
drop policy if exists customers_shared_update on public.customers_shared;
drop policy if exists customers_shared_delete on public.customers_shared;
create policy customers_shared_read   on public.customers_shared for select to authenticated using (true);
create policy customers_shared_insert on public.customers_shared for insert to authenticated with check (true);
create policy customers_shared_update on public.customers_shared for update to authenticated using (true) with check (true);
create policy customers_shared_delete on public.customers_shared for delete to authenticated using (public.is_manager());

-- เวลาแก้ไขล่าสุด ตั้งโดยฐานข้อมูลเสมอ (ใช้ดึงเฉพาะรายการที่เปลี่ยน)
create or replace function public.touch_customer_shared()
returns trigger language plpgsql as $$
begin new.updated_at := clock_timestamp(); return new; end $$;
drop trigger if exists customers_shared_touch on public.customers_shared;
create trigger customers_shared_touch before insert or update on public.customers_shared
  for each row execute function public.touch_customer_shared();

-- ตรวจผล
select count(*) as "ลูกค้าในทะเบียนกลาง" from public.customers_shared;
