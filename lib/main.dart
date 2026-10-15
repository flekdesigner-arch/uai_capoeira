// PATCH SITE 04 - ENTRYPOINT CONDICIONAL
//
// Web/PWA compila somente o core público no boot.
// Android/Windows mantêm o bootstrap completo existente.
import 'app/bootstrap/uai_native_bootstrap.dart'
    if (dart.library.html) 'app/bootstrap/uai_web_bootstrap.dart' as bootstrap;

Future<void> main() => bootstrap.startApp();
