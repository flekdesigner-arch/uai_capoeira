import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

extension type _StandaloneNavigator(JSObject _) implements JSObject {
  external JSBoolean? get standalone;
}

extension type _InstallPrompt(JSObject _) implements JSObject {
  external JSPromise<JSAny?> prompt();
  external JSPromise<_InstallChoice> get userChoice;
}

extension type _InstallChoice(JSObject _) implements JSObject {
  external JSString? get outcome;
}

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

  web.Event? _fallbackDeferredPrompt;
  bool _bridgeInstallAvailable = false;
  bool _initialized = false;
  int _requestSequence = 0;

  Stream<bool> get installAvailableStream =>
      _installAvailableController.stream;

  bool get isInstallPromptAvailable =>
      (_bridgeInstallAvailable || _fallbackDeferredPrompt != null) &&
      !isInstalled;

  bool get isInstalled {
    return web.window.matchMedia('(display-mode: standalone)').matches ||
        _navigatorStandalone;
  }

  bool get _navigatorStandalone {
    // iOS/Safari expõe navigator.standalone apenas em runtime.
    // O acesso dinâmico fica protegido para não afetar outros navegadores.
    try {
      return _StandaloneNavigator(web.window.navigator).standalone?.toDart == true;
    } catch (_) {
      return false;
    }
  }

  bool _eventDetailIsTrue(web.Event event) {
    if (!event.isA<web.CustomEvent>()) return false;
    final value = (event as web.CustomEvent).detail.dartify();
    return value == true || value?.toString() == '1' || value?.toString() == 'true';
  }

  void _emitCurrentAvailability() {
    _installAvailableController.add(isInstallPromptAvailable);
  }

  void _requestBridgeState() {
    web.window.dispatchEvent(
      web.CustomEvent('uai-pwa-install-state-request'),
    );
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;

    // Evento emitido sempre que o index.html captura/perde o prompt.
    web.window.addEventListener('uai-pwa-install-available', ((web.Event event) {
      _bridgeInstallAvailable = _eventDetailIsTrue(event);
      _emitCurrentAvailability();
    }).toJS);

    // Resposta explícita para serviços lazy que nasceram depois do
    // beforeinstallprompt original.
    web.window.addEventListener('uai-pwa-install-state', ((web.Event event) {
      _bridgeInstallAvailable = _eventDetailIsTrue(event);
      _emitCurrentAvailability();
    }).toJS);

    // Fallback: se o bridge do index não existir por algum motivo, o próprio
    // serviço ainda tenta preservar beforeinstallprompt quando já estiver vivo.
    web.window.addEventListener('beforeinstallprompt', ((web.Event event) {
      event.preventDefault();
      _fallbackDeferredPrompt = event;
      _bridgeInstallAvailable = true;
      _emitCurrentAvailability();
    }).toJS);

    web.window.addEventListener('appinstalled', ((web.Event _) {
      _fallbackDeferredPrompt = null;
      _bridgeInstallAvailable = false;
      _installAvailableController.add(false);
    }).toJS);

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
      late JSFunction listener;

      listener = ((web.Event event) {
        if (!event.isA<web.CustomEvent>()) return;
        final detail = (event as web.CustomEvent).detail.dartify()?.toString() ?? '';
        final separator = detail.lastIndexOf('|');
        if (separator <= 0) return;

        final id = detail.substring(0, separator);
        if (id != requestId) return;

        web.window.removeEventListener('uai-pwa-install-result', listener);
        final accepted = detail.substring(separator + 1) == '1';
        _bridgeInstallAvailable = false;
        _fallbackDeferredPrompt = null;
        _emitCurrentAvailability();

        if (!completer.isCompleted) completer.complete(accepted);
      }).toJS;

      web.window.addEventListener('uai-pwa-install-result', listener);
      web.window.dispatchEvent(
        web.CustomEvent(
          'uai-pwa-install-request',
          web.CustomEventInit(detail: requestId.toJS),
        ),
      );

      try {
        return await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            web.window.removeEventListener('uai-pwa-install-result', listener);
            _requestBridgeState();
            return false;
          },
        );
      } catch (_) {
        web.window.removeEventListener('uai-pwa-install-result', listener);
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
      final installPrompt = _InstallPrompt(prompt);
      await installPrompt.prompt().toDart;
      final choiceRaw = await installPrompt.userChoice.toDart;

      _fallbackDeferredPrompt = null;
      _bridgeInstallAvailable = false;
      _installAvailableController.add(false);

      final outcome = choiceRaw.outcome?.toDart;
      return outcome == 'accepted';
    } catch (_) {
      _fallbackDeferredPrompt = null;
      _bridgeInstallAvailable = false;
      _installAvailableController.add(false);
      return false;
    }
  }
}
