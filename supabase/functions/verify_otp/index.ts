// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json().catch(() => ({}));
    const rawEmail = String(payload.email ?? payload.email_address ?? "").trim();
    const givenUserId = payload.user_id ?? payload.userId ?? null;
    const code = String(payload.code ?? "").trim();

    if ((!rawEmail && !givenUserId) || code.length !== 6) {
      return json({ error: "Missing email/user_id or invalid code" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    let user: any = null;
    if (rawEmail) {
      const { data, error } = await supabase
        .from("users")
        .select("id, verification_code, verification_expires_at")
        .eq("email", rawEmail)
        .maybeSingle();
      if (error) return json({ error: error.message }, 500);
      if (!data) return json({ error: "User not found" }, 404);
      user = data;
    } else {
      const { data, error } = await supabase
        .from("users")
        .select("id, verification_code, verification_expires_at")
        .eq("id", givenUserId)
        .maybeSingle();
      if (error) return json({ error: error.message }, 500);
      if (!data) return json({ error: "User not found" }, 404);
      user = data;
    }

    if (user.verification_code !== code) {
      return json({ error: "Invalid code" }, 400);
    }

    if (
      user.verification_expires_at &&
      new Date(user.verification_expires_at) < new Date()
    ) {
      return json({ error: "Code expired" }, 400);
    }

    const { error: upErr } = await supabase
      .from("users")
      .update({
        is_verified: true,
        verification_code: null,
        verification_expires_at: null,
      })
      .eq("id", user.id);
    if (upErr) return json({ error: upErr.message }, 500);

    return json({ ok: true });
  } catch (e: any) {
    return json({ error: e?.message ?? String(e) }, 500);
  }
});

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
