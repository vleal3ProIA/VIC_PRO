// ============================================================================
// Edge Function: admin-coupons
// ----------------------------------------------------------------------------
// CRUD del catálogo de cupones + códigos promocionales. Espejo local +
// sync con Stripe Coupons/PromotionCodes API. Las operaciones que solo
// tocan BD podrían ir directas con RLS-admin, pero centralizamos aquí
// para garantizar que Stripe queda consistente.
//
// Acciones:
//
//   { "action": "list" }
//     Devuelve todos los cupones (activos y desactivados) con sus
//     promotion_codes asociados embebidos.
//
//   { "action": "create_coupon",
//     "name": "Black Friday 2026",
//     "percent_off"?: 20,            // O bien percent_off O bien amount_off
//     "amount_off_cents"?: 500,      // (uno y solo uno)
//     "currency"?: "EUR",            // requerido si amount_off
//     "duration": "once|repeating|forever",
//     "duration_in_months"?: 3,      // requerido si repeating
//     "max_redemptions"?: 100,
//     "redeem_by"?: "2026-12-31T23:59:59Z",
//     "applies_to_plan_slugs"?: ["pro","team"] }
//     Crea en Stripe → inserta en BD → devuelve la fila completa.
//
//   { "action": "deactivate_coupon", "coupon_id": "<uuid>" }
//     Stripe: DELETE /v1/coupons/{stripe_id} (soft-delete).
//     BD: is_active=false. También desactiva los promotion_codes hijos
//     que sigan activos (idempotente).
//
//   { "action": "create_promotion_code",
//     "coupon_id": "<uuid>",
//     "code": "VERANO2026",
//     "max_redemptions"?: 50,
//     "expires_at"?: "2026-09-01T00:00:00Z",
//     "first_time_transaction"?: false }
//     Crea en Stripe → inserta en BD.
//
//   { "action": "deactivate_promotion_code", "promotion_code_id": "<uuid>" }
//     Stripe: POST /v1/promotion_codes/{stripe_id} con active=false.
//     BD: is_active=false.
//
// Seguridad: JWT + role=admin + rate limit 60/h/user.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { getStripe, stripeNotConfigured } from "../_shared/stripe.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

Deno.serve(withSentry("admin-coupons", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const stripe = getStripe();
  if (!stripe) return stripeNotConfigured();

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: adminCheck } = await admin
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  if (!adminCheck || (adminCheck.role as string) !== "admin") {
    return json({ error: "not_admin" }, 403);
  }

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `admin:coupons:user:${user.id}`,
    limit: 60,
    windowSeconds: 3600,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const action = body.action as string | undefined;

  // ──────────────────────────────── LIST ─────────────────────────────────

  if (action === "list") {
    const { data: coupons, error: cErr } = await admin
      .from("coupons")
      .select(
        "id, stripe_coupon_id, name, percent_off, amount_off_cents, currency, " +
          "duration, duration_in_months, max_redemptions, redeem_by, " +
          "applies_to_plan_slugs, is_active, times_redeemed, created_at",
      )
      .order("is_active", { ascending: false })
      .order("created_at", { ascending: false });
    if (cErr) return json({ error: "db_error", detail: cErr.message }, 500);

    const { data: codes, error: pErr } = await admin
      .from("promotion_codes")
      .select(
        "id, stripe_promotion_code_id, coupon_id, code, max_redemptions, " +
          "expires_at, first_time_transaction, is_active, times_redeemed, created_at",
      )
      .order("is_active", { ascending: false })
      .order("created_at", { ascending: false });
    if (pErr) return json({ error: "db_error", detail: pErr.message }, 500);

    return json({ coupons: coupons ?? [], promotion_codes: codes ?? [] }, 200);
  }

  // ───────────────────────────── CREATE COUPON ───────────────────────────

  if (action === "create_coupon") {
    const name = (body.name as string | undefined)?.trim();
    const percentOff = body.percent_off as number | undefined;
    const amountOffCents = body.amount_off_cents as number | undefined;
    const currency = body.currency as string | undefined;
    const duration = body.duration as string | undefined;
    const durationInMonths = body.duration_in_months as number | undefined;
    const maxRedemptions = body.max_redemptions as number | undefined;
    const redeemBy = body.redeem_by as string | undefined;
    const appliesPlans = body.applies_to_plan_slugs as string[] | undefined;

    if (!name) return json({ error: "missing_name" }, 400);
    if (!duration || !["once", "repeating", "forever"].includes(duration)) {
      return json({ error: "invalid_duration" }, 400);
    }
    const hasPct = typeof percentOff === "number";
    const hasAmt = typeof amountOffCents === "number";
    if (hasPct === hasAmt) {
      return json({ error: "need_exactly_one_off" }, 400);
    }
    if (hasAmt && !currency) {
      return json({ error: "amount_needs_currency" }, 400);
    }
    if (duration === "repeating" && !durationInMonths) {
      return json({ error: "repeating_needs_months" }, 400);
    }

    try {
      // deno-lint-ignore no-explicit-any
      const stripePayload: Record<string, any> = {
        name,
        duration,
      };
      if (hasPct) stripePayload.percent_off = percentOff;
      if (hasAmt) {
        stripePayload.amount_off = amountOffCents;
        stripePayload.currency = (currency as string).toLowerCase();
      }
      if (durationInMonths) stripePayload.duration_in_months = durationInMonths;
      if (maxRedemptions) stripePayload.max_redemptions = maxRedemptions;
      if (redeemBy) {
        stripePayload.redeem_by = Math.floor(
          new Date(redeemBy).getTime() / 1000,
        );
      }

      const stripeCoupon = await stripe.coupons.create(stripePayload);

      const { data: row, error: insErr } = await admin
        .from("coupons")
        .insert({
          stripe_coupon_id: stripeCoupon.id,
          name,
          percent_off: hasPct ? percentOff : null,
          amount_off_cents: hasAmt ? amountOffCents : null,
          currency: hasAmt ? (currency as string).toUpperCase() : null,
          duration,
          duration_in_months: durationInMonths ?? null,
          max_redemptions: maxRedemptions ?? null,
          redeem_by: redeemBy ?? null,
          applies_to_plan_slugs: appliesPlans ?? null,
        })
        .select()
        .single();

      if (insErr) {
        // Rollback en Stripe para no dejar el cupón huérfano.
        try {
          await stripe.coupons.del(stripeCoupon.id);
        } catch (_) { /* best-effort */ }
        return json({ error: "db_error", detail: insErr.message }, 500);
      }
      return json({ coupon: row }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ───────────────────────── DEACTIVATE COUPON ───────────────────────────

  if (action === "deactivate_coupon") {
    const couponId = body.coupon_id as string | undefined;
    if (!couponId) return json({ error: "missing_coupon_id" }, 400);

    const { data: c, error: selErr } = await admin
      .from("coupons")
      .select("id, stripe_coupon_id, is_active")
      .eq("id", couponId)
      .maybeSingle();
    if (selErr) return json({ error: "db_error", detail: selErr.message }, 500);
    if (!c) return json({ error: "not_found" }, 404);
    if (!c.is_active) return json({ already: true }, 200);

    try {
      if (c.stripe_coupon_id) {
        try {
          await stripe.coupons.del(c.stripe_coupon_id);
        } catch (e) {
          // 404 en Stripe es OK (ya borrado); cualquier otro error propaga.
          const msg = (e as Error).message ?? "";
          if (!/No such coupon/i.test(msg)) {
            return json({ error: "stripe_error", detail: msg }, 500);
          }
        }
      }
      await admin
        .from("coupons")
        .update({ is_active: false })
        .eq("id", couponId);
      // Desactivar también los códigos hijos que sigan activos.
      await admin
        .from("promotion_codes")
        .update({ is_active: false })
        .eq("coupon_id", couponId)
        .eq("is_active", true);
      return json({ ok: true }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ─────────────────────── CREATE PROMOTION CODE ─────────────────────────

  if (action === "create_promotion_code") {
    const couponId = body.coupon_id as string | undefined;
    const codeRaw = (body.code as string | undefined)?.trim();
    const maxRedemptions = body.max_redemptions as number | undefined;
    const expiresAt = body.expires_at as string | undefined;
    const firstTimeTx = (body.first_time_transaction as boolean | undefined) ?? false;

    if (!couponId) return json({ error: "missing_coupon_id" }, 400);
    if (!codeRaw) return json({ error: "missing_code" }, 400);
    const code = codeRaw.toUpperCase();
    if (!/^[A-Z0-9_-]{3,32}$/.test(code)) {
      return json({ error: "invalid_code" }, 400);
    }

    const { data: c, error: selErr } = await admin
      .from("coupons")
      .select("id, stripe_coupon_id, is_active")
      .eq("id", couponId)
      .maybeSingle();
    if (selErr) return json({ error: "db_error", detail: selErr.message }, 500);
    if (!c) return json({ error: "coupon_not_found" }, 404);
    if (!c.is_active) return json({ error: "coupon_inactive" }, 400);
    if (!c.stripe_coupon_id) {
      return json({ error: "coupon_not_synced_with_stripe" }, 500);
    }

    try {
      // deno-lint-ignore no-explicit-any
      const stripePayload: Record<string, any> = {
        coupon: c.stripe_coupon_id,
        code,
      };
      if (maxRedemptions) stripePayload.max_redemptions = maxRedemptions;
      if (expiresAt) {
        stripePayload.expires_at = Math.floor(
          new Date(expiresAt).getTime() / 1000,
        );
      }
      if (firstTimeTx) {
        stripePayload.restrictions = { first_time_transaction: true };
      }

      const stripePromo = await stripe.promotionCodes.create(stripePayload);

      const { data: row, error: insErr } = await admin
        .from("promotion_codes")
        .insert({
          stripe_promotion_code_id: stripePromo.id,
          coupon_id: couponId,
          code,
          max_redemptions: maxRedemptions ?? null,
          expires_at: expiresAt ?? null,
          first_time_transaction: firstTimeTx,
        })
        .select()
        .single();

      if (insErr) {
        // No hay del() en promotionCodes (Stripe los desactiva, no borra).
        // Hacemos best-effort de desactivar para no dejar uno huérfano y
        // activo en Stripe.
        try {
          await stripe.promotionCodes.update(stripePromo.id, { active: false });
        } catch (_) { /* best-effort */ }
        return json({ error: "db_error", detail: insErr.message }, 500);
      }
      return json({ promotion_code: row }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  // ─────────────────── DEACTIVATE PROMOTION CODE ─────────────────────────

  if (action === "deactivate_promotion_code") {
    const id = body.promotion_code_id as string | undefined;
    if (!id) return json({ error: "missing_promotion_code_id" }, 400);

    const { data: p, error: selErr } = await admin
      .from("promotion_codes")
      .select("id, stripe_promotion_code_id, is_active")
      .eq("id", id)
      .maybeSingle();
    if (selErr) return json({ error: "db_error", detail: selErr.message }, 500);
    if (!p) return json({ error: "not_found" }, 404);
    if (!p.is_active) return json({ already: true }, 200);

    try {
      if (p.stripe_promotion_code_id) {
        await stripe.promotionCodes.update(p.stripe_promotion_code_id, {
          active: false,
        });
      }
      await admin
        .from("promotion_codes")
        .update({ is_active: false })
        .eq("id", id);
      return json({ ok: true }, 200);
    } catch (e) {
      return json(
        { error: "stripe_error", detail: (e as Error).message },
        500,
      );
    }
  }

  return json({ error: "unknown_action" }, 400);
}));
