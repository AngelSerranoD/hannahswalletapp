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

Uso:
    python tool/prepare_fonts.py
"""

import os
import sys
import urllib.request

GF = 'https://github.com/google/fonts/raw/main/ofl'
DEST = os.path.join('assets', 'fonts')

# La china va aparte: se descarga de notofonts y no de Google Fonts.
NOTO_SC = ('https://github.com/notofonts/noto-cjk/raw/main/'
           'Sans/SubsetOTF/SC/NotoSansSC-Regular.otf')


def fetch(url, path):
    print(f'  bajando {os.path.basename(path)}...')
    urllib.request.urlretrieve(url, path)
    return os.path.getsize(path)


def main():
    os.makedirs(DEST, exist_ok=True)

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
