import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudos_config_model.dart';

class EstudosThemePreset {
  static const String dinamico = 'dinamico';
  static const String pergaminhoAncestral = 'pergaminho_ancestral';
  static const String terraQuilombo = 'terra_quilombo';
  static const String cafeImperial = 'cafe_imperial';
  static const String sangueEOuro = 'sangue_e_ouro';
  static const String mataNoturna = 'mata_noturna';

  static const List<String> values = [
    pergaminhoAncestral,
    terraQuilombo,
    cafeImperial,
    sangueEOuro,
    mataNoturna,
  ];

  static bool isValid(String value) => values.contains(value);

  static String label(String value) {
    switch (value) {
      case terraQuilombo:
        return 'Terra Quilombo';
      case cafeImperial:
        return 'Café Imperial';
      case sangueEOuro:
        return 'Sangue e Ouro';
      case mataNoturna:
        return 'Mata Noturna';
      case pergaminhoAncestral:
      default:
        return 'Pergaminho Ancestral';
    }
  }

  static String description(String value) {
    switch (value) {
      case terraQuilombo:
        return 'Tons terrosos que remetem às raízes e à resistência.';
      case cafeImperial:
        return 'Paleta quente, elegante e acolhedora.';
      case sangueEOuro:
        return 'Contraste nobre, forte e marcante.';
      case mataNoturna:
        return 'Profundidade escura com atmosfera ancestral.';
      case pergaminhoAncestral:
      default:
        return 'Visual clássico inspirado em pergaminhos e manuscritos antigos.';
    }
  }

  static UaiThemeTokens tokens(String value) {
    switch (value) {
      case terraQuilombo:
        return _terraQuilombo;
      case cafeImperial:
        return _cafeImperial;
      case sangueEOuro:
        return _sangueEOuro;
      case mataNoturna:
        return _mataNoturna;
      case pergaminhoAncestral:
      default:
        return _pergaminhoAncestral;
    }
  }
}

class EstudosAlunoTheme extends StatelessWidget {
  final EstudosConfigModel? config;
  final Widget child;

  const EstudosAlunoTheme({
    super.key,
    required this.config,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    if (cfg == null || !cfg.forcarTemaEstudos) return child;
    final preset = cfg.temaEstudosSelecionado;
    if (!EstudosThemePreset.isValid(preset)) return child;

    final tokens = EstudosThemePreset.tokens(preset);
    final base = Theme.of(context);
    final appBarBg = tokens.surface;
    final appBarFg = tokens.readableTextOn(appBarBg);
    final primaryButtonFg = tokens.readableTextOn(tokens.primary);
    final secondaryButtonBg = tokens.cardAlt;
    final secondaryButtonFg = tokens.textPrimary;
    final themed = base.copyWith(
      scaffoldBackgroundColor: tokens.background,
      primaryColor: tokens.primary,
      colorScheme: base.colorScheme.copyWith(
        primary: tokens.primary,
        onPrimary: primaryButtonFg,
        secondary: tokens.accent,
        onSecondary: tokens.readableTextOn(tokens.accent),
        surface: tokens.surface,
        error: tokens.error,
        onError: tokens.readableTextOn(tokens.error),
        onSurface: tokens.textPrimary,
        outline: tokens.border,
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: tokens.accent,
              iconColor: tokens.accent,
              disabledForegroundColor: tokens.textMuted,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                tokens.accent.withValues(alpha: 0.10),
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: secondaryButtonFg,
              iconColor: tokens.accent,
              disabledForegroundColor: tokens.textMuted,
              side: BorderSide(color: tokens.border),
              backgroundColor: secondaryButtonBg.withValues(alpha: 0.72),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.buttonRadius),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return BorderSide(
                    color: tokens.border.withValues(alpha: 0.45),
                  );
                }
                if (states.contains(WidgetState.pressed) ||
                    states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return BorderSide(color: tokens.accent);
                }
                return BorderSide(color: tokens.border);
              }),
              overlayColor: WidgetStatePropertyAll(
                tokens.accent.withValues(alpha: 0.10),
              ),
            ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: tokens.primary,
              foregroundColor: primaryButtonFg,
              iconColor: primaryButtonFg,
              disabledBackgroundColor: tokens.cardAlt,
              disabledForegroundColor: tokens.textMuted,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.buttonRadius),
              ),
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                tokens.accent.withValues(alpha: 0.12),
              ),
            ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        titleTextStyle:
            base.appBarTheme.titleTextStyle?.copyWith(
              color: appBarFg,
              fontWeight: FontWeight.w900,
            ) ??
            TextStyle(
              color: appBarFg,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );

    return Theme(data: themed, child: child);
  }
}

const _pergaminhoAncestral = UaiThemeTokens(
  primary: Color(0xFF9B6A2F),
  primaryLight: Color(0xFFC99A56),
  primaryDark: Color(0xFF5A3517),
  accent: Color(0xFFC49A4A),
  background: Color(0xFFE9D9B8),
  surface: Color(0xFFF1E5C9),
  card: Color(0xFFF7EED7),
  cardAlt: Color(0xFFE8D6AF),
  textPrimary: Color(0xFF332313),
  textSecondary: Color(0xFF684D2D),
  textMuted: Color(0xFF9A7B51),
  border: Color(0xFFD2BC8A),
  success: Color(0xFF5C8A45),
  warning: Color(0xFFC49A4A),
  error: Color(0xFFB24A3B),
  info: Color(0xFF6B7F8E),
  eventos: Color(0xFF6B7F8E),
  associacao: Color(0xFF8B6F9E),
  rifas: Color(0xFFC49A4A),
  uniformes: Color(0xFF5C8A45),
  inscricoes: Color(0xFF6B7F8E),
  primaryGradient: LinearGradient(
    colors: [Color(0xFF6F451E), Color(0xFFC49A4A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  softGradient: LinearGradient(
    colors: [Color(0xFFF7EED7), Color(0xFFE8D6AF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  cardRadius: 20,
  buttonRadius: 15,
  inputRadius: 15,
  cardShadow: [
    BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 8)),
  ],
  softShadow: [
    BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 4)),
  ],
);

const _terraQuilombo = UaiThemeTokens(
  primary: Color(0xFF9A4F2D),
  primaryLight: Color(0xFFD17B48),
  primaryDark: Color(0xFF4B2618),
  accent: Color(0xFF7A8C45),
  background: Color(0xFF2A1710),
  surface: Color(0xFF3A2117),
  card: Color(0xFF4A2A1C),
  cardAlt: Color(0xFF5B3825),
  textPrimary: Color(0xFFFFF1DD),
  textSecondary: Color(0xFFE2C3A4),
  textMuted: Color(0xFFB89473),
  border: Color(0xFF765137),
  success: Color(0xFF7A8C45),
  warning: Color(0xFFD5A24B),
  error: Color(0xFFD4624D),
  info: Color(0xFF8FA7A0),
  eventos: Color(0xFF8FA7A0),
  associacao: Color(0xFFB58A6B),
  rifas: Color(0xFFD5A24B),
  uniformes: Color(0xFF7A8C45),
  inscricoes: Color(0xFF8FA7A0),
  primaryGradient: LinearGradient(
    colors: [Color(0xFF4B2618), Color(0xFF9A4F2D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  softGradient: LinearGradient(
    colors: [Color(0xFF3A2117), Color(0xFF5B3825)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  cardRadius: 20,
  buttonRadius: 15,
  inputRadius: 15,
  cardShadow: [
    BoxShadow(color: Color(0x88000000), blurRadius: 22, offset: Offset(0, 10)),
  ],
  softShadow: [
    BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 5)),
  ],
);

const _cafeImperial = UaiThemeTokens(
  primary: Color(0xFF8B4A24),
  primaryLight: Color(0xFFC47A3D),
  primaryDark: Color(0xFF3B1E12),
  accent: Color(0xFFD6A45C),
  background: Color(0xFF17110D),
  surface: Color(0xFF221812),
  card: Color(0xFF2D1F18),
  cardAlt: Color(0xFF3A281F),
  textPrimary: Color(0xFFFFF4E6),
  textSecondary: Color(0xFFE8D2B8),
  textMuted: Color(0xFFC0A58B),
  border: Color(0xFF4F382B),
  success: Color(0xFF7AC77A),
  warning: Color(0xFFD6A45C),
  error: Color(0xFFE15F4F),
  info: Color(0xFF7DB7D8),
  eventos: Color(0xFF7DB7D8),
  associacao: Color(0xFFC896D8),
  rifas: Color(0xFFD6A45C),
  uniformes: Color(0xFF7AC77A),
  inscricoes: Color(0xFF7DB7D8),
  primaryGradient: LinearGradient(
    colors: [Color(0xFF3B1E12), Color(0xFF8B4A24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  softGradient: LinearGradient(
    colors: [Color(0xFF221812), Color(0xFF3A281F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  cardRadius: 20,
  buttonRadius: 15,
  inputRadius: 15,
  cardShadow: [
    BoxShadow(color: Color(0x90000000), blurRadius: 24, offset: Offset(0, 12)),
  ],
  softShadow: [
    BoxShadow(color: Color(0x60000000), blurRadius: 14, offset: Offset(0, 6)),
  ],
);

const _sangueEOuro = UaiThemeTokens(
  primary: Color(0xFF7B1E2B),
  primaryLight: Color(0xFFB13A46),
  primaryDark: Color(0xFF3A0C14),
  accent: Color(0xFFD0A248),
  background: Color(0xFF16090B),
  surface: Color(0xFF241012),
  card: Color(0xFF31161A),
  cardAlt: Color(0xFF432026),
  textPrimary: Color(0xFFFFEFE8),
  textSecondary: Color(0xFFE3C3B5),
  textMuted: Color(0xFFB98F81),
  border: Color(0xFF64313A),
  success: Color(0xFF6FAA61),
  warning: Color(0xFFD0A248),
  error: Color(0xFFE35A4F),
  info: Color(0xFF9AA7C0),
  eventos: Color(0xFF9AA7C0),
  associacao: Color(0xFFD0A248),
  rifas: Color(0xFFD0A248),
  uniformes: Color(0xFF6FAA61),
  inscricoes: Color(0xFF9AA7C0),
  primaryGradient: LinearGradient(
    colors: [Color(0xFF3A0C14), Color(0xFF7B1E2B), Color(0xFFD0A248)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  softGradient: LinearGradient(
    colors: [Color(0xFF241012), Color(0xFF432026)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  cardRadius: 20,
  buttonRadius: 15,
  inputRadius: 15,
  cardShadow: [
    BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 12)),
  ],
  softShadow: [
    BoxShadow(color: Color(0x60000000), blurRadius: 14, offset: Offset(0, 6)),
  ],
);

const _mataNoturna = UaiThemeTokens(
  primary: Color(0xFF547A3B),
  primaryLight: Color(0xFF88A85E),
  primaryDark: Color(0xFF1B2F1F),
  accent: Color(0xFFC0A052),
  background: Color(0xFF07100B),
  surface: Color(0xFF0E1A12),
  card: Color(0xFF142219),
  cardAlt: Color(0xFF1C3123),
  textPrimary: Color(0xFFF4F0D8),
  textSecondary: Color(0xFFD2CBA8),
  textMuted: Color(0xFF9EA27E),
  border: Color(0xFF304733),
  success: Color(0xFF75B45C),
  warning: Color(0xFFC0A052),
  error: Color(0xFFD55C4D),
  info: Color(0xFF79A9A0),
  eventos: Color(0xFF79A9A0),
  associacao: Color(0xFFC0A052),
  rifas: Color(0xFFC0A052),
  uniformes: Color(0xFF75B45C),
  inscricoes: Color(0xFF79A9A0),
  primaryGradient: LinearGradient(
    colors: [Color(0xFF07100B), Color(0xFF547A3B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  softGradient: LinearGradient(
    colors: [Color(0xFF0E1A12), Color(0xFF1C3123)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  cardRadius: 20,
  buttonRadius: 15,
  inputRadius: 15,
  cardShadow: [
    BoxShadow(color: Color(0xA0000000), blurRadius: 24, offset: Offset(0, 12)),
  ],
  softShadow: [
    BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6)),
  ],
);
