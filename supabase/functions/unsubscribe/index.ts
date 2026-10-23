// POST -> opt a user out of marketing emails. No sign-in: the link carries the user id and an HMAC of it
// (UNSUBSCRIBE_SECRET), so only the email's recipient can use it. Accepts the id/token in the query
// (RFC 8058 one-click from the List-Unsubscribe header) or in a JSON body (the /unsubscribe/ page).
// Idempotent; reveals nothing about the account. Never rotate UNSUBSCRIBE_SECRET: old emails keep using it.
import { admin, json, safeEqual, serve } from "../_shared/common.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

async function token(secret: string, uid: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`unsubscribe:${uid}`)));
  return btoa(String.fromCharCode(...mac)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

serve(async (req) => {
  // Mail clients without one-click POST open the List-Unsubscribe link with GET: send them to the page.
  // A plain Response (not Response.redirect, whose headers are immutable) so serve() can add CORS headers.
  if (req.method === "GET") return new Response(null, { status: 303, headers: { Location: `https://genjutsu-trends.com/unsubscribe/${new URL(req.url).search}` } });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const secret = Deno.env.get("UNSUBSCRIBE_SECRET") ?? "";
  if (secret.length < 32) { console.error("unsubscribe: UNSUBSCRIBE_SECRET not set"); return json({ error: "not configured" }, 500); }
  const q = new URL(req.url).searchParams;
  let u = q.get("u") ?? "", t = q.get("t") ?? "";
  if (!u && (req.headers.get("content-type") ?? "").includes("application/json")) {
    const b = await req.json().catch(() => ({}));
    u = String(b.u ?? ""); t = String(b.t ?? "");
  }
  if (!UUID.test(u) || !t || !safeEqual(t, await token(secret, u))) return json({ error: "This unsubscribe link is not valid." }, 400);
  const { error } = await admin.from("profiles").update({ marketing_opt_out_at: new Date().toISOString() })
    .eq("user_id", u).is("marketing_opt_out_at", null);
  if (error) { console.error("unsubscribe failed", error.message); return json({ error: "Please try again." }, 500); }
  return json({ ok: true });
});
