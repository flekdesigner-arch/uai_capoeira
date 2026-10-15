import 'dart:async';
import 'dart:html' as html;

/// Serviço Web responsável pela instalação do PWA.
///
/// HOTFIX:
/// Não usa `dart:js_util`. A comunicação com o bridge global do index.html
/// acontece exclusivamente por CustomEvent, compatível com o toolchain atual.
class PwaInstallService {
  PwaInstallService._internal() {
    _init();
  }

  static final PwaInstallService instance = PwaInstallService._internal();

  final StreamController<bool> _installAvailableController =
      StreamController<bool>.broadcast();

  html.Event? _fallbackDeferredPrompt;
  bool _bridgeInstallAvailable = false;
  bool _initialized = false;
  int _requestSequence = 0;

  Stream<bool> get installAvailableStream =>
      _installAvailableController.stream;

  bool get isInstallPromptAvailable =>
      (_bridgeInstallAvailable || _fallbackDeferredPrompt != null) &&
      !isInstalled;

  bool get isInstalled {
    return html.window.matchMedia('(display-mode: standalone)').matches ||
        _navigatorStandalone;
  }

  bool get _navigatorStandalone {
    // iOS/Safari expõe navigator.standalone apenas em runtime.
    // O acesso dinâmico fica protegido para não afetar outros navegadores.
    try {
      final navigator = html.window.navigator as dynamic;
      return navigator.standalone == true;
    } catch (_) {
      return false;
    }
  }

  bool _eventDetailIsTrue(html.Event event) {
    if (event is! html.CustomEvent) return false;
    final value = event.detail;
    return value == true || value?.toString() == '1' || value?.toString() == 'true';
  }

  void _emitCurrentAvailability() {
    _installAvailableController.add(isInstallPromptAvailable);
  }

  void _requestBridgeState() {
    html.window.dispatchEvent(
      html.CustomEvent('uai-pwa-install-state-request'),
    );
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;

    // Evento emitido sempre que o index.html captura/perde o prompt.
    html.window.addEventListener('uai-pwa-install-available', (event) {
      _bridgeInstallAvailable = _eventDetailIsTrue(event);
      _emitCurrentAvailability();
    });

    // Resposta explícita para serviços lazy que nasceram depois do
    // beforeinstallprompt original.
    html.window.addEventListener('uai-pwa-install-state', (event) {
      _bridgeInstallAvailable = _eventDetailIsTrue(event);
      _emitCurrentAvailability();
    });

    // Fallback: se o bridge do index não existir por algum motivo, o próprio
    // serviço ainda tenta preservar beforeinstallprompt quando já estiver vivo.
    html.window.addEventListener('beforeinstallprompt', (event) {
      event.preventDefault();
      _fallbackDeferredPrompt = event;
      _bridgeInstallAvailable = true;
      _emitCurrentAvailability();
    });

    html.window.addEventListener('appinstalled', (_) {
      _fallbackDeferredPrompt = null;
      _bridgeInstallAvailable = false;
      _installAvailableController.add(false);
    });

    // Como esta biblioteca pode ser deferred/lazy, pergunta imediatamente ao
    // index.html se um prompt já foi capturado antes dela existir.
    scheduleMicrotask(() {
      _requestBridgeState();
      _emitCurrentAvailability();
    });
  }

  Future<bool> promptInstall() async {
    if (isInstalled) {
      _installAvailableController.add(false);
      return true;
    }

    // Caminho principal: solicita ao bridge global do index.html que use o
    // DeferredPrompt capturado anteriormente.
    if (_bridgeInstallAvailable) {
      final requestId = '${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';
      final completer = Completer<bool>();
      late html.EventListener listener;

      listener = (html.Event event) {
        if (event is! html.CustomEvent) return;
        final detail = event.detail?.toString() ?? '';
        final separator = detail.lastIndexOf('|');
        if (separator <= 0) return;

        final id = detail.substring(0, separator);
        if (id != requestId) return;

        html.window.removeEventListener('uai-pwa-install-result', listener);
        final accepted = detail.substring(separator + 1) == '1';
        _bridgeInstallAvailable = false;
        _fallbackDeferredPrompt = null;
        _emitCurrentAvailability();

        if (!completer.isCompleted) completer.complete(accepted);
      };

      html.window.addEventListener('uai-pwa-install-result', listener);
      html.window.dispatchEvent(
        html.CustomEvent(
          'uai-pwa-install-request',
          detail: requestId,
        ),
      );

      try {
        return await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            html.window.removeEventListener('uai-pwa-install-result', listener);
            _requestBridgeState();
            return false;
          },
        );
      } catch (_) {
        html.window.removeEventListener('uai-pwa-install-result', listener);
        _requestBridgeState();
        return false;
      }
    }

    // Fallback direto, útil em ambientes onde o bridge não capturou o evento.
    final prompt = _fallbackDeferredPrompt;
    if (prompt == null) {
      _requestBridgeState();
      _emitCurrentAvailability();
      return false;
    }

    try {
      await (prompt as dynamic).prompt();
      final choiceRaw = await (prompt as dynamic).userChoice;

      _fallbackDeferredPrompt = null;
      _bridgeInstallAvailable = false;
      _installAvailableController.add(false);

      final outcome = (choiceRaw as dynamic).outcome?.toString();
      return outcome == 'accepted';
    } catch (_) {
      _fallbackDeferredPrompt = null;
      _bridgeInstallAvailable = false;
      _installAvailableController.add(false);
      return false;
    }
  }
}
