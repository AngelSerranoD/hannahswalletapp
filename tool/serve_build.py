#!/usr/bin/env python3
"""Sirve build/web para probar la PWA en local.

`python -m http.server` no vale para esto: responde en HTTP/1.0 y sin
keep-alive, y en esas condiciones el navegador falla al registrar el service
worker con un escueto "unknown error when fetching the script". Aqui se habla
HTTP/1.1 y se anaden las cabeceras de `vercel.json`, para que la prueba local
se parezca al despliegue de verdad.

Las cabeceras se leen del propio `vercel.json` del build, no de una copia
escrita aqui: antes habia una lista a mano que ya se habia quedado sin
Permissions-Policy ni las de aislamiento, y una prueba local con otra CSP no
prueba nada.
"""

import functools
import json
import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


def load_rules(root):
    """Reglas `headers` de vercel.json como (regex, [(clave, valor)]).

    Los `source` de este proyecto son rutas con grupos de alternativas
    ("/(.*)", "/(index.html|...)", "/"), que valen tal cual como regex
    anclada. Si algun dia se usan parametros con nombre (":ruta*"), hay que
    traducirlos aqui.
    """
    path = os.path.join(root, 'vercel.json')
    if not os.path.exists(path):
        sys.exit('No hay vercel.json en el build. Ejecuta: python tool/build_pwa.py')
    with open(path, encoding='utf-8') as handle:
        conf = json.load(handle)
    rules = []
    for rule in conf.get('headers', []):
        if ':' in rule['source']:
            sys.exit('serve_build.py no sabe traducir el source '
                     f'"{rule["source"]}" de vercel.json.')
        pattern = re.compile('^' + rule['source'] + '$')
        rules.append((pattern, [(h['key'], h['value']) for h in rule['headers']]))
    return rules


class Handler(SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    rules = []

    def end_headers(self):
        ruta = self.path.split('?', 1)[0]
        headers = {}
        # Como en Vercel: si dos reglas ponen la misma cabecera, gana la
        # ultima que casa.
        for pattern, values in self.rules:
            if pattern.match(ruta):
                headers.update(values)
        # Sin cache HTTP: al probar interesa ver lo que hace el service
        # worker, no lo que guardo el navegador en una prueba anterior.
        headers['Cache-Control'] = 'no-store'
        for key, value in headers.items():
            self.send_header(key, value)
        super().end_headers()

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    # Relativo al script y no al directorio actual: se puede lanzar desde
    # cualquier sitio (el panel de previsualización arranca en otra carpeta).
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        '..', 'build', 'web')
    if not os.path.isdir(root):
        sys.exit('No hay build/web. Ejecuta antes: python tool/build_pwa.py')
    Handler.rules = load_rules(root)
    handler = functools.partial(Handler, directory=root)
    print(f'Sirviendo {root} en http://127.0.0.1:{port}  (Ctrl+C para parar)')
    print(f'Cabeceras de {root}/vercel.json: {len(Handler.rules)} reglas')
    ThreadingHTTPServer(('127.0.0.1', port), handler).serve_forever()


if __name__ == '__main__':
    main()
