// POST {job_id} -> {job}                   Refreshes one of the caller's jobs from Higgsfield.
// POST {job_id, action: "hide"} -> {ok}    "Delete" on My videos: hides a finished job for its owner and
//                                          turns its share link off (the row stays for payments/refunds).
// POST {job_id, action: "rate", stars, comment?} -> {ok}   Private 1–5 rating of a finished video (owner only).
// POST {job_id, action: "gallery", opt_in: bool} -> {ok}    Consent to feature this video + prompt in the gallery.
import { admin, getUser, json, syncJob, serve, TERMINAL } from "../_shared/common.ts";

serve(async (req) => {
  const user = await getUser(req);
  if (!user) return json({ error: "Please sign in first." }, 401);

  const body = await req.json().catch(() => ({}));
  const { job_id, action } = body;
  const { data: job } = await admin.from("jobs").select("*")
    .eq("id", job_id).eq("user_id", user.id).maybeSingle();
  if (!job) return json({ error: "Not found" }, 404);
  if (action === "hide") {
    if (!TERMINAL.has(job.status) && job.status !== "submit_unknown") {
      return json({ error: "You can delete a video once it has finished." }, 400);
    }
    // Deleting also withdraws gallery consent: a deleted video must never be featured.
    await admin.from("jobs").update({ hidden_at: new Date().toISOString(), share_token: null, gallery_opt_in_at: null }).eq("id", job.id);
    return json({ ok: true });
  }
  if (action === "rate") {
    if (job.status !== "completed") return json({ error: "You can rate a video once it's ready." }, 400);
    const stars = Number(body.stars);
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) return json({ error: "Pick 1 to 5 stars." }, 400);
    // No comment sent (a star click) keeps the saved comment; a sent one replaces it. Cut by characters, not
    // UTF-16 units, so an emoji at the limit isn't split.
    const row: Record<string, unknown> = { job_id: job.id, user_id: user.id, stars, updated_at: new Date().toISOString() };
    if (typeof body.comment === "string") row.comment = Array.from(body.comment.trim()).slice(0, 500).join("") || null;
    const { error } = await admin.from("ratings").upsert(row, { onConflict: "job_id" });
    if (error) { console.error("rating failed", job.id, error.message); return json({ error: "Couldn't save your rating." }, 500); }
    return json({ ok: true });
  }
  if (action === "gallery") { // owner's opt-in (or opt-out) to show this video and its prompt in the gallery
    if (job.status !== "completed") return json({ error: "You can share a video once it's ready." }, 400);
    const on = body.opt_in === true, at = on ? new Date().toISOString() : null;
    const { error } = await admin.from("jobs").update({ gallery_opt_in_at: at }).eq("id", job.id);
    if (error) { console.error("gallery opt-in failed", job.id, error.message); return json({ error: "Couldn't save that. Please try again." }, 500); }
    return json({ ok: true, opt_in: on, at });
  }
  return json({ job: await syncJob(job) });
});
