// POST {job_id} -> {job}                   Refreshes one of the caller's jobs from Higgsfield.
// POST {job_id, action: "hide"} -> {ok}    "Delete" on My videos: hides a finished job for its owner and
//                                          turns its share link off (the row stays for payments/refunds).
import { admin, getUser, json, syncJob, serve, TERMINAL } from "../_shared/common.ts";

serve(async (req) => {
  const user = await getUser(req);
  if (!user) return json({ error: "Please sign in first." }, 401);

  const { job_id, action } = await req.json().catch(() => ({}));
  const { data: job } = await admin.from("jobs").select("*")
    .eq("id", job_id).eq("user_id", user.id).maybeSingle();
  if (!job) return json({ error: "Not found" }, 404);
  if (action === "hide") {
    if (!TERMINAL.has(job.status) && job.status !== "submit_unknown") {
      return json({ error: "You can delete a video once it has finished." }, 400);
    }
    await admin.from("jobs").update({ hidden_at: new Date().toISOString(), share_token: null }).eq("id", job.id);
    return json({ ok: true });
  }
  return json({ job: await syncJob(job) });
});
