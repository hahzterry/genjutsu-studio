// POST {job_id} (signed in, own finished job) -> {url}: creates (or reuses) the job's public share link,
// https://genjutsu-trends.com/watch/<trend>/?v=<token> (or /watch/?v=… for custom videos).
// GET ?v=<token> (public) -> {video_url, trend}: what /watch/ needs to show one shared video.
import { admin, getUser, json, serve } from "../_shared/common.ts";

const SITE = "https://genjutsu-trends.com/";
const TOKEN_RE = /^[A-Za-z0-9_-]{22}$/;

function newToken() {
  const b = crypto.getRandomValues(new Uint8Array(16)); // 128 bits
  return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

serve(async (req) => {
  if (req.method === "GET") {
    const v = new URL(req.url).searchParams.get("v") ?? "";
    if (!TOKEN_RE.test(v)) return json({ error: "not found" }, 404);
    const { data: j } = await admin.from("jobs").select("output_url, trend, status")
      .eq("share_token", v).eq("status", "completed").is("hidden_at", null).maybeSingle();
    if (!j?.output_url || !/^https:\/\//.test(j.output_url)) return json({ error: "not found" }, 404);
    return json({ video_url: j.output_url, trend: /^[a-z0-9-]{1,40}$/.test(j.trend) ? j.trend : "custom" });
  }

  const user = await getUser(req);
  if (!user) return json({ error: "Please sign in first." }, 401);
  const { job_id } = await req.json().catch(() => ({}));
  if (typeof job_id !== "string") return json({ error: "Not found" }, 404);
  const { data: job } = await admin.from("jobs").select("id, status, share_token, output_url, trend")
    .eq("id", job_id).eq("user_id", user.id).is("hidden_at", null).maybeSingle();
  if (!job || job.status !== "completed" || !job.output_url) return json({ error: "Only finished videos can be shared." }, 400);
  let token = job.share_token;
  if (!token) {
    token = newToken();
    // Conditional update so two clicks can't create two different links.
    const { data: set } = await admin.from("jobs").update({ share_token: token })
      .eq("id", job.id).is("share_token", null).select("share_token").maybeSingle();
    if (!set) {
      const { data: again } = await admin.from("jobs").select("share_token").eq("id", job.id).single();
      token = again?.share_token ?? null;
    }
  }
  if (!token) return json({ error: "Could not create the link." }, 500);
  // Per-trend watch page so link previews show the trend's image (build.py makes one for every slug).
  const slug = /^[a-z0-9-]{1,40}$/.test(job.trend ?? "") && job.trend !== "custom" ? `${job.trend}/` : "";
  return json({ url: `${SITE}watch/${slug}?v=${token}` });
});
