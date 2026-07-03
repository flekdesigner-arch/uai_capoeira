import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_theme_preset.dart';

class TemaGlobalConfig {
  final bool ativo;
  final String temaPadraoGlobal;
  final bool forcarTemaGlobal;
  final bool permitirUsuarioEscolher;
  final List<String> temasDisponiveisUsuario;
  final String fallbackTema;
  final bool modoCampanha;
  final String campanhaNome;
  final DateTime? atualizadoEm;
  final String? atualizadoPorUid;
  final String? atualizadoPorNome;

  const TemaGlobalConfig({
    required this.ativo,
    required this.temaPadraoGlobal,
    required this.forcarTemaGlobal,
    required this.permitirUsuarioEscolher,
    required this.temasDisponiveisUsuario,
    required this.fallbackTema,
    required this.modoCampanha,
    required this.campanhaNome,
    required this.atualizadoEm,
    required this.atualizadoPorUid,
    required this.atualizadoPorNome,
  });

  factory TemaGlobalConfig.padrao() {
    return const TemaGlobalConfig(
      ativo: true,
      temaPadraoGlobal: 'uai_classico',
      forcarTemaGlobal: false,
      permitirUsuarioEscolher: true,
      temasDisponiveisUsuario: [
        'uai_classico',
        'dracula_uai',
        'cafe_terra',
        'verde_neon',
      ],
      fallbackTema: 'uai_classico',
      modoCampanha: false,
      campanhaNome: '',
      atualizadoEm: null,
      atualizadoPorUid: null,
      atualizadoPorNome: null,
    );
  }

  factory TemaGlobalConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return TemaGlobalConfig.padrao();
    }

    return TemaGlobalConfig(
      ativo: map['ativo'] != false,
      temaPadraoGlobal: map['tema_padrao_global']?.toString() ?? 'uai_classico',
      forcarTemaGlobal: map['forcar_tema_global'] == true,
      permitirUsuarioEscolher: map['permitir_usuario_escolher'] != false,
      temasDisponiveisUsuario: _listFromAny(map['temas_disponiveis_usuario']),
      fallbackTema: map['fallback_tema']?.toString() ?? 'uai_classico',
      modoCampanha: map['modo_campanha'] == true,
      campanhaNome: map['campanha_nome']?.toString() ?? '',
      atualizadoEm: _dateFromAny(map['atualizado_em'] ?? map['atualizadoEm']),
      atualizadoPorUid: map['atualizado_por_uid']?.toString(),
      atualizadoPorNome: map['atualizado_por_nome']?.toString(),
    ).sanitized();
  }

  factory TemaGlobalConfig.fromJson(Map<String, dynamic> map) {
    return TemaGlobalConfig.fromMap(map);
  }

  TemaGlobalConfig copyWith({
    bool? ativo,
    String? temaPadraoGlobal,
    bool? forcarTemaGlobal,
    bool? permitirUsuarioEscolher,
    List<String>? temasDisponiveisUsuario,
    String? fallbackTema,
    bool? modoCampanha,
    String? campanhaNome,
    DateTime? atualizadoEm,
    String? atualizadoPorUid,
    String? atualizadoPorNome,
    bool clearAtualizadoEm = false,
    bool clearAtualizadoPorUid = false,
    bool clearAtualizadoPorNome = false,
  }) {
    return TemaGlobalConfig(
      ativo: ativo ?? this.ativo,
      temaPadraoGlobal: temaPadraoGlobal ?? this.temaPadraoGlobal,
      forcarTemaGlobal: forcarTemaGlobal ?? this.forcarTemaGlobal,
      permitirUsuarioEscolher:
          permitirUsuarioEscolher ?? this.permitirUsuarioEscolher,
      temasDisponiveisUsuario:
          temasDisponiveisUsuario ?? this.temasDisponiveisUsuario,
      fallbackTema: fallbackTema ?? this.fallbackTema,
      modoCampanha: modoCampanha ?? this.modoCampanha,
      campanhaNome: campanhaNome ?? this.campanhaNome,
      atualizadoEm: clearAtualizadoEm
          ? null
          : (atualizadoEm ?? this.atualizadoEm),
      atualizadoPorUid: clearAtualizadoPorUid
          ? null
          : (atualizadoPorUid ?? this.atualizadoPorUid),
      atualizadoPorNome: clearAtualizadoPorNome
          ? null
          : (atualizadoPorNome ?? this.atualizadoPorNome),
    );
  }

  TemaGlobalConfig sanitized() {
    final fallback = _sanitizeThemeId(fallbackTema) ?? 'uai_classico';
    final normalizedList = _sanitizeThemeList(temasDisponiveisUsuario);
    final withFallback = normalizedList.contains(fallback)
        ? normalizedList
        : <String>[...normalizedList, fallback];

    final withClassico = withFallback.contains('uai_classico')
        ? withFallback
        : <String>['uai_classico', ...withFallback];

    final unique = <String>[];
    for (final id in withClassico) {
      final clean = _sanitizeThemeId(id);
      if (clean == null || unique.contains(clean)) continue;
      unique.add(clean);
    }

    final normalizedFallback = unique.contains(fallback)
        ? fallback
        : 'uai_classico';
    final normalizedThemePadrao = _themeWithinAllowed(
      temaPadraoGlobal,
      unique,
      normalizedFallback,
    );

    return copyWith(
      ativo: ativo,
      temaPadraoGlobal: normalizedThemePadrao,
      forcarTemaGlobal: forcarTemaGlobal,
      permitirUsuarioEscolher: permitirUsuarioEscolher,
      temasDisponiveisUsuario: unique.isEmpty
          ? TemaGlobalConfig.padrao().temasDisponiveisUsuario
          : unique,
      fallbackTema: normalizedFallback,
      modoCampanha: modoCampanha,
      campanhaNome: campanhaNome.trim(),
      atualizadoEm: atualizadoEm,
      atualizadoPorUid: atualizadoPorUid?.trim().isEmpty == true
          ? null
          : atualizadoPorUid?.trim(),
      atualizadoPorNome: atualizadoPorNome?.trim().isEmpty == true
          ? null
          : atualizadoPorNome?.trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ativo': ativo,
      'tema_padrao_global': temaPadraoGlobal,
      'forcar_tema_global': forcarTemaGlobal,
      'permitir_usuario_escolher': permitirUsuarioEscolher,
      'temas_disponiveis_usuario': temasDisponiveisUsuario,
      'fallback_tema': fallbackTema,
      'modo_campanha': modoCampanha,
      'campanha_nome': campanhaNome,
      if (atualizadoEm != null) 'atualizado_em': atualizadoEm,
      if (atualizadoPorUid != null) 'atualizado_por_uid': atualizadoPorUid,
      if (atualizadoPorNome != null) 'atualizado_por_nome': atualizadoPorNome,
    };
  }

  TemaGlobalConfig sanitizedWithAudit({
    DateTime? atualizadoEm,
    String? atualizadoPorUid,
    String? atualizadoPorNome,
  }) {
    return sanitized().copyWith(
      atualizadoEm: atualizadoEm,
      atualizadoPorUid: atualizadoPorUid,
      atualizadoPorNome: atualizadoPorNome,
    );
  }

  static String? _sanitizeThemeId(String? id) {
    final clean = id?.trim();
    if (clean == null || clean.isEmpty) return null;
    if (!UaiThemePresetX.isOfficialId(clean)) return null;
    return clean;
  }

  static List<String> _sanitizeThemeList(List<String> values) {
    final result = <String>[];
    for (final value in values) {
      final clean = _sanitizeThemeId(value);
      if (clean == null || result.contains(clean)) continue;
      result.add(clean);
    }
    return result;
  }

  static String _themeWithinAllowed(
    String themeId,
    List<String> allowed,
    String fallback,
  ) {
    final clean = _sanitizeThemeId(themeId);
    if (clean == null) return fallback;
    if (allowed.contains(clean)) return clean;
    return fallback;
  }

  static List<String> _listFromAny(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toList(growable: false);
    }
    return <String>[];
  }

  static DateTime? _dateFromAny(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}
