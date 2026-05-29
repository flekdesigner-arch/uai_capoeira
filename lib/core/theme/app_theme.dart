import 'package:flutter/material.dart';

import 'app_theme_controller.dart';
import 'app_theme_preset.dart';
import 'app_theme_tokens.dart';

class AppTheme {
  AppTheme._();

  static UaiThemeTokens tokensFor(UaiThemePreset preset) {
    switch (preset) {
      case UaiThemePreset.uaiClassico:
        return UaiThemeTokens.uaiClassico;
      case UaiThemePreset.draculaUai:
        return UaiThemeTokens.draculaVermelho;
      case UaiThemePreset.cafeTerra:
        return UaiThemeTokens.cafeTerra;
      case UaiThemePreset.verdeNeon:
        return UaiThemeTokens.verdeNeon;
      case UaiThemePreset.usuarioPersonalizado:
        return AppThemeController.instance.userThemeTokens;
    }
  }

  static bool _isDarkPreset(UaiThemePreset preset, UaiThemeTokens tokens) {
    if (preset == UaiThemePreset.uaiClassico) return false;
    if (preset == UaiThemePreset.usuarioPersonalizado) {
      return tokens.background.computeLuminance() < 0.45;
    }
    return true;
  }

  static Color _readableTextOn(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.48 ? const Color(0xFF111827) : Colors.white;
  }

  static ThemeData build(UaiThemePreset preset) {
    final UaiThemeTokens t = tokensFor(preset);
    final bool isDark = _isDarkPreset(preset, t);
    final String? fontFamily = t.fontFamily;

    final appBarBg = isDark ? t.cardAlt : t.primary;
    final appBarFg = _readableTextOn(appBarBg);

    final scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: t.primary,
      onPrimary: _readableTextOn(t.primary),
      secondary: t.accent,
      onSecondary: _readableTextOn(t.accent),
      error: t.error,
      onError: _readableTextOn(t.error),
      surface: t.surface,
      onSurface: t.textPrimary,
      primaryContainer: t.primaryDark,
      onPrimaryContainer: _readableTextOn(t.primaryDark),
      secondaryContainer: t.cardAlt,
      onSecondaryContainer: t.textPrimary,
      outline: t.border,
      shadow: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
      primaryColor: t.primary,
      fontFamily: fontFamily,
      extensions: <ThemeExtension<dynamic>>[t],

      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        iconTheme: IconThemeData(color: appBarFg),
        titleTextStyle: TextStyle(
          color: appBarFg,
          fontSize: 19,
          fontWeight:
          preset == UaiThemePreset.verdeNeon ? FontWeight.w500 : FontWeight.w900,
          fontFamily: fontFamily,
          letterSpacing: preset == UaiThemePreset.verdeNeon ? 0.8 : 0,
        ),
      ),

      cardTheme: CardThemeData(
        color: t.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.cardRadius),
          side: BorderSide(color: t.border),
        ),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: _readableTextOn(t.primary),
          disabledBackgroundColor: t.cardAlt,
          disabledForegroundColor: t.textMuted,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: TextStyle(
            fontWeight:
            preset == UaiThemePreset.verdeNeon ? FontWeight.w600 : FontWeight.w900,
            letterSpacing: preset == UaiThemePreset.verdeNeon ? 0.6 : 0.2,
            fontFamily: fontFamily,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.primary,
          side: BorderSide(color: t.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: fontFamily,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: fontFamily,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.card,
        hintStyle: TextStyle(color: t.textMuted, fontFamily: fontFamily),
        labelStyle: TextStyle(color: t.textSecondary, fontFamily: fontFamily),
        helperStyle: TextStyle(color: t.textMuted, fontFamily: fontFamily),
        errorStyle: TextStyle(color: t.error, fontFamily: fontFamily),
        prefixIconColor: t.textMuted,
        suffixIconColor: t.textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.error, width: 1.5),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: t.card,
        selectedColor: t.primary,
        disabledColor: t.cardAlt,
        labelStyle: TextStyle(
          color: t.textSecondary,
          fontWeight: FontWeight.w700,
          fontFamily: fontFamily,
        ),
        secondaryLabelStyle: TextStyle(
          color: _readableTextOn(t.primary),
          fontWeight: FontWeight.w800,
          fontFamily: fontFamily,
        ),
        side: BorderSide(color: t.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: t.surface,
        selectedItemColor: t.primary,
        unselectedItemColor: t.textMuted,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontFamily: fontFamily,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: fontFamily,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.cardRadius),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? t.cardAlt : t.textPrimary,
        contentTextStyle: TextStyle(
          color: isDark ? t.textPrimary : Colors.white,
          fontWeight: FontWeight.w700,
          fontFamily: fontFamily,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w900,
          fontFamily: fontFamily,
        ),
        headlineMedium: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w900,
          fontFamily: fontFamily,
        ),
        headlineSmall: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w900,
          fontFamily: fontFamily,
        ),
        titleLarge: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w900,
          fontFamily: fontFamily,
        ),
        titleMedium: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w800,
          fontFamily: fontFamily,
        ),
        titleSmall: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w800,
          fontFamily: fontFamily,
        ),
        bodyLarge: TextStyle(color: t.textPrimary, fontFamily: fontFamily),
        bodyMedium: TextStyle(color: t.textSecondary, fontFamily: fontFamily),
        bodySmall: TextStyle(color: t.textMuted, fontFamily: fontFamily),
        labelLarge: TextStyle(
          color: t.textPrimary,
          fontWeight: FontWeight.w800,
          fontFamily: fontFamily,
        ),
      ),

      iconTheme: IconThemeData(color: t.textSecondary),
      dividerTheme: DividerThemeData(color: t.border),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary),
    );
  }

  static ThemeData buildLight(UaiThemePreset preset) => build(preset);
  static ThemeData buildDark(UaiThemePreset preset) => build(preset);
}

extension UaiThemeX on BuildContext {
  UaiThemeTokens get uai => UaiThemeTokens.of(this);
}
