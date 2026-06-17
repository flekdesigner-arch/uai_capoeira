import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dispositivo_rastreio_web_stub.dart'
    if (dart.library.html) 'dispositivo_rastreio_web.dart';

class DispositivoRastreioService {
  const DispositivoRastreioService();

  Map<String, dynamic> coletar(
    BuildContext context, {
    String? tela,
    String? origem,
    Map<String, dynamic>? extra,
  }) {
    final media = MediaQuery.of(context);
    final size = media.size;

    final largura = size.width;
    final altura = size.height;

    final tipoDispositivo = _classificarDispositivo(size.shortestSide);
    final tipoPlataforma = _classificarPlataforma();
    final web = coletarDadosNavegadorSeguro();
    final userAgent = web['user_agent_cliente']?.toString() ?? '';
    final marcaModelo = detectarMarcaModeloCelular(userAgent);

    return {
      'tipo_dispositivo': tipoDispositivo,
      'tipo_plataforma': tipoPlataforma,
      'plataforma_flutter': defaultTargetPlatform.name,
      'is_web': kIsWeb,

      'largura_tela': largura.round(),
      'altura_tela': altura.round(),
      'menor_lado': size.shortestSide.round(),
      'maior_lado': size.longestSide.round(),
      'pixel_ratio': media.devicePixelRatio,
      'orientacao': media.orientation.name,

      'tema_sistema': media.platformBrightness.name,
      'text_scale': media.textScaler.toString(),

      'padding_top': media.padding.top.round(),
      'padding_bottom': media.padding.bottom.round(),
      'view_insets_bottom': media.viewInsets.bottom.round(),

      'idioma': web['idioma'] ?? _idiomaFlutter(),
      'timezone': web['timezone'] ?? DateTime.now().timeZoneName,
      'timezone_offset_minutos': DateTime.now().timeZoneOffset.inMinutes,
      'user_agent_cliente': userAgent.isEmpty ? null : userAgent,
      'navegador_nome': detectarNavegador(userAgent)['nome'],
      'navegador_versao': detectarNavegador(userAgent)['versao'],
      'sistema_operacional_aproximado': detectarSistemaOperacional(userAgent),
      'celular_marca_aproximada': marcaModelo['marca'],
      'celular_modelo_aproximado': marcaModelo['modelo'],
      'user_agent_data': web['user_agent_data'],
      'mobile_user_agent_data': web['mobile_user_agent_data'],
      'brands_user_agent_data': web['brands_user_agent_data'],
      'plataforma_browser': web['plataforma_browser'],

      'tela': tela,
      'origem': origem,
      'coletado_em': DateTime.now().toIso8601String(),

      ...?extra,
    };
  }

  String _classificarDispositivo(double menorLado) {
    if (menorLado < 600) return 'celular';
    if (menorLado < 900) return 'tablet';
    return 'desktop';
  }

  String _classificarPlataforma() {
    if (kIsWeb) return 'web';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String _idiomaFlutter() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final pais = locale.countryCode;
    if (pais == null || pais.isEmpty) return locale.languageCode;
    return '${locale.languageCode}-$pais';
  }

  static Map<String, String> detectarNavegador(String userAgent) {
    final ua = userAgent.trim();
    if (ua.isEmpty) return {'nome': 'desconhecido', 'versao': ''};

    final regras = <String, RegExp>{
      'Edge': RegExp(r'Edg/([\d.]+)', caseSensitive: false),
      'Opera': RegExp(r'OPR/([\d.]+)', caseSensitive: false),
      'Chrome': RegExp(r'Chrome/([\d.]+)', caseSensitive: false),
      'Safari': RegExp(r'Version/([\d.]+).*Safari', caseSensitive: false),
      'Firefox': RegExp(r'Firefox/([\d.]+)', caseSensitive: false),
      'Samsung Internet': RegExp(
        r'SamsungBrowser/([\d.]+)',
        caseSensitive: false,
      ),
    };

    for (final entry in regras.entries) {
      final match = entry.value.firstMatch(ua);
      if (match != null) {
        return {'nome': entry.key, 'versao': match.group(1) ?? ''};
      }
    }

    return {'nome': 'desconhecido', 'versao': ''};
  }

  static String detectarSistemaOperacional(String userAgent) {
    final ua = userAgent.toLowerCase();
    if (ua.isEmpty) return 'desconhecido';
    if (ua.contains('android')) return 'Android';
    if (ua.contains('iphone')) return 'iOS iPhone';
    if (ua.contains('ipad')) return 'iPadOS';
    if (ua.contains('windows nt')) return 'Windows';
    if (ua.contains('mac os x')) return 'macOS';
    if (ua.contains('linux')) return 'Linux';
    return 'desconhecido';
  }

  static Map<String, String> detectarMarcaModeloCelular(String userAgent) {
    final ua = userAgent.trim();
    if (ua.isEmpty) {
      return {
        'marca': 'desconhecido',
        'modelo': 'nao_disponivel_pelo_navegador',
      };
    }

    String token(RegExp regex) => regex.firstMatch(ua)?.group(1)?.trim() ?? '';

    final samsung = token(RegExp(r'\b(SM-[A-Z0-9]+)\b', caseSensitive: false));
    if (samsung.isNotEmpty) {
      return {'marca': 'Samsung', 'modelo': samsung.toUpperCase()};
    }

    final redmi = token(RegExp(r'\b(Redmi[^;\)]+)', caseSensitive: false));
    if (redmi.isNotEmpty) {
      return {'marca': 'Xiaomi/Redmi', 'modelo': redmi};
    }

    final xiaomi = token(RegExp(r'\b(M2\d{3,}[^;\)]*)', caseSensitive: false));
    if (xiaomi.isNotEmpty || RegExp(r'\b22\d{2,}').hasMatch(ua)) {
      return {
        'marca': 'Xiaomi',
        'modelo': xiaomi.isNotEmpty ? xiaomi : 'Android aproximado',
      };
    }

    final moto = token(RegExp(r'\b(Moto[^;\)]+)', caseSensitive: false));
    if (moto.isNotEmpty) {
      return {'marca': 'Motorola', 'modelo': moto};
    }

    if (ua.contains('iPhone')) return {'marca': 'Apple', 'modelo': 'iPhone'};
    if (ua.contains('iPad')) return {'marca': 'Apple', 'modelo': 'iPad'};
    if (!ua.contains('Android')) {
      return {
        'marca': 'nao_aplicavel',
        'modelo': 'nao_disponivel_pelo_navegador',
      };
    }

    return {'marca': 'desconhecido', 'modelo': 'nao_disponivel_pelo_navegador'};
  }
}
