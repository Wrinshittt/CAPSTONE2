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
    const providedFullName = payload.full_name ?? payload.name ?? null;

    // Accept email OR user_id (but not neither)
    if (!rawEmail && !givenUserId) {
      return json({ error: "Missing email or user_id" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Look up the user row by whichever identifier we got
    let user: any = null;
    if (rawEmail) {
      const { data, error } = await supabase
        .from("users")
        .select("id,email,full_name")
        .eq("email", rawEmail)
        .maybeSingle();
      if (error) return json({ error: error.message }, 500);
      if (!data) return json({ error: "Email not found" }, 404);
      user = data;
    } else {
      const { data, error } = await supabase
        .from("users")
        .select("id,email,full_name")
        .eq("id", givenUserId)
        .maybeSingle();
      if (error) return json({ error: error.message }, 500);
      if (!data) return json({ error: "User not found" }, 404);
      user = data;
    }

    const email = user.email as string;
    const full_name = (providedFullName ?? user.full_name ?? "").toString();

    // Generate 6-digit code & expiry (10 minutes)
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    // Store on the user
    const { error: upErr } = await supabase
      .from("users")
      .update({
        verification_code: code,
        verification_expires_at: expiresAt,
        is_verified: false,
      })
      .eq("id", user.id);
    if (upErr) return json({ error: upErr.message }, 500);

    // Send the email via SendGrid
    const SG_KEY = Deno.env.get("SENDGRID_API_KEY");
    const FROM_EMAIL = Deno.env.get("FROM_EMAIL");
    const FROM_NAME = Deno.env.get("FROM_NAME") ?? "Smart Finder";
    if (!SG_KEY || !FROM_EMAIL) {
      return json({ error: "Missing SENDGRID_API_KEY or FROM_EMAIL secret" }, 500);
    }

    const mailBody = {
      personalizations: [{ to: [{ email }] }],
      from: { email: FROM_EMAIL, name: FROM_NAME },
      subject: "Your verification code",
      content: [
        {
          type: "text/plain",
          value:
            `Hi ${full_name}!\n\nYour verification code is ${code}.\nIt expires in 10 minutes.\n\n— Smart Finder`,
        },
      ],
    };

    const sgRes = await fetch("https://api.sendgrid.com/v3/mail/send", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${SG_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(mailBody),
    });

    if (!sgRes.ok) {
      const text = await sgRes.text();
      return json({ error: "sendgrid_failed", detail: text }, 500);
    }

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
