#!/usr/bin/env python3
"""Sirve build/web para probar la PWA en local.

`python -m http.server` no vale para esto: responde en HTTP/1.0 y sin
keep-alive, y en esas condiciones el navegador falla al registrar el service
worker con un escueto "unknown error when fetching the script". Aqui se habla
HTTP/1.1 y se anaden las mismas cabeceras que pondra Vercel, para que la prueba
local se parezca al despliegue de verdad.
"""

import functools
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HEADERS = {
    'Content-Security-Policy': (
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; "
        "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
        "font-src 'self' data:; connect-src 'self'; worker-src 'self' blob:; "
        "manifest-src 'self'; base-uri 'self'; form-action 'none'; "
        "object-src 'none'; frame-ancestors 'none'"
    ),
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
}


class Handler(SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def end_headers(self):
        for key, value in HEADERS.items():
            self.send_header(key, value)
        # Sin cache HTTP: al probar interesa ver lo que hace el service
        # worker, no lo que guardo el navegador en una prueba anterior.
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    root = os.path.join('build', 'web')
    if not os.path.isdir(root):
        sys.exit('No hay build/web. Ejecuta antes: python tool/build_pwa.py')
    handler = functools.partial(Handler, directory=root)
    print(f'Sirviendo {root} en http://127.0.0.1:{port}  (Ctrl+C para parar)')
    ThreadingHTTPServer(('127.0.0.1', port), handler).serve_forever()


if __name__ == '__main__':
    main()
