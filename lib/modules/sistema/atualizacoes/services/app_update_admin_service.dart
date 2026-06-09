// lib/modules/sistema/atualizacoes/services/app_update_admin_service.dart
//
// =====================================================
// 🧪 LABORATÓRIO DE ATUALIZAÇÕES - SERVICE ADMIN
// =====================================================
//
// Responsável por:
// - Listar histórico de versões.
// - Criar/atualizar rascunhos de versões.
// - Fazer upload do APK para Firebase Storage.
// - Publicar versão.
// - Atualizar configuracoes/app automaticamente.
// - Manter compatibilidade com o fluxo antigo:
//
// configuracoes/app
//   versao_atual: "2.0.61"
//
// Coleção nova:
//
// versoes_app/{versionId}
//
// Caminho do APK:
//
// apks/uai_capoeira_2.0.61.apk
//
// =====================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class AppUpdateAdminService {
  AppUpdateAdminService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  static const String versoesCollection = 'versoes_app';
  static const String configCollection = 'configuracoes';
  static const String configAppDoc = 'app';
  static const String apksFolder = 'apks';

  CollectionReference<Map<String, dynamic>> get _versoesRef {
    return _firestore.collection(versoesCollection);
  }

  DocumentReference<Map<String, dynamic>> get _configAppRef {
    return _firestore.collection(configCollection).doc(configAppDoc);
  }

  // =====================================================
  // 👤 USUÁRIO ATUAL
  // =====================================================

  User? get usuarioAtual => _auth.currentUser;

  Future<String> getNomeUsuarioAtual() async {
    final user = usuarioAtual;

    if (user == null) return 'Usuário não identificado';

    try {
      final doc = await _firestore.collection('usuarios').doc(user.uid).get();

      final data = doc.data();

      final nome = data?['nome_completo']?.toString().trim();

      if (nome != null && nome.isNotEmpty) return nome;

      return user.displayName ?? user.email ?? user.uid;
    } catch (_) {
      return user.displayName ?? user.email ?? user.uid;
    }
  }

  Future<({String uid, String nome})> _usuarioObrigatorio() async {
    final user = usuarioAtual;

    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    final nome = await getNomeUsuarioAtual();

    return (uid: user.uid, nome: nome);
  }

  // =====================================================
  // 📡 STREAMS E CONSULTAS
  // =====================================================

  Stream<List<AppVersionModel>> watchVersoes({
    int limit = 50,
  }) {
    return _versoesRef
        .orderBy('criadoEm', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(AppVersionModel.fromFirestore).toList();
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchConfigApp() {
    return _configAppRef.snapshots();
  }

  Future<Map<String, dynamic>> getConfigApp() async {
    final doc = await _configAppRef.get(const GetOptions(source: Source.server));

    return doc.data() ?? {};
  }

  Future<AppVersionModel?> getVersaoPorId(String versionId) async {
    if (versionId.trim().isEmpty) return null;

    final doc = await _versoesRef.doc(versionId).get();

    if (!doc.exists) return null;

    return AppVersionModel.fromFirestore(doc);
  }

  Future<AppVersionModel?> getUltimaVersaoPublicada() async {
    final snapshot = await _versoesRef
        .where('publicada', isEqualTo: true)
        .orderBy('publicadoEm', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    return AppVersionModel.fromFirestore(snapshot.docs.first);
  }

  Future<bool> versaoExiste(String versao) async {
    final versionId = AppVersionModel.gerarVersionId(versao);

    if (versionId.isEmpty) return false;

    final doc = await _versoesRef.doc(versionId).get();

    return doc.exists;
  }

  // =====================================================
  // 📝 CRIAR / ATUALIZAR RASCUNHO
  // =====================================================

  Future<AppVersionModel> salvarRascunho({
    required String versao,
    required int build,
    required String titulo,
    required String resumo,
    required bool obrigatoria,
    required List<String> melhorias,
    required List<String> correcoes,
    required List<String> implementacoes,
    required List<String> removidos,
    required String observacoes,
    String canal = 'producao',
  }) async {
    final usuario = await _usuarioObrigatorio();

    final versaoLimpa = versao.trim();

    if (!AppVersionModel.versaoValida(versaoLimpa)) {
      throw Exception('Versão inválida. Use o formato 2.0.61.');
    }

    final versionId = AppVersionModel.gerarVersionId(versaoLimpa);
    final nomeArquivo = AppVersionModel.gerarNomeArquivo(versaoLimpa);
    final storagePath = AppVersionModel.gerarStoragePath(versaoLimpa);

    final docRef = _versoesRef.doc(versionId);
    final doc = await docRef.get();

    final antigo = doc.exists ? AppVersionModel.fromFirestore(doc) : null;

    final model = AppVersionModel(
      versionId: versionId,
      versao: versaoLimpa,
      build: build,
      nomeArquivo: antigo?.nomeArquivo.isNotEmpty == true
          ? antigo!.nomeArquivo
          : nomeArquivo,
      storagePath: antigo?.storagePath.isNotEmpty == true
          ? antigo!.storagePath
          : storagePath,
      downloadUrl: antigo?.downloadUrl ?? '',
      tamanhoBytes: antigo?.tamanhoBytes ?? 0,
      obrigatoria: obrigatoria,
      publicada: antigo?.publicada ?? false,
      canal: canal.trim().isEmpty ? 'producao' : canal.trim(),
      titulo: titulo.trim().isEmpty
          ? 'Versão $versaoLimpa disponível'
          : titulo.trim(),
      resumo: resumo.trim(),
      melhorias: _limparLista(melhorias),
      correcoes: _limparLista(correcoes),
      implementacoes: _limparLista(implementacoes),
      removidos: _limparLista(removidos),
      observacoes: observacoes.trim(),
      criadoEm: antigo?.criadoEm,
      publicadoEm: antigo?.publicadoEm,
      atualizadoEm: DateTime.now(),
      criadoPor: antigo?.criadoPor.isNotEmpty == true
          ? antigo!.criadoPor
          : usuario.uid,
      criadoPorNome: antigo?.criadoPorNome.isNotEmpty == true
          ? antigo!.criadoPorNome
          : usuario.nome,
    );

    final payload = model.toMap();

    payload['atualizadoEm'] = FieldValue.serverTimestamp();

    if (!doc.exists) {
      payload['criadoEm'] = FieldValue.serverTimestamp();
      payload['criadoPor'] = usuario.uid;
      payload['criadoPorNome'] = usuario.nome;
    }

    await docRef.set(payload, SetOptions(merge: true));

    final salvo = await docRef.get();

    return AppVersionModel.fromFirestore(salvo);
  }

  // =====================================================
  // 📦 UPLOAD DO APK
  // =====================================================

  Future<AppVersionModel> uploadApkBytes({
    required String versao,
    required Uint8List bytes,
    required void Function(double progress) onProgress,
  }) async {
    final usuario = await _usuarioObrigatorio();

    final versaoLimpa = versao.trim();

    if (!AppVersionModel.versaoValida(versaoLimpa)) {
      throw Exception('Versão inválida. Use o formato 2.0.61.');
    }

    if (bytes.isEmpty) {
      throw Exception('Arquivo APK vazio ou inválido.');
    }

    if (bytes.length < 1024 * 1024) {
      throw Exception('Arquivo muito pequeno para ser um APK válido.');
    }

    final versionId = AppVersionModel.gerarVersionId(versaoLimpa);
    final nomeArquivo = AppVersionModel.gerarNomeArquivo(versaoLimpa);
    final storagePath = AppVersionModel.gerarStoragePath(versaoLimpa);

    final ref = _storage.ref().child(storagePath);

    final metadata = SettableMetadata(
      contentType: 'application/vnd.android.package-archive',
      customMetadata: {
        'versao': versaoLimpa,
        'nomeArquivo': nomeArquivo,
        'enviadoPor': usuario.uid,
        'enviadoPorNome': usuario.nome,
      },
    );

    final uploadTask = ref.putData(bytes, metadata);

    final completer = Completer<void>();

    late final StreamSubscription<TaskSnapshot> sub;

    sub = uploadTask.snapshotEvents.listen(
          (snapshot) {
        final total = snapshot.totalBytes;

        if (total > 0) {
          final progress = snapshot.bytesTransferred / total;
          onProgress(progress.clamp(0.0, 1.0));
        }

        if (snapshot.state == TaskState.success) {
          if (!completer.isCompleted) completer.complete();
        }

        if (snapshot.state == TaskState.error) {
          if (!completer.isCompleted) {
            completer.completeError(Exception('Erro ao enviar APK.'));
          }
        }
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    try {
      await uploadTask;
      await completer.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          throw TimeoutException('Tempo limite excedido ao enviar APK.');
        },
      );
    } finally {
      await sub.cancel();
    }

    final downloadUrl = await ref.getDownloadURL();
    final storageMetadata = await ref.getMetadata();

    final docRef = _versoesRef.doc(versionId);
    final doc = await docRef.get();

    final antigo = doc.exists
        ? AppVersionModel.fromFirestore(doc)
        : AppVersionModel.empty(versao: versaoLimpa);

    final model = antigo.copyWith(
      versionId: versionId,
      versao: versaoLimpa,
      nomeArquivo: nomeArquivo,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      tamanhoBytes: storageMetadata.size ?? bytes.length,
      atualizadoEm: DateTime.now(),
    );

    final payload = model.toMap();

    payload['downloadUrl'] = downloadUrl;
    payload['storagePath'] = storagePath;
    payload['nomeArquivo'] = nomeArquivo;
    payload['tamanhoBytes'] = storageMetadata.size ?? bytes.length;
    payload['atualizadoEm'] = FieldValue.serverTimestamp();

    if (!doc.exists) {
      payload['criadoEm'] = FieldValue.serverTimestamp();
      payload['criadoPor'] = usuario.uid;
      payload['criadoPorNome'] = usuario.nome;
    }

    await docRef.set(payload, SetOptions(merge: true));

    final salvo = await docRef.get();

    return AppVersionModel.fromFirestore(salvo);
  }

  // =====================================================
  // 🚀 PUBLICAR VERSÃO
  // =====================================================

  Future<AppVersionModel> publicarVersao({
    required String versionId,
    required bool obrigatoria,
  }) async {
    final usuario = await _usuarioObrigatorio();

    final docRef = _versoesRef.doc(versionId);
    final doc = await docRef.get();

    if (!doc.exists) {
      throw Exception('Versão não encontrada.');
    }

    final model = AppVersionModel.fromFirestore(doc);

    if (model.versao.trim().isEmpty) {
      throw Exception('Versão inválida.');
    }

    if (model.storagePath.trim().isEmpty || model.downloadUrl.trim().isEmpty) {
      throw Exception('Envie o APK antes de publicar a versão.');
    }

    if (model.tamanhoBytes <= 0) {
      throw Exception('Tamanho do APK inválido.');
    }

    final publicada = model.copyWith(
      obrigatoria: obrigatoria,
      publicada: true,
    );

    final batch = _firestore.batch();

    batch.set(
      docRef,
      {
        'obrigatoria': obrigatoria,
        'publicada': true,
        'publicadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      _configAppRef,
      publicada.toConfigAppMap(
        usuarioId: usuario.uid,
        usuarioNome: usuario.nome,
      ),
      SetOptions(merge: true),
    );

    await batch.commit();

    final salvo = await docRef.get();

    return AppVersionModel.fromFirestore(salvo);
  }

  Future<void> despublicarVersao(String versionId) async {
    await _versoesRef.doc(versionId).set(
      {
        'publicada': false,
        'atualizadoEm': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> excluirVersao({
    required String versionId,
    bool excluirApk = false,
  }) async {
    final doc = await _versoesRef.doc(versionId).get();

    if (!doc.exists) return;

    final model = AppVersionModel.fromFirestore(doc);

    if (excluirApk && model.storagePath.trim().isNotEmpty) {
      try {
        await _storage.ref().child(model.storagePath).delete();
      } catch (_) {
        // Se o arquivo não existir no Storage, só seguimos e removemos o doc.
      }
    }

    await _versoesRef.doc(versionId).delete();
  }

  // =====================================================
  // 🔎 UTILITÁRIOS
  // =====================================================

  Future<bool> apkExisteNoStorage(String versao) async {
    try {
      final path = AppVersionModel.gerarStoragePath(versao);
      await _storage.ref().child(path).getMetadata();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> tamanhoApkNoStorage(String versao) async {
    try {
      final path = AppVersionModel.gerarStoragePath(versao);
      final metadata = await _storage.ref().child(path).getMetadata();
      return metadata.size ?? 0;
    } catch (_) {
      return 0;
    }
  }

  String proximaVersaoPatch(String versaoAtual) {
    try {
      final parts = versaoAtual.split('.').map(int.parse).toList();

      if (parts.length < 3) return versaoAtual;

      parts[2] = parts[2] + 1;

      return '${parts[0]}.${parts[1]}.${parts[2]}';
    } catch (_) {
      return versaoAtual;
    }
  }

  List<String> _limparLista(List<String> values) {
    return values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
