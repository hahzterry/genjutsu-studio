# Open issues

Known gaps we've decided to leave for now.

- **Generated videos live on Higgsfield's CDN, not ours.** `jobs.output_url` points at Higgsfield's storage and we don't know their retention. If they delete old outputs, "Your videos" shows broken players after a few weeks. Fix: on `completed`, copy the MP4 into Supabase storage (`outputs/<user>/<job>.mp4`, ~5 MB each) and store that URL instead.
- **No custom SMTP.** Supabase's built-in mailer sends ~2 emails/hour, so sign-in links stall under real traffic.
- **No Terms / Privacy / Refund pages**, and no "I have permission to use these photos" consent checkbox.
- **Higgsfield balance has no auto top-up or low-balance alert.**
- **Watermarked source clips:** Alors on Danse, Industry Baby, Shrek Raindance.
- **Sign-in by code is built but off** (`EMAIL_CODE` in `docs/config.js`). Supabase's free plan won't let us edit email templates without custom SMTP. Once SMTP is set up: add `{{ .Token }}` to the Magic Link + Confirm signup templates, then set `EMAIL_CODE: true`. Until then photos survive the sign-in link through an IndexedDB draft (same browser only, so not from inside a mail app).
- **No captcha on sign-in.** Enable Cloudflare Turnstile together with custom SMTP.
- **PayPal live app belongs to a family member's business account (test period).** Before a public launch, move to your own Business account: new live keys, re-register the webhook, update `PAYPAL_*` secrets and `docs/config.js`.
- **Low-risk security leftovers (re-review 2026-10-14).** The Higgsfield callback carries the shared `WEBHOOK_SECRET` in its query string (a per-job HMAC would be better); uploads that never become a finished job aren't swept, and there's no per-user storage limit (needs a cleanup cron); a partial-refund event without `seller_payable_breakdown` claws back only that refund's share.
