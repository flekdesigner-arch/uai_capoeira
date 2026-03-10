// lib/theme/app_colors.dart

import 'package:flutter/material.dart';

class AppColors {
  // ==================== CORES PRINCIPAIS UAI CAPOEIRA ====================

  /// 🎯 VERMELHOS (baseado na logo)
  static const Color primary = Color(0xFFB71C1C);        // Vermelho escuro (shade900)
  static const Color primaryLight = Color(0xFFF44336);    // Vermelho claro (shade500)
  static const Color primaryDark = Color(0xFF8B0000);     // Vermelho mais escuro

  // ==================== CORES DE MÓDULOS E FUNCIONALIDADES ====================

  /// 📌 Módulos do app
  static const Color eventos = Color(0xFF1976D2);         // Azul
  static const Color associacao = Color(0xFF9C27B0);       // Roxo
  static const Color rifas = Color(0xFFFFA000);            // Âmbar
  static const Color uniformes = Color(0xFF388E3C);        // Verde
  static const Color inscricoes = Color(0xFF009688);       // Teal

  /// 📊 Badges e indicadores
  static const Color badgeAlunos = Color(0xFF1976D2);      // Azul (mesmo de eventos)
  static const Color badgeTurmas = Color(0xFF388E3C);      // Verde (mesmo de uniformes)
  static const Color badgeNotificacoes = Color(0xFFFFA000); // Âmbar (mesmo de rifas)

  // ==================== CORES DE STATUS ====================

  static const Color success = Color(0xFF4CAF50);          // Verde sucesso
  static const Color warning = Color(0xFFFFC107);          // Amarelo alerta
  static const Color error = Color(0xFFF44336);            // Vermelho erro
  static const Color info = Color(0xFF2196F3);             // Azul informação

  // ==================== CINZAS (TODOS OS QUE VOCÊ USA) ====================

  /// Cinza 50 - quase branco
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);          // Skeleton loading
  static const Color grey400 = Color(0xFFBDBDBD);          // Ícones desabilitados
  static const Color grey500 = Color(0xFF9E9E9E);          // Textos secundários
  static const Color grey600 = Color(0xFF757575);          // Textos de dica
  static const Color grey700 = Color(0xFF616161);          // Títulos de seção
  static const Color grey800 = Color(0xFF424242);
  static const Color grey900 = Color(0xFF212121);          // Texto principal

  // ==================== CORES BÁSICAS ====================

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);

  // ==================== CORES DE FUNDO ====================

  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // ==================== MÉTODOS ÚTEIS ====================

  /// Retorna a cor do módulo baseado no nome
  static Color getModuleColor(String moduleName) {
    switch (moduleName.toLowerCase()) {
      case 'eventos':
        return eventos;
      case 'associacao':
        return associacao;
      case 'rifas':
        return rifas;
      case 'uniformes':
        return uniformes;
      case 'inscricoes':
        return inscricoes;
      default:
        return primary;
    }
  }

  /// Retorna uma versão mais clara da cor (útil para hover/selected)
  static Color lighten(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return hslLight.toColor();
  }

  /// Retorna uma versão mais escura da cor
  static Color darken(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}