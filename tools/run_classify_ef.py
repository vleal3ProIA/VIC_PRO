#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Invoca la EF `classify-question-bank` en bucle hasta procesar todas las
preguntas raiz del subject. Usa el ai-gateway del proyecto (Gemini con
fallback Groq), por lo que NO necesita exponer API keys: las credenciales
viven en `ai_credentials` de la BD.

Requiere un JWT de un super_admin (o usuario con capability `manage_ai`).
Para obtenerlo:
  1. Inicia sesion en https://testexamen.es como vleal3@gmail.com.
  2. Abre devtools (F12) -> Application -> Local storage -> sb-jzg...auth-token.
  3. Copia el valor de "access_token" (NO el refresh_token).

Variables de entorno:
  SUPABASE_URL          (default: https://jzgtghddqofxewzmpmbx.supabase.co)
  SUPABASE_ANON_KEY     publica, copiala de Supabase Dashboard > Project > API
  SUPABASE_ACCESS_TOKEN JWT del super_admin (caduca en 1h tipicamente)
  SUBJECT_ID            uuid del subject (default: Constitucion Espanola)
  BATCH_LIMIT           preguntas por lote (default: 30)
"""

from __future__ import annotations
import json
import os
import sys
import time
import urllib.request
import urllib.error

DEFAULT_URL = "https://jzgtghddqofxewzmpmbx.supabase.co"
DEFAULT_SUBJECT = "942f19b7-e60c-4e58-bde4-629ded718b96"
DEFAULT_LIMIT = 30


def call_ef(base_url: str, anon: str, token: str, body: dict) -> dict:
    url = f"{base_url}/functions/v1/classify-question-bank"
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apikey": anon,
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode("utf-8", errors="replace")
        except Exception:
            err_body = ""
        raise RuntimeError(
            f"HTTP {e.code} {e.reason} | body: {err_body[:600]}"
        )


def main() -> None:
    base_url = os.environ.get("SUPABASE_URL", DEFAULT_URL).rstrip("/")
    anon = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    subject_id = os.environ.get("SUBJECT_ID", DEFAULT_SUBJECT).strip()
    try:
        limit = int(os.environ.get("BATCH_LIMIT", str(DEFAULT_LIMIT)))
    except ValueError:
        limit = DEFAULT_LIMIT

    if not anon or not token:
        print(
            "ERROR: define SUPABASE_ANON_KEY y SUPABASE_ACCESS_TOKEN en el "
            "entorno antes de ejecutar (lee la cabecera del script).",
            file=sys.stderr,
        )
        sys.exit(2)

    print(f"URL:     {base_url}")
    print(f"Subject: {subject_id}")
    print(f"Limit:   {limit} preguntas/lote")
    print()

    total_processed = 0
    total_high = 0
    total_other = 0
    total_errors = 0
    iteration = 0
    consecutive_no_progress = 0

    while True:
        iteration += 1
        t0 = time.time()
        try:
            r = call_ef(base_url, anon, token, {
                "subject_id": subject_id,
                "limit": limit,
            })
        except Exception as e:
            print(f"[iter {iteration}] FALLO: {e}", file=sys.stderr)
            sys.exit(3)
        dt = time.time() - t0

        if not r.get("ok"):
            print(f"[iter {iteration}] EF respondio not-ok: {r}",
                  file=sys.stderr)
            sys.exit(4)

        processed = r.get("processed", 0)
        high = r.get("classified_high", 0)
        other = r.get("classified_other", 0)
        errs = r.get("errors", 0)
        remaining = r.get("remaining", 0)

        total_processed += processed
        total_high += high
        total_other += other
        total_errors += errs

        print(
            f"[iter {iteration:3}] {dt:5.1f}s  "
            f"procesadas={processed:3}  high={high:3}  "
            f"other={other:3}  err={errs:2}  pendientes={remaining}"
        )

        if processed == 0 or remaining == 0:
            if processed == 0:
                consecutive_no_progress += 1
                if consecutive_no_progress >= 2:
                    print("\nSin progreso en 2 iteraciones seguidas, paro.")
                    break
            else:
                consecutive_no_progress = 0
            if remaining == 0:
                print("\nTODO PROCESADO.")
                break
        else:
            consecutive_no_progress = 0

        # Pequeno respiro para no saturar Gemini (rate limit).
        time.sleep(1.0)

    print()
    print("=== Resumen ===")
    print(f"  Iteraciones:                  {iteration}")
    print(f"  Total procesadas:             {total_processed}")
    print(f"  Movidas a articulo (high):    {total_high}")
    print(f"  Dejadas en raiz (medium/low): {total_other}")
    print(f"  Errores:                      {total_errors}")


if __name__ == "__main__":
    main()
