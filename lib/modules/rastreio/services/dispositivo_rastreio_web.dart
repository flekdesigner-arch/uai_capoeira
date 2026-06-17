import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Map<String, dynamic> coletarDadosNavegadorSeguro() {
  final navigator = web.window.navigator;
  final dados = <String, dynamic>{
    'user_agent_cliente': navigator.userAgent,
    'idioma': navigator.language,
    'plataforma_browser': navigator.platform,
  };

  try {
    final intl = web.window.getProperty<JSObject?>('Intl'.toJS);
    final dateTimeFormat = intl?.callMethod<JSObject>('DateTimeFormat'.toJS);
    final options = dateTimeFormat?.callMethod<JSObject>(
      'resolvedOptions'.toJS,
    );
    final timezone = options?.getProperty<JSString?>('timeZone'.toJS)?.toDart;
    dados['timezone'] = timezone ?? DateTime.now().timeZoneName;
  } catch (_) {
    dados['timezone'] = DateTime.now().timeZoneName;
  }

  try {
    final navObject = navigator as JSObject;
    final uaData = navObject.getProperty<JSObject?>('userAgentData'.toJS);
    if (uaData != null) {
      final mobile = uaData.getProperty<JSBoolean?>('mobile'.toJS)?.toDart;
      final platform = uaData.getProperty<JSString?>('platform'.toJS)?.toDart;
      final brands = uaData.getProperty<JSAny?>('brands'.toJS)?.dartify();

      dados['mobile_user_agent_data'] = mobile == true;
      dados['plataforma_browser'] = platform ?? dados['plataforma_browser'];
      dados['user_agent_data'] = {
        'mobile': mobile == true,
        'platform': platform,
      };
      if (brands is List) {
        dados['brands_user_agent_data'] = brands;
      }
    }
  } catch (_) {
    dados['user_agent_data'] = null;
  }

  return dados;
}
