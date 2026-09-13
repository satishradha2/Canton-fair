const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});

const escapeHtml = (value: unknown) => String(value ?? "")
  .replaceAll("&", "&amp;").replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");

async function hash(value: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function page(title: string, content: string) {
  return new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title><style>body{font-family:system-ui;margin:0;background:#f4f6fa;color:#132238}.wrap{max-width:720px;margin:auto;padding:32px 18px}main{background:white;border:1px solid #dce2ea;border-radius:8px;padding:24px}label{display:block;font-weight:700;margin-top:16px}input,textarea{box-sizing:border-box;width:100%;padding:12px;margin-top:6px;border:1px solid #aab5c3;border-radius:6px;font:inherit}button{margin-top:20px;padding:12px 18px;background:#075b67;color:white;border:0;border-radius:6px;font-weight:700}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style></head><body><div class="wrap"><main>${content}</main></div></body></html>`, {
    headers: { ...cors, "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: cors });
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json(503, { error: "Sharing service is not configured." });
  const current = new URL(request.url);
  const token = current.searchParams.get("t") ?? "";

  if (request.method === "POST" && !token) {
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer\s+\S+$/i.test(authorization)) return json(401, { error: "Sign in required." });
    const auth = await fetch(`${url}/auth/v1/user`, { headers: { apikey: serviceKey, Authorization: authorization } });
    if (!auth.ok) return json(401, { error: "Session could not be verified." });
    const user = await auth.json();
    const body = await request.json();
    if (typeof body.team_id !== "string") return json(400, { error: "Team is required." });
    const member = await fetch(`${url}/rest/v1/team_members?team_id=eq.${encodeURIComponent(body.team_id)}&user_id=eq.${encodeURIComponent(user.id)}&select=role`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
    });
    if (!member.ok || (await member.json()).length === 0) return json(403, { error: "Team membership required." });
    if (body.action === "responses") {
      const responses = await fetch(`${url}/rest/v1/external_share_tokens?team_id=eq.${encodeURIComponent(body.team_id)}&mode=eq.supplier_request&response=not.is.null&select=id,title,response,responded_at,created_at&order=responded_at.desc`, {
        headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      });
      if (!responses.ok) return json(503, { error: "Could not load supplier responses." });
      return json(200, { responses: await responses.json() });
    }
    if (body.action !== "create" || !["supplier_request", "read_only"].includes(body.mode) ||
        typeof body.title !== "string" || typeof body.payload !== "object" || body.payload == null) {
      return json(400, { error: "Invalid share request." });
    }
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    const secret = Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
    const hours = Math.min(720, Math.max(1, Number(body.expires_in_hours) || 168));
    const record = await fetch(`${url}/rest/v1/external_share_tokens`, {
      method: "POST", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({ token_hash: await hash(secret), team_id: body.team_id, created_by: user.id,
        mode: body.mode, title: body.title.slice(0, 200), payload: body.payload,
        expires_at: new Date(Date.now() + hours * 3600000).toISOString() }),
    });
    if (!record.ok) return json(503, { error: "Apply migration 016_external_sharing.sql first." });
    return json(200, { url: `${url}/functions/v1/external-share?t=${secret}`, expires_in_hours: hours });
  }

  if (!token || token.length !== 64) return page("Link unavailable", "<h1>Link unavailable</h1><p>This link is invalid.</p>");
  const result = await fetch(`${url}/rest/v1/external_share_tokens?token_hash=eq.${await hash(token)}&select=*`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  const rows = result.ok ? await result.json() : [];
  const item = rows[0];
  if (!item || new Date(item.expires_at).getTime() < Date.now() || item.revoked_at) {
    return page("Link expired", "<h1>Link expired</h1><p>Ask the sender for a new link.</p>");
  }

  if (request.method === "POST") {
    if (item.mode !== "supplier_request") return json(405, { error: "Read-only link." });
    const form = await request.formData();
    const response = Object.fromEntries(["company", "contact", "email", "phone", "quotation", "certificates", "notes"]
      .map((key) => [key, String(form.get(key) ?? "").slice(0, 20000)]));
    await fetch(`${url}/rest/v1/external_share_tokens?id=eq.${item.id}`, {
      method: "PATCH", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json" },
      body: JSON.stringify({ response, responded_at: new Date().toISOString() }),
    });
    return page("Information received", "<h1>Thank you</h1><p>Your information was securely submitted.</p>");
  }

  if (item.mode === "read_only") {
    return page(item.title, `<h1>${escapeHtml(item.title)}</h1><p>Shared supplier summary</p><pre>${escapeHtml(JSON.stringify(item.payload, null, 2))}</pre><p>This link expires ${escapeHtml(item.expires_at)}.</p>`);
  }
  return page(item.title, `<h1>${escapeHtml(item.title)}</h1><p>Please complete the requested supplier information.</p><form method="post">
    <label>Company name<input name="company"></label><label>Contact person<input name="contact"></label>
    <label>Email<input type="email" name="email"></label><label>Phone<input name="phone"></label>
    <label>Quotation details<textarea name="quotation" rows="4"></textarea></label>
    <label>Certificates and references<textarea name="certificates" rows="4"></textarea></label>
    <label>Additional notes<textarea name="notes" rows="5"></textarea></label><button type="submit">Submit information</button></form>`);
});
