// Public watch page (/watch/?v=<token>): shows one shared video. No sign-in; the share function returns
// only the video URL and the trend's slug for that token.
(async () => {
  const C = window.GENJUTSU_CONFIG;
  const v = new URLSearchParams(location.search).get("v") || "";
  const $ = (id) => document.getElementById(id);
  const fail = () => { $("watch-loading").hidden = true; $("watch-missing").hidden = false; };
  if (!/^[A-Za-z0-9_-]{22}$/.test(v)) return fail();
  try {
    const r = await fetch(`${C.SUPABASE_URL}/functions/v1/share?v=${encodeURIComponent(v)}`, { headers: { apikey: C.SUPABASE_ANON_KEY } });
    if (!r.ok) return fail();
    const d = await r.json();
    if (!/^https:\/\//.test(d.video_url || "")) return fail();
    const names = await fetch("/trend-names.json").then((x) => (x.ok ? x.json() : {})).catch(() => ({}));
    const slug = /^[a-z0-9-]{1,40}$/.test(d.trend) ? d.trend : "custom";
    const name = names[slug];
    const vid = $("watch-video"); vid.src = d.video_url; vid.hidden = false;
    $("watch-title").textContent = name ? `${name}, made with Genjutsu` : "Made with Genjutsu";
    const cta = $("watch-cta");
    cta.href = name ? `/trends/${slug}/` : "/";
    cta.textContent = name ? `Make your own ${name} video →` : "Make your own AI video →";
    $("watch-loading").hidden = true; $("watch-found").hidden = false;
  } catch { fail(); }
})();
