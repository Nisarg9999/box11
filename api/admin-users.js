// Vercel serverless function: admin-only user management.
// Needs env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (never put these in index.html).
import { createClient } from "@supabase/supabase-js";

const DOMAIN = "users.box11.app"; // usernames become username@DOMAIN internally
const TABS = ["dashboard", "products", "shipments", "stock", "sales", "expenses", "reports", "settings", "customize", "backup"];
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const cleanPerms = (p) => Object.fromEntries(TABS.map((t) => [t, ["view", "edit"].includes(p?.[t]) ? p[t] : "none"]));

export default async function handler(req, res) {
  const bad = (m, c = 400) => res.status(c).json({ error: m });
  if (req.method !== "POST") return bad("POST only", 405);
  try {
    const token = (req.headers.authorization || "").replace(/^Bearer /, "");
    const { data: { user } = {}, error: ue } = await sb.auth.getUser(token);
    if (ue || !user) return bad("Please sign in again.", 401);
    const { data: me } = await sb.from("profiles").select("role,disabled").eq("id", user.id).single();
    if (me?.role !== "admin" || me?.disabled) return bad("Admins only.", 403);

    const b = req.body || {};

    if (b.action === "create") {
      const username = String(b.username || "").trim().toLowerCase();
      if (!/^[a-z0-9._-]{3,30}$/.test(username)) return bad("Invalid username.");
      if (String(b.password || "").length < 8) return bad("Password must be at least 8 characters.");
      const { data, error } = await sb.auth.admin.createUser({
        email: `${username}@${DOMAIN}`, password: b.password, email_confirm: true, user_metadata: { username },
      });
      if (error) return bad(/already|registered/i.test(error.message) ? "That username is already taken." : error.message);
      const { error: pe } = await sb.from("profiles").upsert({
        id: data.user.id, email: data.user.email, username,
        full_name: String(b.full_name || "").trim() || null,
        role: b.role === "admin" ? "admin" : "user", permissions: cleanPerms(b.permissions), disabled: false,
      });
      if (pe) { await sb.auth.admin.deleteUser(data.user.id); return bad(pe.message); }
      return res.json({ ok: true });
    }

    const id = b.id;
    if (!id) return bad("Missing user id.");
    const self = id === user.id;

    if (b.action === "update") {
      const upd = {}, authUp = {};
      if ("full_name" in b) upd.full_name = String(b.full_name || "").trim() || null;
      if (!self) { // admins cannot lock themselves out
        if (b.role) upd.role = b.role === "admin" ? "admin" : "user";
        if (b.permissions) upd.permissions = cleanPerms(b.permissions);
        if ("disabled" in b) { upd.disabled = !!b.disabled; authUp.ban_duration = b.disabled ? "876000h" : "none"; }
      }
      if (b.password) {
        if (String(b.password).length < 8) return bad("Password must be at least 8 characters.");
        authUp.password = b.password;
      }
      if (Object.keys(authUp).length) {
        const { error } = await sb.auth.admin.updateUserById(id, authUp);
        if (error) return bad(error.message);
      }
      if (Object.keys(upd).length) {
        const { error } = await sb.from("profiles").update(upd).eq("id", id);
        if (error) return bad(error.message);
      }
      return res.json({ ok: true });
    }

    if (b.action === "delete") {
      if (self) return bad("You cannot delete your own account.");
      await sb.from("profiles").delete().eq("id", id);
      const { error } = await sb.auth.admin.deleteUser(id);
      if (error) return bad(error.message);
      return res.json({ ok: true });
    }

    return bad("Unknown action.");
  } catch (e) {
    return bad(String(e.message || e), 500);
  }
}
