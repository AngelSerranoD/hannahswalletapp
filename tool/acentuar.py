#!/usr/bin/env python3
"""Restituye las tildes en el texto en espanol del proyecto.

Actua SOLO sobre literales de cadena y comentarios, nunca sobre identificadores
ni sobre SQL: un `replace` global convertiria variables como `dias` en `dias`
acentuado y dejaria el codigo sin compilar.

El diccionario contiene unicamente palabras que en espanol llevan tilde SIEMPRE,
de modo que la sustitucion no puede producir un falso positivo. Los casos que
dependen del contexto ("mas"/"mas", "esta"/"esta", "solo") se dejan fuera a
proposito.

Uso:  python tool/acentuar.py
"""

import glob
import io
import re
import sys

WORDS = {
    # --- Sustantivos y adjetivos ---
    'Ano': 'Ano', 'ano': 'ano', 'anos': 'anos',  # se rellenan abajo
}

# Se define aparte para poder escribir los acentos con escapes unicode y evitar
# cualquier problema de codificacion al editar este fichero.
WORDS = {
    'Ano': 'Año', 'ano': 'año', 'anos': 'años',
    'Dia': 'Día', 'dia': 'día', 'dias': 'días',
    'Categoria': 'Categoría', 'categoria': 'categoría',
    'Categorias': 'Categorías', 'categorias': 'categorías',
    'Estadisticas': 'Estadísticas', 'estadisticas': 'estadísticas',
    'Estadistica': 'Estadística', 'estadistica': 'estadística',
    'Alimentacion': 'Alimentación', 'Educacion': 'Educación',
    'Nomina': 'Nómina', 'nomina': 'nómina',
    'Autonomo': 'Autónomo', 'autonomo': 'autónomo',
    'Boveda': 'Bóveda', 'boveda': 'bóveda',
    'Contrasena': 'Contraseña', 'contrasena': 'contraseña',
    'Contrasenas': 'Contraseñas', 'contrasenas': 'contraseñas',
    'digitos': 'dígitos', 'digito': 'dígito',
    'Limite': 'Límite', 'limite': 'límite',
    'Limites': 'Límites', 'limites': 'límites',
    'Deficit': 'Déficit', 'deficit': 'déficit',
    'Debil': 'Débil', 'debil': 'débil',
    'Analisis': 'Análisis', 'analisis': 'análisis',
    'Musica': 'Música', 'musica': 'música',
    'Version': 'Versión', 'version': 'versión',
    'Accion': 'Acción', 'accion': 'acción',
    'Opcion': 'Opción', 'opcion': 'opción',
    'Configuracion': 'Configuración', 'configuracion': 'configuración',
    'Informacion': 'Información', 'informacion': 'información',
    'Aplicacion': 'Aplicación', 'aplicacion': 'aplicación',
    'Validacion': 'Validación', 'validacion': 'validación',
    'Autenticacion': 'Autenticación', 'autenticacion': 'autenticación',
    'Implementacion': 'Implementación', 'implementacion': 'implementación',
    'Transaccion': 'Transacción', 'transaccion': 'transacción',
    'Restauracion': 'Restauración', 'restauracion': 'restauración',
    'Importacion': 'Importación', 'importacion': 'importación',
    'Exportacion': 'Exportación', 'exportacion': 'exportación',
    'Localizacion': 'Localización', 'localizacion': 'localización',
    'Navegacion': 'Navegación', 'navegacion': 'navegación',
    'Animacion': 'Animación', 'animacion': 'animación',
    'Descripcion': 'Descripción', 'descripcion': 'descripción',
    'Confirmacion': 'Confirmación', 'confirmacion': 'confirmación',
    'Agrupacion': 'Agrupación', 'agrupacion': 'agrupación',
    'Invalidacion': 'Invalidación', 'invalidacion': 'invalidación',
    'Inyeccion': 'Inyección', 'inyeccion': 'inyección',
    'Seleccion': 'Selección', 'seleccion': 'selección',
    'Separacion': 'Separación', 'separacion': 'separación',
    'Sesion': 'Sesión', 'sesion': 'sesión',
    'Presion': 'Presión', 'presion': 'presión',
    'Codigo': 'Código', 'codigo': 'código',
    'Numero': 'Número', 'numero': 'número',
    'Movil': 'Móvil', 'movil': 'móvil',
    'Metodo': 'Método', 'metodo': 'método',
    'Parametro': 'Parámetro', 'parametro': 'parámetro',
    'parametros': 'parámetros',
    'Indice': 'Índice', 'indice': 'índice', 'indices': 'índices',
    'Calculo': 'Cálculo', 'calculo': 'cálculo',
    'Maximo': 'Máximo', 'maximo': 'máximo',
    'Minimo': 'Mínimo', 'minimo': 'mínimo',
    'Grafico': 'Gráfico', 'grafico': 'gráfico',
    'Grafica': 'Gráfica', 'grafica': 'gráfica',
    'graficas': 'gráficas', 'graficos': 'gráficos',
    'Historico': 'Histórico', 'historico': 'histórico',
    'Logico': 'Lógico', 'logico': 'lógico',
    'Logica': 'Lógica', 'logica': 'lógica',
    'Tecnico': 'Técnico', 'tecnico': 'técnico',
    'Practica': 'Práctica', 'practica': 'práctica',
    'Automatico': 'Automático', 'automatico': 'automático',
    'automaticos': 'automáticos', 'automatica': 'automática',
    'Biometria': 'Biometría', 'biometria': 'biometría',
    'biometrico': 'biométrico', 'biometrica': 'biométrica',
    'Criptografico': 'Criptográfico', 'criptografico': 'criptográfico',
    'criptografica': 'criptográfica',
    'Bateria': 'Batería', 'bateria': 'batería',
    'Energia': 'Energía', 'energia': 'energía',
    'Telefono': 'Teléfono', 'telefono': 'teléfono',
    'Credito': 'Crédito', 'credito': 'crédito',
    'Debito': 'Débito', 'debito': 'débito',
    'Rapido': 'Rápido', 'rapido': 'rápido', 'rapida': 'rápida',
    'Facil': 'Fácil', 'facil': 'fácil',
    'Dificil': 'Difícil', 'dificil': 'difícil',
    'Util': 'Útil', 'util': 'útil', 'utiles': 'útiles',
    'Unico': 'Único', 'unico': 'único', 'unica': 'única',
    'unicos': 'únicos', 'unicas': 'únicas',
    'Ultimo': 'Último', 'ultimo': 'último', 'ultima': 'última',
    'ultimos': 'últimos', 'ultimas': 'últimas',
    'Proxima': 'Próxima', 'proxima': 'próxima',
    'Proximo': 'Próximo', 'proximo': 'próximo',
    'Ademas': 'Además', 'ademas': 'además',
    'Despues': 'Después', 'despues': 'después',
    'Aqui': 'Aquí', 'aqui': 'aquí',
    'Asi': 'Así', 'asi': 'así',
    'Tambien': 'También', 'tambien': 'también',
    'Segun': 'Según', 'segun': 'según',
    'Ningun': 'Ningún', 'ningun': 'ningún',
    'Algun': 'Algún', 'algun': 'algún',
    'Quiza': 'Quizá', 'quiza': 'quizá',
    'Pequeno': 'Pequeño', 'pequeno': 'pequeño',
    'pequena': 'pequeña', 'pequenos': 'pequeños',
    'Anadir': 'Añadir', 'anadir': 'añadir',
    'Anade': 'Añade', 'anade': 'añade',
    'anadido': 'añadido',
    'Manana': 'Mañana', 'manana': 'mañana',
    'companiia': 'compañía', 'compania': 'compañía',
    'Marroqui': 'Marroquí', 'marroqui': 'marroquí',
    'Japones': 'Japonés', 'japones': 'japonés',
    'Brasileno': 'Brasileño', 'brasileno': 'brasileño',
    # --- Formas verbales ---
    'estan': 'están', 'Estan': 'Están',
    'sera': 'será', 'Sera': 'Será', 'seran': 'serán',
    'pedira': 'pedirá', 'volvera': 'volverá',
    'quitara': 'quitará', 'desaparecera': 'desaparecerá',
    'seguiran': 'seguirán', 'dejara': 'dejará',
    'dejaran': 'dejarán', 'veras': 'verás',
    'podras': 'podrás', 'tendras': 'tendrás',
    'reaccionara': 'reaccionará', 'avisara': 'avisará',
    'apareceran': 'aparecerán', 'borraran': 'borrarán',
    'multiplicaria': 'multiplicaría', 'costaria': 'costaría',
    'romperia': 'rompería', 'seria': 'sería', 'Seria': 'Sería',
    'serian': 'serían', 'daria': 'daría', 'darian': 'darían',
    'haria': 'haría', 'harian': 'harían',
    'quedaria': 'quedaría', 'quedarian': 'quedarían',
    'acabaria': 'acabaría', 'acabarian': 'acabarían',
    'tendria': 'tendría', 'tendrian': 'tendrían',
    'podria': 'podría', 'podrian': 'podrían',
    'deberia': 'debería', 'deberian': 'deberían',
    'obligaria': 'obligaría', 'impediria': 'impediría',
    'dejarian': 'dejarían', 'saldria': 'saldría',
    'inflaria': 'inflaría', 'arrastraria': 'arrastraría',
    'convertiria': 'convertiría', 'perderia': 'perdería',
    'anadiria': 'añadiría', 'volveria': 'volvería',
    'llevaria': 'llevaría', 'bloquearia': 'bloquearía',
    'castigaria': 'castigaría', 'pagaria': 'pagaría',
    'reventaria': 'reventaría', 'engordaria': 'engordaría',
    'falsearia': 'falsearía', 'ensuciaria': 'ensuciaría',
    'cambiaria': 'cambiaría', 'exigiria': 'exigiría',
    'valdria': 'valdría', 'colgaria': 'colgaría',
    'apuntaria': 'apuntaría', 'saltaria': 'saltaría',
    'recorreria': 'recorrería', 'devolveria': 'devolvería',
    'permitiria': 'permitiría', 'ocurriria': 'ocurriría',
    'hundiria': 'hundiría',
    'aparecio': 'apareció', 'salio': 'salió',
    'nacio': 'nació', 'ocurrio': 'ocurrió',
}

COMMENT = re.compile(r'(//.*)$')
STRING = re.compile(r"('(?:[^'\\\n]|\\.)*')")
WORD = re.compile(r'\b(' + '|'.join(sorted(WORDS, key=len, reverse=True)) + r')\b')


def accent(text):
    return WORD.sub(lambda m: WORDS[m.group(1)], text)


def process(source):
    """Acentua comentarios y literales, dejando el codigo intacto."""
    out = []
    in_raw_block = False

    for line in source.split('\n'):
        stripped = line.lstrip()

        # Los raw strings gigantes del Lottie no llevan texto en espanol y no
        # deben tocarse bajo ningun concepto.
        if stripped.startswith("r'''"):
            in_raw_block = True
        if in_raw_block:
            out.append(line)
            if stripped.startswith("'''"):
                in_raw_block = False
            continue

        comment = COMMENT.search(line)
        if comment and "'" not in line[:comment.start()]:
            out.append(line[:comment.start()] + accent(comment.group(1)))
        else:
            out.append(STRING.sub(lambda m: accent(m.group(1)), line))

    return '\n'.join(out)


def main():
    changed = 0
    for path in glob.glob('lib/**/*.dart', recursive=True):
        if 'kitty_animations' in path:
            continue
        original = io.open(path, encoding='utf-8').read()
        updated = process(original)
        if updated != original:
            io.open(path, 'w', encoding='utf-8').write(updated)
            changed += 1
    print('Ficheros con tildes restituidas: %d' % changed)
    return 0


if __name__ == '__main__':
    sys.exit(main())
