import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme_preset.dart';
import 'app_theme_tokens.dart';

class UserThemeSettings {
  final Color primary;
  final Color background;
  final Color surface;
  final Color card;
  final Color textPrimary;
  final Color? accent;
  final Color? cardAlt;
  final Color? textSecondary;
  final Color? textMuted;
  final Color? border;
  final double cardRadius;
  final double buttonRadius;
  final double inputRadius;
  final String? fontFamily;

  const UserThemeSettings({
    required this.primary,
    required this.background,
    required this.surface,
    required this.card,
    required this.textPrimary,
    this.accent,
    this.cardAlt,
    this.textSecondary,
    this.textMuted,
    this.border,
    this.cardRadius = 20,
    this.buttonRadius = 15,
    this.inputRadius = 15,
    this.fontFamily,
  });

  static const UserThemeSettings defaultDark = UserThemeSettings(
    primary: Color(0xFF6D5DF7),
    background: Color(0xFF101018),
    surface: Color(0xFF171724),
    card: Color(0xFF222238),
    textPrimary: Color(0xFFF8F8FF),
    accent: Color(0xFF00E5FF),
    cardAlt: Color(0xFF2E2E4A),
    textSecondary: Color(0xFFDDE0FF),
    textMuted: Color(0xFFB2B7D8),
    border: Color(0xFF3E4260),
    cardRadius: 20,
    buttonRadius: 15,
    inputRadius: 15,
    fontFamily: null,
  );

  UserThemeSettings copyWith({
    Color? primary,
    Color? background,
    Color? surface,
    Color? card,
    Color? textPrimary,
    Color? accent,
    Color? cardAlt,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    double? cardRadius,
    double? buttonRadius,
    double? inputRadius,
    String? fontFamily,
    bool clearFontFamily = false,
  }) {
    return UserThemeSettings(
      primary: primary ?? this.primary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      textPrimary: textPrimary ?? this.textPrimary,
      accent: accent ?? this.accent,
      cardAlt: cardAlt ?? this.cardAlt,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      cardRadius: cardRadius ?? this.cardRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      inputRadius: inputRadius ?? this.inputRadius,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
    );
  }

  UaiThemeTokens toTokens() {
    return UaiThemeTokens.custom(
      primary: primary,
      background: background,
      surface: surface,
      card: card,
      textPrimary: textPrimary,
      accent: accent,
      cardAlt: cardAlt,
      textSecondary: textSecondary,
      textMuted: textMuted,
      border: border,
      cardRadius: cardRadius,
      buttonRadius: buttonRadius,
      inputRadius: inputRadius,
      fontFamily: fontFamily,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'primary': _hex(primary),
      'background': _hex(background),
      'surface': _hex(surface),
      'card': _hex(card),
      'textPrimary': _hex(textPrimary),
      'accent': accent == null ? null : _hex(accent!),
      'cardAlt': cardAlt == null ? null : _hex(cardAlt!),
      'textSecondary': textSecondary == null ? null : _hex(textSecondary!),
      'textMuted': textMuted == null ? null : _hex(textMuted!),
      'border': border == null ? null : _hex(border!),
      'cardRadius': cardRadius,
      'buttonRadius': buttonRadius,
      'inputRadius': inputRadius,
      'fontFamily': fontFamily,
    };
  }

  factory UserThemeSettings.fromMap(Map<String, dynamic> map) {
    return UserThemeSettings(
      primary: _colorFromAny(map['primary']) ?? defaultDark.primary,
      background: _colorFromAny(map['background']) ?? defaultDark.background,
      surface: _colorFromAny(map['surface']) ?? defaultDark.surface,
      card: _colorFromAny(map['card']) ?? defaultDark.card,
      textPrimary: _colorFromAny(map['textPrimary']) ?? defaultDark.textPrimary,
      accent: _colorFromAny(map['accent']),
      cardAlt: _colorFromAny(map['cardAlt']),
      textSecondary: _colorFromAny(map['textSecondary']),
      textMuted: _colorFromAny(map['textMuted']),
      border: _colorFromAny(map['border']),
      cardRadius: _doubleFromAny(map['cardRadius'], defaultDark.cardRadius),
      buttonRadius: _doubleFromAny(map['buttonRadius'], defaultDark.buttonRadius),
      inputRadius: _doubleFromAny(map['inputRadius'], defaultDark.inputRadius),
      fontFamily: _normalizeFontFamily(map['fontFamily']?.toString()),
    );
  }

  static String _hex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  static Color? _colorFromAny(dynamic raw) {
    if (raw == null) return null;

    if (raw is int) return Color(raw);

    var value = raw.toString().trim();
    if (value.isEmpty || value == 'null') return null;

    value = value.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return null;

    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;

    return Color(parsed);
  }

  static double _doubleFromAny(dynamic raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static String? _normalizeFontFamily(String? value) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty || clean == 'default' || clean == 'null') {
      return null;
    }

    return clean;
  }
}

class SavedUserTheme {
  final String id;
  final String name;
  final UserThemeSettings settings;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SavedUserTheme({
    required this.id,
    required this.name,
    required this.settings,
    this.createdAt,
    this.updatedAt,
  });

  factory SavedUserTheme.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return SavedUserTheme(
      id: doc.id,
      name: data['nome']?.toString().trim().isNotEmpty == true
          ? data['nome'].toString().trim()
          : 'Tema sem nome',
      settings: UserThemeSettings.fromMap(data),
      createdAt: _dateFromAny(data['criadoEm']),
      updatedAt: _dateFromAny(data['atualizadoEm']),
    );
  }

  static DateTime? _dateFromAny(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  static const String _presetKey = 'uai_theme_preset';
  static const String _modeKey = 'uai_theme_mode';
  static const String _activeSavedThemeIdKey = 'uai_active_saved_theme_id';

  static const String _customPrimaryKey = 'uai_custom_primary';
  static const String _customBackgroundKey = 'uai_custom_background';
  static const String _customSurfaceKey = 'uai_custom_surface';
  static const String _customCardKey = 'uai_custom_card';
  static const String _customTextPrimaryKey = 'uai_custom_text_primary';
  static const String _customAccentKey = 'uai_custom_accent';
  static const String _customCardAltKey = 'uai_custom_card_alt';
  static const String _customTextSecondaryKey = 'uai_custom_text_secondary';
  static const String _customTextMutedKey = 'uai_custom_text_muted';
  static const String _customBorderKey = 'uai_custom_border';
  static const String _customCardRadiusKey = 'uai_custom_card_radius';
  static const String _customButtonRadiusKey = 'uai_custom_button_radius';
  static const String _customInputRadiusKey = 'uai_custom_input_radius';
  static const String _customFontFamilyKey = 'uai_custom_font_family';

  UaiThemePreset _preset = UaiThemePreset.uaiClassico;
  ThemeMode _themeMode = ThemeMode.light;
  UserThemeSettings _userTheme = UserThemeSettings.defaultDark;
  String? _activeSavedThemeId;
  bool _initialized = false;

  UaiThemePreset get currentPreset => _preset;
  ThemeMode get themeMode => _themeMode;
  UserThemeSettings get userTheme => _userTheme;
  UaiThemeTokens get userThemeTokens => _userTheme.toTokens();
  String? get activeSavedThemeId => _activeSavedThemeId;
  bool get initialized => _initialized;

  CollectionReference<Map<String, dynamic>>? get _themesCollection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('temas_personalizados');
  }

  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();

    _preset = UaiThemePresetX.fromId(prefs.getString(_presetKey));
    _themeMode = _themeModeFromString(prefs.getString(_modeKey)) ?? ThemeMode.light;
    _userTheme = _readUserTheme(prefs);
    _activeSavedThemeId = prefs.getString(_activeSavedThemeIdKey);

    // Quando o tema ativo é um tema salvo na nuvem, a fonte correta é o Firebase.
    // Antes, o app primeiro lia o cache local e só depois tentava buscar a nuvem.
    // Se o FirebaseAuth ainda não estivesse pronto, ele ficava preso no cache antigo.
    if (_preset == UaiThemePreset.usuarioPersonalizado &&
        _activeSavedThemeId != null &&
        _activeSavedThemeId!.isNotEmpty) {
      await _waitForAuthUserIfNeeded();
      await tryLoadActiveSavedThemeFromFirebase(notify: false);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _waitForAuthUserIfNeeded() async {
    if (FirebaseAuth.instance.currentUser != null) return;

    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Se não conseguir autenticar nesse momento, mantém o cache local.
      // Quando o usuário selecionar o tema salvo novamente, ele baixa da nuvem.
    }
  }

  Future<void> setPreset(UaiThemePreset preset) async {
    if (_preset == preset) return;

    _preset = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, preset.id);

    if (preset != UaiThemePreset.usuarioPersonalizado) {
      _activeSavedThemeId = null;
      await prefs.remove(_activeSavedThemeIdKey);
    }

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, _themeModeToString(mode));
    notifyListeners();
  }

  Future<void> apply({
    UaiThemePreset? preset,
    ThemeMode? mode,
  }) async {
    var changed = false;
    final prefs = await SharedPreferences.getInstance();

    if (preset != null && preset != _preset) {
      _preset = preset;
      await prefs.setString(_presetKey, preset.id);

      if (preset != UaiThemePreset.usuarioPersonalizado) {
        _activeSavedThemeId = null;
        await prefs.remove(_activeSavedThemeIdKey);
      }

      changed = true;
    }

    if (mode != null && mode != _themeMode) {
      _themeMode = mode;
      await prefs.setString(_modeKey, _themeModeToString(mode));
      changed = true;
    }

    if (changed) notifyListeners();
  }

  Future<void> applyUserTheme(UserThemeSettings settings) async {
    _userTheme = _sanitizeUserTheme(settings);
    _activeSavedThemeId = null;

    final prefs = await SharedPreferences.getInstance();
    await _writeUserTheme(prefs, _userTheme);
    await prefs.setString(_presetKey, UaiThemePreset.usuarioPersonalizado.id);
    await prefs.setString(_modeKey, _themeModeToString(ThemeMode.light));
    await prefs.remove(_activeSavedThemeIdKey);

    _preset = UaiThemePreset.usuarioPersonalizado;
    _themeMode = ThemeMode.light;

    notifyListeners();
  }

  Future<void> updateUserThemePreview(UserThemeSettings settings) async {
    _userTheme = _sanitizeUserTheme(settings);
    _preset = UaiThemePreset.usuarioPersonalizado;
    _themeMode = ThemeMode.light;
    notifyListeners();
  }

  Future<void> saveCurrentUserTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await _writeUserTheme(prefs, _userTheme);
    await prefs.setString(_presetKey, UaiThemePreset.usuarioPersonalizado.id);
    await prefs.setString(_modeKey, _themeModeToString(ThemeMode.light));
    notifyListeners();
  }

  Future<String> saveUserThemeToFirebase({
    required String name,
    required UserThemeSettings settings,
    String? themeId,
    bool activateAfterSave = true,
  }) async {
    final collection = _themesCollection;
    if (collection == null) {
      throw Exception('Você precisa estar logado para salvar temas na nuvem.');
    }

    final sanitized = _sanitizeUserTheme(settings);
    final cleanName = name.trim().isEmpty ? 'Tema personalizado' : name.trim();

    final data = <String, dynamic>{
      'nome': cleanName,
      'schemaVersion': 2,
      ...sanitized.toMap(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    };

    final String id;
    if (themeId != null && themeId.isNotEmpty) {
      id = themeId;
      await collection.doc(id).set(data, SetOptions(merge: true));
    } else {
      final doc = collection.doc();
      id = doc.id;
      await doc.set({
        ...data,
        'criadoEm': FieldValue.serverTimestamp(),
      });
    }

    if (activateAfterSave) {
      await applySavedUserTheme(
        SavedUserTheme(
          id: id,
          name: cleanName,
          settings: sanitized,
          updatedAt: DateTime.now(),
        ),
      );
    }

    return id;
  }

  Future<List<SavedUserTheme>> loadSavedUserThemes() async {
    final collection = _themesCollection;
    if (collection == null) return [];

    final snapshot = await collection
        .orderBy('atualizadoEm', descending: true)
        .limit(40)
        .get();

    return snapshot.docs.map(SavedUserTheme.fromDoc).toList();
  }

  Future<void> applySavedUserTheme(SavedUserTheme savedTheme) async {
    _userTheme = _sanitizeUserTheme(savedTheme.settings);
    _preset = UaiThemePreset.usuarioPersonalizado;
    _themeMode = ThemeMode.light;
    _activeSavedThemeId = savedTheme.id;

    final prefs = await SharedPreferences.getInstance();
    await _writeUserTheme(prefs, _userTheme);
    await prefs.setString(_presetKey, UaiThemePreset.usuarioPersonalizado.id);
    await prefs.setString(_modeKey, _themeModeToString(ThemeMode.light));
    await prefs.setString(_activeSavedThemeIdKey, savedTheme.id);

    notifyListeners();
  }

  Future<void> deleteSavedUserTheme(String themeId) async {
    final collection = _themesCollection;
    if (collection == null) {
      throw Exception('Você precisa estar logado para excluir temas da nuvem.');
    }

    await collection.doc(themeId).delete();

    if (_activeSavedThemeId == themeId) {
      _activeSavedThemeId = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeSavedThemeIdKey);
      notifyListeners();
    }
  }

  Future<bool> tryLoadActiveSavedThemeFromFirebase({bool notify = false}) async {
    final activeId = _activeSavedThemeId;
    final collection = _themesCollection;

    if (activeId == null || activeId.isEmpty || collection == null) {
      return false;
    }

    try {
      final doc = await collection.doc(activeId).get();
      if (!doc.exists) return false;

      final savedTheme = SavedUserTheme.fromDoc(doc);
      _userTheme = _sanitizeUserTheme(savedTheme.settings);

      final prefs = await SharedPreferences.getInstance();
      await _writeUserTheme(prefs, _userTheme);

      if (notify) notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> resetUserTheme() async {
    await applyUserTheme(UserThemeSettings.defaultDark);
  }

  Future<void> reset() async {
    _preset = UaiThemePreset.uaiClassico;
    _themeMode = ThemeMode.light;
    _activeSavedThemeId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, _preset.id);
    await prefs.setString(_modeKey, _themeModeToString(_themeMode));
    await prefs.remove(_activeSavedThemeIdKey);

    notifyListeners();
  }

  UserThemeSettings _readUserTheme(SharedPreferences prefs) {
    return UserThemeSettings(
      primary: _readColor(prefs, _customPrimaryKey, UserThemeSettings.defaultDark.primary),
      background: _readColor(prefs, _customBackgroundKey, UserThemeSettings.defaultDark.background),
      surface: _readColor(prefs, _customSurfaceKey, UserThemeSettings.defaultDark.surface),
      card: _readColor(prefs, _customCardKey, UserThemeSettings.defaultDark.card),
      textPrimary: _readColor(prefs, _customTextPrimaryKey, UserThemeSettings.defaultDark.textPrimary),
      accent: _readNullableColor(prefs, _customAccentKey),
      cardAlt: _readNullableColor(prefs, _customCardAltKey),
      textSecondary: _readNullableColor(prefs, _customTextSecondaryKey),
      textMuted: _readNullableColor(prefs, _customTextMutedKey),
      border: _readNullableColor(prefs, _customBorderKey),
      cardRadius: prefs.getDouble(_customCardRadiusKey) ?? UserThemeSettings.defaultDark.cardRadius,
      buttonRadius: prefs.getDouble(_customButtonRadiusKey) ?? UserThemeSettings.defaultDark.buttonRadius,
      inputRadius: prefs.getDouble(_customInputRadiusKey) ?? UserThemeSettings.defaultDark.inputRadius,
      fontFamily: _normalizeFontFamily(prefs.getString(_customFontFamilyKey)),
    );
  }

  Future<void> _writeUserTheme(
      SharedPreferences prefs,
      UserThemeSettings settings,
      ) async {
    await prefs.setInt(_customPrimaryKey, settings.primary.value);
    await prefs.setInt(_customBackgroundKey, settings.background.value);
    await prefs.setInt(_customSurfaceKey, settings.surface.value);
    await prefs.setInt(_customCardKey, settings.card.value);
    await prefs.setInt(_customTextPrimaryKey, settings.textPrimary.value);

    await _writeNullableColor(prefs, _customAccentKey, settings.accent);
    await _writeNullableColor(prefs, _customCardAltKey, settings.cardAlt);
    await _writeNullableColor(prefs, _customTextSecondaryKey, settings.textSecondary);
    await _writeNullableColor(prefs, _customTextMutedKey, settings.textMuted);
    await _writeNullableColor(prefs, _customBorderKey, settings.border);

    await prefs.setDouble(_customCardRadiusKey, settings.cardRadius);
    await prefs.setDouble(_customButtonRadiusKey, settings.buttonRadius);
    await prefs.setDouble(_customInputRadiusKey, settings.inputRadius);

    final fontFamily = _normalizeFontFamily(settings.fontFamily);
    if (fontFamily == null) {
      await prefs.remove(_customFontFamilyKey);
    } else {
      await prefs.setString(_customFontFamilyKey, fontFamily);
    }
  }

  UserThemeSettings _sanitizeUserTheme(UserThemeSettings settings) {
    final bgIsDark = settings.background.computeLuminance() < 0.45;
    final fixedTextPrimary =
    _hasGoodContrast(settings.textPrimary, settings.card)
        ? settings.textPrimary
        : (bgIsDark ? const Color(0xFFF8F8F2) : const Color(0xFF111827));

    final fixedSurface = _avoidSameColor(settings.surface, settings.background, bgIsDark);
    final fixedCard = _avoidSameColor(settings.card, fixedSurface, bgIsDark);

    return settings.copyWith(
      surface: fixedSurface,
      card: fixedCard,
      textPrimary: fixedTextPrimary,
      cardRadius: settings.cardRadius.clamp(8.0, 32.0),
      buttonRadius: settings.buttonRadius.clamp(8.0, 28.0),
      inputRadius: settings.inputRadius.clamp(8.0, 28.0),
      fontFamily: _normalizeFontFamily(settings.fontFamily),
      clearFontFamily: _normalizeFontFamily(settings.fontFamily) == null,
    );
  }

  bool _hasGoodContrast(Color text, Color background) {
    final diff = (text.computeLuminance() - background.computeLuminance()).abs();
    return diff >= 0.34;
  }

  Color _avoidSameColor(Color color, Color reference, bool dark) {
    final diff = (color.computeLuminance() - reference.computeLuminance()).abs();
    if (diff >= 0.03) return color;

    final hsl = HSLColor.fromColor(color);
    final lightness = dark
        ? (hsl.lightness + 0.06).clamp(0.0, 1.0)
        : (hsl.lightness - 0.05).clamp(0.0, 1.0);

    return hsl.withLightness(lightness).toColor();
  }

  static Color _readColor(
      SharedPreferences prefs,
      String key,
      Color fallback,
      ) {
    final value = prefs.getInt(key);
    if (value == null) return fallback;
    return Color(value);
  }

  static Color? _readNullableColor(SharedPreferences prefs, String key) {
    final value = prefs.getInt(key);
    if (value == null) return null;
    return Color(value);
  }

  static Future<void> _writeNullableColor(
      SharedPreferences prefs,
      String key,
      Color? color,
      ) async {
    if (color == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, color.value);
    }
  }

  static String? _normalizeFontFamily(String? value) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty || clean == 'default') return null;
    return clean;
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  static ThemeMode? _themeModeFromString(String? value) {
    switch (value) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }
}
