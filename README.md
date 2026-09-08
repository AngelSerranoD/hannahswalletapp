# Hannah's Wallet

Control de gastos, ingresos y presupuestos. **Sin servidor, sin cuenta y sin
telemetría**: los datos se guardan cifrados en el propio dispositivo y solo
salen de él si tú exportas una copia.

Inspirada en *Flowfy* —sus funciones y su paleta— con dos diferencias
deliberadas: privacidad real y un gato que reacciona a cómo va tu mes.

## Consumo

La app calentaba el móvil con solo tenerla abierta. La causa no era el cifrado
ni las consultas: era **la mascota**. Su animación de reposo se repetía
indefinidamente —sesenta repintados por segundo, para siempre— y el
`IndexedStack` de las pestañas la mantenía viva aunque estuvieras en Ajustes
mirando otra cosa.

Lo que se hizo:

| Cambio | Efecto |
|---|---|
| El gato **para** tras 12 s sin interacción | De animar siempre a animar solo cuando hay alguien mirando |
| `TickerMode` por pestaña | Fuera de la pestaña visible no se anima nada |
| Pestañas construidas al visitarlas | Abrir la app lanzaba las consultas de las cuatro |
| Limitador en el detector de actividad | De cientos de eventos por segundo a uno |
| Formateadores de `intl` reutilizados | Se construía uno por importe y por fecha, en cada fotograma |
| `RepaintBoundary` en el halo, `filterQuality: none` | El gradiente dejó de repintarse con el gato |
| 44 correcciones de lints de rendimiento | Widgets `const` que Flutter ya no reconstruye |

El gato vuelve a moverse en cuanto tocas la pantalla, y las celebraciones y
alertas se reproducen siempre: no se ha perdido nada de la mascota, solo deja
de gastar cuando el móvil está en la mesa.

`performance_test.dart` lo comprueba midiendo `transientCallbackCount`, el
número de animaciones vivas: **cero significa que nada está pidiendo
fotogramas**. Es una regresión que sería invisible —la app se vería igual— y
solo se notaría en la batería, así que conviene tenerla cubierta.

También se quitó lo que sobraba: tres providers que nadie usaba, dos
dependencias sin un solo import (`collection` y `cupertino_icons`) y los
`.symbols` del build.

## Compilar y desplegar en Vercel

```bash
python tool/build_pwa.py
```

Usa este script y no `flutter build web` a secas. Además de compilar con los
flags correctos, **verifica el resultado y aborta si algo falla**:

- CanvasKit y fuentes empaquetados, sin descargas de `gstatic.com`
- Sin referencias a dominios de terceros
- CSP presente y sin scripts en línea
- `vercel.json` con las cabeceras de seguridad
- Un service worker que cachea de verdad

También poda los ficheros `.symbols` (7 MB de mapas de depuración que ningún
navegador pide) y genera el service worker con la lista de recursos del build.

### Subirlo

El resultado queda en `build/web`, y ahí dentro va ya el `vercel.json`. Con la
CLI:

```bash
cp .vercel/project.json build/web/.vercel/project.json
cd build/web && vercel deploy --prod
```

El `cp` no es opcional. La CLI decide a qué proyecto sube mirando el `.vercel`
del directorio que despliega y, si no lo encuentra, **crea uno nuevo con el
nombre de la carpeta**. Como la carpeta se llama `web`, `vercel deploy build/web`
acaba publicando en un proyecto llamado `web`, luego `web-1`, `web-2`... Lo mismo
pasa arrastrando la carpeta a [vercel.com/new](https://vercel.com/new).

La vinculación del repositorio se crea una sola vez con `vercel link`, pero vive
en la raíz y `build/` se regenera en cada compilación: de ahí la copia.

Vercel sirve HTTPS por defecto, que no es un detalle: **sin HTTPS no hay
Face ID** —WebAuthn no existe fuera de un origen seguro— ni IndexedDB fiable en
iOS.

### Probarlo antes en local

```bash
python tool/serve_build.py
```

Sirve `build/web` en `http://127.0.0.1:8099` con las mismas cabeceras que
pondrá Vercel. No uses `python -m http.server`: responde en HTTP/1.0 y el
navegador falla al registrar el service worker con un escueto *"unknown error
when fetching the script"*.

### Qué se descarga

| Momento | Peso |
|---|---|
| Hasta poder usar la app | ~10 MB (motor, código y fuentes latinas) |
| A los 3 s, en segundo plano | 8 MB de la fuente china |

Vercel comprime con brotli, así que en la práctica es bastante menos. A partir
de la segunda visita no se descarga nada: lo sirve el service worker.

### El service worker

Flutter ya no genera uno que cachee —el suyo solo se desinstala a sí mismo—,
así que la app **no arrancaría sin conexión**, que es justo lo contrario de lo
que promete. `tool/build_pwa.py` lo sustituye por
`tool/service_worker_template.js`, que precarga lo esencial (unos 10 MB) y
cachea el resto según se usa. El motor de CanvasKit (28 MB con todos los
renderers, de los que cada navegador usa uno) queda fuera del precache a
propósito: se guarda solo en la primera visita, que siempre tiene conexión.

## Los colores

Paleta del estanque, en tema claro único:

```
#0A3323  verde oscuro   texto principal, botones      12,5:1 sobre el fondo
#105666  verde noche    texto secundario, ingresos     7,4:1
#839958  verde musgo    RELLENO (no texto)             2,8:1
#D3968C  rosa palo      RELLENO (no texto)             2,2:1
#F7F4D5  beige          fondo
```

Los dos últimos no sirven para texto sobre el beige: se quedan muy por debajo
del mínimo. Eso no los descarta, los coloca — como fondo de un distintivo o de
una barra, con el verde oscuro escrito encima, dan 4,4:1 y 5,6:1. Usarlos al
revés sería un error de contraste difícil de ver en un monitor y muy evidente
al sol.

Las tarjetas y los bordes se **derivan** del beige: la paleta trae un solo tono
claro, y sin derivar uno más la tarjeta y el fondo serían el mismo color.

### El color no es el único portador

Se conservan los recursos no cromáticos: signo `+` / `−` y peso para ingresos
frente a gastos, y **trama diagonal** en la barra de un presupuesto rebasado.
Funcionan para quien no distingue el verde del rosa.

### El gato va en color

La mascota conserva sus colores originales. Es lo único con color saturado en
pantalla, así que funciona como foco, y su terracota convive con los verdes.

## Las fuentes

| Uso | Fuente | Licencia |
|---|---|---|
| Títulos | **Pinyon Script** | SIL OFL |
| Todo lo demás | **Archivo** | SIL OFL |
| Chino | **Noto Sans SC** | SIL OFL |

Las tres se pueden **incrustar en una app sin restricciones**. Ese fue el
primer criterio, por delante del parecido: antes estuvieron aquí Coolvetica y
CandleScript, y las dos licencias gratuitas excluyen expresamente los webfonts
y las apps.

La elección de los sustitutos no se hizo por catálogo. Se descargaron seis
candidatas y se compararon renderizando **los títulos reales de la app a su
tamaño real**: Archivo resultó la más cercana a Coolvetica en compacidad y peso
(Inter salía más ancha, Manrope más ligera), y Pinyon Script la más cercana a
CandleScript además de la más legible a 19 px.

Pinyon Script trae **757 glifos** y cubre el español entero. Eso importa más de
lo que parece: la demo anterior tenía 56 —solo A-Z, a-z y el espacio— y para
cada carácter que le faltaba **dibujaba el nombre de la fuente**, así que
"Estadísticas" salía en pantalla como *"EstadCandlescriptsticas"*. Con Pinyon
Script no hace falta ninguna regla de reparto: la caligráfica se aplica a
cualquier título.

Se preparan con `python tool/prepare_fonts.py`, que las descarga, genera las
tres instancias estáticas de Archivo (se publica como fuente variable) y
comprueba que cubran el repertorio que la app usa.

## Escribir en chino

La interfaz está en español, pero se puede **escribir en chino** en cualquier
campo: el nombre de una categoría, el concepto de un gasto, una nota.

Esto no sale gratis. Roboto no tiene un solo glifo chino, y normalmente el
motor de Flutter lo resolvería descargando una fuente de reserva de
`fonts.gstatic.com` — que es justo lo que la política de seguridad prohíbe. Sin
una fuente empaquetada, el texto se guardaría bien pero se vería como
rectángulos vacíos.

Por eso va **Noto Sans SC** dentro de la app (8,3 MB, cobertura completa). No
se declara en la sección `fonts:` del pubspec, porque eso la descargaría al
arrancar incluso para quien solo escribe en español: se carga sola en segundo
plano después del primer frame, y Flutter rehace el layout cuando llega.

---|---|
| Ingreso vs gasto | Signo `+` / `−` y peso tipográfico |
| Presupuesto rebasado | **Trama diagonal** en la barra |
| Categorías | Seis tonos separados ≥1,38:1, con distintivo invertido |
| Estado de la mascota | Intensidad del halo, y el texto que lo acompaña |
| Series del gráfico | Punto **relleno** vs **contorno** en la leyenda |

Los tres recursos —signo, trama y peso— funcionan igual en blanco y negro,
impresos, o para alguien que no distingue tonos.

### El gato va en color

La mascota conserva sus colores originales, los del icono. Es deliberado: es lo
único con color en toda la pantalla, así que funciona como foco, y su terracota
convive de forma natural con los cuatro tonos cálidos. Se regenera con
`python tool/generate_kitty_lottie.py`.

---|---|
| Verde / rojo en importes | Signo `+` / `−` y peso tipográfico |
| Barra roja al rebasar | **Trama diagonal** en la barra |
| 10 colores de categoría | 6 grises separados ≥1,4:1, con distintivo invertido |
| Halo de color en la mascota | Halo por intensidad, de claro a tinta |
| Puntos de leyenda en color | Punto **relleno** vs **contorno** |

Los tres recursos —signo, trama y peso— funcionan igual en una pantalla en
blanco y negro, impresos, o para alguien que no distingue tonos. El color
nunca era el único portador, pero ahora directamente no hay ninguno.

Los tonos de texto están verificados sobre los dos fondos reales de la app:
tinta 18,4:1, texto principal 13,2:1, secundario 6,0:1 y terciario 4,0:1.

Los distintivos de categoría se **invierten**: el gris va al fondo y el icono
se pinta en blanco o tinta, el que contraste. Con el planteamiento anterior
—fondo del color al 16 %— un gris claro daba 1,4:1 y el icono desaparecía.

---

## Cómo se ejecuta

### PWA (el objetivo principal: iPhone)

```bash
python tool/build_pwa.py
```

Usa este script y no `flutter build web` a secas. Compila con los flags
correctos y **comprueba el resultado**: que el motor y las fuentes viajen
dentro, que no queden referencias a dominios de terceros y que la política de
seguridad siga en su sitio. Si algo de eso falla, aborta.

El resultado queda en `build/web/`. Sírvelo por **HTTPS** (obligatorio: sin él
iOS no instala la app ni deja usar IndexedDB) y ábrelo en Safari.

Para probarlo en local antes de subirlo:

```bash
cd build/web && python -m http.server 8099
```

`http://127.0.0.1:8099` funciona porque `localhost` cuenta como contexto seguro.

**Activa la compresión en tu hosting** (gzip o brotli). La primera carga son unos
11 MB sin comprimir —el motor de Flutter más el código de la app—, que con brotli
se quedan en 3-4 MB. A partir de ahí el service worker lo cachea todo y la app
abre al instante, incluso sin conexión.

**Si lo sirves desde un subdirectorio** (por ejemplo GitHub Pages en
`usuario.github.io/hannahswallet/`), hay que compilar indicando la ruta o la app
no encontrará sus propios ficheros:

```bash
python tool/build_pwa.py /hannahswallet/
```

### Instalar en el iPhone

1. Abre la URL **en Safari** (no vale Chrome en iOS: solo Safari puede instalar).
2. Botón *Compartir* → **Añadir a pantalla de inicio**.
3. Ábrela desde el icono, no desde Safari.

Ese último paso importa de verdad: Safari borra el almacenamiento de los sitios
que no visitas en 7 días, pero las apps añadidas a la pantalla de inicio están
**exentas** de esa política y llevan su propio contador. Usada desde el icono,
tus datos se quedan.

### Android (se mantiene, aunque el foco sea el iPhone)

```bash
flutter build apk --release
```

---

## Arquitectura

Clean Architecture en tres capas, con las dependencias apuntando siempre hacia
dentro:

```
lib/
├── core/            Tema, utilidades, errores e inyección de dependencias
├── domain/          Entidades y contratos de repositorio. Sin dependencias externas
├── data/            Implementaciones: bases de datos, cifrado, servicios
└── presentation/    Providers de Riverpod, pantallas y widgets
```

### Dos backends, una sola interfaz

La app corre en dos mundos con capacidades muy distintas, así que
`AppBackend` abstrae la persistencia y cada plataforma aporta la suya. La
selección se hace con un **import condicional**, de modo que el compilador ni
siquiera ve el código de la otra plataforma:

| | **PWA (iPhone)** | **Móvil nativo** |
|---|---|---|
| Almacén | Blob AES-GCM en IndexedDB | SQLCipher (fichero `.db` cifrado) |
| Clave | PBKDF2 (310 000 iter.) de tu contraseña maestra | Aleatoria, en Keychain/Keystore |
| Al abrir | Escribes la contraseña | Transparente |
| Consultas | Agregaciones en Dart sobre memoria | SQL con índices |
| Biometría | Face ID vía WebAuthn PRF (iOS 18+) | Biometría + PIN de pantalla |
| Auto-bloqueo | Por inactividad y al salir | Bloqueo de pantalla con margen |

**Por qué esa diferencia**: en el navegador no existe un almacén protegido por
hardware. Guardar una clave en el propio navegador para descifrar "sin
molestar" sería teatro — quien pueda leer IndexedDB también puede leer donde
esté la clave. La única raíz de confianza posible es algo que solo tú sepas.

> ⚠️ **Si olvidas la contraseña maestra, los datos son irrecuperables.** No se
> guarda en ninguna parte y no hay servidor que pueda restablecerla. Exporta
> una copia JSON de vez en cuando: es tu único seguro.

### El dinero se guarda en enteros

Todos los importes viajan en **céntimos** (`int`), nunca en `double`. En coma
flotante `0.1 + 0.2` da `0.30000000000000004`, y tras unos cientos de
movimientos el saldo deja de cuadrar por un céntimo sin que sepas por qué.
Ver `core/utils/money.dart`.

### El saldo no se reinicia cada mes

La cifra grande de la cabecera es el **patrimonio acumulado histórico**, no el
neto del mes: parte del saldo inicial de cada cartera, recorre todos los
movimientos sin filtro de fecha e ignora las transferencias entre carteras
propias (mover dinero de un sitio a otro no crea ni destruye patrimonio).

### Presupuestos que no hay que recrear cada día 1

Un mismo modelo cubre los cuatro casos, combinando dos campos:

- `category_id` nulo → presupuesto **global** del mes; con valor → **por categoría**.
- `month_key` con valor (`'2026-08'`) → solo ese mes; nulo → **plantilla** que
  se aplica a todos los meses que no tengan uno propio.

---

## La mascota

El gato es **Lottie**, con las animaciones generadas por script y embebidas como
constantes Dart (`presentation/widgets/mascot/kitty_animations.dart`). Se
generan con:

```bash
python tool/generate_kitty_lottie.py
```

Edita `tool/generate_kitty_lottie.py` para cambiar al gato: formas, colores y
tiempos están ahí, y el script reescribe el fichero Dart.

Tres clips: **reposo** (respira, parpadea, mueve la cola), **celebración**
(salta con monedas, al guardar un movimiento) y **alerta** (tiembla, gota de
sudor, al pasar del 90 % del presupuesto).

`KittyMascotController` expone la misma API que tendría una máquina de estados
de Rive — `budgetHealth`, `fireSuccess()`, `fireAlert()` — pero implementada en
Dart, así que las transiciones se pueden leer y probar. El reposo además se
ralentiza cuanto peor va el mes: sin leer un número, un gato que respira
despacio ya dice que la cosa aprieta.

---

## Pruebas

```bash
flutter test
```

124 pruebas cubren lo que más duele si se rompe:

- **`money_test.dart`** — parseo de importes con coma y punto, y que la suma en
  céntimos no acumule error.
- **`date_range_test.dart`** — intervalos semiabiertos, semana que empieza en
  lunes, cambios de año.
- **`recurrence_test.dart`** — el día 31 en meses de 30, febrero bisiesto.
- **`mascot_state_test.dart`** — que la alerta salte al cruzar el 90 % y **no**
  se repita en cada refresco.
- **`web_vault_test.dart`** — cifrado, contraseña incorrecta, persistencia entre
  sesiones y todas las agregaciones del backend web.
- **`backup_format_test.dart`** — rechazo de ficheros ajenos o de versiones
  futuras.
- **`security_test.dart`** — sobres de clave, migración del formato antiguo,
  límite de intentos y desbloqueo biométrico con un autenticador simulado.
- **`app_flow_test.dart`** — recorrido completo sobre la app real: crear la
  bóveda, anotar un gasto, bloquear, volver a entrar y comprobar que los datos
  siguen ahí. Es el que detecta que dos piezas correctas no encajen.
- **`face_id_flow_test.dart`** — activar Face ID desde Ajustes, abrir con él y
  qué pasa al cancelarlo, con un doble del Secure Enclave.
- **`chinese_input_test.dart`** — que el chino se teclee, se cifre, se guarde y
  vuelva intacto, y que la fuente esté empaquetada.
- **`performance_test.dart`** — que la mascota deje de animar cuando nadie la
  mira, y que los formateadores se reutilicen.
- **`fonts_test.dart`** — la regla de reparto entre la caligráfica y el cuerpo.
- **`goldens_test.dart`** — capturas de referencia de la interfaz.

Para regenerar las capturas tras un cambio de diseño:

```bash
flutter test --update-goldens test/goldens_test.dart
```


---

## Seguridad

### Cómo se abre la bóveda

Los datos se cifran con una **clave de datos aleatoria** (AES-256-GCM). Esa
clave no se guarda nunca en claro: se guarda **envuelta**, tantas veces como
formas de abrir la app haya configuradas.

| Sobre | Llave que lo abre | Dónde vive esa llave |
|---|---|---|
| Contraseña | PBKDF2-HMAC-SHA256, 310 000 iteraciones | En tu cabeza |
| Face ID | HKDF sobre el secreto de WebAuthn PRF | En el Secure Enclave del iPhone |

Las dos abren **la misma** clave, así que activar Face ID no duplica los datos
ni debilita la contraseña. Y cambiar la contraseña reescribe solo su sobre
—unas decenas de bytes— en lugar de volver a cifrar todo el historial.

### Face ID en una PWA

Se usa la extensión **PRF de WebAuthn** (Safari 18 / iOS 18 o superior). No es
un "¿eres tú?" cosmético: el Secure Enclave devuelve un secreto de 32 bytes que
solo calcula **después** de verificar tu cara, y ese secreto es el que
desenvuelve la clave. Saltarse el diálogo no sirve de nada — sin el secreto, la
bóveda sigue siendo ruido.

Por eso la opción **no se ofrece** si el dispositivo tiene Face ID pero no PRF:
sería prometer una protección que no existe.

### Bloqueo automático

El cifrado protege los datos **en reposo**. Con la bóveda abierta, la clave está
en memoria y todo es legible, así que la sesión se cierra sola:

- al **salir de la app**, siempre y sin margen;
- tras **N minutos de inactividad** (3 por defecto, configurable en Ajustes).

### Intentos fallidos

Los 5 primeros errores no penalizan. A partir de ahí la espera se duplica —5 s,
10 s, 20 s...— hasta un tope de 5 minutos, y **durante la espera no abre ni la
contraseña correcta**. El contador vive fuera de la bóveda: comprobarlo no puede
exigir descifrar justo lo que se está protegiendo.

### La app no habla con nadie, y lo impone el navegador

La cabecera `connect-src 'self'` **prohíbe** cualquier conexión fuera del propio
origen. No es una promesa: es el navegador quien lo bloquea.

Esa política destapó que Flutter, por defecto, descargaba el motor CanvasKit y
la fuente Roboto desde `gstatic.com` en cada arranque. Ahora ambos viajan dentro
del bundle. El único resto es el mecanismo de fuentes de reserva del motor: si
escribes un emoji en la nota de un gasto, el navegador bloqueará la descarga de
la fuente y se verá un rectángulo. Es el precio de no abrir ni una conexión.

Las cabeceras completas están en `web/_headers` (Netlify y Cloudflare Pages).
Para otros servidores, cópialas de ahí:

- **nginx**: `add_header` con cada una de las líneas.
- **Apache**: `Header always set` en un `.htaccess`.
- **Vercel**: bloque `headers` en `vercel.json`.

Tres de ellas —`frame-ancestors`, `X-Content-Type-Options` y
`Permissions-Policy`— **solo funcionan como cabecera HTTP real**, no como
etiqueta `<meta>`. Si tu hosting no las permite, la app sigue funcionando pero
pierdes la protección contra clickjacking.

### Lo que sigue sin estar protegido

Sé honesto con estos puntos:

- **El JSON exportado no va cifrado.** Es legible por cualquiera que lo abra.
  La app avisa antes de compartirlo. Es, a la vez, tu único seguro si olvidas
  la contraseña.
- **Si pierdes todas las formas de abrir la bóveda, los datos se pierden.** No
  hay servidor, no hay recuperación, no hay puerta trasera.
- **La PWA no puede ocultarse del conmutador de apps de iOS.** Una app nativa
  puede taparse al cambiar de aplicación; una web no tiene esa API.

---

## Portabilidad de los datos

Ajustes → **Exportar copia** genera un JSON con todo el historial. El formato es
**idéntico en las dos plataformas**, así que sirve para pasar los datos del
móvil a la PWA o al revés, y también para migrar a otra app o procesarlos con
cualquier lenguaje.

El fichero exportado **no va cifrado**: dentro de la app los datos están
protegidos, pero una vez fuera son legibles. La app lo avisa antes de compartir.
