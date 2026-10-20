// GET with header x-report-secret -> usage aggregates for the owner's daily report.
// Called only by a scheduled job in a private repo; no personal data is returned.
import { admin, intEnv, json, safeEqual, serve } from "../_shared/common.ts";

serve(async (req) => {
  const secret = Deno.env.get("REPORT_SECRET") ?? "";
  if (secret.length < 32 || !safeEqual(req.headers.get("x-report-secret") ?? "", secret)) {
    return json({ error: "unauthorized" }, 401);
  }
  const { data, error } = await admin.rpc("usage_report");
  if (error) { console.error("usage_report failed", error); return json({ error: "report failed" }, 500); }
  return json({ ...data, caps: {
    user_daily_jobs: intEnv("USER_DAILY_JOBS", 10), user_daily_credits: intEnv("USER_DAILY_CREDITS", 2600),
    site_daily_credits: intEnv("SITE_DAILY_CREDITS", 3000), renders_paused: Deno.env.get("RENDERS_PAUSED") === "1",
  }, payments_live: Deno.env.get("PAYPAL_ENV") === "live" });
});
