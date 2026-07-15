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
  pergaminhoAncestral,
  terraQuilombo,
  cafeImperial,
  sangueEOuro,
  mataNoturna,
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
      case UaiThemePreset.pergaminhoAncestral:
        return 'pergaminho_ancestral';
      case UaiThemePreset.terraQuilombo:
        return 'terra_quilombo';
      case UaiThemePreset.cafeImperial:
        return 'cafe_imperial';
      case UaiThemePreset.sangueEOuro:
        return 'sangue_e_ouro';
      case UaiThemePreset.mataNoturna:
        return 'mata_noturna';
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
      case UaiThemePreset.pergaminhoAncestral:
        return 'Pergaminho Ancestral';
      case UaiThemePreset.terraQuilombo:
        return 'Terra Quilombo';
      case UaiThemePreset.cafeImperial:
        return 'Café Imperial';
      case UaiThemePreset.sangueEOuro:
        return 'Sangue e Ouro';
      case UaiThemePreset.mataNoturna:
        return 'Mata Noturna';
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
      case UaiThemePreset.pergaminhoAncestral:
        return 'Visual clássico inspirado em pergaminhos e manuscritos antigos.';
      case UaiThemePreset.terraQuilombo:
        return 'Tons terrosos que remetem às raízes e à resistência.';
      case UaiThemePreset.cafeImperial:
        return 'Paleta quente, elegante e acolhedora.';
      case UaiThemePreset.sangueEOuro:
        return 'Contraste nobre, forte e marcante.';
      case UaiThemePreset.mataNoturna:
        return 'Profundidade escura com atmosfera ancestral.';
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
      case UaiThemePreset.pergaminhoAncestral:
        return Icons.menu_book_rounded;
      case UaiThemePreset.terraQuilombo:
        return Icons.landscape_rounded;
      case UaiThemePreset.cafeImperial:
        return Icons.coffee_rounded;
      case UaiThemePreset.sangueEOuro:
        return Icons.shield_rounded;
      case UaiThemePreset.mataNoturna:
        return Icons.park_rounded;
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
      case UaiThemePreset.pergaminhoAncestral:
        return const Color(0xFF9B6A2F);
      case UaiThemePreset.terraQuilombo:
        return const Color(0xFF9A4F2D);
      case UaiThemePreset.cafeImperial:
        return const Color(0xFF8B4A24);
      case UaiThemePreset.sangueEOuro:
        return const Color(0xFF7B1E2B);
      case UaiThemePreset.mataNoturna:
        return const Color(0xFF547A3B);
      case UaiThemePreset.usuarioPersonalizado:
        return const Color(0xFF6D5DF7);
    }
  }

  bool get isDark {
    switch (this) {
      case UaiThemePreset.uaiClassico:
      case UaiThemePreset.batizadoUai:
      case UaiThemePreset.pergaminhoAncestral:
        return false;
      case UaiThemePreset.draculaUai:
      case UaiThemePreset.cafeTerra:
      case UaiThemePreset.verdeNeon:
      case UaiThemePreset.setembroAmarelo:
      case UaiThemePreset.outubroRosa:
      case UaiThemePreset.novembroAzul:
      case UaiThemePreset.copaBrasil:
      case UaiThemePreset.natal:
      case UaiThemePreset.terraQuilombo:
      case UaiThemePreset.cafeImperial:
      case UaiThemePreset.sangueEOuro:
      case UaiThemePreset.mataNoturna:
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
    UaiThemePreset.pergaminhoAncestral,
    UaiThemePreset.terraQuilombo,
    UaiThemePreset.cafeImperial,
    UaiThemePreset.sangueEOuro,
    UaiThemePreset.mataNoturna,
    UaiThemePreset.usuarioPersonalizado,
  ];

  static const UaiThemePreset defaultEstudosPreset =
      UaiThemePreset.pergaminhoAncestral;

  static const List<UaiThemePreset> officialPresetsForEstudos = [
    UaiThemePreset.pergaminhoAncestral,
    UaiThemePreset.terraQuilombo,
    UaiThemePreset.cafeImperial,
    UaiThemePreset.sangueEOuro,
    UaiThemePreset.mataNoturna,
  ];

  bool get isAvailableForEstudos => officialPresetsForEstudos.contains(this);

  static bool isAvailableForEstudosId(String? id) {
    if (id == null || id.trim().isEmpty) return false;
    final clean = id.trim();
    return officialPresetsForEstudos.any((preset) => preset.id == clean);
  }

  static UaiThemePreset? estudosPresetFromId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final clean = id.trim();
    for (final preset in officialPresetsForEstudos) {
      if (preset.id == clean) return preset;
    }
    return null;
  }

  static bool isOfficialId(String? id) {
    if (id == null || id.trim().isEmpty) return false;
    return officialPresets.any((preset) => preset.id == id.trim());
  }

  static UaiThemePreset? presetFromId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final clean = id.trim();
    for (final preset in officialPresets) {
      if (preset.id == clean) return preset;
    }
    return null;
  }

  static UaiThemePreset fromId(String? id) {
    for (final preset in UaiThemePreset.values) {
      if (preset.id == id) return preset;
    }

    return UaiThemePreset.uaiClassico;
  }
}
