import 'dart:async';
import 'dart:html' as html;

class PwaInstallService {
  PwaInstallService._internal() {
    _init();
  }

  static final PwaInstallService instance = PwaInstallService._internal();

  final StreamController<bool> _installAvailableController =
  StreamController<bool>.broadcast();

  html.Event? _deferredPrompt;
  bool _initialized = false;

  Stream<bool> get installAvailableStream => _installAvailableController.stream;

  bool get isInstallPromptAvailable => _deferredPrompt != null;

  void _init() {
    if (_initialized) return;
    _initialized = true;

    html.window.addEventListener('beforeinstallprompt', (event) {
      event.preventDefault();
      _deferredPrompt = event;
      _installAvailableController.add(true);
    });

    html.window.addEventListener('appinstalled', (_) {
      _deferredPrompt = null;
      _installAvailableController.add(false);
    });
  }

  Future<bool> promptInstall() async {
    final prompt = _deferredPrompt;

    if (prompt == null) {
      return false;
    }

    try {
      // Chamada dinâmica para o evento beforeinstallprompt.
      // Evita depender de dart:js_util, que pode não existir no projeto.
      await (prompt as dynamic).prompt();

      final choiceRaw = await (prompt as dynamic).userChoice;

      _deferredPrompt = null;
      _installAvailableController.add(false);

      final outcome = (choiceRaw as dynamic).outcome?.toString();
      return outcome == 'accepted';
    } catch (_) {
      _deferredPrompt = null;
      _installAvailableController.add(false);
      return false;
    }
  }
}
