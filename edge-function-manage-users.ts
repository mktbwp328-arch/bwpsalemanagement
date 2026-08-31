// ============================================================
// BWP Sales — ฟังก์ชันจัดการผู้ใช้ (ผู้ดูแลสร้างบัญชีให้พนักงาน)
//
// วิธีติดตั้ง (ทำครั้งเดียว):
//   1. เปิด Supabase → เมนูซ้าย "Edge Functions" → Deploy a new function
//   2. ตั้งชื่อฟังก์ชันว่า  manage-users   (ต้องตรงตัว)
//   3. ลบโค้ดตัวอย่างทิ้ง แล้ววางไฟล์นี้ทั้งหมด → Deploy
//
// ฟังก์ชันนี้ใช้กุญแจระดับผู้ดูแล (service role) ซึ่งอยู่บนเซิร์ฟเวอร์เท่านั้น
// ไม่มีทางหลุดออกมาที่หน้าเว็บ และตรวจสิทธิ์ผู้เรียกทุกครั้งก่อนทำงาน
// ============================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

const DOMAIN = "bwp.invalid";

// เบอร์โทร -> ตัวเลขล้วน (รับ 081-234-5678, +66812345678)
function normPhone(v: unknown): string {
  let s = String(v || "").replace(/[^\d+]/g, "");
  if (s.startsWith("+66")) s = "0" + s.slice(3);
  else if (s.startsWith("66") && s.length >= 11) s = "0" + s.slice(2);
  return s;
}
const isPhone = (v: unknown) => /^0\d{8,9}$/.test(normPhone(v));

// เบอร์โทร/ชื่อผู้ใช้ -> อีเมลภายในระบบ
const toEmail = (u: unknown) => {
  const v = String(u || "").trim();
  if (v.includes("@")) return v.toLowerCase();
  if (isPhone(v)) return normPhone(v) + "@" + DOMAIN;
  return v.toLowerCase().replace(/\s+/g, "") + "@" + DOMAIN;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  try {
    // ---- 1) ผู้เรียกต้องเข้าสู่ระบบ ----
    const authHeader = req.headers.get("Authorization") ?? "";
    const asUser = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await asUser.auth.getUser();
    if (!user) return json(401, { error: "กรุณาเข้าสู่ระบบก่อน" });

    // ---- 2) ต้องเป็นผู้ดูแล/ผู้จัดการเท่านั้น ----
    const admin = createClient(url, svc);
    const { data: me } = await admin
      .from("profiles").select("role").eq("id", user.id).single();
    if (!me || !["admin", "manager"].includes(me.role)) {
      return json(403, { error: "เฉพาะผู้ดูแลระบบเท่านั้นที่จัดการผู้ใช้ได้" });
    }

    const body = await req.json().catch(() => ({}));
    const action = body.action || "list";

    // ---- 3) รายชื่อผู้ใช้ ----
    if (action === "list") {
      const { data, error } = await admin
        .from("profiles").select("id,email,name,role,created_at")
        .order("created_at");
      if (error) return json(400, { error: error.message });
      return json(200, { users: data });
    }

    // ---- 4) สร้างบัญชีใหม่ (ยืนยันอัตโนมัติ ไม่ต้องส่งอีเมล) ----
    if (action === "create") {
      const idf = body.phone ?? body.username;          // รับได้ทั้งเบอร์โทรและชื่อผู้ใช้
      const email = toEmail(idf);
      if (!/^[a-z0-9._-]{3,32}@/.test(email)) {
        return json(400, { error: "เบอร์โทรไม่ถูกต้อง เช่น 081-234-5678" });
      }
      if (!body.password || String(body.password).length < 6) {
        return json(400, { error: "รหัสผ่านต้องยาวอย่างน้อย 6 ตัวอักษร" });
      }
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password: String(body.password),
        email_confirm: true,                       // ยืนยันให้เลย ไม่ส่งอีเมล
        user_metadata: { name: body.name || "" },
      });
      if (error) {
        const m = /already/i.test(error.message)
          ? "เบอร์นี้มีบัญชีอยู่แล้ว" : error.message;
        return json(400, { error: m });
      }
      const role = ["sales", "manager", "admin"].includes(body.role) ? body.role : "sales";
      await admin.from("profiles")
        .update({ name: body.name || null, role, phone: email.split("@")[0] })
        .eq("id", data.user!.id);
      return json(200, { ok: true, id: data.user!.id, email });
    }

    // ---- 4.1) เปลี่ยนเบอร์โทรที่ใช้เข้าระบบ ----
    if (action === "phone") {
      if (!body.id) return json(400, { error: "ไม่พบผู้ใช้" });
      if (!isPhone(body.phone)) return json(400, { error: "เบอร์โทรไม่ถูกต้อง" });
      const email = toEmail(body.phone);
      const { error } = await admin.auth.admin.updateUserById(String(body.id), {
        email,
        email_confirm: true,
      });
      if (error) {
        const m = /already/i.test(error.message)
          ? "เบอร์นี้มีบัญชีอยู่แล้ว" : error.message;
        return json(400, { error: m });
      }
      await admin.from("profiles")
        .update({ email, phone: normPhone(body.phone) })
        .eq("id", String(body.id));
      return json(200, { ok: true, email });
    }

    // ---- 5) ตั้งรหัสผ่านใหม่ให้พนักงาน ----
    if (action === "password") {
      if (!body.id) return json(400, { error: "ไม่พบผู้ใช้" });
      if (!body.password || String(body.password).length < 6) {
        return json(400, { error: "รหัสผ่านต้องยาวอย่างน้อย 6 ตัวอักษร" });
      }
      const { error } = await admin.auth.admin.updateUserById(String(body.id), {
        password: String(body.password),
      });
      if (error) return json(400, { error: error.message });
      return json(200, { ok: true });
    }

    // ---- 6) เปลี่ยนสิทธิ์ / เปลี่ยนชื่อ ----
    if (action === "update") {
      if (!body.id) return json(400, { error: "ไม่พบผู้ใช้" });
      const patch: Record<string, unknown> = {};
      if (body.name !== undefined) patch.name = body.name;
      if (["sales", "manager", "admin"].includes(body.role)) patch.role = body.role;
      if (!Object.keys(patch).length) return json(400, { error: "ไม่มีข้อมูลที่จะแก้" });
      const { error } = await admin.from("profiles").update(patch).eq("id", String(body.id));
      if (error) return json(400, { error: error.message });
      return json(200, { ok: true });
    }

    // ---- 7) ลบบัญชี (ข้อมูลงานขายของคนนั้นถูกลบตามไปด้วย) ----
    if (action === "delete") {
      if (!body.id) return json(400, { error: "ไม่พบผู้ใช้" });
      if (String(body.id) === user.id) {
        return json(400, { error: "ลบบัญชีตัวเองไม่ได้" });
      }
      const { error } = await admin.auth.admin.deleteUser(String(body.id));
      if (error) return json(400, { error: error.message });
      return json(200, { ok: true });
    }

    return json(400, { error: "คำสั่งไม่ถูกต้อง" });
  } catch (e) {
    return json(500, { error: String((e as Error).message || e) });
  }
});
