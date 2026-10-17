-- ============================================================
-- BWP Sales — สิทธิ์ "หัวหน้าฝ่ายขาย" (role = 'lead')
--
-- หัวหน้าฝ่ายขาย: เห็นหน้า "ภาพรวมทีมขาย" และเปิดดูข้อมูลของแต่ละคนได้
--                 แต่ "ดูอย่างเดียว" แก้ไขข้อมูลของคนอื่นไม่ได้
--                 (ไม่เห็นข้อมูลพนักงาน / ไม่มีเครื่องมือกู้ข้อมูลเหมือนผู้ดูแล)
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

-- 1) เพิ่มบทบาท lead
alter table public.profiles  drop constraint if exists profiles_role_check;
alter table public.profiles  add  constraint profiles_role_check  check (role in ('sales','lead','manager','admin'));
alter table public.employees drop constraint if exists employees_role_check;
alter table public.employees add  constraint employees_role_check check (role in ('sales','lead','manager','admin'));

-- 2) ดูข้อมูลทีมได้ = หัวหน้าฝ่ายขาย / ผู้จัดการ / ผู้ดูแล
create or replace function public.can_view_team()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('lead','manager','admin'));
$$;
revoke all on function public.can_view_team() from public;
revoke all on function public.can_view_team() from anon;
grant execute on function public.can_view_team() to authenticated;

-- 3) อ่านได้ (แก้ไขยังเป็นของเจ้าของ/ผู้จัดการเหมือนเดิม)
drop policy if exists user_data_read on public.user_data;
create policy user_data_read on public.user_data
  for select to authenticated
  using (user_id = auth.uid() or public.can_view_team());

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.can_view_team());

drop policy if exists bwp_att_read on storage.objects;
create policy bwp_att_read on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.can_view_team()));

-- รายชื่อทีม (ใช้ในหน้าภาพรวมทีม)
create or replace function public.team_list()
returns table (id uuid, name text, email text, phone text, role text,
               updated_at timestamptz, size_kb numeric)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.phone, p.role, d.updated_at,
         round((pg_column_size(d.data)/1024.0)::numeric, 1)
  from public.profiles p
  left join public.user_data d on d.user_id = p.id
  where public.can_view_team()
  order by p.name;
$$;
revoke all on function public.team_list() from public;
revoke all on function public.team_list() from anon;
grant execute on function public.team_list() to authenticated;

-- 4) ตั้งน.ส.เบญจวรรณ เป็นหัวหน้าฝ่ายขาย
update public.profiles  set role = 'lead' where id = '2cde5239-e63a-4850-a831-655921a92926';
update public.employees set role = 'lead'
 where phone = (select phone from public.profiles where id = '2cde5239-e63a-4850-a831-655921a92926');

-- ตรวจผล
select name as "ชื่อ", role as "สิทธิ์" from public.profiles order by created_at;

-- ============================================================
-- ลดกลับเป็นพนักงานขาย:
--   update public.profiles set role='sales' where id='2cde5239-e63a-4850-a831-655921a92926';
-- ============================================================
