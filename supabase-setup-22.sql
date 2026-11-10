-- ============================================================
-- BWP Sales — เลขที่ใบขอตัวอย่าง (RD) / ใบข้อกำหนดของลูกค้า (DR) รันรวมทั้งทีมขาย ตามเดือน
--
-- รูปแบบ: RD-ปี-เดือน+ลำดับ เช่น พ.ย. 2569 → RD-2569-1101, 1102, ...  (ทุกเดือนเริ่ม 01)
-- ลำดับนับรวมทุกคนในทีม ใครออกก่อน (ตามวันที่ในเอกสาร) ได้เลขก่อน
--
-- ไฟล์นี้: 1) เรียงเลขเอกสารเดิมของทุกคนใหม่ทั้งหมด (เลขเดิมเก็บไว้ใน noOld)
--          2) ตั้งตัวนับกลาง (doc_counters) ให้ใบใหม่เดินเลขต่อจากนี้
-- ต้องรัน supabase-setup-13.sql มาก่อน (มีตาราง doc_counters และฟังก์ชัน next_doc_no)
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ============================================================

do $$
declare
  r record;
  v_now bigint := (extract(epoch from now())*1000)::bigint;
begin
  -- เอกสารทั้งหมดของทุกคน เรียงตามเดือน/วันที่/เลขเดิม แล้วให้ลำดับใหม่
  create temp table _rn on commit drop as
  with docs as (
    select d.user_id, (e.ord-1)::int as idx, e.x->>'type' as t,
           (e.x->>'date')::date as dt,
           coalesce(nullif(e.x->>'noOld',''), e.x->>'no', '') as orig,
           e.x->>'no' as cur
    from public.user_data d,
         jsonb_array_elements(d.data->'docs') with ordinality e(x, ord)
    where e.x->>'type' in ('sample','requirement')
      and (e.x->>'date') ~ '^\d{4}-\d{2}-\d{2}'
  ), ranked as (
    select *, case t when 'sample' then 'RD' else 'DR' end as pre,
           extract(year from dt)::int + 543 as yr, to_char(dt,'MM') as mm,
           row_number() over (partition by t, date_trunc('month', dt)
                              order by dt, orig, user_id) as rn
    from docs
  )
  select user_id, idx, cur, pre, yr, mm, rn,
         pre||'-'||yr||'-'||mm||lpad(rn::text, 2, '0') as newno
  from ranked;

  -- เขียนเลขใหม่กลับเข้าไปในข้อมูลของแต่ละคน (เก็บเลขเดิมไว้ใน noOld, ประทับเวลาแก้ไขให้ทุกเครื่องรับเลขใหม่)
  for r in select * from _rn where newno is distinct from cur loop
    update public.user_data
       set data = jsonb_set(data, array['docs', r.idx::text],
                  (data->'docs'->r.idx)
                    || jsonb_build_object('no', r.newno, 'noFixed', 1, '_m', v_now)
                    || case when coalesce(data->'docs'->r.idx->>'noOld','') = ''
                            then jsonb_build_object('noOld', r.cur) else '{}'::jsonb end),
           updated_at = now()
     where user_id = r.user_id;
  end loop;

  -- ปิดการเรียงเลขแบบเฉพาะคนในเครื่อง (ทีมใช้เลขกลางแล้ว)
  update public.user_data
     set data = jsonb_set(data, '{renum}', coalesce(data->'renum','{}'::jsonb) || '{"sample":2,"requirement":2,"team":1}'::jsonb)
   where data ? 'docs';

  -- ตัวนับกลางต่อเดือน: prefix = "RD-11", yr = 2569 → n = ลำดับล่าสุดของเดือนนั้น
  insert into public.doc_counters (prefix, yr, n)
  select pre||'-'||mm, yr, max(rn) from _rn group by pre, mm, yr
  on conflict (prefix, yr) do update set n = greatest(public.doc_counters.n, excluded.n), updated_at = now();
end $$;

-- ตรวจผล: จำนวนเอกสารต่อเดือน และเลขล่าสุดของตัวนับ
select prefix as "รหัส-เดือน", yr as "ปี", n as "เลขล่าสุด"
  from public.doc_counters where prefix ~ '^(RD|DR)-\d{2}$' order by yr, prefix;
