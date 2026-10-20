// Fail closed: only an exact "live" or "sandbox" is accepted (sandbox is further limited to
// TEST_EMAILS accounts in the paypal function). Anything else stops every PayPal call.
const ENV = Deno.env.get("PAYPAL_ENV");
export const PP_BASE = ENV === "live" ? "https://api-m.paypal.com"
  : ENV === "sandbox" ? "https://api-m.sandbox.paypal.com" : "";

export async function ppToken(): Promise<string> {
  if (!PP_BASE) throw new Error("PAYPAL_ENV must be 'live' or 'sandbox'");
  const basic = btoa(`${Deno.env.get("PAYPAL_CLIENT_ID")}:${Deno.env.get("PAYPAL_CLIENT_SECRET")}`);
  const r = await fetch(`${PP_BASE}/v1/oauth2/token`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials",
  });
  if (!r.ok) throw new Error(`PayPal auth failed: ${r.status}`);
  return (await r.json()).access_token;
}
