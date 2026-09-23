// Arranque de la app web. Plantilla propia: `flutter build web` la usa en vez
// de la que genera por defecto y rellena las tres marcas {{...}}.
//
// Autor: Ángel Serrano Domínguez
// Copyright (c) 2026 Ángel Serrano Domínguez. Todos los derechos reservados.
{{flutter_js}}
{{flutter_build_config}}

// Por qué hay plantilla: el motor, por defecto, pide dos cosas a la CDN de
// Google (CanvasKit y las fuentes de reserva). La CSP de la app
// (`connect-src 'self'`) las bloquea, y con razón: la app no habla con nadie.
// Aquí se le dice al motor que las busque en el propio build. (Este archivo no
// puede nombrar esos dominios: `tool/build_pwa.py` rechaza el build si los ve.)
function cargarMotor() {
  _flutter.loader.load({
    config: {
      // `flutter build web` siempre copia canvaskit/ al build; lo que cambia
      // con --no-web-resources-cdn es solo de dónde se carga. Con esta línea,
      // un `flutter build web` a secas ya no deja la app en blanco por la CSP.
      canvasKitBaseUrl: "canvaskit/",
      // Si el motor cree que a un texto le falta un glifo, descarga una Noto
      // de aquí. `tool/build_pwa.py` deja en esta carpeta la que pide (Noto
      // Sans Symbols recortada, ver `tool/prepare_fonts.py`).
      fontFallbackBaseUrl: "fuentes-reserva/",
    },
  });
}

// El service worker propio (el que `tool/build_pwa.py` pone en
// flutter_service_worker.js) se registra aquí, no con `serviceWorkerSettings`:
// en Flutter 3.41, `flutter.js` solo lo registra si ya había uno de antes (es
// su camino para retirar el suyo), así que en una instalación nueva no se
// registraba nunca y la PWA no abría sin conexión.
//
// Y, como hacía `flutter.js`, el motor espera a que el service worker controle
// la página (4 s como mucho): CanvasKit no va en el precache y solo se guarda
// si su descarga pasa por el service worker. Sin esta espera, en la primera
// visita no pasaba y la app no abría sin conexión hasta la tercera.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("flutter_service_worker.js");
  var controlada = navigator.serviceWorker.controller
    ? Promise.resolve()
    : new Promise(function (listo) {
        navigator.serviceWorker.addEventListener("controllerchange", listo);
      });
  var tope = new Promise(function (listo) { setTimeout(listo, 4000); });
  Promise.race([controlada, tope]).then(cargarMotor);
} else {
  cargarMotor();
}
