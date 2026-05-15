// ============================================================================
// Edge Function: webauthn
// ----------------------------------------------------------------------------
// Gestiona la "ceremonia" WebAuthn (passkeys) — 4 acciones:
//
//   { "action": "register-options" }   (requiere sesión)
//      Genera el challenge + opciones para que el navegador llame a
//      navigator.credentials.create(). Guarda el challenge para verificarlo
//      después.
//
//   { "action": "register-verify", "challengeId", "response", "friendlyName" }
//      Verifica la respuesta del navegador, guarda la public key del passkey
//      en `webauthn_credentials`. El usuario ya tiene un passkey registrado.
//
//   { "action": "auth-options" }   (sin sesión)
//      Genera challenge para login con passkey (discoverable credentials).
//
//   { "action": "auth-verify", "challengeId", "response" }
//      Verifica la respuesta, identifica al usuario por su credential_id,
//      llama a admin.generateLink para mintar un token, y lo devuelve. La
//      app lo canjea con verifyOTP y obtiene una sesión Supabase real.
//
// Seguridad: aunque está marcado `verify_jwt = true` por defecto, los flujos
// de auth-options/auth-verify pueden invocarse con el anon key como
// Authorization (sin sesión). El propio Supabase exige Authorization para
// invocar Edge Functions, pero acepta el anon key — eso es suficiente para
// el flujo de login con passkey.
//
// rpId / origin se derivan dinámicamente del header `Origin` del request, así
// que localhost en dev y dominio real en prod funcionan sin tocar código.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "npm:@simplewebauthn/server@10";
import type {
  AuthenticationResponseJSON,
  RegistrationResponseJSON,
} from "npm:@simplewebauthn/server@10/script/deps";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Deriva rpId y origin del header Origin del request. Ej:
//   Origin: http://localhost:5000   → rpId='localhost', origin='http://localhost:5000'
//   Origin: https://app.example.com → rpId='app.example.com', origin='https://app.example.com'
function parseRp(req: Request): { rpId: string; origin: string } {
  const originHeader = req.headers.get("Origin") ?? "";
  try {
    const u = new URL(originHeader);
    return { rpId: u.hostname, origin: originHeader };
  } catch (_) {
    return { rpId: "localhost", origin: "http://localhost:5000" };
  }
}

const RP_NAME = "myapp";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "missing_authorization" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);
    const body = await req.json().catch(() => ({}));
    const action = body?.action;
    const { rpId, origin } = parseRp(req);

    // Identificar al usuario (puede no haberlo: auth-options / auth-verify).
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user ?? null;

    // ===== REGISTER OPTIONS ==================================================
    if (action === "register-options") {
      if (!user) return json({ error: "auth_required" }, 401);

      // Lista los credenciales que el usuario ya tiene → excludeCredentials
      // (evita que el navegador registre dos veces el mismo passkey).
      const { data: existing } = await admin
        .from("webauthn_credentials")
        .select("credential_id, transports")
        .eq("user_id", user.id);

      const options = await generateRegistrationOptions({
        rpName: RP_NAME,
        rpID: rpId,
        userID: new TextEncoder().encode(user.id),
        userName: user.email ?? user.id,
        userDisplayName:
          (user.user_metadata?.display_name as string | undefined) ??
          (user.user_metadata?.username as string | undefined) ??
          user.email ??
          user.id,
        attestationType: "none",
        authenticatorSelection: {
          residentKey: "preferred",
          userVerification: "preferred",
        },
        excludeCredentials: (existing ?? []).map((c) => ({
          id: c.credential_id,
          transports: c.transports as
            | ("internal" | "hybrid" | "usb" | "nfc" | "ble")[]
            | undefined,
        })),
      });

      const { data: ch, error: chErr } = await admin
        .from("webauthn_challenges")
        .insert({
          user_id: user.id,
          challenge: options.challenge,
          type: "registration",
        })
        .select("id")
        .single();
      if (chErr) {
        return json(
          { error: "challenge_store_failed", detail: chErr.message },
          500,
        );
      }
      return json({ options, challengeId: ch.id });
    }

    // ===== REGISTER VERIFY ===================================================
    if (action === "register-verify") {
      if (!user) return json({ error: "auth_required" }, 401);
      const challengeId = body?.challengeId as string | undefined;
      const response = body?.response as RegistrationResponseJSON | undefined;
      const friendlyName = (body?.friendlyName as string | undefined) ?? null;
      if (!challengeId || !response) {
        return json({ error: "missing_fields" }, 400);
      }

      const { data: ch } = await admin
        .from("webauthn_challenges")
        .select("challenge, expires_at, user_id")
        .eq("id", challengeId)
        .eq("type", "registration")
        .maybeSingle();
      if (!ch || ch.user_id !== user.id) {
        return json({ error: "challenge_not_found" }, 400);
      }
      if (new Date(ch.expires_at) < new Date()) {
        return json({ error: "challenge_expired" }, 400);
      }

      const verification = await verifyRegistrationResponse({
        response,
        expectedChallenge: ch.challenge,
        expectedOrigin: origin,
        expectedRPID: rpId,
        requireUserVerification: false,
      });
      if (!verification.verified || !verification.registrationInfo) {
        return json({ error: "verification_failed" }, 400);
      }
      const info = verification.registrationInfo;

      // El SDK 10.x expone los datos en `credential` o (legacy) campos top-level.
      // Soportamos ambas formas para robustez.
      // deno-lint-ignore no-explicit-any
      const cred: any = (info as any).credential ?? info;
      const credentialID: string = cred.id ?? cred.credentialID;
      const publicKeyRaw = cred.publicKey ?? cred.credentialPublicKey;
      const counter: number = cred.counter ?? 0;
      const transports: string[] | undefined =
        response.response.transports as string[] | undefined;
      const deviceType: string | undefined =
        info.credentialDeviceType as string | undefined;
      const backedUp: boolean = !!info.credentialBackedUp;

      // publicKey llega como Uint8Array; lo guardamos en base64url.
      const publicKeyB64 = btoa(String.fromCharCode(...publicKeyRaw))
        .replace(/\+/g, "-")
        .replace(/\//g, "_")
        .replace(/=+$/, "");

      const ins = await admin.from("webauthn_credentials").insert({
        user_id: user.id,
        credential_id: credentialID,
        public_key: publicKeyB64,
        counter,
        device_type: deviceType,
        backed_up: backedUp,
        transports,
        friendly_name: friendlyName,
      });
      if (ins.error) {
        return json({ error: "insert_failed", detail: ins.error.message }, 500);
      }
      await admin
        .from("webauthn_challenges")
        .delete()
        .eq("id", challengeId);

      return json({ success: true });
    }

    // ===== AUTH OPTIONS ======================================================
    if (action === "auth-options") {
      const options = await generateAuthenticationOptions({
        rpID: rpId,
        userVerification: "preferred",
        // allowCredentials vacío → discoverable credentials (el navegador
        // muestra el selector de passkeys del usuario sin que tengamos que
        // saber su email todavía).
        allowCredentials: [],
      });
      const { data: ch, error: chErr } = await admin
        .from("webauthn_challenges")
        .insert({
          challenge: options.challenge,
          type: "authentication",
        })
        .select("id")
        .single();
      if (chErr) {
        return json(
          { error: "challenge_store_failed", detail: chErr.message },
          500,
        );
      }
      return json({ options, challengeId: ch.id });
    }

    // ===== AUTH VERIFY =======================================================
    if (action === "auth-verify") {
      const challengeId = body?.challengeId as string | undefined;
      const response = body?.response as AuthenticationResponseJSON | undefined;
      if (!challengeId || !response) {
        return json({ error: "missing_fields" }, 400);
      }

      const { data: ch } = await admin
        .from("webauthn_challenges")
        .select("challenge, expires_at")
        .eq("id", challengeId)
        .eq("type", "authentication")
        .maybeSingle();
      if (!ch) return json({ error: "challenge_not_found" }, 400);
      if (new Date(ch.expires_at) < new Date()) {
        return json({ error: "challenge_expired" }, 400);
      }

      // Busca la credencial por su id (lo envía el navegador en response.id).
      const { data: cred } = await admin
        .from("webauthn_credentials")
        .select("id, user_id, public_key, counter, transports")
        .eq("credential_id", response.id)
        .maybeSingle();
      if (!cred) return json({ error: "credential_not_found" }, 401);

      // Decodifica la public key de base64url a Uint8Array.
      const padded = cred.public_key
        .replace(/-/g, "+")
        .replace(/_/g, "/")
        .padEnd(
          cred.public_key.length + ((4 - (cred.public_key.length % 4)) % 4),
          "=",
        );
      const pkBytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));

      const verification = await verifyAuthenticationResponse({
        response,
        expectedChallenge: ch.challenge,
        expectedOrigin: origin,
        expectedRPID: rpId,
        credential: {
          id: response.id,
          publicKey: pkBytes,
          counter: Number(cred.counter ?? 0),
          transports: (cred.transports ?? []) as (
            | "internal"
            | "hybrid"
            | "usb"
            | "nfc"
            | "ble"
          )[],
        },
        requireUserVerification: false,
      });
      if (!verification.verified) {
        return json({ error: "verification_failed" }, 401);
      }

      // Actualiza el counter (anti-clonado) y last_used_at.
      await admin
        .from("webauthn_credentials")
        .update({
          counter: verification.authenticationInfo.newCounter,
          last_used_at: new Date().toISOString(),
        })
        .eq("id", cred.id);
      await admin
        .from("webauthn_challenges")
        .delete()
        .eq("id", challengeId);

      // Mintar una sesión Supabase: pedimos un magic link via admin API y
      // devolvemos el `hashed_token`. La app lo canjea con
      // `verifyOTP({token_hash, type: 'magiclink'})` y obtiene la sesión.
      const { data: targetUser } = await admin.auth.admin.getUserById(
        cred.user_id,
      );
      const email = targetUser?.user?.email;
      if (!email) return json({ error: "user_email_missing" }, 500);

      const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
        type: "magiclink",
        email,
      });
      if (linkErr || !link?.properties?.hashed_token) {
        return json(
          { error: "session_mint_failed", detail: linkErr?.message },
          500,
        );
      }
      return json({
        tokenHash: link.properties.hashed_token,
        email,
      });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    return json({ error: "internal_error", detail: String(e) }, 500);
  }
});
