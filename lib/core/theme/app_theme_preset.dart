import 'package:flutter/material.dart';

enum UaiThemePreset {
  uaiClassico,
  draculaUai,
  cafeTerra,
  verdeNeon,
  usuarioPersonalizado,
}

extension UaiThemePresetX on UaiThemePreset {
  String get id {
    switch (this) {
      case UaiThemePreset.uaiClassico:
        return 'uai_classico';
      case UaiThemePreset.draculaUai:
        return 'dracula_uai';
      case UaiThemePreset.cafeTerra:
        return 'cafe_terra';
      case UaiThemePreset.verdeNeon:
        return 'verde_neon';
      case UaiThemePreset.usuarioPersonalizado:
        return 'usuario_personalizado';
    }
  }

  String get label {
    switch (this) {
      case UaiThemePreset.uaiClassico:
        return 'UAI Clássico';
      case UaiThemePreset.draculaUai:
        return 'Drácula Vinho';
      case UaiThemePreset.cafeTerra:
        return 'Café Terra';
      case UaiThemePreset.verdeNeon:
        return 'Verde Neon';
      case UaiThemePreset.usuarioPersonalizado:
        return 'Tema do Usuário';
    }
  }

  String get description {
    switch (this) {
      case UaiThemePreset.uaiClassico:
        return 'Claro premium: vermelho UAI, branco e cards elegantes.';
      case UaiThemePreset.draculaUai:
        return 'Escuro elegante com vinho sangue e contraste forte.';
      case UaiThemePreset.cafeTerra:
        return 'Escuro quente: café, marrom terra, creme e dourado suave.';
      case UaiThemePreset.verdeNeon:
        return 'Dark tecnológico com verde neon, preto e vibe robótica.';
      case UaiThemePreset.usuarioPersonalizado:
        return 'Monte seu próprio tema com cores, cantos e fonte.';
    }
  }

  IconData get icon {
    switch (this) {
      case UaiThemePreset.uaiClassico:
        return Icons.sports_martial_arts_rounded;
      case UaiThemePreset.draculaUai:
        return Icons.auto_awesome_rounded;
      case UaiThemePreset.cafeTerra:
        return Icons.coffee_rounded;
      case UaiThemePreset.verdeNeon:
        return Icons.bolt_rounded;
      case UaiThemePreset.usuarioPersonalizado:
        return Icons.tune_rounded;
    }
  }

  Color get previewColor {
    switch (this) {
      case UaiThemePreset.uaiClassico:
        return const Color(0xFFB71C1C);
      case UaiThemePreset.draculaUai:
        return const Color(0xFFD21F35);
      case UaiThemePreset.cafeTerra:
        return const Color(0xFF8B4A24);
      case UaiThemePreset.verdeNeon:
        return const Color(0xFF39FF14);
      case UaiThemePreset.usuarioPersonalizado:
        return const Color(0xFF6D5DF7);
    }
  }

  bool get isDark {
    switch (this) {
      case UaiThemePreset.uaiClassico:
        return false;
      case UaiThemePreset.draculaUai:
      case UaiThemePreset.cafeTerra:
      case UaiThemePreset.verdeNeon:
      case UaiThemePreset.usuarioPersonalizado:
        return true;
    }
  }

  static UaiThemePreset fromId(String? id) {
    for (final preset in UaiThemePreset.values) {
      if (preset.id == id) return preset;
    }

    return UaiThemePreset.uaiClassico;
  }
}
