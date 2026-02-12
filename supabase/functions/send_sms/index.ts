// supabase/functions/send_sms/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders: Record<string, string> = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SmsType = "plain" | "unicode";

type Payload = {
    landlord_phone: string;
    tenant_user_id: string; // MUST be auth.users.id
    message: string;

    // optional overrides
    tenant_phone?: string; // display-only (best effort)
    tenant_name?: string;
    sender_id?: string;
    type?: SmsType;
};

function jsonResponse(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}

/* ------------------------------------------------------------------ */
/* ✅ STRICT PH MOBILE NORMALIZER (use ONLY for landlord recipient)     */
/* ------------------------------------------------------------------ */
function normalizePHNumber(phone: string): string {
    let p = (phone || "").trim();

    // keep digits only (allow leading + first)
    p = p.replace(/[^\d+]/g, "");
    if (p.startsWith("+")) p = p.slice(1);

    // 09xxxxxxxxx -> 639xxxxxxxxx
    if (p.startsWith("09") && p.length === 11) p = "63" + p.slice(1);

    // 9xxxxxxxxx -> 639xxxxxxxxx
    if (p.startsWith("9") && p.length === 10) p = "63" + p;

    // 6309xxxxxxxxx (bad DB data) -> 639xxxxxxxxx
    if (p.startsWith("6309") && p.length === 13) p = "63" + p.slice(3);

    // ✅ final validation: PH mobile only
    if (!/^639\d{9}$/.test(p)) {
        throw new Error(`Invalid PH mobile number: "${phone}" -> "${p}"`);
    }

    return p;
}

/**
 * ✅ Best-effort normalizer for tenant_phone (DISPLAY ONLY)
 * Never throws. If invalid, returns null.
 */
function tryNormalizePHMobile(phone: string): string | null {
    try {
        return normalizePHNumber(phone);
    } catch {
        return null;
    }
}

/* ------------------------------------------------------------------ */

function pickName(row: any): string {
    if (!row) return "";
    const v =
        row.fullname ??
        row.full_name ??
        row.fullName ??
        row.name ??
        "";
    const s = (v ?? "").toString().trim();
    if (s) return s;

    // handle users table: first_name + last_name
    const first = (row.first_name ?? "").toString().trim();
    const last = (row.last_name ?? "").toString().trim();
    return `${first} ${last}`.trim();
}

function pickPhone(row: any): string {
    if (!row) return "";
    return (
        row.phone ??
        row.contact_number ??
        row.mobile ??
        row.phone_number ??
        row.number ??
        ""
    )
        .toString()
        .trim();
}

async function restGetOne(table: string, filter: string, select = "*") {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) {
        return { ok: false, error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY", row: null };
    }

    const endpoint = `${url}/rest/v1/${table}?${filter}&select=${encodeURIComponent(select)}&limit=1`;

    const res = await fetch(endpoint, {
        headers: {
            apikey: serviceKey,
            Authorization: `Bearer ${serviceKey}`,
        },
    });

    const raw = await res.text();
    if (!res.ok) return { ok: false, error: raw, row: null };

    let data: any;
    try {
        data = JSON.parse(raw);
    } catch {
        return { ok: false, error: "Non-JSON response from PostgREST", row: null };
    }

    const row = Array.isArray(data) && data.length ? data[0] : null;
    return { ok: true, error: null, row };
}

async function sendViaPhilSMS(params: {
    apiKey: string;
    recipient: string;
    sender_id: string;
    type: SmsType;
    message: string;
}) {
    const res = await fetch("https://dashboard.philsms.com/api/v3/sms/send", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${params.apiKey}`,
        },
        body: JSON.stringify({
            recipient: params.recipient,
            sender_id: params.sender_id,
            type: params.type,
            message: params.message,
        }),
    });

    const raw = await res.text();
    let parsed: any = raw;
    try {
        parsed = JSON.parse(raw);
    } catch { }

    return { ok: res.ok, status: res.status, provider_response: parsed };
}

/* ------------------------------------------------------------------ */

serve(async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    try {
        const apiKey = Deno.env.get("PHILSMS_API_KEY");
        if (!apiKey) return jsonResponse({ error: "PHILSMS_API_KEY not set" }, 500);

        const body = (await req.json()) as Payload;

        if (!body.landlord_phone?.trim()) return jsonResponse({ error: "Missing landlord_phone" }, 400);
        if (!body.tenant_user_id?.trim()) return jsonResponse({ error: "Missing tenant_user_id" }, 400);
        if (!body.message?.trim()) return jsonResponse({ error: "Missing message" }, 400);

        // ✅ landlord is the actual SMS recipient → MUST be valid
        const landlordPhone = normalizePHNumber(body.landlord_phone);

        // ✅ tenant info is display-only → never block sending if phone is messy
        let tenantName = (body.tenant_name ?? "").trim();
        let tenantPhone = (body.tenant_phone ?? "").trim();

        if (tenantPhone) {
            tenantPhone = tryNormalizePHMobile(tenantPhone) ?? "UNKNOWN";
        }

        // Lookups (best-effort)
        const prof = await restGetOne("tenant_profile", `user_id=eq.${body.tenant_user_id}`);
        const user = await restGetOne(
            "users",
            `id=eq.${body.tenant_user_id}`,
            "id,full_name,first_name,last_name,phone,contact_number"
        );
        const rt = await restGetOne("room_tenants", `user_id=eq.${body.tenant_user_id}`);

        if (!tenantName) {
            tenantName = pickName(prof.row) || pickName(user.row) || pickName(rt.row);
        }

        if (!tenantPhone || tenantPhone === "UNKNOWN") {
            const rawPhone = pickPhone(prof.row) || pickPhone(user.row) || pickPhone(rt.row);
            if (rawPhone) tenantPhone = tryNormalizePHMobile(rawPhone) ?? "UNKNOWN";
        }

        if (!tenantName) {
            // still allow sending? up to you. Here we default to "Tenant"
            tenantName = "Tenant";
        }

        // ✅ your format
        const finalMessage =
            `${tenantName} (${tenantPhone || "UNKNOWN"})\n` +
            `Message: ${body.message.trim()}`;

        const sender_id = body.sender_id ?? "PhilSMS";
        const type: SmsType = body.type ?? "plain";

        const result = await sendViaPhilSMS({
            apiKey,
            recipient: landlordPhone,
            sender_id,
            type,
            message: finalMessage,
        });

        // NOTE: provider can still "accept" but later fail; return provider_response for debugging.
        if (!result.ok) {
            return jsonResponse(
                {
                    error: "PhilSMS request failed",
                    sent_to_raw: body.landlord_phone,
                    sent_to_normalized: landlordPhone,
                    formatted_message: finalMessage,
                    provider_response: result.provider_response,
                },
                502
            );
        }

        return jsonResponse({
            ok: true,
            sent_to_raw: body.landlord_phone,
            sent_to_normalized: landlordPhone,
            formatted_message: finalMessage,
            provider_http_status: result.status,
            provider_response: result.provider_response,
        });
    } catch (e: any) {
        return jsonResponse({ error: e?.message ?? String(e) }, 500);
    }
});
