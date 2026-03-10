// lib/config/app_config.dart
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  // Google Sign-In Client ID para Web
  static String get googleWebClientId {
    // Em produção, isso viria de uma variável de ambiente
    // Mas por enquanto, vamos manter aqui
    return '570246579920-pln8q6koks7ger8nrk44gevmvk6b6mah.apps.googleusercontent.com';
  }
}