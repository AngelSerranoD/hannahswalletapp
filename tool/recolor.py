#!/usr/bin/env python3
"""Migra las referencias de color al esquema semantico de la paleta Flowfy.

Los nombres antiguos describian el icono del gato (terracotta, sky, espresso,
cream, coin...). Al cambiar la paleta a la de Flowfy esos nombres pasaban a
mentir: `terracotta` habria sido un rosa. Este script los sustituye por
nombres que dicen QUE PAPEL cumple cada color, no a que se parece.

Uso:  python tool/recolor.py
"""

import glob
import io
import re
import sys

# Mapeo de nombre antiguo -> nuevo. El orden importa: los nombres mas largos
# primero, para que `billGreenSoft` no se convierta en `incomeSoft` a medias
# por haber sustituido antes `billGreen`.
RENAMES = [
    ('billGreenSoft', 'incomeSoft'),
    ('billGreen', 'income'),
    ('categoryPalette', 'categoryPalette'),
    ('terracotta', 'primary'),
    ('primaryBright', 'primaryBright'),
    ('skyDeep', 'secondary'),
    ('sky', 'secondarySoft'),
    ('rust', 'primaryBright'),
    ('coin', 'warning'),
    ('alert', 'danger'),
    ('espresso', 'ink'),
    ('cream', 'paper'),
]

PATTERN = re.compile(
    r'AppColors\.(' + '|'.join(sorted((a for a, _ in RENAMES), key=len, reverse=True)) + r')\b'
)
LOOKUP = dict(RENAMES)


def main():
    changed = []
    for path in glob.glob('lib/**/*.dart', recursive=True):
        if 'app_colors.dart' in path or 'kitty_animations' in path:
            continue
        original = io.open(path, encoding='utf-8').read()
        updated = PATTERN.sub(lambda m: 'AppColors.' + LOOKUP[m.group(1)], original)
        if updated != original:
            io.open(path, 'w', encoding='utf-8').write(updated)
            changed.append(path)

    for path in changed:
        print('  ' + path)
    print(f'\nFicheros migrados: {len(changed)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
