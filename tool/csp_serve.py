"""Servidor estatico de DIAGNOSTICO que replica produccion para validar el
build de Flutter Web en local:
  - Sirve build/web/ con los MIME correctos (.wasm -> application/wasm).
  - Aplica la MISMA Content-Security-Policy que el .htaccess de produccion
    (incluida gstatic en connect-src), para reproducir el entorno real.
  - SPA fallback: rutas inexistentes -> index.html.

Uso (lo lanza Preview via .claude/launch.json):
  python tool/csp_serve.py 8138
"""

import http.server
import mimetypes
import os
import sys

# MIME correctos (Windows a veces no registra .wasm/.js bien).
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("application/json", ".json")
mimetypes.add_type("image/svg+xml", ".svg")

# Sirve desde build/web/ (relativo a la raiz del repo = ../ del tool/).
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
ROOT = os.path.abspath(ROOT)

CSP = (
    "default-src 'self'; "
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://js.stripe.com "
    "https://unpkg.com https://www.gstatic.com; "
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
    "font-src 'self' data: https://fonts.gstatic.com; "
    "img-src 'self' data: blob: https:; "
    "connect-src 'self' https://*.supabase.co wss://*.supabase.co "
    "https://api.stripe.com https://*.ingest.sentry.io https://*.sentry.io "
    "https://api.pwnedpasswords.com https://www.gstatic.com "
    "https://fonts.gstatic.com; "
    "frame-src 'self' https://js.stripe.com https://hooks.stripe.com; "
    "worker-src 'self' blob:; object-src 'none'; base-uri 'self'; "
    "form-action 'self'; frame-ancestors 'self'"
)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Content-Security-Policy", CSP)
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def do_GET(self):
        # Replica el bloqueo de dotfiles de Apache (`<FilesMatch "^\.">`):
        # cualquier fichero cuyo BASENAME empiece por '.' -> 403. Esto
        # reproduce fielmente produccion (incluido el 403 de assets/.env que
        # nos rompia el arranque). Con DENY_DOTFILES=0 se desactiva.
        if os.environ.get("DENY_DOTFILES", "1") == "1":
            base = os.path.basename(self.path.split("?")[0])
            if base.startswith("."):
                self.send_error(403, "Forbidden (dotfile)")
                return
        # SPA fallback: si la ruta no es un archivo real, servir index.html.
        path = self.translate_path(self.path)
        if not os.path.isfile(path) and not os.path.isdir(path):
            self.path = "/index.html"
        return super().do_GET()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8138
    print(f"Serving {ROOT} on http://localhost:{port} (con CSP de produccion)")
    http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
