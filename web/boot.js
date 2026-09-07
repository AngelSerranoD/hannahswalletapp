// Retira la pantalla de carga en cuanto Flutter pinta su primer frame.
//
// Vive en un fichero y no como <script> dentro del HTML para que la política
// de seguridad de contenido (CSP) pueda prohibir los scripts en línea, que es
// la defensa principal contra la inyección de código.
window.addEventListener('flutter-first-frame', function () {
  var boot = document.getElementById('boot');
  if (!boot) return;
  boot.classList.add('hidden');
  setTimeout(function () { boot.remove(); }, 400);
});
