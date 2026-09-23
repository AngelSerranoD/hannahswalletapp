// Candado de despliegue. Lo ejecuta Vercel antes de publicar (es el
// `buildCommand` de vercel.json) y, si falla, no publica nada.
//
// Una build buena sale de `python tool/build_pwa.py`, que cambia el service
// worker de Flutter (que solo se desinstala) por el propio y le pone la marca
// de abajo. `flutter build web` a secas deja el de Flutter, sin marca: esa
// build no abriría sin conexión y no se debe publicar.
//
// Viaja en `web/` para que TODA build lo lleve, también las que están mal.
//
// Autor: Ángel Serrano Domínguez
// Copyright (c) 2026 Ángel Serrano Domínguez. Todos los derechos reservados.
'use strict';

const fs = require('fs');

const MARCA = 'hecho-con: tool/build_pwa.py';

let worker = '';
try {
  worker = fs.readFileSync('flutter_service_worker.js', 'utf8');
} catch (_) {
  // Sin service worker tampoco se publica: cae en el aviso de abajo.
}

if (!worker.includes(MARCA)) {
  console.error('Esta build no sale de python tool/build_pwa.py (le falta su ' +
      'service worker): no se despliega.');
  process.exit(1);
}
console.log('Build de tool/build_pwa.py: se puede desplegar.');
