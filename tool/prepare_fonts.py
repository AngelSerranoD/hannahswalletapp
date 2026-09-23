#!/usr/bin/env python3
"""Descarga y prepara las fuentes de la app.

Las dos familias son **SIL Open Font License**, que permite incrustarlas en una
aplicacion sin restricciones. Ese fue el criterio de seleccion, no solo el
parecido: las que habia antes -Coolvetica y CandleScript- se descartaron porque
sus licencias gratuitas excluyen expresamente las apps y los webfonts.

  * **Archivo** (cuerpo) sustituye a Coolvetica. Se eligio comparando las
    candidatas al tamano real de uso: es la mas cercana en compacidad y peso.
    Inter resulto mas ancha y Manrope mas ligera.

  * **Pinyon Script** (titulos) sustituye a CandleScript. Ademas de parecerse,
    resuelve el problema que tenia aquella: la demo solo traia 56 glifos y
    dibujaba su propio nombre en lugar de los caracteres que le faltaban, asi
    que "Estadisticas" salia como "EstadCandlescriptsticas". Pinyon Script trae
    757 glifos y cubre el latino entero.

Archivo se publica como fuente VARIABLE. Aqui se instancia en tres pesos
estaticos para no depender del soporte de fuentes variables de cada motor.

Ademas prepara la fuente de reserva de la version web (Noto Sans Symbols
recortada): ver `preparar_reserva_web`.

Uso:
    python tool/prepare_fonts.py                # todas
    python tool/prepare_fonts.py --reserva-web  # solo la reserva de la web
"""

import os
import sys
import urllib.request

GF = 'https://github.com/google/fonts/raw/main/ofl'
DEST = os.path.join('assets', 'fonts')

# La china va aparte: se descarga de notofonts y no de Google Fonts.
NOTO_SC = ('https://github.com/notofonts/noto-cjk/raw/main/'
           'Sans/SubsetOTF/SC/NotoSansSC-Regular.otf')

# Fuente de reserva de la web. `tool/build_pwa.py` la copia a la ruta en la que
# el motor de Flutter la pide; no se declara en pubspec.yaml porque la app no
# la usa: es para el motor.
RESERVA_WEB = os.path.join(DEST, 'web', 'NotoSansSymbols-Reserva.woff2')

# Lo que se conserva de Noto Sans Symbols: el bloque Latin-1 y la puntuacion
# tipografica que escribe el espanol (y que sale de `intl` y de las
# localizaciones de Flutter). Es exactamente lo que hace que el motor la pida:
# cuando un texto no tiene una familia registrada, da por "ausente" cualquier
# caracter a partir de U+00A0 -una tilde, una enie- y, en el desempate entre
# las Noto que lo cubren, gana Noto Sans Symbols. El ASCII no hace falta: el
# motor nunca lo comprueba.
RESERVA_WEB_CARACTERES = (
    list(range(0x00A0, 0x0100))            # Latin-1: tildes, enie, ¿ ¡ « »
    + [0x2013, 0x2014,                     # guiones – —
       0x2018, 0x2019, 0x201C, 0x201D,     # comillas ‘ ’ “ ”
       0x2022, 0x2026,                     # • …
       0x202F, 0x20AC]                     # espacio fino duro, €
)


def fetch(url, path):
    print(f'  bajando {os.path.basename(path)}...')
    urllib.request.urlretrieve(url, path)
    return os.path.getsize(path)


def preparar_reserva_web():
    """Noto Sans Symbols recortada para la version web.

    El motor web de Flutter, cuando cree que a un texto le falta un glifo,
    descarga una Noto de `fontFallbackBaseUrl` (por defecto fonts.gstatic.com,
    que la CSP bloquea). La app apunta esa URL a su propio origen
    (`web/flutter_bootstrap.js`) y deja alli esta fuente: el motor la
    encuentra sin salir a la red.
    """
    from fontTools import subset
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    variable = os.path.join(DEST, '_NotoSansSymbols-var.ttf')
    fetch(f'{GF}/notosanssymbols/NotoSansSymbols%5Bwght%5D.ttf', variable)
    font = instancer.instantiateVariableFont(TTFont(variable), {'wght': 400})
    os.remove(variable)

    cubiertos = set(font.getBestCmap())
    quedan = [c for c in RESERVA_WEB_CARACTERES if c in cubiertos]
    opciones = subset.Options()
    opciones.flavor = 'woff2'
    opciones.layout_features = ['*']
    opciones.name_IDs = ['*']            # conserva el aviso de licencia OFL
    recorte = subset.Subsetter(opciones)
    recorte.populate(unicodes=quedan)
    recorte.subset(font)
    os.makedirs(os.path.dirname(RESERVA_WEB), exist_ok=True)
    font.flavor = 'woff2'
    font.save(RESERVA_WEB)
    print(f'  {os.path.relpath(RESERVA_WEB)}  {len(quedan)} caracteres, '
          f'{os.path.getsize(RESERVA_WEB) // 1024} KB')


def main():
    os.makedirs(DEST, exist_ok=True)

    # Solo la reserva web, sin volver a bajar ni instanciar las demas: cambiar
    # un byte de Archivo movería las capturas golden.
    if '--reserva-web' in sys.argv:
        preparar_reserva_web()
        return 0

    try:
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
    except ImportError:
        sys.exit('Falta fonttools:  pip install fonttools')

    # --- Titulos ---
    fetch(f'{GF}/pinyonscript/PinyonScript-Regular.ttf',
          os.path.join(DEST, 'PinyonScript-Regular.ttf'))

    # --- Cuerpo: variable -> tres instancias estaticas ---
    variable = os.path.join(DEST, '_Archivo-var.ttf')
    fetch(f'{GF}/archivo/Archivo%5Bwdth,wght%5D.ttf', variable)
    for weight, name in ((400, 'Regular'), (500, 'Medium'), (700, 'Bold')):
        font = TTFont(variable)
        # `wdth: 100` fija la anchura normal; sin esto la instancia heredaria
        # el valor por defecto del eje, que no tiene por que ser el que se ve.
        static = instancer.instantiateVariableFont(font, {'wght': weight, 'wdth': 100})
        out = os.path.join(DEST, f'Archivo-{name}.ttf')
        static.save(out)
        print(f'  Archivo-{name}.ttf  {os.path.getsize(out) // 1024} KB')
    os.remove(variable)

    # --- Chino ---
    cjk = os.path.join(DEST, 'NotoSansSC-Regular.otf')
    if not os.path.exists(cjk):
        fetch(NOTO_SC, cjk)

    # --- Reserva de la web ---
    preparar_reserva_web()

    # --- Comprobacion: que cubran lo que la app necesita ---
    needed = ('abcdefghijklmnopqrstuvwxyz'
              'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
              '0123456789'
              'áéíóúñÜü'
              '.,:;()?!¿¡€%+-')
    problems = []
    for name in ('PinyonScript-Regular.ttf', 'Archivo-Regular.ttf'):
        font = TTFont(os.path.join(DEST, name))
        cmap = set()
        for table in font['cmap'].tables:
            cmap.update(table.cmap.keys())
        missing = [c for c in needed if ord(c) not in cmap]
        if missing:
            problems.append(f'{name} no cubre: {"".join(missing)}')

    print()
    if problems:
        for p in problems:
            print('  FALLA ' + p)
        return 1
    print('Todas las fuentes cubren el repertorio que usa la app.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
