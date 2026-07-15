import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_theme_controller.dart';
import 'cloud_global_theme.dart';

class CloudGlobalThemeService {
  CloudGlobalThemeService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final CloudGlobalThemeService instance = CloudGlobalThemeService();

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('temas_globais');

  Query<Map<String, dynamic>> get _availableForUsersQuery =>
      _collection.where('ativo', isEqualTo: true).limit(80);

  Stream<List<CloudGlobalTheme>> streamAvailableForUsers() {
    return _availableForUsersQuery.snapshots().map(
      _availableThemesFromSnapshot,
    );
  }

  Future<List<CloudGlobalTheme>> listAvailableForUsers() async {
    final snapshot = await _availableForUsersQuery.get();
    return _availableThemesFromSnapshot(snapshot);
  }

  Future<List<CloudGlobalTheme>> listAllForAdmin() async {
    final snapshot = await _collection
        .orderBy('atualizadoEm', descending: true)
        .limit(100)
        .get();
    return _themesFromSnapshot(snapshot);
  }

  Future<String> createGlobalTheme({
    required String nome,
    required UserThemeSettings settings,
    required String criadoPorUid,
    required String criadoPorNome,
    String? descricao,
    bool ativo = true,
    bool disponivelParaUsuarios = false,
    bool disponivelParaEstudos = false,
    Color? success,
    Color? warning,
    Color? error,
    String? themeId,
  }) async {
    final doc = themeId == null || themeId.trim().isEmpty
        ? _collection.doc()
        : _collection.doc(themeId.trim());
    final settingsMap = settings.toMap();

    await doc.set({
      'id': doc.id,
      'nome': _cleanText(nome, 'Tema global'),
      'descricao': _cleanText(descricao, ''),
      'ativo': ativo,
      'disponivelParaUsuarios': disponivelParaUsuarios,
      'disponivelParaEstudos': disponivelParaEstudos,
      'origem': CloudGlobalTheme.origemPadrao,
      'criadoPorUid': criadoPorUid,
      'criadoPorNome': criadoPorNome,
      'criadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
      ...settingsMap,
      if (success != null) 'success': _hex(success),
      if (warning != null) 'warning': _hex(warning),
      if (error != null) 'error': _hex(error),
      'isDark': settings.background.computeLuminance() < 0.35,
      'previewColor': settingsMap['primary'],
      'arquivado': false,
    });

    return doc.id;
  }

  Future<void> updateGlobalTheme(
    String themeId, {
    String? nome,
    String? descricao,
    UserThemeSettings? settings,
    bool? ativo,
    bool? disponivelParaUsuarios,
    bool? disponivelParaEstudos,
    Color? success,
    Color? warning,
    Color? error,
  }) async {
    final data = <String, dynamic>{
      'atualizadoEm': FieldValue.serverTimestamp(),
    };

    if (nome != null) data['nome'] = _cleanText(nome, 'Tema global');
    if (descricao != null) data['descricao'] = _cleanText(descricao, '');
    if (ativo != null) data['ativo'] = ativo;
    if (disponivelParaUsuarios != null) {
      data['disponivelParaUsuarios'] = disponivelParaUsuarios;
    }
    if (disponivelParaEstudos != null) {
      data['disponivelParaEstudos'] = disponivelParaEstudos;
    }
    if (settings != null) {
      final settingsMap = settings.toMap();
      data.addAll(settingsMap);
      data['isDark'] = settings.background.computeLuminance() < 0.35;
      data['previewColor'] = settingsMap['primary'];
    }
    if (success != null) data['success'] = _hex(success);
    if (warning != null) data['warning'] = _hex(warning);
    if (error != null) data['error'] = _hex(error);

    await _collection.doc(themeId).set(data, SetOptions(merge: true));
  }

  Future<void> setActive(String themeId, bool ativo) async {
    await updateGlobalTheme(themeId, ativo: ativo);
  }

  Future<void> archiveGlobalTheme(String themeId) async {
    await _collection.doc(themeId).set({
      'ativo': false,
      'disponivelParaUsuarios': false,
      'disponivelParaEstudos': false,
      'arquivado': true,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteGlobalTheme(String themeId) async {
    await archiveGlobalTheme(themeId);
  }

  UserThemeSettings themeToUserThemeSettings(CloudGlobalTheme theme) {
    return theme.toUserThemeSettings();
  }

  List<CloudGlobalTheme> _availableThemesFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final themes = snapshot.docs
        .map(CloudGlobalTheme.fromDoc)
        .where((theme) => theme.ativo && theme.disponivelParaUsuarios)
        .toList();
    themes.sort((a, b) {
      final aDate = a.atualizadoEm;
      final bDate = b.atualizadoEm;
      if (aDate == null && bDate == null) return a.nome.compareTo(b.nome);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    if (themes.length <= 40) return themes;
    return themes.take(40).toList(growable: false);
  }

  List<CloudGlobalTheme> _themesFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map(CloudGlobalTheme.fromDoc).toList();
  }

  static String _cleanText(String? value, String fallback) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? fallback : clean;
  }

  static String _hex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}
