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

import 'package:crypto/crypto.dart' as crypto;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class AppUpdateAdminService {
  AppUpdateAdminService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
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

  Stream<List<AppVersionModel>> watchVersoes({int limit = 50}) {
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
    final doc = await _configAppRef.get(
      const GetOptions(source: Source.server),
    );

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

  /// Fonte de verdade para o sequenciamento global de releases.
  ///
  /// Produção, BETA e teste interno compartilham a MESMA sequência de
  /// versão/build. Ex.: produção 146 -> BETA 147 -> produção 148.
  /// Não usamos somente configuracoes/app porque ele aponta apenas para a
  /// produção e faria a Central tentar reutilizar o número de uma BETA.
  Future<List<AppVersionModel>> listarVersoesParaSequenciamento({int limit = 500}) async {
    final snapshot = await _versoesRef.limit(limit).get(
      const GetOptions(source: Source.server),
    );
    return snapshot.docs.map(AppVersionModel.fromFirestore).toList();
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
      androidArtifacts: antigo?.androidArtifacts ?? const {},
      platformArtifacts: antigo?.platformArtifacts ?? const {},
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
      contentDisposition: 'attachment; filename="$nomeArquivo"',
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
  // 📦 UPLOAD ANDROID POR ARQUITETURA (ABI)
  // =====================================================

  Future<AppVersionModel> uploadAndroidArtifactBytes({
    required String versao,
    required String architecture,
    required Uint8List bytes,
    required void Function(double progress) onProgress,
  }) async {
    final usuario = await _usuarioObrigatorio();
    final versaoLimpa = versao.trim();
    final abi = architecture.trim();

    const allowed = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};
    if (!AppVersionModel.versaoValida(versaoLimpa)) {
      throw Exception('Versão inválida. Use o formato 2.0.116.');
    }
    if (!allowed.contains(abi)) {
      throw Exception('Arquitetura Android inválida: $abi');
    }
    if (bytes.length < 1024 * 1024) {
      throw Exception('APK $abi muito pequeno ou inválido.');
    }

    final versionId = AppVersionModel.gerarVersionId(versaoLimpa);
    final nomeArquivo = AppVersionModel.gerarNomeArquivoPorAbi(versaoLimpa, abi);
    final storagePath = AppVersionModel.gerarStoragePathPorAbi(versaoLimpa, abi);
    final ref = _storage.ref().child(storagePath);
    final sha256 = crypto.sha256.convert(bytes).toString();

    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(
        contentType: 'application/vnd.android.package-archive',
        contentDisposition: 'attachment; filename="$nomeArquivo"',
        customMetadata: {
          'versao': versaoLimpa,
          'architecture': abi,
          'platform': 'android',
          'nomeArquivo': nomeArquivo,
          'enviadoPor': usuario.uid,
          'enviadoPorNome': usuario.nome,
          'sha256': sha256,
        },
      ),
    );

    final sub = uploadTask.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress((snapshot.bytesTransferred / snapshot.totalBytes).clamp(0.0, 1.0));
      }
    });
    try {
      await uploadTask.timeout(const Duration(minutes: 10));
    } finally {
      await sub.cancel();
    }

    final url = await ref.getDownloadURL();
    final metadata = await ref.getMetadata();
    final docRef = _versoesRef.doc(versionId);
    final doc = await docRef.get();
    final antigo = doc.exists
        ? AppVersionModel.fromFirestore(doc)
        : AppVersionModel.empty(versao: versaoLimpa);

    final artifacts = Map<String, AppReleaseArtifact>.from(antigo.androidArtifacts);
    artifacts[abi] = AppReleaseArtifact(
      platform: 'android',
      architecture: abi,
      nomeArquivo: nomeArquivo,
      storagePath: storagePath,
      downloadUrl: url,
      tamanhoBytes: metadata.size ?? bytes.length,
      sha256: sha256,
    );

    // ARM64 vira o artefato legado/primário, mantendo compatibilidade com
    // versões antigas do cliente que ainda leem apk_url/apk_path.
    final primary = artifacts['arm64-v8a'] ?? artifacts.values.first;
    final model = antigo.copyWith(
      versionId: versionId,
      versao: versaoLimpa,
      androidArtifacts: artifacts,
      nomeArquivo: primary.nomeArquivo,
      storagePath: primary.storagePath,
      downloadUrl: primary.downloadUrl,
      tamanhoBytes: primary.tamanhoBytes,
      atualizadoEm: DateTime.now(),
    );

    final payload = model.toMap();
    payload['androidArtifacts'] = artifacts.map((key, value) => MapEntry(key, value.toMap()));
    payload['nomeArquivo'] = primary.nomeArquivo;
    payload['storagePath'] = primary.storagePath;
    payload['downloadUrl'] = primary.downloadUrl;
    payload['tamanhoBytes'] = primary.tamanhoBytes;
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
  // 🌐 METADADOS MULTIPLATAFORMA DA RELEASE
  // =====================================================

  Future<AppVersionModel> registrarPlataformasRelease({
    required String versao,
    required bool pwaPublicado,
    required int pwaTamanhoBytes,
    required bool windowsGerado,
    required int windowsTamanhoBytes,
    String windowsInstallDir = '',
    String windowsPackagePath = '',
  }) async {
    final versionId = AppVersionModel.gerarVersionId(versao);
    final ref = _versoesRef.doc(versionId);
    final doc = await ref.get();
    if (!doc.exists) throw Exception('Release $versao não encontrada.');

    final atual = AppVersionModel.fromFirestore(doc);
    final platforms = Map<String, dynamic>.from(atual.platformArtifacts);
    platforms['pwa'] = {
      'platform': 'pwa',
      'publicado': pwaPublicado,
      'hosting': pwaPublicado ? 'firebase_hosting' : '',
      'tamanhoBytes': pwaTamanhoBytes,
      'atualizadoEmIso': DateTime.now().toIso8601String(),
    };
    platforms['windows'] = {
      'platform': 'windows',
      'architecture': 'x64',
      'gerado': windowsGerado,
      'instalado': windowsGerado && windowsInstallDir.trim().isNotEmpty,
      'installDir': windowsInstallDir.trim(),
      'packagePath': windowsPackagePath.trim(),
      'tamanhoBytes': windowsTamanhoBytes,
      'atualizadoEmIso': DateTime.now().toIso8601String(),
    };

    await ref.set({
      'platformArtifacts': platforms,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final salvo = await ref.get();
    return AppVersionModel.fromFirestore(salvo);
  }

  /// Reconsulta o Firebase Storage para que o histórico use o tamanho físico
  /// real de cada APK, em vez de um valor antigo gravado no Firestore.
  Future<AppVersionModel> sincronizarTamanhosStorage(AppVersionModel model) async {
    if (model.androidArtifacts.isEmpty) return model;
    final updated = <String, AppReleaseArtifact>{};
    for (final entry in model.androidArtifacts.entries) {
      final artifact = entry.value;
      var size = artifact.tamanhoBytes;
      try {
        final metadata = await _storage.ref().child(artifact.storagePath).getMetadata();
        size = metadata.size ?? size;
      } catch (_) {}
      updated[entry.key] = AppReleaseArtifact(
        platform: artifact.platform,
        architecture: artifact.architecture,
        nomeArquivo: artifact.nomeArquivo,
        storagePath: artifact.storagePath,
        downloadUrl: artifact.downloadUrl,
        tamanhoBytes: size,
        sha256: artifact.sha256,
      );
    }
    final primary = updated['arm64-v8a'] ?? updated.values.first;
    await _versoesRef.doc(model.versionId).set({
      'androidArtifacts': updated.map((k, v) => MapEntry(k, v.toMap())),
      'tamanhoBytes': primary.tamanhoBytes,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return model.copyWith(androidArtifacts: updated, tamanhoBytes: primary.tamanhoBytes);
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

    if (model.androidArtifacts.isEmpty &&
        (model.storagePath.trim().isEmpty || model.downloadUrl.trim().isEmpty)) {
      throw Exception('Envie ao menos um APK Android antes de publicar a versão.');
    }

    if (model.tamanhoBytes <= 0) {
      throw Exception('Tamanho do APK inválido.');
    }

    if (model.publicada) {
      throw Exception(
        'A versão ${model.versao} já foi publicada no canal ${model.canalLabel}. '
        'Uma release publicada não pode ser reutilizada; gere a próxima versão.',
      );
    }

    // Android usa build como versionCode. Ele precisa crescer globalmente,
    // inclusive entre produção, BETA e teste interno. Também impedimos uma
    // versão semanticamente antiga de ser publicada por engano. Rollback é um
    // fluxo separado e não passa por este método.
    final sequencia = await listarVersoesParaSequenciamento();
    AppVersionModel? maiorPublicada;
    var maiorBuildPublicado = 0;
    for (final release in sequencia) {
      if (!release.publicada || release.versionId == model.versionId) continue;
      if (release.build > maiorBuildPublicado) maiorBuildPublicado = release.build;
      if (maiorPublicada == null ||
          AppVersionModel.compararVersoes(
                maiorPublicada.versao,
                release.versao,
              ) ==
              1) {
        maiorPublicada = release;
      }
    }
    if (model.build <= maiorBuildPublicado) {
      throw Exception(
        'Build ${model.build} não pode ser publicado: o maior versionCode já publicado é '
        '$maiorBuildPublicado. Gere build ${maiorBuildPublicado + 1} ou superior.',
      );
    }
    if (maiorPublicada != null &&
        AppVersionModel.compararVersoes(maiorPublicada.versao, model.versao) != 1) {
      throw Exception(
        'A versão ${model.versao} não é maior que a última release global '
        '${maiorPublicada.versao}. Produção/BETA/Teste compartilham a mesma sequência.',
      );
    }

    final publicada = model.copyWith(obrigatoria: obrigatoria, publicada: true);

    final batch = _firestore.batch();

    batch.set(docRef, {
      'obrigatoria': obrigatoria,
      'publicada': true,
      'publicadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (publicada.isProducao) {
      batch.set(
        _configAppRef,
        publicada.toConfigAppMap(
          usuarioId: usuario.uid,
          usuarioNome: usuario.nome,
        ),
        SetOptions(merge: true),
      );
    } else {
      batch.set(docRef, {
        'betaAtiva': true,
        'canalPublicadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();

    final salvo = await docRef.get();

    return AppVersionModel.fromFirestore(salvo);
  }

  Future<void> despublicarVersao(String versionId) async {
    await _versoesRef.doc(versionId).set({
      'publicada': false,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
  // 🧠 CENTRAL V3 - METADADOS DE RELEASE
  // =====================================================

  Future<AppVersionModel> salvarCompatibilidade({
    required String versao,
    int minAndroidSdk = 23,
    String versaoMinimaOrigem = '',
    List<String> abis = const ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
  }) async {
    final ref = _versoesRef.doc(AppVersionModel.gerarVersionId(versao));
    await ref.set({
      'compatibilidade': {
        'minAndroidSdk': minAndroidSdk,
        'versaoMinimaOrigem': versaoMinimaOrigem.trim(),
        'abis': abis,
        'plataformas': const ['android', 'windows', 'pwa'],
      },
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final doc = await ref.get();
    return AppVersionModel.fromFirestore(doc);
  }

  Future<void> definirProtecaoRelease(String versao, bool protegida) async {
    await _versoesRef.doc(AppVersionModel.gerarVersionId(versao)).set({
      'protegida': protegida,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
