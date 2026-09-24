/* ============================================================
   BWP Sales — ย้ายฐานข้อมูลทั้งหมดไป Supabase โปรเจกต์ใหม่
   ------------------------------------------------------------
   ทำอะไรบ้าง (ตามลำดับ):
     1. สร้างตาราง ฟังก์ชัน สิทธิ์ ที่เก็บไฟล์ ในโปรเจกต์ใหม่ (จากไฟล์ supabase-setup*.sql)
     2. คัดลอกทะเบียนพนักงาน
     3. คัดลอกบัญชีผู้ใช้ทุกคน พร้อมรหัสผ่านเดิม (id เดิม — ข้อมูลในเครื่องของแต่ละคนยังใช้ได้)
     4. คัดลอกข้อมูลทุกตาราง (ลูกค้า เอกสาร PO ใบเสร็จ ลายเซ็น คลังสินค้า เลขที่เอกสาร)
     5. เปิดตัวตรวจสอบตอนสมัครบัญชีกลับมา
     6. คัดลอกไฟล์แนบ (รูป PO / PDF)
     7. ตรวจนับว่าครบทุกตาราง

   โปรเจกต์เก่า: อ่านอย่างเดียว ไม่แก้ ไม่ลบอะไรทั้งสิ้น
   รหัสผ่าน/คีย์ที่กรอก: ใช้ในเครื่องนี้เท่านั้น ไม่บันทึกลงไฟล์ ไม่ส่งไปที่อื่น

   วิธีรัน:  cd migrate  →  npm install  →  node migrate.js
   ============================================================ */
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { Client } = require('pg');

const ROOT = path.join(__dirname, '..');
const BUCKET = 'attachments';

/* ไฟล์ SQL ตามลำดับที่เคยรันจริง
   ไม่รวม set-admin-pin (จะรีเซ็ต PIN แอดมินเป็น 000000) และไฟล์ล้าง/ลบข้อมูล */
const SCHEMA_FILES = [
  'supabase-setup.sql', 'supabase-setup-2.sql', 'supabase-setup-3.sql', 'supabase-setup-4.sql',
  'supabase-setup-5.sql', 'supabase-setup-6.sql', 'supabase-setup-7.sql', 'supabase-setup-8.sql',
  'supabase-setup-9.sql', 'supabase-setup-10.sql', 'supabase-setup-11.sql', 'supabase-setup-12.sql',
  'supabase-setup-13.sql', 'supabase-setup-14.sql', 'supabase-setup-15.sql', 'supabase-fix-role.sql'
];

/* ตัวดักตอนสร้างบัญชี 2 ตัว — ปิดไว้ก่อนระหว่างคัดลอกผู้ใช้
   (ไม่งั้นจะสร้างโปรไฟล์ซ้ำ และบล็อกบัญชีพนักงานที่ปิดใช้งานไปแล้ว) แล้วค่อยเปิดกลับตอนท้าย */
const AUTH_TRIGGERS_SQL = `
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists on_auth_user_signup_check on auth.users;
create trigger on_auth_user_signup_check
  before insert on auth.users
  for each row execute function public.check_employee_signup();
`;

/* ตารางข้อมูลที่ต้องคัดลอก — เรียงตามลำดับที่ต้องมีก่อนหลัง */
const PUBLIC_TABLES = ['profiles', 'user_data', 'doc_signatures', 'quote_approvals', 'products', 'doc_counters'];

/* ---------- ถาม-ตอบในหน้าจอ ---------- */
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = q => new Promise(r => rl.question(q, a => r(a.trim())));
const log = (...a) => console.log(...a);
const ok = s => log('  \x1b[32m✓\x1b[0m ' + s);
const warn = s => log('  \x1b[33m!\x1b[0m ' + s);
const fail = s => log('  \x1b[31m✗\x1b[0m ' + s);
const step = s => log('\n\x1b[1m' + s + '\x1b[0m');

function refOf(url) { const m = String(url).match(/postgres\.([a-z0-9]{20})[:@]/) || String(url).match(/db\.([a-z0-9]{20})\.supabase/); return m ? m[1] : ''; }

/* ---------- หาที่อยู่ Session pooler ให้เอง ----------
   ผู้ใช้กรอกแค่รหัสผ่าน ไม่ต้องไปหา connection string เอง
   ลองทีละ region จนเจอ — region ผิดจะตอบว่า "Tenant or user not found" */
const REGIONS = ['ap-southeast-1', 'ap-southeast-2', 'ap-northeast-1', 'ap-northeast-2', 'ap-south-1',
  'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2', 'ca-central-1', 'sa-east-1',
  'eu-central-1', 'eu-central-2', 'eu-west-1', 'eu-west-2', 'eu-west-3', 'eu-north-1'];
async function findPooler(ref, password) {
  const pw = encodeURIComponent(password);
  for (const pre of ['aws-0', 'aws-1']) {
    for (const reg of REGIONS) {
      const url = `postgresql://postgres.${ref}:${pw}@${pre}-${reg}.pooler.supabase.com:5432/postgres`;
      const c = new Client({ connectionString: url, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 6000 });
      try { await c.connect(); await c.end(); return url; }
      catch (e) {
        const m = String(e.message || '');
        try { await c.end(); } catch (_) {}
        if (/password authentication failed/i.test(m)) throw new Error('รหัสผ่านฐานข้อมูลไม่ถูกต้อง (' + ref + ')');
        /* region ผิด / ต่อไม่ได้ — ลองตัวถัดไป */
      }
    }
  }
  throw new Error('หาที่อยู่ฐานข้อมูลของ ' + ref + ' ไม่เจอ — ลองวาง Connection string แบบ Session pooler ทั้งบรรทัดแทน');
}
/* รับได้ทั้งรหัสผ่านอย่างเดียว หรือ connection string เต็ม */
async function resolveDb(input, ref, label) {
  const v = String(input || '').trim();
  if (/^postgres(ql)?:\/\//i.test(v)) return v;
  log('   กำลังหาที่อยู่ฐานข้อมูล' + label + ' …');
  const url = await findPooler(ref, v);
  ok('เจอแล้ว: ' + url.replace(/:[^:@/]+@/, ':****@'));
  return url;
}

/* ตัดคำสั่งสร้างตัวดักบน auth.users ออกจาก SQL (จะสร้างกลับตอนท้าย) */
function stripAuthTriggers(sql) {
  return sql
    .replace(/drop trigger if exists on_auth_user_created on auth\.users;/gi, '')
    .replace(/create trigger on_auth_user_created[\s\S]*?;/gi, '')
    .replace(/drop trigger if exists on_auth_user_signup_check on auth\.users;/gi, '')
    .replace(/create trigger on_auth_user_signup_check[\s\S]*?;/gi, '');
}

async function columns(db, schema, table) {
  const r = await db.query(
    `select column_name from information_schema.columns
      where table_schema=$1 and table_name=$2
        and is_generated='NEVER' and coalesce(identity_generation,'')<>'ALWAYS'
      order by ordinal_position`, [schema, table]);
  return r.rows.map(x => x.column_name);
}

/* คัดลอกทั้งตาราง แบบไม่ต้องรู้ชื่อคอลัมน์ล่วงหน้า — ใช้เฉพาะคอลัมน์ที่มีทั้งสองฝั่ง */
async function copyTable(OLD, NEW, schema, table) {
  const oldCols = await columns(OLD, schema, table);
  const newCols = await columns(NEW, schema, table);
  const cols = newCols.filter(c => oldCols.includes(c));
  if (!cols.length) throw new Error('ไม่พบคอลัมน์ของ ' + schema + '.' + table);
  const list = cols.map(c => '"' + c + '"').join(',');
  const src = (await OLD.query(`select to_jsonb(t) as j from ${schema}.${table} t`)).rows;
  let n = 0;
  for (const r of src) {
    const res = await NEW.query(
      `insert into ${schema}.${table} (${list})
       select ${list} from jsonb_populate_record(null::${schema}.${table}, $1)
       on conflict do nothing`, [r.j]);
    n += res.rowCount;
  }
  return { src: src.length, copied: n };
}

async function count(db, fq) { return +(await db.query(`select count(*)::int as n from ${fq}`)).rows[0].n; }

/* ---------- ไฟล์แนบ ---------- */
async function copyStorage(OLD, oldUrl, oldKey, newUrl, newKey) {
  const objs = (await OLD.query(
    `select name, metadata from storage.objects where bucket_id=$1 order by name`, [BUCKET])).rows;
  let done = 0, skip = 0, bad = 0;
  for (const o of objs) {
    const enc = o.name.split('/').map(encodeURIComponent).join('/');
    try {
      const g = await fetch(`${oldUrl}/storage/v1/object/${BUCKET}/${enc}`,
        { headers: { apikey: oldKey, Authorization: 'Bearer ' + oldKey } });
      if (!g.ok) { bad++; fail('ดาวน์โหลดไม่ได้: ' + o.name + ' (' + g.status + ')'); continue; }
      const body = Buffer.from(await g.arrayBuffer());
      const type = (o.metadata && o.metadata.mimetype) || g.headers.get('content-type') || 'application/octet-stream';
      const p = await fetch(`${newUrl}/storage/v1/object/${BUCKET}/${enc}`, {
        method: 'POST',
        headers: { apikey: newKey, Authorization: 'Bearer ' + newKey, 'Content-Type': type, 'x-upsert': 'true' },
        body });
      if (!p.ok) { bad++; fail('อัปโหลดไม่ได้: ' + o.name + ' (' + p.status + ' ' + (await p.text()).slice(0, 120) + ')'); continue; }
      done++;
      if (done % 10 === 0) log('    … ' + done + '/' + objs.length);
    } catch (e) { bad++; fail(o.name + ': ' + e.message); }
  }
  return { total: objs.length, done, skip, bad };
}

(async () => {
  log('\n\x1b[1m=== ย้ายฐานข้อมูล BWP Sales ไปโปรเจกต์ Supabase ใหม่ ===\x1b[0m');
  log('ต้องใช้ข้อมูล 4 อย่าง (หาได้ใน Supabase ของแต่ละโปรเจกต์):');
  log('  • รหัสผ่านฐานข้อมูล — ถ้าจำไม่ได้: Project Settings → Database → Reset database password');
  log('    (ตั้งเป็นตัวอักษรกับตัวเลขล้วน จะได้ไม่มีปัญหา)');
  log('  • service_role key — Project Settings → API Keys → service_role (กด Reveal)');
  log('ข้อมูลที่กรอกใช้ในเครื่องนี้เท่านั้น ไม่บันทึกลงไฟล์\n');

  const OLD_REF = 'vltsxzlbflayxnvtnhlv', NEW_REF = 'zjjxmbivkdupfsuzjtoj';
  /* เช็คว่าเป็น service_role จริง ไม่ใช่ anon — วางผิดตัวบ่อย เพราะหน้าตาคล้ายกัน */
  const jwtOf = k => { try { return JSON.parse(Buffer.from(String(k).split('.')[1], 'base64url').toString()) || {}; } catch (e) { return {}; } };
  const keyRole = k => jwtOf(k).role || '';

  /* วางทีเดียวทั้งก้อน — แยกรหัสผ่าน/คีย์ของแต่ละโปรเจกต์ให้เอง
     รหัสผ่าน: บรรทัดที่มีคำว่า "รหัสผ่าน" + "เก่า"/"ใหม่" ตามด้วยรหัส
     คีย์:     ดูจากข้างในคีย์เองว่าเป็นของโปรเจกต์ไหน และต้องเป็น service_role */
  /* แยกรหัสผ่าน/คีย์จากข้อความหนึ่งบรรทัด — ใช้ทั้งตอนอ่านจากไฟล์และตอนวางในหน้าจอ */
  const parseLine = (s, g) => {
    s = String(s || '').trim();
    if (!s || s.startsWith('#')) return;
    for (const tok of s.split(/\s+/)) {
      if (/^eyJ[\w-]+\.[\w-]+\.[\w-]+$/.test(tok)) {
        const p = jwtOf(tok);
        if (p.role !== 'service_role') { warn('ข้ามคีย์ที่เป็น "' + (p.role || '?') + '" (ต้องเป็น service_role)'); continue; }
        if (p.ref === OLD_REF) g.oldKey = tok; else if (p.ref === NEW_REF) g.newKey = tok;
      }
    }
    const m = s.match(/รหัสผ่าน.*?(เก่า|ใหม่)\s*[:：=]?\s*(\S+)\s*$/);
    if (m && !/^eyJ/.test(m[2])) {
      /* เผื่อพิมพ์วงเล็บหรือเครื่องหมายคำพูดครอบรหัสมาด้วย */
      const pw = m[2].replace(/^[(\[{"'“”‘’]+|[)\]}"'“”‘’]+$/g, '');
      if (m[1] === 'เก่า') g.oldPw = pw; else g.newPw = pw;
    }
  };

  /* วิธีที่ง่ายที่สุด: ใส่ข้อมูลในไฟล์ keys.txt แล้วบันทึก — อ่านเสร็จลบไฟล์ทิ้งทันที ไม่ให้รหัสค้างในเครื่อง */
  const KEYFILE = path.join(__dirname, 'keys.txt');
  const fromFile = {};
  if (fs.existsSync(KEYFILE)) {
    fs.readFileSync(KEYFILE, 'utf8').split(/\r?\n/).forEach(l => parseLine(l, fromFile));
    if (Object.keys(fromFile).length) {
      try { fs.unlinkSync(KEYFILE); ok('อ่านรหัสจากไฟล์ keys.txt แล้ว และลบไฟล์ทิ้งเรียบร้อย'); } catch (e) { warn('ลบไฟล์ keys.txt ไม่ได้ — ลบเองด้วย'); }
    }
  }

  const got = Object.keys(fromFile).length ? fromFile : await new Promise(resolve => {
    const g = {}; let blanks = 0, done = false;
    log('\x1b[1mวางข้อความที่มีรหัสผ่านและ service_role key ทั้งหมดลงมาทีเดียวได้เลย (คลิกขวา หรือ Ctrl+V)\x1b[0m');
    log('ถ้าวางแล้วไม่ไปต่อเอง ให้กด Enter อีก 2 ครั้ง\n');
    const finish = () => { if (done) return; done = true; rl.removeListener('line', onLine); resolve(g); };
    const onLine = line => {
      const s = String(line || '').trim();
      if (!s) { if (Object.keys(g).length && ++blanks >= 2) finish(); return; }
      blanks = 0;
      for (const tok of s.split(/\s+/)) {
        if (/^eyJ[\w-]+\.[\w-]+\.[\w-]+$/.test(tok)) {
          const p = jwtOf(tok);
          if (p.role !== 'service_role') { warn('ข้ามคีย์ที่เป็น "' + (p.role || '?') + '" (ต้องเป็น service_role)'); continue; }
          if (p.ref === OLD_REF) g.oldKey = tok; else if (p.ref === NEW_REF) g.newKey = tok;
          else warn('ข้ามคีย์ของโปรเจกต์อื่น (' + p.ref + ')');
        } else if (/^sb_secret_/.test(tok)) {
          warn('คีย์แบบ sb_secret_ แยกไม่ได้ว่าเป็นของโปรเจกต์ไหน — จะถามแยกทีหลัง');
        }
      }
      const m = s.match(/รหัสผ่าน.*?(เก่า|ใหม่)\s*[:：=]?\s*(\S+)\s*$/);
      if (m && !/^eyJ/.test(m[2])) { if (m[1] === 'เก่า') g.oldPw = m[2]; else g.newPw = m[2]; }
      if (g.oldPw && g.newPw && g.oldKey && g.newKey) finish();
    };
    if (process.env.OLD_DB_URL && process.env.NEW_DB_URL) return resolve(g);
    rl.on('line', onLine);
  });
  const show = (label, v) => v ? ok(label + ' ✓ (' + String(v).length + ' ตัวอักษร)') : warn(label + ' ยังไม่ได้ — จะถามแยก');
  show('รหัสผ่านโปรเจกต์เก่า', got.oldPw); show('รหัสผ่านโปรเจกต์ใหม่', got.newPw);
  show('service_role key โปรเจกต์เก่า', got.oldKey); show('service_role key โปรเจกต์ใหม่', got.newKey);

  const oldIn  = process.env.OLD_DB_URL || got.oldPw || await ask('1) รหัสผ่านฐานข้อมูล โปรเจกต์ "เก่า" (' + OLD_REF + '): ');
  const newIn  = process.env.NEW_DB_URL || got.newPw || await ask('2) รหัสผ่านฐานข้อมูล โปรเจกต์ "ใหม่" (' + NEW_REF + '): ');
  const askKey = async (label) => {
    for (;;) {
      const k = await ask(label);
      if (/^sb_secret_/.test(k)) return k;
      const r = keyRole(k);
      if (r === 'service_role') return k;
      fail(r ? 'คีย์นี้เป็น "' + r + '" ไม่ใช่ service_role — ใช้แถวที่มีป้าย secret (กด Reveal) แล้ววางใหม่'
             : 'รูปแบบคีย์ไม่ถูกต้อง — วางใหม่');
    }
  };
  const oldKey = process.env.OLD_SERVICE_KEY || got.oldKey || await askKey('3) service_role key โปรเจกต์ "เก่า": ');
  const newKey = process.env.NEW_SERVICE_KEY || got.newKey || await askKey('4) service_role key โปรเจกต์ "ใหม่": ');

  step('ขั้น 0 — หาที่อยู่ฐานข้อมูล');
  let oldDbUrl, newDbUrl;
  try {
    oldDbUrl = await resolveDb(oldIn, OLD_REF, 'เก่า');
    newDbUrl = await resolveDb(newIn, NEW_REF, 'ใหม่');
  } catch (e) { fail(e.message); rl.close(); process.exit(1); }

  const oldRef = refOf(oldDbUrl), newRef = refOf(newDbUrl);
  if (oldRef && newRef && oldRef === newRef) { fail('ใส่โปรเจกต์เดียวกันทั้งสองช่อง — หยุด'); process.exit(1); }
  if (oldRef && oldRef !== 'vltsxzlbflayxnvtnhlv') warn('ช่องที่ 1 ไม่ใช่โปรเจกต์เก่าที่คาดไว้ (' + oldRef + ')');
  if (newRef && newRef !== 'zjjxmbivkdupfsuzjtoj') warn('ช่องที่ 2 ไม่ใช่โปรเจกต์ใหม่ที่คาดไว้ (' + newRef + ')');
  const oldUrl = 'https://' + (oldRef || 'vltsxzlbflayxnvtnhlv') + '.supabase.co';
  const newUrl = 'https://' + (newRef || 'zjjxmbivkdupfsuzjtoj') + '.supabase.co';

  const OLD = new Client({ connectionString: oldDbUrl, ssl: { rejectUnauthorized: false } });
  const NEW = new Client({ connectionString: newDbUrl, ssl: { rejectUnauthorized: false } });

  step('ขั้น 0 — เชื่อมต่อฐานข้อมูล');
  try { await OLD.connect(); ok('ต่อโปรเจกต์เก่าได้'); } catch (e) { fail('ต่อโปรเจกต์เก่าไม่ได้: ' + e.message); process.exit(1); }
  try { await NEW.connect(); ok('ต่อโปรเจกต์ใหม่ได้'); } catch (e) { fail('ต่อโปรเจกต์ใหม่ไม่ได้: ' + e.message); process.exit(1); }

  const oldUsers = await count(OLD, 'auth.users');
  const oldData = await count(OLD, 'public.user_data');
  ok('โปรเจกต์เก่ามีผู้ใช้ ' + oldUsers + ' คน · ข้อมูลงานขาย ' + oldData + ' ชุด');
  const newUsers = await count(NEW, 'auth.users');
  if (newUsers > 0) {
    warn('โปรเจกต์ใหม่มีผู้ใช้อยู่แล้ว ' + newUsers + ' คน (อาจเคยรันสคริปต์นี้ไปแล้ว)');
    const a = await ask('   รันต่อไหม? รายการที่มีอยู่แล้วจะข้ามไป ไม่เขียนทับ (พิมพ์ y เพื่อรันต่อ): ');
    if (a.toLowerCase() !== 'y') { log('ยกเลิก'); process.exit(0); }
  }
  const go = await ask('\nพร้อมเริ่มย้ายแล้ว — ให้ทีมหยุดบันทึกงานก่อน แล้วพิมพ์ y เพื่อเริ่ม: ');
  if (go.toLowerCase() !== 'y') { log('ยกเลิก'); process.exit(0); }

  try {
    step('ขั้น 1 — สร้างโครงสร้างฐานข้อมูลในโปรเจกต์ใหม่');
    for (const f of SCHEMA_FILES) {
      const p = path.join(ROOT, f);
      if (!fs.existsSync(p)) { warn('ไม่พบไฟล์ ' + f + ' — ข้าม'); continue; }
      await NEW.query(stripAuthTriggers(fs.readFileSync(p, 'utf8')));
      ok(f);
    }

    step('ขั้น 2 — ทะเบียนพนักงาน');
    const emp = await copyTable(OLD, NEW, 'public', 'employees');
    ok('พนักงาน ' + emp.copied + '/' + emp.src + ' คน');

    step('ขั้น 3 — บัญชีผู้ใช้ (พร้อมรหัสผ่านเดิม)');
    const au = await copyTable(OLD, NEW, 'auth', 'users');
    ok('บัญชีผู้ใช้ ' + au.copied + '/' + au.src);
    const ai = await copyTable(OLD, NEW, 'auth', 'identities');
    ok('ข้อมูลเข้าระบบ ' + ai.copied + '/' + ai.src);

    step('ขั้น 4 — ข้อมูลงานขาย');
    for (const t of PUBLIC_TABLES) {
      const r = await copyTable(OLD, NEW, 'public', t);
      (r.copied === r.src ? ok : warn)(t.padEnd(16) + r.copied + '/' + r.src);
    }

    step('ขั้น 5 — เปิดตัวตรวจสอบตอนสมัครบัญชีกลับมา');
    await NEW.query(AUTH_TRIGGERS_SQL);
    ok('เปิดแล้ว (พนักงานใหม่ต้องมีชื่อในทะเบียนพนักงานก่อนถึงจะสมัครได้ เหมือนเดิม)');
  } catch (e) {
    fail('หยุดกลางทาง: ' + e.message);
    log('   โปรเจกต์เก่าไม่ได้ถูกแก้ไขอะไร — แก้ปัญหาแล้วรันใหม่ได้ รายการที่คัดลอกไปแล้วจะข้าม');
    await OLD.end(); await NEW.end(); rl.close(); process.exit(1);
  }

  step('ขั้น 6 — ไฟล์แนบ (รูป PO / PDF)');
  const st = await copyStorage(OLD, oldUrl, oldKey, newUrl, newKey);
  (st.bad ? warn : ok)('ไฟล์แนบ ' + st.done + '/' + st.total + (st.bad ? ' (ไม่สำเร็จ ' + st.bad + ')' : ''));

  step('ขั้น 7 — ตรวจนับเทียบกัน');
  let allOk = true;
  for (const fq of ['public.employees', 'auth.users', 'auth.identities', ...PUBLIC_TABLES.map(t => 'public.' + t)]) {
    const a = await count(OLD, fq), b = await count(NEW, fq);
    if (a === b) ok(fq.padEnd(24) + 'เก่า ' + a + ' = ใหม่ ' + b);
    else { allOk = false; fail(fq.padEnd(24) + 'เก่า ' + a + ' ≠ ใหม่ ' + b); }
  }
  const sa = await count(OLD, `storage.objects where bucket_id='${BUCKET}'`);
  const sb = await count(NEW, `storage.objects where bucket_id='${BUCKET}'`);
  if (sa === sb) ok('ไฟล์แนบ'.padEnd(24) + 'เก่า ' + sa + ' = ใหม่ ' + sb);
  else { allOk = false; fail('ไฟล์แนบ'.padEnd(24) + 'เก่า ' + sa + ' ≠ ใหม่ ' + sb); }

  log('\n' + (allOk
    ? '\x1b[32m\x1b[1m✓ ย้ายครบทุกอย่างแล้ว — แจ้ง Claude ได้เลย เพื่อสลับหน้าเว็บไปใช้โปรเจกต์ใหม่\x1b[0m'
    : '\x1b[33m\x1b[1m! ย้ายเสร็จแต่ตัวเลขบางตารางไม่ตรง — คัดลอกข้อความในหน้าจอนี้ส่งให้ Claude ดู\x1b[0m'));
  await OLD.end(); await NEW.end(); rl.close();
})().catch(e => { fail(e.message); process.exit(1); });
