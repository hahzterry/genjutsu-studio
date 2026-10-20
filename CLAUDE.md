# Genjutsu Studio — rules for every session

## Security review gate (mandatory)
Every code, config, DB-migration or secret change must be reviewed by a security agent **before** it is
committed+pushed, deployed (`supabase functions deploy`, GitHub Pages) or applied (SQL, secrets).
- Spawn a fresh security-reviewer agent with the diff (`git diff`) and the context of what changed and why.
- Proceed only after the agent returns an explicit **ACCEPT**. Fix every finding it raises and re-submit until it accepts.
- No exceptions for "small" or "copy-only" changes. If the review can't run, don't ship — tell Shoham.

Background: on 2026-10-15..19 the public site ran on sandbox PayPal; strangers paid with fake sandbox cards and
started real (paid) Higgsfield renders.
