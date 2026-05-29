import 'package:flutter/material.dart';

/// Compatibilidade com código antigo.
///
/// O ideal daqui para frente é usar:
/// - Theme.of(context).colorScheme.primary
/// - context.uai.primary
/// - context.uai.card
///
/// Mas manter esta classe evita quebrar arquivos antigos que ainda usam AppColors.primary.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFB71C1C);
  static const Color primaryLight = Color(0xFFF44336);
  static const Color primaryDark = Color(0xFF8B0000);
  static const Color primarySoft = Color(0xFFFFEBEE);

  static const Color eventos = Color(0xFF1976D2);
  static const Color associacao = Color(0xFF9C27B0);
  static const Color rifas = Color(0xFFFFA000);
  static const Color uniformes = Color(0xFF388E3C);
  static const Color inscricoes = Color(0xFF009688);

  static const Color badgeAlunos = Color(0xFF1976D2);
  static const Color badgeTurmas = Color(0xFF388E3C);
  static const Color badgeNotificacoes = Color(0xFFFFA000);

  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color successSoft = Color(0xFFC8E6C9);

  static const Color warning = Color(0xFFFFC107);
  static const Color warningLight = Color(0xFFFFF3E0);

  static const Color error = Color(0xFFF44336);
  static const Color errorLight = Color(0xFFFFEBEE);

  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFE3F2FD);
  static const Color infoSoft = Color(0xFFBBDEFB);

  static const Color purple = Colors.purple;
  static const Color purpleLight = Color(0xFFF3E5F5);

  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey400 = Color(0xFFBDBDBD);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey600 = Color(0xFF757575);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey800 = Color(0xFF424242);
  static const Color grey900 = Color(0xFF212121);

  static const Color greyBackground = Color(0xFFF5F5F5);
  static const Color greyBorder = Color(0xFFE0E0E0);
  static const Color greyText = Color(0xFF757575);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);

  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);

  static Color getModuleColor(String moduleName) {
    switch (moduleName.toLowerCase()) {
      case 'eventos':
        return eventos;
      case 'associacao':
      case 'associação':
        return associacao;
      case 'rifas':
        return rifas;
      case 'uniformes':
        return uniformes;
      case 'inscricoes':
      case 'inscrições':
        return inscricoes;
      default:
        return primary;
    }
  }

  static Color lighten(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  static Color darken(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}
