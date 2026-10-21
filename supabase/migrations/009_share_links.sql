-- Public share links (2026-10-21). The owner clicks Share on a finished video; the server gives it a random
-- token, and /watch/?v=<token> shows that one video to anyone. Additive. Clients still can't read jobs of
-- others: the public lookup goes through the share edge function, which returns only the video and trend.
alter table public.jobs add column if not exists share_token text;
create unique index if not exists jobs_share_token on public.jobs (share_token) where share_token is not null;

-- "Delete" on My videos hides the video for its owner and turns its share link off. The row stays,
-- because payments, refunds and reports depend on it.
alter table public.jobs add column if not exists hidden_at timestamptz;
