#!/usr/bin/env python3
"""Genera las animaciones Lottie del gato de Hannah's Wallet.

Escribe `lib/presentation/widgets/mascot/kitty_animations.dart` con tres
constantes: reposo, celebracion y alerta.

Se genera con un script en lugar de escribir el JSON a mano porque un fichero
Lottie son varios miles de numeros: a mano es imposible mantener la coherencia
entre las tres animaciones (que el gato mida lo mismo, que las gafas caigan en
el mismo sitio) y cualquier retoque obliga a repasarlo entero.

Para modificar al gato: se cambia aqui y se vuelve a ejecutar
    python tool/generate_kitty_lottie.py
"""

import json
import os

W = H = 300
FPS = 60
DURATION = 180  # se ajusta por animacion

# --- Paleta, tomada del icono de la app -----------------------------------

def rgb(hex_str, alpha=1.0):
    hex_str = hex_str.lstrip('#')
    return [int(hex_str[i:i + 2], 16) / 255 for i in (0, 2, 4)] + [alpha]

# Paleta del gato: la ORIGINAL, la del icono que dio Angel.
#
# Se mantiene en color a proposito aunque el resto de la app sea sepia. El gato
# es la mascota, no un elemento de interfaz: es el unico punto de color de la
# pantalla y por eso funciona como foco. Ademas su terracota y su marron
# conviven de forma natural con los cuatro tonos calidos de la paleta.
TERRACOTTA = rgb('CB652E')   # pelaje
RUST       = rgb('9F4B26')   # sombras del pelaje, interior de las orejas
ESPRESSO   = rgb('5F2515')   # contornos, pupilas, nariz
CREAM      = rgb('F7EBD3')   # lentes de las gafas
COIN       = rgb('F2C044')   # moneda
BILL       = rgb('5EA269')   # billete
ALERT      = rgb('D1483C')   # mejillas y halo de alerta
WHITE      = rgb('FFFFFF')   # brillo de las pupilas
SKY        = rgb('9ED1EE')   # gota de sudor

# Puntos fijos de la escena. Se comparten entre las tres animaciones para que
# el gato no cambie de sitio ni de tamano al pasar de una a otra.
HEAD_AT = (150, 128)
BODY_AT = (150, 214)

# --- Constructores de propiedades -----------------------------------------

def val(v):
    """Propiedad estatica."""
    return {"a": 0, "k": v}


def anim(keys, dims=None):
    """Propiedad animada.

    `keys` es una lista de (frame, valor). El ultimo keyframe de Lottie solo
    lleva tiempo y valor; los anteriores necesitan las curvas de easing `i`/`o`.
    Se usa un ease-in-out suave (0.33/0.67), que es lo que da la sensacion de
    movimiento organico en vez de lineal y robotico.
    """
    if dims is None:
        dims = len(keys[0][1]) if isinstance(keys[0][1], list) else 1
    out = []
    for idx, (t, v) in enumerate(keys):
        v = v if isinstance(v, list) else [v]
        kf = {"t": t, "s": v}
        if idx < len(keys) - 1:
            kf["i"] = {"x": [0.33] * dims, "y": [1.0] * dims}
            kf["o"] = {"x": [0.67] * dims, "y": [0.0] * dims}
        out.append(kf)
    return {"a": 1, "k": out}


def transform(p=(0, 0), a=(0, 0), s=(100, 100), r=0, o=100):
    """Transformacion de grupo (`ty: tr`)."""
    return {
        "ty": "tr",
        "p": p if isinstance(p, dict) else val(list(p)),
        "a": a if isinstance(a, dict) else val(list(a)),
        "s": s if isinstance(s, dict) else val(list(s)),
        "r": r if isinstance(r, dict) else val(r),
        "o": o if isinstance(o, dict) else val(o),
        "sk": val(0), "sa": val(0),
    }


def ellipse(size, pos=(0, 0)):
    return {"ty": "el", "s": val(list(size)), "p": val(list(pos)), "d": 1}


def rect(size, pos=(0, 0), radius=0):
    return {"ty": "rc", "s": val(list(size)), "p": val(list(pos)),
            "r": val(radius), "d": 1}


def path(points, closed=True, tangents=None):
    """Path a partir de vertices. `tangents` = lista de (in, out) por vertice."""
    n = len(points)
    if tangents is None:
        tangents = [((0, 0), (0, 0))] * n
    return {
        "ty": "sh",
        "ks": val({
            "i": [list(t[0]) for t in tangents],
            "o": [list(t[1]) for t in tangents],
            "v": [list(p) for p in points],
            "c": closed,
        }),
        "d": 1,
    }


def fill(color, opacity=100):
    return {"ty": "fl", "c": val(list(color)),
            "o": opacity if isinstance(opacity, dict) else val(opacity), "r": 1}


def stroke(color, width, opacity=100):
    return {"ty": "st", "c": val(list(color)), "o": val(opacity),
            "w": val(width), "lc": 2, "lj": 2}


def group(items, name="g", tr=None):
    return {"ty": "gr", "nm": name, "it": items + [tr or transform()]}


def stack(parts):
    """Convierte una lista escrita de ATRAS hacia DELANTE al orden de Lottie.

    Lottie -como After Effects- dibuja el PRIMER elemento de `shapes` ENCIMA de
    los siguientes. Escribir las piezas en ese orden es antinatural: uno piensa
    "primero la cabeza, luego los ojos encima". Sin esta inversion, la cabeza
    se pintaba sobre las gafas, el hocico y la boca, y el gato salia sin cara.
    """
    return list(reversed(parts))


def layer(name, shapes, index, *, pos=(150, 150), anchor=(0, 0),
          scale=(100, 100), rot=0, opacity=100, ip=0, op=None, parent=None):
    lay = {
        "ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1,
        "ks": {
            "o": opacity if isinstance(opacity, dict) else val(opacity),
            "r": rot if isinstance(rot, dict) else val(rot),
            "p": pos if isinstance(pos, dict) else val(list(pos) + [0]),
            "a": anchor if isinstance(anchor, dict) else val(list(anchor) + [0]),
            "s": scale if isinstance(scale, dict) else val(list(scale) + [100]),
        },
        "ao": 0,
        "shapes": shapes,
        "ip": ip, "op": op if op is not None else DURATION, "st": 0, "bm": 0,
    }
    if parent is not None:
        lay["parent"] = parent
    return lay


# --- Piezas del gato -------------------------------------------------------
# Todas se dibujan centradas en (0, 0); la capa las coloca en la escena. Asi
# una misma pieza sirve en las tres animaciones sin recalcular coordenadas.

def head_layer(index, parts, *, at=HEAD_AT, pos=None, scale=(100, 100), rot=0):
    """Capa de la cabeza, preparada para tener capas hijas.

    Las piezas se dibujan centradas en (0, 0) y un grupo interno las lleva a
    `at`. La capa fija su ANCHOR en `at`, no en (0, 0), y ese detalle es la
    clave de todo el montaje:

    Lottie compone al hijo como `matrizDelPadre * posicionDelHijo`. Si el
    padre tuviese anchor (0, 0) y position (150, 128), su matriz seria una
    traslacion de +150/+128 y las pupilas, colocadas en coordenadas absolutas,
    acabarian desplazadas el doble, fuera de la pantalla.

    Con `anchor == position`, la matriz del padre no aporta desplazamiento
    propio: solo gira y escala alrededor del centro de la cabeza. Asi las
    pupilas se posicionan en coordenadas de escena y aun asi acompanan al
    balanceo y a la respiracion.
    """
    return layer("head", [group(parts, "head-root", transform(p=at))], index,
                 pos=pos if pos is not None else at, anchor=at,
                 scale=scale, rot=rot)


def ear(side):
    """Oreja triangular con el interior mas oscuro. side = -1 izq, +1 der.

    La punta va en y = -88 y no en -46: la cabeza es una elipse de 152x138, que
    a la altura de la oreja (x = +-48) todavia llega hasta y = -55. Con la punta
    a -46 la oreja quedaba ENTERAMENTE dentro del craneo y el gato salia sin
    orejas.
    """
    x = 48 * side
    outer = path([(x - 27, 4), (x, -88), (x + 27, 4)])
    inner = path([(x - 13, -8), (x, -66), (x + 13, -8)])
    return [
        group([outer, fill(TERRACOTTA), stroke(ESPRESSO, 7)], f"ear-out-{side}"),
        group([inner, fill(RUST)], f"ear-in-{side}"),
    ]


def head_shape():
    return group([ellipse((152, 138)), fill(TERRACOTTA), stroke(ESPRESSO, 7)],
                 "head")


def muzzle():
    return group([ellipse((78, 52), (0, 26)), fill(RUST, 55)], "muzzle")


def cheeks():
    return group([
        ellipse((26, 16), (-52, 20)),
        ellipse((26, 16), (52, 20)),
        fill(ALERT, 28),
    ], "cheeks")


def glasses():
    """Las gafas del icono: dos aros con lente crema y el puente."""
    return group(stack([
        group([ellipse((62, 62), (-34, -6)), fill(CREAM), stroke(ESPRESSO, 8)], "lens-l"),
        group([ellipse((62, 62), (34, -6)), fill(CREAM), stroke(ESPRESSO, 8)], "lens-r"),
        group([rect((14, 7), (0, -6), 3), fill(ESPRESSO)], "bridge"),
        group([rect((26, 6), (-74, -12), 3), fill(ESPRESSO)], "temple-l"),
        group([rect((26, 6), (74, -12), 3), fill(ESPRESSO)], "temple-r"),
    ]), "glasses")


def nose():
    return group([
        path([(-9, 16), (9, 16), (0, 28)]),
        fill(ESPRESSO),
    ], "nose")


def mouth_neutral():
    return group([
        path([(-13, 34), (0, 40), (13, 34)], closed=False,
             tangents=[((0, 0), (5, 4)), ((-5, -3), (5, -3)), ((-5, 4), (0, 0))]),
        stroke(ESPRESSO, 5),
    ], "mouth")


def mouth_smile():
    return group([
        path([(-20, 30), (0, 46), (20, 30)], closed=False,
             tangents=[((0, 0), (8, 9)), ((-8, -4), (8, -4)), ((-8, 9), (0, 0))]),
        stroke(ESPRESSO, 6),
    ], "mouth-smile")


def mouth_worried():
    return group([
        path([(-16, 40), (0, 30), (16, 40)], closed=False,
             tangents=[((0, 0), (6, -6)), ((-6, 2), (6, 2)), ((-6, -6), (0, 0))]),
        stroke(ESPRESSO, 5),
    ], "mouth-worried")


def whiskers():
    items = []
    for side in (-1, 1):
        for i, y in enumerate((14, 24, 34)):
            x0 = 40 * side
            x1 = (92 + i * 4) * side
            items.append(group([
                path([(x0, y), (x1, y - 6 + i * 5)], closed=False),
                stroke(ESPRESSO, 4, 70),
            ], f"whisker-{side}-{i}"))
    return items


def coin(pos, size=34, symbol=True):
    items = [
        group([ellipse((size, size)), fill(COIN), stroke(ESPRESSO, 5)], "coin-body"),
    ]
    if symbol:
        # Simbolo del euro simplificado: la C y los dos travesanos.
        items.append(group([
            path([(6, -8), (-2, -9), (-7, 0), (-2, 9), (6, 8)], closed=False,
                 tangents=[((0, 0), (-3, -1)), ((3, 0), (-3, 0)),
                           ((0, -4), (0, 4)), ((-3, 0), (3, 0)), ((-3, 1), (0, 0))]),
            stroke(ESPRESSO, 4),
        ], "euro-c"))
        items.append(group([rect((16, 3.5), (-6, -3)), fill(ESPRESSO)], "euro-bar1"))
        items.append(group([rect((16, 3.5), (-6, 3)), fill(ESPRESSO)], "euro-bar2"))
    return group(stack(items), "coin", transform(p=pos, s=(100, 100)))


# --- Ojos ------------------------------------------------------------------
# El parpadeo se hace escalando la pupila en Y hasta casi cero, que es como se
# resuelve en produccion: mucho mas barato que animar el path del parpado.

def pupil_layer(index, side, blink_frames, parent=None, base=HEAD_AT):
    x = 34 * side
    keys = [(0, [100, 100, 100])]
    for f in blink_frames:
        keys += [
            (f - 3, [100, 100, 100]),
            (f, [100, 12, 100]),
            (f + 3, [100, 100, 100]),
        ]
    keys.append((DURATION, [100, 100, 100]))

    shapes = [
        group([ellipse((26, 26)), fill(ESPRESSO)], "pupil"),
        group([ellipse((9, 9), (6, -7)), fill(WHITE)], "glint"),
    ]
    return layer(f"pupil-{side}", shapes, index,
                 pos=(base[0] + x, base[1] - 6),
                 scale=anim(keys, dims=3), parent=parent)


def happy_eye(index, side, parent=None, base=HEAD_AT):
    """Ojo cerrado en arco: la cara de gato contento."""
    x = 34 * side
    arc = path([(-16, 4), (0, -12), (16, 4)], closed=False,
               tangents=[((0, 0), (7, -8)), ((-7, 3), (7, 3)), ((-7, -8), (0, 0))])
    return layer(f"happy-eye-{side}", [group([arc, stroke(ESPRESSO, 7)], "arc")],
                 index, pos=(base[0] + x, base[1] - 6), parent=parent)


# =========================================================================
#  Animacion 1: REPOSO
# =========================================================================

def build_idle():
    global DURATION
    DURATION = 180  # 3 s a 60 fps

    breathe = anim([(0, [100, 100, 100]), (60, [102.5, 103.5, 100]),
                    (120, [100, 100, 100]), (180, [100.4, 100.4, 100])], dims=3)
    sway = anim([(0, -1.5), (45, 1.5), (90, -1.5), (135, 1.5), (180, -1.5)], dims=1)

    layers = []

    # 1. Cola, detras de todo, meciendose.
    tail = group([
        path([(0, 0), (34, 6), (54, -22), (44, -52)], closed=False,
             tangents=[((0, 0), (14, 2)), ((-12, -2), (12, 2)),
                       ((-6, 12), (6, -12)), ((-2, 12), (0, 0))]),
        stroke(TERRACOTTA, 20),
    ], "tail")
    layers.append(layer("tail", [tail], 8,
                        pos=(196, 236),
                        rot=anim([(0, -12), (60, 10), (120, -12), (180, -12)], dims=1)))

    # 2. Cuerpo con las patas y la moneda que sostiene.
    body = stack([
        group([ellipse((136, 120), (0, 26)), fill(TERRACOTTA), stroke(ESPRESSO, 7)], "torso"),
        group([ellipse((44, 34), (-44, 46)), fill(RUST), stroke(ESPRESSO, 6)], "paw-l"),
        group([ellipse((44, 34), (44, 46)), fill(RUST), stroke(ESPRESSO, 6)], "paw-r"),
    ])
    layers.append(layer("body", body, 7, pos=BODY_AT, scale=breathe))

    # 3. Moneda entre las patas, con un rebote muy corto.
    layers.append(layer("coin-held", [coin((0, 0), 40)], 6,
                        pos=(150, 250),
                        scale=anim([(0, [100, 100, 100]), (30, [104, 104, 100]),
                                    (60, [100, 100, 100]), (180, [100, 100, 100])], dims=3),
                        rot=anim([(0, -6), (90, 6), (180, -6)], dims=1)))

    # 4. La cabeza entera, como capa padre de ojos y gafas.
    head_parts = stack(ear(-1) + ear(1) + [head_shape(), muzzle(), cheeks()]
                       + whiskers() + [nose(), mouth_neutral(), glasses()])
    layers.append(head_layer(5, head_parts, scale=breathe, rot=sway))

    # 5. Pupilas, hijas de la cabeza para acompanar el balanceo.
    layers.append(pupil_layer(3, -1, [42, 108, 156], parent=5))
    layers.append(pupil_layer(4, 1, [42, 108, 156], parent=5))

    # 6. Un billete que asoma detras, muy sutil.
    bill = group(stack([
        group([rect((66, 40), (0, 0), 6), fill(BILL), stroke(ESPRESSO, 5)], "bill-body"),
        group([ellipse((20, 20)), stroke(ESPRESSO, 3.5)], "bill-mark"),
    ]), "bill", transform(r=-14))
    layers.append(layer("bill", [bill], 9, pos=(224, 258), opacity=90))

    return compose("kitty-idle", layers, DURATION)


# =========================================================================
#  Animacion 2: CELEBRACION
# =========================================================================

def build_celebrate():
    global DURATION
    DURATION = 96  # 1,6 s: corta, es una reaccion

    # Salto con anticipacion (se agacha antes) y aterrizaje amortiguado.
    jump_y = anim([(0, [150, 214, 0]), (8, [150, 224, 0]), (30, [150, 168, 0]),
                   (52, [150, 220, 0]), (64, [150, 210, 0]), (96, [150, 214, 0])], dims=3)
    squash = anim([(0, [100, 100, 100]), (8, [112, 88, 100]), (30, [94, 108, 100]),
                   (52, [112, 88, 100]), (64, [100, 100, 100]), (96, [100, 100, 100])], dims=3)
    head_y = anim([(0, [150, 128, 0]), (8, [150, 138, 0]), (30, [150, 76, 0]),
                   (52, [150, 130, 0]), (64, [150, 122, 0]), (96, [150, 128, 0])], dims=3)
    head_r = anim([(0, 0), (18, -9), (40, 9), (64, -3), (96, 0)], dims=1)

    layers = []

    body = stack([
        group([ellipse((136, 120), (0, 26)), fill(TERRACOTTA), stroke(ESPRESSO, 7)], "torso"),
        # Patas levantadas en senal de celebracion.
        group([ellipse((40, 32), (-58, 6)), fill(RUST), stroke(ESPRESSO, 6)], "paw-l"),
        group([ellipse((40, 32), (58, 6)), fill(RUST), stroke(ESPRESSO, 6)], "paw-r"),
    ])
    layers.append(layer("body", body, 7, pos=jump_y, scale=squash))

    head_parts = stack(ear(-1) + ear(1) + [head_shape(), muzzle(), cheeks()]
                       + whiskers() + [nose(), mouth_smile(), glasses()])
    layers.append(head_layer(5, head_parts, pos=head_y, rot=head_r))

    # Ojos felices en arco durante todo el salto.
    layers.append(happy_eye(3, -1, parent=5))
    layers.append(happy_eye(4, 1, parent=5))

    # Monedas que salen disparadas y se desvanecen.
    spec = [(-86, -10, 0), (86, 6, 6), (-52, -46, 12), (58, -52, 18), (0, -74, 10)]
    for i, (dx, dy, delay) in enumerate(spec):
        start = 14 + delay
        layers.append(layer(
            f"coin-{i}", [coin((0, 0), 30)], 10 + i,
            pos=anim([(start, [150, 200, 0]),
                      (start + 26, [150 + dx, 150 + dy, 0]),
                      (start + 46, [150 + dx * 1.25, 150 + dy - 40, 0])], dims=3),
            opacity=anim([(start, 0), (start + 4, 100),
                          (start + 30, 100), (start + 46, 0)], dims=1),
            rot=anim([(start, 0), (start + 46, 300 if dx > 0 else -300)], dims=1),
            scale=anim([(start, [40, 40, 100]), (start + 10, [110, 110, 100]),
                        (start + 46, [70, 70, 100])], dims=3),
            ip=start,
        ))

    # Destello de fondo al despegar.
    sparkle = group([
        path([(0, -40), (9, -9), (40, 0), (9, 9), (0, 40), (-9, 9), (-40, 0), (-9, -9)]),
        fill(COIN),
    ], "sparkle")
    layers.append(layer("sparkle", [sparkle], 20, pos=(150, 150),
                        opacity=anim([(16, 0), (24, 70), (44, 0), (96, 0)], dims=1),
                        scale=anim([(16, [40, 40, 100]), (44, [150, 150, 100])], dims=3)))

    return compose("kitty-celebrate", layers, DURATION)


# =========================================================================
#  Animacion 3: ALERTA
# =========================================================================

def build_alert():
    global DURATION
    DURATION = 96

    # Temblor nervioso: desplazamientos cortos y rapidos en X.
    shake = anim([(0, [150, 214, 0]), (6, [145, 214, 0]), (12, [155, 214, 0]),
                  (18, [146, 214, 0]), (24, [154, 214, 0]), (30, [150, 214, 0]),
                  (60, [150, 214, 0]), (66, [147, 214, 0]), (72, [153, 214, 0]),
                  (78, [150, 214, 0]), (96, [150, 214, 0])], dims=3)
    head_shake = anim([(0, [150, 128, 0]), (6, [144, 129, 0]), (12, [156, 129, 0]),
                       (18, [145, 128, 0]), (24, [155, 128, 0]), (30, [150, 128, 0]),
                       (60, [150, 128, 0]), (66, [146, 129, 0]), (72, [154, 129, 0]),
                       (78, [150, 128, 0]), (96, [150, 128, 0])], dims=3)

    layers = []

    body = stack([
        group([ellipse((136, 120), (0, 26)), fill(TERRACOTTA), stroke(ESPRESSO, 7)], "torso"),
        # Patas juntas al frente: postura encogida.
        group([ellipse((42, 32), (-24, 44)), fill(RUST), stroke(ESPRESSO, 6)], "paw-l"),
        group([ellipse((42, 32), (24, 44)), fill(RUST), stroke(ESPRESSO, 6)], "paw-r"),
    ])
    layers.append(layer("body", body, 7, pos=shake))

    # Cartera vacia del reves.
    empty = group(stack([
        group([rect((60, 44), (0, 0), 8), fill(ESPRESSO, 85)], "purse"),
        group([path([(-18, -22), (0, -34), (18, -22)], closed=False),
               stroke(ESPRESSO, 5)], "purse-clip"),
    ]), "empty-purse", transform(r=12))
    layers.append(layer("purse", [empty], 8, pos=(214, 252), opacity=80))

    head_parts = stack(ear(-1) + ear(1) + [head_shape(), muzzle()] + whiskers() + [
        # Cejas inclinadas: el gesto que de verdad transmite preocupacion.
        group([path([(-52, -34), (-20, -24)], closed=False), stroke(ESPRESSO, 6)], "brow-l"),
        group([path([(52, -34), (20, -24)], closed=False), stroke(ESPRESSO, 6)], "brow-r"),
        nose(), mouth_worried(), glasses(),
    ])
    layers.append(head_layer(5, head_parts, pos=head_shake,
                             rot=anim([(0, 0), (30, -4), (60, 4), (96, 0)], dims=1)))

    # Pupilas encogidas: sobresalto.
    for idx, side in ((3, -1), (4, 1)):
        layers.append(layer(
            f"pupil-{side}",
            [group([ellipse((26, 26)), fill(ESPRESSO)], "pupil"),
             group([ellipse((9, 9), (6, -7)), fill(WHITE)], "glint")],
            idx, pos=(HEAD_AT[0] + 34 * side, HEAD_AT[1] - 6), parent=5,
            scale=anim([(0, [100, 100, 100]), (10, [62, 62, 100]),
                        (30, [88, 88, 100]), (60, [66, 66, 100]),
                        (96, [100, 100, 100])], dims=3),
        ))

    # Gota de sudor: cae, se desvanece y vuelve a empezar.
    drop = group([
        path([(0, -16), (10, 4), (0, 16), (-10, 4)],
             tangents=[((0, 0), (0, 0)), ((-2, -8), (2, 6)),
                       ((6, 0), (-6, 0)), ((-2, 6), (2, -8))]),
        fill(SKY), stroke(ESPRESSO, 3),
    ], "drop")
    layers.append(layer("sweat", [drop], 2, pos=anim(
        [(8, [214, 96, 0]), (34, [222, 140, 0]), (52, [226, 158, 0]),
         (60, [214, 96, 0]), (86, [222, 140, 0]), (96, [226, 152, 0])], dims=3),
        opacity=anim([(8, 0), (16, 100), (46, 100), (54, 0),
                      (60, 0), (68, 100), (90, 100), (96, 0)], dims=1),
        scale=anim([(8, [60, 60, 100]), (34, [100, 100, 100]),
                    (52, [90, 110, 100]), (96, [90, 110, 100])], dims=3)))

    # Halo rojo que late detras del gato.
    halo = group([ellipse((250, 250)), fill(ALERT)], "halo")
    layers.append(layer("halo", [halo], 30, pos=(150, 160),
                        opacity=anim([(0, 0), (24, 16), (48, 0), (72, 14), (96, 0)], dims=1),
                        scale=anim([(0, [80, 80, 100]), (24, [104, 104, 100]),
                                    (48, [80, 80, 100]), (72, [102, 102, 100]),
                                    (96, [80, 80, 100])], dims=3)))

    return compose("kitty-alert", layers, DURATION)


# --- Ensamblado ------------------------------------------------------------

def compose(name, layers, duration):
    # Lottie pinta de menor a mayor `ind`: se ordena para que el orden de
    # apilado sea explicito y no dependa del orden de construccion.
    layers = sorted(layers, key=lambda l: l["ind"])
    for lay in layers:
        lay["op"] = duration
    return {
        "v": "5.9.6", "fr": FPS, "ip": 0, "op": duration,
        "w": W, "h": H, "nm": name, "ddd": 0,
        "assets": [], "layers": layers,
    }


def dart_constant(name, doc, data):
    payload = json.dumps(data, separators=(',', ':'), ensure_ascii=True)
    assert "'''" not in payload
    return f"{doc}\nconst String {name} = r'''\n{payload}\n''';\n"


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, 'lib', 'presentation', 'widgets', 'mascot',
                       'kitty_animations.dart')

    idle = build_idle()
    celebrate = build_celebrate()
    alert = build_alert()

    header = '''// GENERADO AUTOMATICAMENTE POR tool/generate_kitty_lottie.py
// NO EDITAR A MANO: cualquier cambio se pierde al regenerar.
//
// Tres animaciones Lottie del gato de Hannah's Wallet, embebidas como
// constantes en lugar de como ficheros de assets.
//
// Por que como constantes y no en `assets/lottie/*.json`:
//   * la mascota es codigo de la app, no contenido que se sustituya;
//   * se evita una lectura asincrona del bundle en el primer frame del
//     dashboard, que es justo donde mas se nota un salto;
//   * no hay forma de que la app se quede sin mascota porque falte un asset.
//
// Se cargan con `LottieComposition.parseJsonBytes` sobre estas cadenas.

'''

    body = '\n'.join([
        dart_constant(
            'kittyIdleAnimation',
            '/// Reposo: respiracion, parpadeo, cola meciendose y moneda en las patas.\n'
            '/// 180 fotogramas a 60 fps (3 s), en bucle continuo.',
            idle),
        dart_constant(
            'kittyCelebrateAnimation',
            '/// Celebracion: salto con monedas al vuelo. La dispara `successTrigger`\n'
            '/// tras guardar un movimiento. 96 fotogramas (1,6 s), sin bucle.',
            celebrate),
        dart_constant(
            'kittyAlertAnimation',
            '/// Alerta: temblor, cejas caidas, gota de sudor y halo rojo. La dispara\n'
            '/// `alertTrigger` al superar el 90 % del presupuesto. 96 fotogramas.',
            alert),
    ])

    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(header + body)

    for label, data in (('idle', idle), ('celebrate', celebrate), ('alert', alert)):
        size = len(json.dumps(data, separators=(',', ':')))
        print(f'  {label:<10} {len(data["layers"]):>2} capas  '
              f'{data["op"]:>3} frames  {size / 1024:6.1f} KB')
    print(f'\nEscrito: {out}')


if __name__ == '__main__':
    main()
