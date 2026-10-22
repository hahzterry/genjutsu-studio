// GET with header x-backup-secret -> the whole database, age-encrypted, plus a manifest without personal data.
// Called only by the nightly job in the private genjutsu-ops repo. The data is encrypted here, before it
// leaves Supabase, to BACKUP_AGE_RECIPIENT (a public key); only the owner's Mac holds the private key.
import { Encrypter } from "npm:age-encryption@0.3.1";
import { encodeBase64 } from "jsr:@std/encoding@1.0.10/base64";
import { admin, json, safeEqual, serve } from "../_shared/common.ts";

serve(async (req) => {
  const secret = Deno.env.get("BACKUP_SECRET") ?? "";
  if (secret.length < 32 || !safeEqual(req.headers.get("x-backup-secret") ?? "", secret)) {
    return json({ error: "unauthorized" }, 401);
  }
  const recipient = Deno.env.get("BACKUP_AGE_RECIPIENT") ?? "";
  if (!/^age1[0-9a-z]{58}$/.test(recipient)) { console.error("backup: bad BACKUP_AGE_RECIPIENT"); return json({ error: "not configured" }, 500); }
  const [snap, audit] = await Promise.all([admin.rpc("backup_snapshot"), admin.rpc("schema_audit")]);
  if (snap.error || audit.error || !snap.data) { console.error("backup failed", snap.error ?? audit.error); return json({ error: "backup failed" }, 500); }
  const plain = new TextEncoder().encode(JSON.stringify(snap.data));
  const e = new Encrypter();
  e.addRecipient(recipient);
  const ciphertext = await e.encrypt(plain);
  const sha = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", plain)), (b) => b.toString(16).padStart(2, "0")).join("");
  const tables = snap.data.tables as Record<string, unknown[]>;
  return json({
    manifest: {
      taken_at: snap.data.taken_at, plaintext_sha256: sha, plaintext_bytes: plain.length,
      rows: Object.fromEntries(Object.entries(tables).map(([k, v]) => [k, v.length])),
      auth_users: (snap.data.auth_users as unknown[]).length,
      structure: { tables: audit.data.tables.map((t: { name: string; kind: string; rls: boolean; policies: string[] }) => ({ name: t.name, kind: t.kind, rls: t.rls, policies: t.policies })),
        visitor_functions: audit.data.visitor_functions, buckets: audit.data.buckets },
    },
    ciphertext: encodeBase64(ciphertext),
  });
});
