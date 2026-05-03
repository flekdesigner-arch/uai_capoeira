// lib/config/app_config.dart
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  // Google Sign-In Client ID para Web
  static String get googleWebClientId {
    return '570246579920-pln8q6koks7ger8nrk44gevmvk6b6mah.apps.googleusercontent.com';
  }

  // Google Sign-In Client ID para Android (opcional)
  static String get googleAndroidClientId {
    return 'SEU_ANDROID_CLIENT_ID.apps.googleusercontent.com'; // Se tiver
  }

  // Google Sign-In Client ID para iOS (opcional)
  static String get googleIosClientId {
    return 'SEU_IOS_CLIENT_ID.apps.googleusercontent.com'; // Se tiver
  }

  // Método helper para pegar o client ID correto baseado na plataforma
  static String getGoogleClientId() {
    if (kIsWeb) {
      return googleWebClientId;
    }
    // Adicione lógica para outras plataformas se necessário
    return googleWebClientId; // Fallback para web
  }
}