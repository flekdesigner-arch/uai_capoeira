import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme_controller.dart';
import 'app_theme_preset.dart';
import 'tema_global_config.dart';

class TemaGlobalService extends ChangeNotifier {
  TemaGlobalService._() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!_initialized) return;
      unawaited(refresh(silent: true));
    });
  }

  static final TemaGlobalService instance = TemaGlobalService._();

  static const String _cacheKey = 'uai_tema_global_cache_v1';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  TemaGlobalConfig _config = TemaGlobalConfig.padrao();
  bool _initialized = false;
  bool _loading = false;
  bool _documentExists = false;
  String? _error;
  StreamSubscription<User?>? _authSubscription;

  TemaGlobalConfig get config => _config.sanitized();
  bool get initialized => _initialized;
  bool get loading => _loading;
  bool get documentExists => _documentExists;
  String? get error => _error;

  bool get ativo => config.ativo;
  bool get forcarTemaGlobal => config.forcarTemaGlobal;
  bool get permitirUsuarioEscolher => config.permitirUsuarioEscolher;
  bool get modoCampanha => config.modoCampanha;
  String get campanhaNome => config.campanhaNome;
  String get temaPadraoGlobal => config.temaPadraoGlobal;
  String get fallbackTema => config.fallbackTema;
  List<String> get temasDisponiveisUsuario =>
      List<String>.unmodifiable(config.temasDisponiveisUsuario);

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('configuracoes_sistema').doc('tema_global');

  CollectionReference<Map<String, dynamic>> get _historico =>
      _doc.collection('historico');

  Future<void> initialize({bool fetchRemote = true}) async {
    if (_initialized) return;

    await _carregarCacheLocal();
    _initialized = true;
    notifyListeners();

    if (fetchRemote) {
      unawaited(refresh(silent: true));
    }
  }

  Future<void> _carregarCacheLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.trim().isEmpty) {
        _config = TemaGlobalConfig.padrao();
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _config = TemaGlobalConfig.fromMap(decoded);
      } else {
        _config = TemaGlobalConfig.padrao();
      }
    } catch (_) {
      _config = TemaGlobalConfig.padrao();
    }
  }

  Future<TemaGlobalConfig> refresh({bool silent = false}) async {
    if (!_initialized && !silent) {
      await initialize(fetchRemote: false);
    }

    if (_loading) return config;

    _loading = true;
    _error = null;
    if (!silent) notifyListeners();

    try {
      final doc = await _doc.get();
      if (!doc.exists) {
        _documentExists = false;
        _config = TemaGlobalConfig.padrao();
        await _salvarCacheLocal(_config);
        return config;
      }

      final data = doc.data();
      if (data == null || data.isEmpty) {
        throw StateError('Documento de tema_global vazio ou inválido.');
      }

      _documentExists = true;
      _config = TemaGlobalConfig.fromMap(data);
      await _salvarCacheLocal(_config);
      return config;
    } catch (e) {
      _error = e.toString();
      _documentExists = false;
      _config = TemaGlobalConfig.padrao();
      await _salvarCacheLocal(_config);
      return config;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _salvarCacheLocal(TemaGlobalConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(config.sanitized().toMap()));
    } catch (_) {
      // Cache local é opcional.
    }
  }

  Future<TemaGlobalConfig> criarConfiguracaoPadrao({
    required String uid,
    required String nome,
  }) async {
    final config = TemaGlobalConfig.padrao().copyWith(
      atualizadoEm: DateTime.now(),
      atualizadoPorUid: uid,
      atualizadoPorNome: nome,
    );
    await salvarConfiguracao(
      config,
      uid: uid,
      nome: nome,
      origem: 'criar_padrao',
    );
    return config;
  }

  Future<void> restaurarUaiClassico({
    required String uid,
    required String nome,
  }) async {
    final config = TemaGlobalConfig.padrao().copyWith(
      ativo: true,
      temaPadraoGlobal: 'uai_classico',
      forcarTemaGlobal: false,
      permitirUsuarioEscolher: true,
      temasDisponiveisUsuario: const [
        'uai_classico',
        'dracula_uai',
        'cafe_terra',
        'verde_neon',
      ],
      fallbackTema: 'uai_classico',
      modoCampanha: false,
      campanhaNome: '',
      atualizadoEm: DateTime.now(),
      atualizadoPorUid: uid,
      atualizadoPorNome: nome,
    );
    await salvarConfiguracao(
      config,
      uid: uid,
      nome: nome,
      origem: 'restaurar_uai_classico',
    );
  }

  Future<void> salvarConfiguracao(
    TemaGlobalConfig config, {
    required String uid,
    required String nome,
    String origem = 'central_global_temas',
  }) async {
    final sanitized = config.sanitizedWithAudit(
      atualizadoEm: DateTime.now(),
      atualizadoPorUid: uid,
      atualizadoPorNome: nome,
    );

    await _doc.set({
      ...sanitized.toMap(),
      'atualizado_em': FieldValue.serverTimestamp(),
      'atualizado_por_uid': uid,
      'atualizado_por_nome': nome,
    }, SetOptions(merge: true));

    await _historico.add({
      ...sanitized.toMap(),
      'atualizado_em': FieldValue.serverTimestamp(),
      'atualizado_por_uid': uid,
      'atualizado_por_nome': nome,
      'origem': origem,
      'resumo': 'Configuração global de tema atualizada',
    });

    _documentExists = true;
    _config = sanitized;
    await _salvarCacheLocal(_config);
    _error = null;
    notifyListeners();
  }

  UaiThemePreset resolvePreset({
    required UaiThemePreset selectedPreset,
    required bool hasUserCustomTheme,
  }) {
    final c = config;
    final fallback =
        _resolvePreset(c.fallbackTema) ?? UaiThemePreset.uaiClassico;
    final globalPreset = _resolvePreset(c.temaPadraoGlobal) ?? fallback;

    if (!c.ativo) {
      return _resolveSelectedPreset(
        selectedPreset: selectedPreset,
        allowedPresetIds: c.temasDisponiveisUsuario,
        fallbackPreset: fallback,
        hasUserCustomTheme: hasUserCustomTheme,
      );
    }

    if (c.forcarTemaGlobal) {
      return globalPreset;
    }

    if (!c.permitirUsuarioEscolher) {
      return globalPreset;
    }

    return _resolveSelectedPreset(
      selectedPreset: selectedPreset,
      allowedPresetIds: c.temasDisponiveisUsuario,
      fallbackPreset: globalPreset,
      hasUserCustomTheme: hasUserCustomTheme,
    );
  }

  List<UaiThemePreset> resolvedAllowedPresets({
    bool includeUserPersonalizado = true,
  }) {
    final ids = <String>{...config.temasDisponiveisUsuario, 'uai_classico'};
    final presets = <UaiThemePreset>[];

    for (final preset in UaiThemePresetX.officialPresets) {
      if (!includeUserPersonalizado &&
          preset == UaiThemePreset.usuarioPersonalizado) {
        continue;
      }
      if (ids.contains(preset.id)) {
        presets.add(preset);
      }
    }

    if (!presets.contains(UaiThemePreset.uaiClassico)) {
      presets.insert(0, UaiThemePreset.uaiClassico);
    }

    return presets;
  }

  bool isAllowedForUser(UaiThemePreset preset) {
    return resolvedAllowedPresets().any((item) => item == preset);
  }

  UaiThemePreset? _resolvePreset(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    if (!UaiThemePresetX.isOfficialId(id)) return null;
    return UaiThemePresetX.fromId(id);
  }

  UaiThemePreset _resolveSelectedPreset({
    required UaiThemePreset selectedPreset,
    required List<String> allowedPresetIds,
    required UaiThemePreset fallbackPreset,
    required bool hasUserCustomTheme,
  }) {
    final selectedId = selectedPreset.id;
    final allowed = <String>{...allowedPresetIds, 'uai_classico'};

    if (selectedPreset == UaiThemePreset.usuarioPersonalizado) {
      if (allowed.contains(selectedId) && hasUserCustomTheme) {
        return UaiThemePreset.usuarioPersonalizado;
      }
      return fallbackPreset;
    }

    if (!UaiThemePresetX.isOfficialId(selectedId)) {
      return fallbackPreset;
    }

    if (!allowed.contains(selectedId)) {
      return fallbackPreset;
    }

    return selectedPreset;
  }
}
