import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ParentInvite = {
  id: string;
  family_id: string;
  parent_name: string;
  status: "pending" | "accepted" | "expired" | "revoked";
  expires_at: string;
  accepted_parent_user_id: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "missing_authorization" }, 401);
  }

  const body = await request.json().catch(() => null) as { token?: string } | null;
  const token = body?.token?.trim();
  if (!token) {
    return json({ error: "missing_token" }, 400);
  }

  const supabaseUrl = getEnv("SUPABASE_URL");
  const anonKey = getEnv("SUPABASE_ANON_KEY");
  const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "invalid_authorization" }, 401);
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const tokenHash = await sha256Hex(token);

  const { data: inviteData, error: inviteError } = await serviceClient
    .from("parent_invites")
    .select("id,family_id,parent_name,status,expires_at,accepted_parent_user_id")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (inviteError) {
    console.error(inviteError);
    return json({ error: "invite_lookup_failed" }, 500);
  }

  if (!inviteData) {
    return json({ error: "invite_not_found" }, 404);
  }

  const invite = inviteData as ParentInvite;

  if (invite.status === "accepted") {
    if (invite.accepted_parent_user_id === userData.user.id) {
      return acceptedResponse(invite, userData.user.id);
    }

    return json({ error: "invite_already_accepted" }, 409);
  }

  if (invite.status === "revoked") {
    return json({ error: "invite_revoked" }, 409);
  }

  if (invite.status === "expired" || new Date(invite.expires_at).getTime() <= Date.now()) {
    await serviceClient
      .from("parent_invites")
      .update({ status: "expired" })
      .eq("id", invite.id);

    return json({ error: "invite_expired" }, 409);
  }

  const { error: memberError } = await serviceClient
    .from("family_members")
    .upsert({
      family_id: invite.family_id,
      user_id: userData.user.id,
      role: "parent",
      display_name: invite.parent_name,
    }, { onConflict: "family_id,user_id" });

  if (memberError) {
    console.error(memberError);
    return json({ error: "membership_link_failed" }, 500);
  }

  const { data: acceptedInviteData, error: updateError } = await serviceClient
    .from("parent_invites")
    .update({
      status: "accepted",
      accepted_at: new Date().toISOString(),
      accepted_parent_user_id: userData.user.id,
    })
    .eq("id", invite.id)
    .select("id,family_id,parent_name,status,expires_at,accepted_parent_user_id")
    .single();

  if (updateError) {
    console.error(updateError);
    return json({ error: "invite_accept_failed" }, 500);
  }

  return acceptedResponse(acceptedInviteData as ParentInvite, userData.user.id);
});

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing ${name}`);
  }
  return value;
}

function acceptedResponse(invite: ParentInvite, userId: string): Response {
  return json({
    family_id: invite.family_id,
    parent_name: invite.parent_name,
    accepted_parent_user_id: userId,
  });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
