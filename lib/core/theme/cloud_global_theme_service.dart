import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_theme_controller.dart';
import 'cloud_global_theme.dart';

class CloudGlobalThemeService {
  CloudGlobalThemeService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static final CloudGlobalThemeService instance = CloudGlobalThemeService();

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('temas_globais');

  Query<Map<String, dynamic>> get _availableForUsersQuery => _collection
      .where('ativo', isEqualTo: true)
      .where('disponivelParaUsuarios', isEqualTo: true)
      .orderBy('atualizadoEm', descending: true)
      .limit(40);

  Stream<List<CloudGlobalTheme>> streamAvailableForUsers() {
    return _availableForUsersQuery.snapshots().map(_themesFromSnapshot);
  }

  Future<List<CloudGlobalTheme>> listAvailableForUsers() async {
    final snapshot = await _availableForUsersQuery.get();
    return _themesFromSnapshot(snapshot);
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

  List<CloudGlobalTheme> _themesFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map(CloudGlobalTheme.fromDoc).toList();
  }

  static String _cleanText(String? value, String fallback) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? fallback : clean;
  }
}
