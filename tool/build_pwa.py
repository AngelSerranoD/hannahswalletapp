#!/usr/bin/env python3
"""Compila la PWA y comprueba que no se le ha escapado ninguna conexion.

Por que existe este script en vez de un `flutter build web` a secas:

Flutter, por defecto, descarga el motor CanvasKit y la fuente Roboto desde
`gstatic.com` EN CADA ARRANQUE de la aplicacion. Eso rompe dos promesas del
proyecto a la vez: la app no funcionaria sin conexion, y cada apertura enviaria
la IP del usuario a un tercero desde una aplicacion que dice no hablar con
nadie. La unica forma de evitarlo es compilar con `--no-web-resources-cdn` y
llevar la fuente empaquetada.

Es un flag facil de olvidar y su ausencia no da ningun error: la app funciona
igual de bien mientras haya cobertura. Por eso el script no se limita a
compilar, sino que revisa el resultado y falla si encuentra referencias
externas.

Uso:
    python tool/build_pwa.py                 # despliegue en la raiz del dominio
    python tool/build_pwa.py /hannahswallet/ # despliegue en un subdirectorio
"""

import hashlib
import json
import os
import re
import subprocess
import sys

# Dominios que NO deben aparecer como origen de ningun recurso en tiempo de
# ejecucion. La referencia muerta dentro del ternario de `flutter_bootstrap.js`
# se filtra aparte, mas abajo.
FORBIDDEN = (
    'fonts.gstatic.com',
    'fonts.googleapis.com',
    'ajax.googleapis.com',
)

# Se revisan los ficheros de arranque, no `main.dart.js`.
#
# `main.dart.js` SIEMPRE contendra la cadena "fonts.gstatic.com": es el valor
# por defecto de `fontFallbackBaseUrl`, de donde el motor descargaria una
# fuente Noto si apareciera un caracter que Roboto no cubre (emoji, chino,
# arabe...). No es una conexion que la app haga: es una que HARIA en ese caso
# concreto, y la CSP la bloquea.
#
# Consecuencia asumida: un emoji en la nota de un gasto se vera como un
# rectangulo. Es el precio de no abrir ni una sola conexion a un tercero, y
# para una app de cuentas en espanol compensa.
CHECK_FILES = ('index.html', 'flutter.js', 'flutter_bootstrap.js')


def run(cmd):
    print('$', ' '.join(cmd))
    result = subprocess.run(cmd, shell=(os.name == 'nt'))
    if result.returncode != 0:
        sys.exit(result.returncode)


def prune(build_dir):
    """Quita del build lo que nunca se descarga en produccion.

    Los `.symbols` son mapas de simbolos para depurar fallos DENTRO del motor
    de Flutter: ningun navegador los pide al ejecutar la app. Son unos 6 MB que
    solo estorban al desplegar.

    Los `.wasm` NO se tocan aunque parezcan sobrantes: `flutter_bootstrap.js`
    elige el renderer en tiempo de ejecucion y referencia a todos, asi que
    borrar uno puede dejar la app sin arrancar en un navegador concreto.
    """
    removed = 0
    freed = 0
    for root, _, files in os.walk(build_dir):
        for name in files:
            if name.endswith('.symbols'):
                path = os.path.join(root, name)
                freed += os.path.getsize(path)
                os.remove(path)
                removed += 1
    if removed:
        print()
        print('Podados %d ficheros de simbolos (%.1f MB)'
              % (removed, freed / 1024 / 1024))


# Que NO entra en el precache.
#
# El worker cachea igualmente todo lo que pase por su `fetch`, asi que dejar
# algo fuera de aqui no significa que no funcione sin conexion: significa que se
# guarda la primera vez que se usa, en vez de descargarse entero al instalar.
#
# La diferencia importa: precacheandolo todo eran 34,6 MB de golpe, y en un
# movil con datos moviles eso es una instalacion que la gente cancela. Asi se
# queda en unos 6 MB.
NO_PRECACHE = (
    '.symbols',
    'vercel.json',
    '_headers',
    'NOTICES',
)

# `canvaskit/` son 28 MB con TODOS los renderers, y cada navegador usa uno
# solo: Safari el `canvaskit.wasm` normal, Chrome el de `chromium/`. Se cachean
# al vuelo en la primera visita, que siempre tiene conexion porque hace falta
# para instalar la app.
NO_PRECACHE_DIRS = ('canvaskit/',)

# La fuente china son 8 MB que solo necesita quien escriba en chino.
NO_PRECACHE_NAMES = ('NotoSansSC-Regular.otf',)


def install_service_worker(build_dir):
    """Sustituye el service worker de Flutter por el de la app.

    Las versiones recientes de Flutter generan un `flutter_service_worker.js`
    que solo se desinstala a si mismo: no cachea nada, asi que la PWA no
    funcionaria sin conexion. Se reemplaza su contenido, conservando el nombre
    para que el registro que hace `flutter_bootstrap.js` siga valiendo.
    """
    template_path = os.path.join('tool', 'service_worker_template.js')
    if not os.path.exists(template_path):
        return 'Falta tool/service_worker_template.js'

    assets = []
    digest = hashlib.sha256()
    for root, _, files in os.walk(build_dir):
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, build_dir).replace(os.sep, '/')
            if rel in ('flutter_service_worker.js',):
                continue
            if name.endswith(NO_PRECACHE) or name in NO_PRECACHE_NAMES:
                continue
            if rel.startswith(NO_PRECACHE_DIRS):
                continue
            with open(path, 'rb') as handle:
                digest.update(handle.read())
            assets.append(rel)

    # La version sale del contenido: cada despliegue con cambios estrena cache,
    # y uno identico reutiliza la que ya hay.
    version = digest.hexdigest()[:12]

    with open(template_path, encoding='utf-8') as handle:
        worker = handle.read()
    worker = worker.replace('__VERSION__', version)
    worker = worker.replace('__ASSETS__', json.dumps(assets, indent=2))

    out = os.path.join(build_dir, 'flutter_service_worker.js')
    with open(out, 'w', encoding='utf-8') as handle:
        handle.write(worker)

    precache_bytes = sum(
        os.path.getsize(os.path.join(build_dir, a.replace('/', os.sep)))
        for a in assets
    )
    print('Service worker propio: %d recursos en precache (%.1f MB), version %s'
          % (len(assets), precache_bytes / 1024 / 1024, version))
    return None


def verify(build_dir):
    problems = []

    # 1. CanvasKit debe resolverse en local.
    bootstrap = os.path.join(build_dir, 'flutter_bootstrap.js')
    with open(bootstrap, encoding='utf-8', errors='ignore') as handle:
        content = handle.read()
    if '"useLocalCanvasKit":true' not in content.replace(' ', ''):
        problems.append(
            'flutter_bootstrap.js no tiene useLocalCanvasKit: el motor se '
            'descargaria de gstatic.com. Falta --no-web-resources-cdn.'
        )
    if not os.path.exists(os.path.join(build_dir, 'canvaskit', 'canvaskit.wasm')):
        problems.append('Falta canvaskit/ en el build.')

    # 2. La fuente tiene que viajar dentro.
    fonts_dir = os.path.join(build_dir, 'assets', 'assets', 'fonts')
    if not os.path.isdir(fonts_dir) or not os.listdir(fonts_dir):
        problems.append(
            'No hay fuentes empaquetadas: el motor pediria Roboto a '
            'fonts.gstatic.com en cada arranque.'
        )

    # 3. Ningun fichero servido debe apuntar a un dominio externo.
    for name in CHECK_FILES:
        path = os.path.join(build_dir, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding='utf-8', errors='ignore') as handle:
            text = handle.read()
        for domain in FORBIDDEN:
            if domain in text:
                problems.append(f'{name} referencia {domain}.')

    # 4. La configuracion de Vercel tiene que viajar en el build.
    vercel = os.path.join(build_dir, 'vercel.json')
    if not os.path.exists(vercel):
        problems.append(
            'Falta vercel.json en el build: sin el, Vercel serviria la app sin '
            'ninguna cabecera de seguridad.'
        )
    else:
        with open(vercel, encoding='utf-8') as handle:
            conf = handle.read()
        for needed in ("connect-src 'self'", 'frame-ancestors', 'nosniff'):
            if needed not in conf:
                problems.append(f'vercel.json ha perdido {needed}.')

    # 5. El service worker tiene que cachear de verdad.
    sw = os.path.join(build_dir, 'flutter_service_worker.js')
    with open(sw, encoding='utf-8') as handle:
        worker = handle.read()
    if 'registration.unregister' in worker:
        problems.append(
            'El service worker es el de Flutter, que solo se desinstala: la '
            'app no funcionaria sin conexion.'
        )
    if 'caches.open' not in worker:
        problems.append('El service worker no cachea nada.')

    # 6. La politica de seguridad debe seguir ahi.
    index = os.path.join(build_dir, 'index.html')
    with open(index, encoding='utf-8', errors='ignore') as handle:
        html = handle.read()
    if "connect-src 'self'" not in html:
        problems.append('index.html ha perdido la CSP con connect-src self.')
    if re.search(r'<script(?![^>]*\ssrc=)[^>]*>', html):
        problems.append(
            'index.html tiene un <script> en linea: la CSP lo bloqueara.'
        )

    return problems


def main():
    base_href = sys.argv[1] if len(sys.argv) > 1 else '/'
    if not base_href.startswith('/') or not base_href.endswith('/'):
        sys.exit('La ruta base debe empezar y acabar con "/". Ej: /wallet/')

    run([
        'flutter', 'build', 'web',
        '--release',
        '--no-web-resources-cdn',
        '--base-href', base_href,
    ])

    build_dir = os.path.join('build', 'web')
    prune(build_dir)

    sw_error = install_service_worker(build_dir)
    problems = verify(build_dir)
    if sw_error:
        problems.insert(0, sw_error)

    print()
    if problems:
        print('LA COMPROBACION HA FALLADO:')
        for problem in problems:
            print('  - ' + problem)
        return 1

    total = sum(
        os.path.getsize(os.path.join(root, f))
        for root, _, files in os.walk(build_dir)
        for f in files
    )
    print('Comprobaciones superadas:')
    print('  - CanvasKit local, sin descarga externa')
    print('  - Fuentes empaquetadas')
    print('  - Sin referencias a dominios de terceros')
    print('  - CSP presente y sin scripts en linea')
    print('  - vercel.json con las cabeceras de seguridad')
    print('  - Service worker propio: la app abre sin conexion')
    print(f'\nListo en {build_dir}  ({total / 1024 / 1024:.1f} MB en disco)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
