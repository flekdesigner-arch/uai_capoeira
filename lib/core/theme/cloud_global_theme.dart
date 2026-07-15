import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_theme_controller.dart';
import 'app_theme_tokens.dart';

class CloudGlobalTheme {
  static const String origemPadrao = 'global_nuvem';

  final String id;
  final String nome;
  final String descricao;
  final bool ativo;
  final bool disponivelParaUsuarios;
  final bool disponivelParaEstudos;
  final String origem;
  final String? criadoPorUid;
  final String? criadoPorNome;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final Color primary;
  final Color? accent;
  final Color background;
  final Color surface;
  final Color card;
  final Color? cardAlt;
  final Color textPrimary;
  final Color? textSecondary;
  final Color? textMuted;
  final Color? border;
  final Color? success;
  final Color? warning;
  final Color? error;
  final bool isDark;
  final Color previewColor;

  const CloudGlobalTheme({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.ativo,
    required this.disponivelParaUsuarios,
    required this.disponivelParaEstudos,
    required this.origem,
    required this.criadoPorUid,
    required this.criadoPorNome,
    required this.criadoEm,
    required this.atualizadoEm,
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.card,
    required this.cardAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
    required this.isDark,
    required this.previewColor,
  });

  factory CloudGlobalTheme.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return CloudGlobalTheme.fromMap(doc.id, doc.data() ?? const {});
  }

  factory CloudGlobalTheme.fromMap(String id, Map<String, dynamic> map) {
    final fallback = UserThemeSettings.defaultDark;
    final primary = _colorFromAny(map['primary']) ?? fallback.primary;
    final background =
        _colorFromAny(map['background']) ?? fallback.background;

    return CloudGlobalTheme(
      id: id.trim(),
      nome: _stringFromAny(map['nome'], 'Tema global'),
      descricao: _stringFromAny(map['descricao'], ''),
      ativo: map['ativo'] == true,
      disponivelParaUsuarios: map['disponivelParaUsuarios'] == true,
      disponivelParaEstudos: map['disponivelParaEstudos'] == true,
      origem: _normalizeOrigem(map['origem']),
      criadoPorUid: _nullableStringFromAny(map['criadoPorUid']),
      criadoPorNome: _nullableStringFromAny(map['criadoPorNome']),
      criadoEm: _dateFromAny(map['criadoEm']),
      atualizadoEm: _dateFromAny(map['atualizadoEm']),
      primary: primary,
      accent: _colorFromAny(map['accent']),
      background: background,
      surface: _colorFromAny(map['surface']) ?? fallback.surface,
      card: _colorFromAny(map['card']) ?? fallback.card,
      cardAlt: _colorFromAny(map['cardAlt']),
      textPrimary: _colorFromAny(map['textPrimary']) ?? fallback.textPrimary,
      textSecondary: _colorFromAny(map['textSecondary']),
      textMuted: _colorFromAny(map['textMuted']),
      border: _colorFromAny(map['border']),
      success: _colorFromAny(map['success']),
      warning: _colorFromAny(map['warning']),
      error: _colorFromAny(map['error']),
      isDark: map['isDark'] is bool
          ? map['isDark'] == true
          : UaiThemeTokens.isDarkBackground(background),
      previewColor: _colorFromAny(map['previewColor']) ?? primary,
    );
  }

  UserThemeSettings toUserThemeSettings() {
    return UserThemeSettings(
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
    );
  }

  UaiThemeTokens toTokens() {
    return UaiThemeTokens.custom(
      primary: primary,
      accent: accent,
      background: background,
      surface: surface,
      card: card,
      cardAlt: cardAlt,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      border: border,
      success: success,
      warning: warning,
      error: error,
    );
  }

  Map<String, dynamic> toMap({bool includeAuditDates = true}) {
    return {
      'id': id,
      'nome': nome,
      'descricao': descricao,
      'ativo': ativo,
      'disponivelParaUsuarios': disponivelParaUsuarios,
      'disponivelParaEstudos': disponivelParaEstudos,
      'origem': origem,
      if (criadoPorUid != null) 'criadoPorUid': criadoPorUid,
      if (criadoPorNome != null) 'criadoPorNome': criadoPorNome,
      if (includeAuditDates && criadoEm != null) 'criadoEm': criadoEm,
      if (includeAuditDates && atualizadoEm != null)
        'atualizadoEm': atualizadoEm,
      'primary': _hex(primary),
      if (accent != null) 'accent': _hex(accent!),
      'background': _hex(background),
      'surface': _hex(surface),
      'card': _hex(card),
      if (cardAlt != null) 'cardAlt': _hex(cardAlt!),
      'textPrimary': _hex(textPrimary),
      if (textSecondary != null) 'textSecondary': _hex(textSecondary!),
      if (textMuted != null) 'textMuted': _hex(textMuted!),
      if (border != null) 'border': _hex(border!),
      if (success != null) 'success': _hex(success!),
      if (warning != null) 'warning': _hex(warning!),
      if (error != null) 'error': _hex(error!),
      'isDark': isDark,
      'previewColor': _hex(previewColor),
    };
  }

  static String _normalizeOrigem(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == 'nuvem' || value == origemPadrao) return value!;
    return origemPadrao;
  }

  static String _stringFromAny(dynamic raw, String fallback) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  static String? _nullableStringFromAny(dynamic raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static DateTime? _dateFromAny(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
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
    return parsed == null ? null : Color(parsed);
  }

  static String _hex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}
