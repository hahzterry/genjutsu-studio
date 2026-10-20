# Genjutsu Studio — rules for every session

## Security review gate (mandatory)
Every code, config, DB-migration or secret change must be reviewed by a security agent **before** it is
committed+pushed, deployed (`supabase functions deploy`, GitHub Pages) or applied (SQL, secrets).
- Spawn a fresh security-reviewer agent with the diff (`git diff`) and the context of what changed and why.
- Proceed only after the agent returns an explicit **ACCEPT**. Fix every finding it raises and re-submit until it accepts.
- No exceptions for "small" or "copy-only" changes. If the review can't run, don't ship — tell Shoham.

## Deploys must not break users mid-action (mandatory)
- Every change must be backward compatible with what's live: apply DB migrations first and keep them additive
  (new columns/functions, never drop or rename in the same deploy); server code must accept requests from the
  previous app.js; the frontend must work against the previous server for the few minutes Pages takes.
- Right before deploying, check nothing is in flight: no jobs in `submitting` and no PayPal order created in the
  last 5 minutes that isn't completed (`select ... from jobs where status='submitting'`,
  `select ... from payments where status='created' and created_at > now()-interval '5 minutes'`). If there is, wait.
- Money paths stay atomic: credits move only inside single-transaction RPCs (create_job, complete_payment,
  refund_job, claw_payment, charge_surcharge); never split a credit change across two calls.
- After deploying, re-check those queries and the latest jobs/payments; if anything got stuck, reconcile it (README).

Background: on 2026-10-15..19 the public site ran on sandbox PayPal; strangers paid with fake sandbox cards and
started real (paid) Higgsfield renders.
