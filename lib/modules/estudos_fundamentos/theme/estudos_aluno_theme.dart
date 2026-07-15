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
        return UaiThemeTokens.terraQuilombo;
      case cafeImperial:
        return UaiThemeTokens.cafeImperial;
      case sangueEOuro:
        return UaiThemeTokens.sangueEOuro;
      case mataNoturna:
        return UaiThemeTokens.mataNoturna;
      case pergaminhoAncestral:
      default:
        return UaiThemeTokens.pergaminhoAncestral;
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
