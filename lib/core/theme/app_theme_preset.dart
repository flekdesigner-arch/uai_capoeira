import 'package:flutter/material.dart';

enum UaiThemePreset {
  uaiClassico,
  draculaUai,
  cafeTerra,
  verdeNeon,
  setembroAmarelo,
  outubroRosa,
  novembroAzul,
  copaBrasil,
  natal,
  batizadoUai,
  usuarioPersonalizado,
}

extension UaiThemePresetX on UaiThemePreset {
  // Temas oficiais ficam no código; o Firebase só libera ou oculta IDs.
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
      case UaiThemePreset.setembroAmarelo:
        return 'setembro_amarelo';
      case UaiThemePreset.outubroRosa:
        return 'outubro_rosa';
      case UaiThemePreset.novembroAzul:
        return 'novembro_azul';
      case UaiThemePreset.copaBrasil:
        return 'copa_brasil';
      case UaiThemePreset.natal:
        return 'natal';
      case UaiThemePreset.batizadoUai:
        return 'batizado_uai';
      case UaiThemePreset.usuarioPersonalizado:
        return 'usuario_personalizado';
    }
  }

  String get label {
    switch (this) {
      case UaiThemePreset.uaiClassico:
        return 'UAI Clássico';
      case UaiThemePreset.draculaUai:
        return 'Dracula UAI';
      case UaiThemePreset.cafeTerra:
        return 'Café Terra';
      case UaiThemePreset.verdeNeon:
        return 'Verde Neon';
      case UaiThemePreset.setembroAmarelo:
        return 'Setembro Amarelo';
      case UaiThemePreset.outubroRosa:
        return 'Outubro Rosa';
      case UaiThemePreset.novembroAzul:
        return 'Novembro Azul';
      case UaiThemePreset.copaBrasil:
        return 'Copa Brasil';
      case UaiThemePreset.natal:
        return 'Natal';
      case UaiThemePreset.batizadoUai:
        return 'Batizado UAI';
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
      case UaiThemePreset.setembroAmarelo:
        return 'Tema de campanha com amarelo vibrante e contraste forte.';
      case UaiThemePreset.outubroRosa:
        return 'Campanha em rosa com clima escuro e leitura segura.';
      case UaiThemePreset.novembroAzul:
        return 'Azul de campanha com visual escuro elegante.';
      case UaiThemePreset.copaBrasil:
        return 'Verde e amarelo com pegada esportiva e alto contraste.';
      case UaiThemePreset.natal:
        return 'Tema festivo de Natal com vermelho, verde e dourado.';
      case UaiThemePreset.batizadoUai:
        return 'Tema claro cerimonial com azul e identidade UAI.';
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
      case UaiThemePreset.setembroAmarelo:
        return Icons.wb_sunny_rounded;
      case UaiThemePreset.outubroRosa:
        return Icons.favorite_rounded;
      case UaiThemePreset.novembroAzul:
        return Icons.water_drop_rounded;
      case UaiThemePreset.copaBrasil:
        return Icons.sports_soccer_rounded;
      case UaiThemePreset.natal:
        return Icons.celebration_rounded;
      case UaiThemePreset.batizadoUai:
        return Icons.church_rounded;
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
      case UaiThemePreset.setembroAmarelo:
        return const Color(0xFFF0C93A);
      case UaiThemePreset.outubroRosa:
        return const Color(0xFFE83E8C);
      case UaiThemePreset.novembroAzul:
        return const Color(0xFF1976D2);
      case UaiThemePreset.copaBrasil:
        return const Color(0xFF1B8F3A);
      case UaiThemePreset.natal:
        return const Color(0xFFB71C1C);
      case UaiThemePreset.batizadoUai:
        return const Color(0xFF3B82F6);
      case UaiThemePreset.usuarioPersonalizado:
        return const Color(0xFF6D5DF7);
    }
  }

  bool get isDark {
    switch (this) {
      case UaiThemePreset.uaiClassico:
      case UaiThemePreset.batizadoUai:
        return false;
      case UaiThemePreset.draculaUai:
      case UaiThemePreset.cafeTerra:
      case UaiThemePreset.verdeNeon:
      case UaiThemePreset.setembroAmarelo:
      case UaiThemePreset.outubroRosa:
      case UaiThemePreset.novembroAzul:
      case UaiThemePreset.copaBrasil:
      case UaiThemePreset.natal:
      case UaiThemePreset.usuarioPersonalizado:
        return true;
    }
  }

  static const List<UaiThemePreset> officialPresets = [
    UaiThemePreset.uaiClassico,
    UaiThemePreset.draculaUai,
    UaiThemePreset.cafeTerra,
    UaiThemePreset.verdeNeon,
    UaiThemePreset.setembroAmarelo,
    UaiThemePreset.outubroRosa,
    UaiThemePreset.novembroAzul,
    UaiThemePreset.copaBrasil,
    UaiThemePreset.natal,
    UaiThemePreset.batizadoUai,
    UaiThemePreset.usuarioPersonalizado,
  ];

  static bool isOfficialId(String? id) {
    if (id == null || id.trim().isEmpty) return false;
    return officialPresets.any((preset) => preset.id == id.trim());
  }

  static UaiThemePreset fromId(String? id) {
    for (final preset in UaiThemePreset.values) {
      if (preset.id == id) return preset;
    }

    return UaiThemePreset.uaiClassico;
  }
}
