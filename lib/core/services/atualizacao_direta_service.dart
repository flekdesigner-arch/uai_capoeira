// lib/core/services/atualizacao_direta_service.dart
//
// =====================================================
// 📥 SERVIÇO DE ATUALIZAÇÃO DIRETA - UAI CAPOEIRA
// =====================================================
//
// Refatorado para integrar com o Laboratório de Atualizações.
//
// Continua compatível com o fluxo antigo:
//   apks/uai_capoeira_2.0.61.apk
//
// E passa a considerar o novo histórico:
//   versoes_app/{versionId}
//   configuracoes/app
//
// Responsável por:
// - Verificar se existe APK no Firebase Storage.
// - Listar APKs disponíveis.
// - Baixar APK com progresso.
// - Solicitar permissão de instalação.
// - Abrir instalador do Android.
// - Mostrar diálogo de download tematizado com context.uai.
// =====================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/services/app_update_check_service.dart';
import 'package:uai_capoeira/core/services/update_wifi_service.dart';
import 'package:uai_capoeira/core/services/official_apk_website_service.dart';
import 'package:uai_capoeira/core/services/update_storage_service.dart';
import 'package:uai_capoeira/core/services/update_telemetry_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class AtualizacaoDiretaService {
  static bool _downloadManualAtivo = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Connectivity _connectivity = Connectivity();

  static const String _configCollection = 'configuracoes';
  static const String _configAppDoc = 'app';
  static const String _versoesCollection = 'versoes_app';

  // =====================================================
  // 🌐 VERIFICAR CONECTIVIDADE
  // =====================================================
  Future<bool> _verificarInternet() async {
    try {
      final Object result = await _connectivity.checkConnectivity();

      bool hasInternet = false;

      if (result is List<ConnectivityResult>) {
        hasInternet = result.any((item) => item != ConnectivityResult.none);
      } else if (result is ConnectivityResult) {
        hasInternet = result != ConnectivityResult.none;
      }

      if (!hasInternet) {
        debugPrint('❌ Sem conexão com a internet');
      } else {
        debugPrint('✅ Conexão com internet disponível: $result');
      }

      return hasInternet;
    } catch (e) {
      debugPrint('❌ Erro ao verificar conectividade: $e');
      return false;
    }
  }

  // =====================================================
  // 🔎 RESOLVER DADOS DA VERSÃO
  // =====================================================

  Future<AppVersionModel?> _buscarVersaoNoHistorico(String versao) async {
    try {
      final versionId = AppVersionModel.gerarVersionId(versao);

      if (versionId.isEmpty) return null;

      final doc = await _firestore
          .collection(_versoesCollection)
          .doc(versionId)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) return null;

      return AppVersionModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('⚠️ Não foi possível buscar versão no histórico: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _buscarConfigApp() async {
    try {
      final doc = await _firestore
          .collection(_configCollection)
          .doc(_configAppDoc)
          .get(const GetOptions(source: Source.server));

      return doc.data() ?? {};
    } catch (e) {
      debugPrint('⚠️ Não foi possível buscar configuracoes/app: $e');
      return {};
    }
  }

  Future<String> _detectarAbiAndroid() async {
    if (!Platform.isAndroid) return 'arm64-v8a';
    try {
      final info = await _deviceInfo.androidInfo;
      final abis = info.supportedAbis.map((e) => e.toLowerCase()).toList();
      debugPrint('📱 ABIs suportadas pelo aparelho: $abis');
      if (abis.contains('arm64-v8a')) return 'arm64-v8a';
      if (abis.contains('armeabi-v7a')) return 'armeabi-v7a';
      if (abis.contains('x86_64')) return 'x86_64';
    } catch (e) {
      debugPrint('⚠️ Não foi possível detectar ABI: $e');
    }
    return 'arm64-v8a';
  }

  AppReleaseArtifact? _escolherArtifact(
    Map<String, AppReleaseArtifact> artifacts,
    String abi,
  ) {
    if (artifacts.isEmpty) return null;
    return artifacts[abi] ?? artifacts['universal'];
  }

  Map<String, AppReleaseArtifact> _artifactsFromConfig(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, AppReleaseArtifact>{};
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        result[entry.key.toString()] = AppReleaseArtifact.fromMap(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
    return result;
  }

  Future<_ApkInfo> _resolverApkInfo(String versao) async {
    final versaoLimpa = versao.trim();
    if (!AppVersionModel.versaoValida(versaoLimpa)) {
      throw Exception('Versão inválida: $versaoLimpa');
    }

    final abi = await _detectarAbiAndroid();
    final historico = await _buscarVersaoNoHistorico(versaoLimpa);
    if (historico != null) {
      final artifact = _escolherArtifact(historico.androidArtifacts, abi);
      if (artifact != null && artifact.storagePath.trim().isNotEmpty) {
        debugPrint(
          '🎯 APK selecionado automaticamente: $abi -> ${artifact.nomeArquivo}',
        );
        return _ApkInfo(
          versao: versaoLimpa,
          nomeArquivo: artifact.nomeArquivo,
          storagePath: artifact.storagePath,
          downloadUrl: artifact.downloadUrl,
          tamanhoBytes: artifact.tamanhoBytes,
          sha256: artifact.sha256,
        );
      }
      if (historico.androidArtifacts.isNotEmpty) {
        throw StateError('Esta release não possui APK compatível com $abi.');
      }
      // Compatibilidade com releases antigas de APK único.
      if (historico.storagePath.trim().isNotEmpty) {
        return _ApkInfo(
          versao: versaoLimpa,
          nomeArquivo: historico.nomeArquivo.trim().isNotEmpty
              ? historico.nomeArquivo
              : AppVersionModel.gerarNomeArquivo(versaoLimpa),
          storagePath: historico.storagePath,
          downloadUrl: historico.downloadUrl,
          tamanhoBytes: historico.tamanhoBytes,
        );
      }
    }

    final config = await _buscarConfigApp();
    final configVersao = (config['versao_atual'] ?? '').toString().trim();
    if (configVersao == versaoLimpa) {
      final configArtifacts = _artifactsFromConfig(config['android_artifacts']);
      final artifact = _escolherArtifact(configArtifacts, abi);
      if (artifact != null && artifact.storagePath.isNotEmpty) {
        return _ApkInfo(
          versao: versaoLimpa,
          nomeArquivo: artifact.nomeArquivo,
          storagePath: artifact.storagePath,
          downloadUrl: artifact.downloadUrl,
          tamanhoBytes: artifact.tamanhoBytes,
          sha256: artifact.sha256,
        );
      }

      if (configArtifacts.isNotEmpty) {
        throw StateError('Esta release não possui APK compatível com $abi.');
      }
      final configPath = (config['apk_path'] ?? '').toString().trim();
      if (configPath.isNotEmpty) {
        return _ApkInfo(
          versao: versaoLimpa,
          nomeArquivo:
              (config['apk_nome_arquivo'] ??
                      AppVersionModel.gerarNomeArquivo(versaoLimpa))
                  .toString(),
          storagePath: configPath,
          downloadUrl: (config['apk_url'] ?? '').toString(),
          tamanhoBytes: _asInt(config['apk_tamanho_bytes']),
        );
      }
    }

    // Último fallback para uma release nova sem manifesto completo.
    return _ApkInfo(
      versao: versaoLimpa,
      nomeArquivo: AppVersionModel.gerarNomeArquivoPorAbi(versaoLimpa, abi),
      storagePath: AppVersionModel.gerarStoragePathPorAbi(versaoLimpa, abi),
      downloadUrl: '',
      tamanhoBytes: 0,
    );
  }

  /// Artefato verificado antes de agendar download durável do Android.
  /// Releases sem SHA-256/tamanho declarados continuam com o fluxo manual;
  /// não habilitamos download silencioso de pacote sem integridade conhecida.
  Future<WifiApkArtifact?> obterArtefatoVerificadoParaWifi(
    String versao,
  ) async {
    if (!Platform.isAndroid) return null;
    final info = await _resolverApkInfo(versao);
    final hash = info.sha256.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash) ||
        info.tamanhoBytes < 1024 * 1024) {
      return null;
    }
    final reference = _storage.ref().child(info.storagePath);
    final metadata = await reference.getMetadata();
    if (metadata.size != info.tamanhoBytes) return null;
    final url = await reference.getDownloadURL();
    if (url.isEmpty) return null;
    return WifiApkArtifact(url: url, sha256: hash, bytes: info.tamanhoBytes);
  }

  /// Reserva manualmente a rede disponível; só acompanha um worker realmente
  /// ativo no Wi-Fi. O nativo coordena a parada antes de liberar a reserva.
  /// Retorna null quando o instalador do cache já foi aberto.
  Future<String?> _aproveitarAtualizacaoWifi({
    required String versao,
    required String? uid,
    required void Function() verificarSessao,
    required Function(double progress) onProgress,
    required Function(String status) onStatus,
  }) async {
    final wifi = UpdateWifiService.instance;
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    ManualUpdatePreparation? preparation;
    while (DateTime.now().isBefore(deadline)) {
      verificarSessao();
      preparation ??= await wifi.beginManualDownload(versao, expectedUid: uid);
      // O token precisa ser devolvido ao finally mesmo se o cancelamento ocorreu
      // durante a coordenação nativa.
      if (preparation.status == 'manual' && preparation.token.isNotEmpty) {
        return preparation.token;
      }
      verificarSessao();
      if (preparation.status == 'ready') {
        onProgress(1);
        onStatus('🔐 Conferindo versão e APK já baixado...');
        final outcome = await wifi.installReady(
          versao,
          isCancelled: () {
            try {
              verificarSessao();
              return false;
            } catch (_) {
              return true;
            }
          },
        );
        verificarSessao();
        if (outcome == 'installer_opened') {
          onStatus('✅ Instalador do Android iniciado!');
          return null;
        }
        throw StateError(
          'O APK em cache não pôde ser instalado ($outcome). '
          'Confira a conexão, a permissão e a release antes de tentar novamente.',
        );
      }
      if (preparation.status != 'reuse') {
        throw StateError(switch (preparation.status) {
          'busy' => 'Já existe um download manual em andamento.',
          'not_authorized' => 'A conta mudou durante a atualização.',
          'superseded' =>
            'Uma release mais recente substituiu este APK. Reabra a atualização.',
          _ =>
            'Não foi possível confirmar ou coordenar a atualização '
                '(${preparation.status}). Verifique a conexão e tente novamente.',
        });
      }
      final state = await wifi.getState(versao);
      verificarSessao();
      if (state.ready) {
        preparation = const ManualUpdatePreparation('ready', '');
        continue;
      }
      if (!state.reusable) {
        preparation = null;
        continue;
      }
      onStatus(
        state.phase == 'verifying'
            ? '🔐 Validando integridade e assinatura do APK...'
            : '📥 Baixando APK pelo Wi-Fi...',
      );
      if (state.progress >= 0) onProgress(state.progress / 100.0);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException(
      'O Android ainda não concluiu o download. Tente novamente.',
    );
  }

  String _mensagemVerificacaoApk(String resultado) {
    return switch (resultado) {
      'signature_mismatch' =>
        'A assinatura do novo APK é diferente da assinatura '
            'da versão instalada. Gere o release com a mesma chave original.',
      'apk_signature_unreadable' =>
        'O Android não conseguiu ler a assinatura '
            'do APK baixado. Confira o arquivo e a assinatura da compilação.',
      'installed_signature_unreadable' =>
        'O Android não conseguiu confirmar '
            'a assinatura do aplicativo instalado. Não é seguro prosseguir.',
      'apk_unreadable' =>
        'O Android não reconheceu o arquivo como APK válido. '
            'Baixe novamente e confira o APK publicado.',
      'apk_corrupt' =>
        'O APK está corrompido ou incompleto. '
            'Verifique o SHA-256 e publique novamente.',
      'build_metadata_missing' =>
        'A release não informa um build Android válido. '
            'Corrija o campo build na publicação.',
      'integrity_metadata_missing' =>
        'A release não possui tamanho e SHA-256 '
            'verificáveis para este aparelho. Corrija o manifesto dos APKs.',
      'build_mismatch' =>
        'O código de build do APK não corresponde à release '
            'publicada. Confira a ABI e os metadados da publicação.',
      'not_newer' =>
        'O APK recebido não é mais recente que o aplicativo instalado.',
      'abi_mismatch' =>
        'O APK baixado não é compatível com a arquitetura deste celular.',
      'version_mismatch' =>
        'A versão interna do APK difere da versão publicada.',
      'package_mismatch' =>
        'O APK possui um identificador de aplicativo diferente.',
      'hash_mismatch' =>
        'A verificação SHA-256 falhou. O arquivo foi rejeitado.',
      'size_mismatch' =>
        'O tamanho do APK não corresponde ao manifesto da release.',
      'verification_unavailable' =>
        'O servidor não pôde confirmar a release. '
            'Verifique a conexão e tente novamente.',
      'superseded' => 'O APK foi substituído por uma versão mais recente.',
      'invalid_path' => 'O APK está fora da pasta segura de atualizações.',
      _ =>
        'Não foi possível validar o APK ($resultado). '
            'A instalação foi bloqueada por segurança.',
    };
  }

  // =====================================================
  // 🔐 VERIFICAR PERMISSÕES POR VERSÃO DO ANDROID
  // =====================================================
  Future<bool> _solicitarPermissoes(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      debugPrint('📱 Android SDK: $sdkInt');

      final installStatus = await Permission.requestInstallPackages.status;

      if (installStatus.isGranted) {
        debugPrint('✅ Permissão de instalação já concedida');
      } else {
        debugPrint('📱 Solicitando permissão de instalação...');

        final status = await Permission.requestInstallPackages.request();

        if (!status.isGranted) {
          debugPrint('❌ Permissão de instalação negada');

          if (sdkInt >= 26 && context.mounted) {
            final shouldOpenSettings = await _confirmarAbrirConfiguracoes(
              context: context,
              titulo: 'Permissão necessária',
              mensagem:
                  'Para instalar o aplicativo, precisamos de permissão para instalar apps desconhecidos.\n\n'
                  'Deseja abrir as configurações e conceder a permissão manualmente?',
            );

            if (shouldOpenSettings == true) {
              await openAppSettings();
            }
          }

          return false;
        }
      }

      debugPrint(
        '📁 APK será baixado no cache privado do app; permissão de armazenamento não é necessária.',
      );

      return true;
    } catch (e) {
      debugPrint('❌ Erro ao verificar permissões: $e');
      return false;
    }
  }

  Future<bool?> _confirmarAbrirConfiguracoes({
    required BuildContext context,
    required String titulo,
    required String mensagem,
  }) {
    final t = context.uai;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final dt = dialogContext.uai;

        return AlertDialog(
          backgroundColor: dt.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dt.cardRadius),
          ),
          title: Text(
            titulo,
            style: TextStyle(
              color: dt.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            mensagem,
            style: TextStyle(
              color: dt.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: dt.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Abrir configurações'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      // Mantém uso de t sem warning em alguns analisadores.
      // ignore: unnecessary_statements
      t;
    });
  }

  // =====================================================
  // 📁 DIRETÓRIO TEMPORÁRIO EXCLUSIVO DA ATUALIZAÇÃO
  // =====================================================
  Future<Directory> _getDownloadDirectory() {
    return UpdateStorageService.instance.getUpdateDirectory();
  }

  // =====================================================
  // ✅ VERIFICAR SE APK EXISTE
  // =====================================================
  Future<bool> apkExiste(String versao) async {
    try {
      final info = await _resolverApkInfo(versao);
      final ref = _storage.ref().child(info.storagePath);

      final metadata = await ref.getMetadata().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Timeout ao verificar APK');
        },
      );

      debugPrint(
        '✅ APK versão ${info.versao} encontrado em ${info.storagePath} '
        '- Tamanho: ${metadata.size} bytes',
      );

      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        debugPrint('❌ APK versão $versao não encontrado');
        return false;
      }

      debugPrint('❌ Erro Firebase ao verificar APK: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Erro ao verificar APK: $e');
      rethrow;
    }
  }

  // =====================================================
  // 📋 LISTAR APKS DISPONÍVEIS
  // =====================================================
  Future<List<String>> listarApksDisponiveis() async {
    if (!Platform.isAndroid) {
      // Firebase Storage listAll não é suportado pelo SDK C++ no Windows.
      // A atualização direta por APK é exclusiva do Android, então não há
      // motivo para consultar/listar APKs em desktop.
      debugPrint('ℹ️ Listagem de APKs ignorada nesta plataforma.');
      return const <String>[];
    }
    try {
      final ref = _storage.ref().child('apks');

      final result = await ref.listAll().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Timeout ao listar APKs');
        },
      );

      return result.items
          .map((item) => item.name)
          .where((name) => name.endsWith('.apk'))
          .toList();
    } on FirebaseException catch (e) {
      debugPrint('❌ Erro Firebase ao listar APKs: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Erro ao listar APKs: $e');
      return [];
    }
  }

  // =====================================================
  // 📥 BAIXAR E INSTALAR APK
  // =====================================================
  Future<void> baixarEInstalar({
    required BuildContext context,
    required String versao,
    required Function(double progress) onProgress,
    required Function(String status) onStatus,
    bool Function()? isCancelled,
  }) async {
    if (_downloadManualAtivo) {
      throw StateError('Já existe um download manual em andamento.');
    }
    _downloadManualAtivo = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    String? manualToken;
    void verificarSessao() {
      if (isCancelled?.call() == true) throw StateError('Download cancelado.');
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('A conta mudou durante a atualização.');
      }
    }

    try {
      if (!Platform.isAndroid) {
        throw Exception(
          'Atualização direta por APK está disponível apenas no Android.',
        );
      }

      if (Firebase.apps.isEmpty) {
        throw Exception('Firebase ainda não foi inicializado.');
      }

      onStatus('🔍 Verificando conexão...');

      if (!await _verificarInternet()) {
        throw Exception(
          'Sem conexão com a internet. Verifique sua rede e tente novamente.',
        );
      }

      onStatus('🔍 Verificando permissões...');

      if (!context.mounted) {
        throw StateError(
          'A tela de atualização foi fechada antes da solicitação de permissões.',
        );
      }
      if (!await _solicitarPermissoes(context)) {
        throw Exception(
          'Permissões necessárias negadas. Conceda as permissões nas configurações.',
        );
      }

      onStatus('🔍 Verificando disponibilidade...');

      final info = await _resolverApkInfo(versao);
      final downloadSessionId = UpdateTelemetryService.instance
          .newDownloadSessionId();
      await UpdateTelemetryService.instance.recordEvent(
        tipo: 'download_iniciado',
        version: info.versao,
        abi: _abiFromStoragePath(info.storagePath),
        artifactPath: info.storagePath,
        fileName: info.nomeArquivo,
        sessionId: downloadSessionId,
      );

      if (!await apkExiste(info.versao)) {
        throw Exception('APK versão ${info.versao} não encontrado no servidor');
      }

      manualToken = await _aproveitarAtualizacaoWifi(
        versao: info.versao,
        uid: uid,
        verificarSessao: verificarSessao,
        onProgress: onProgress,
        onStatus: onStatus,
      );
      if (manualToken == null) return;
      verificarSessao();

      onStatus('📥 Preparando download...');

      final cleanup = await UpdateStorageService.instance
          .cleanupBeforeDownload();
      if (cleanup.bytesFreed > 0) {
        final mb = cleanup.bytesFreed / 1024 / 1024;
        debugPrint(
          '🧹 Limpeza pré-download liberou ${mb.toStringAsFixed(2)} MB',
        );
      }

      final downloadDir = await _getDownloadDirectory();
      final filePath = '${downloadDir.path}/${info.nomeArquivo}';
      final partialPath = '$filePath.part';
      final file = File(filePath);
      final partialFile = File(partialPath);

      debugPrint('📁 APK temporário será salvo em: $filePath');

      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      if (await file.exists()) {
        await file.delete();
      }

      onStatus('📥 Baixando APK...');

      final ref = _storage.ref().child(info.storagePath);

      Timer? downloadGuard;
      StreamSubscription<TaskSnapshot>? progressSubscription;
      Object? interruption;
      DownloadTask? task;

      try {
        verificarSessao();
        final deadline = DateTime.now().add(const Duration(minutes: 5));
        task = ref.writeToFile(partialFile);
        downloadGuard = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (interruption != null) return;
          try {
            verificarSessao();
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException(
                'Tempo limite excedido. Verifique sua conexão.',
              );
            }
          } catch (e) {
            interruption = e;
            unawaited(
              task!.cancel().then<void>(
                (_) {},
                onError: (Object e, StackTrace stack) {
                  debugPrint('Não foi possível cancelar a transferência: $e');
                },
              ),
            );
          }
        });
        progressSubscription = task.snapshotEvents.listen(
          (event) {
            if (event.totalBytes > 0) {
              final progress = event.bytesTransferred / event.totalBytes;
              onProgress(progress.clamp(0.0, 1.0));
              debugPrint(
                '📊 Download: ${(progress * 100).toStringAsFixed(1)}%',
              );
            }
          },
          onError: (Object _) {}, // O próprio task propaga a falha abaixo.
        );

        await task;

        if (interruption != null) throw interruption!;
        verificarSessao();
      } catch (_) {
        if (await partialFile.exists()) {
          try {
            await partialFile.delete();
          } catch (_) {}
        }
        if (interruption != null) throw interruption!;
        rethrow;
      } finally {
        downloadGuard?.cancel();
        await progressSubscription?.cancel();
      }

      onStatus('✅ Download concluído!');

      if (!await partialFile.exists()) {
        throw Exception('Falha ao baixar o arquivo');
      }

      final fileSize = await partialFile.length();

      if (fileSize == 0) {
        throw Exception('Arquivo baixado está vazio');
      }

      if (fileSize < 1024 * 1024) {
        throw Exception(
          'Arquivo baixado está muito pequeno (${(fileSize / 1024).toStringAsFixed(0)} KB)',
        );
      }

      if (info.tamanhoBytes > 0 && fileSize != info.tamanhoBytes) {
        try {
          await partialFile.delete();
        } catch (_) {}
        throw Exception(
          'Download incompleto. Esperado ${info.tamanhoBytes} bytes, recebido $fileSize bytes.',
        );
      }

      if (info.sha256.trim().isNotEmpty) {
        onStatus('🔐 Validando integridade SHA-256...');
        final digest = crypto.sha256
            .convert(await partialFile.readAsBytes())
            .toString();
        if (digest.toLowerCase() != info.sha256.trim().toLowerCase()) {
          await UpdateTelemetryService.instance.recordEvent(
            tipo: 'hash_invalido',
            version: info.versao,
            abi: _abiFromStoragePath(info.storagePath),
            artifactPath: info.storagePath,
            fileName: info.nomeArquivo,
            sessionId: downloadSessionId,
          );
          try {
            await partialFile.delete();
          } catch (_) {}
          throw Exception(
            'Falha de integridade: SHA-256 do APK não confere com a release publicada.',
          );
        }
      }

      if (await file.exists()) {
        await file.delete();
      }
      await partialFile.rename(filePath);

      debugPrint(
        '📦 Tamanho do arquivo: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );

      await UpdateTelemetryService.instance.recordDownload(
        version: info.versao,
        abi: _abiFromStoragePath(info.storagePath),
        artifactPath: info.storagePath,
        fileName: info.nomeArquivo,
        sessionId: downloadSessionId,
      );

      onStatus('📦 Preparando para instalar...');

      await Future.delayed(const Duration(milliseconds: 500));

      onStatus('🔐 Confirmando que esta ainda é a release mais recente...');
      verificarSessao();
      if (Platform.isAndroid) {
        // Uma versão mais nova pode ter sido publicada ENQUANTO este APK baixava.
        // A instalação manual segue a mesma política de elegibilidade do Worker.
        if (FirebaseAuth.instance.currentUser != null) {
          final latest = await UpdateWifiService.instance.validateLatest(
            info.versao,
          );
          if (latest != 'current') {
            throw StateError(
              'A release foi substituída ou a verificação online falhou. '
              'Abra novamente a atualização para obter a última versão.',
            );
          }
        } else {
          final latest = await AppUpdateCheckService().verificarStatus();
          if (!latest.carregou ||
              latest.canal != 'producao' ||
              latest.versaoDestino != info.versao ||
              (!latest.precisaAtualizar && !latest.deveBloquear)) {
            throw StateError(
              'Não foi possível confirmar a versão oficial antes de instalar.',
            );
          }
        }
      }

      if (Platform.isAndroid) {
        final verification = await const MethodChannel('uai/updates_wifi')
            .invokeMethod<String>('verifyManualApk', {
              'uid': FirebaseAuth.instance.currentUser?.uid ?? '',
              'version': info.versao,
              'path': filePath,
            });
        if (verification != 'verified') {
          throw Exception(
            _mensagemVerificacaoApk(verification ?? 'verification_failed'),
          );
        }
      }

      onStatus('📱 Solicitando instalação...');
      verificarSessao();
      await UpdateStorageService.instance.registerPendingInstallation(
        targetVersion: info.versao,
        apkPath: filePath,
      );

      verificarSessao();
      final result = await OpenFilex.open(filePath);
      await UpdateTelemetryService.instance.recordEvent(
        tipo: 'instalador_aberto',
        version: info.versao,
        abi: _abiFromStoragePath(info.storagePath),
        artifactPath: info.storagePath,
        fileName: info.nomeArquivo,
        sessionId: downloadSessionId,
      );

      if (result.type == ResultType.done) {
        onStatus('✅ Instalação iniciada!');
        debugPrint('✅ Arquivo aberto com sucesso');
      } else {
        debugPrint('⚠️ Falha ao abrir com OpenFilex: ${result.message}');

        if (Platform.isAndroid) {
          verificarSessao();
          onStatus('📱 Tentando método alternativo...');
          await _abrirComIntentAlternativa(filePath);
        } else {
          throw Exception('Erro ao abrir arquivo: ${result.message}');
        }
      }
    } on TimeoutException catch (e) {
      onStatus('⏰ ${e.message}');
      debugPrint('❌ Timeout: $e');
      rethrow;
    } on FirebaseException catch (e) {
      final mensagemErro = _mapFirebaseStorageError(e);

      onStatus('❌ $mensagemErro');
      debugPrint('❌ FirebaseException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      onStatus('❌ Erro: ${e.toString()}');
      debugPrint('❌ Erro detalhado: $e');
      try {
        final info = await _resolverApkInfo(versao);
        await UpdateTelemetryService.instance.recordEvent(
          tipo: 'download_falhou',
          version: info.versao,
          abi: _abiFromStoragePath(info.storagePath),
          artifactPath: info.storagePath,
          fileName: info.nomeArquivo,
        );
      } catch (_) {}
      rethrow;
    } finally {
      try {
        if (manualToken != null) {
          await UpdateWifiService.instance.endManualDownload(
            versao,
            manualToken,
            expectedUid: uid,
          );
        }
      } finally {
        _downloadManualAtivo = false;
      }
    }
  }

  String _abiFromStoragePath(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('arm64-v8a')) return 'arm64-v8a';
    if (lower.contains('armeabi-v7a')) return 'armeabi-v7a';
    if (lower.contains('x86_64')) return 'x86_64';
    return 'desconhecida';
  }

  String _mapFirebaseStorageError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permissão negada no Firebase Storage. Contate o suporte.';
      case 'object-not-found':
        return 'APK não encontrado no servidor.';
      case 'unauthenticated':
        return 'Erro de autenticação. Contate o suporte.';
      case 'canceled':
        return 'Operação cancelada.';
      case 'retry-limit-exceeded':
        return 'Limite de tentativas excedido. Verifique sua conexão.';
      default:
        return 'Erro no Firebase: ${e.message ?? e.code}';
    }
  }

  // =====================================================
  // 🔁 MÉTODO ALTERNATIVO PARA ABRIR APK
  // =====================================================
  Future<void> _abrirComIntentAlternativa(String filePath) async {
    try {
      await Process.run('am', [
        'start',
        '-a',
        'android.intent.action.VIEW',
        '-t',
        'application/vnd.android.package-archive',
        '-d',
        'file://$filePath',
      ]);

      debugPrint('✅ Intent alternativa executada');
    } catch (e) {
      debugPrint('❌ Erro na intent alternativa: $e');

      throw Exception(
        'Não foi possível abrir o instalador. '
        'Tente abrir manualmente o arquivo em: $filePath',
      );
    }
  }

  // =====================================================
  // 🔥 VERIFICAR SE PODE ATUALIZAR
  // Mantém compatibilidade com BotaoAtualizarMelhorado.
  // =====================================================
  Future<Map<String, dynamic>> verificarAtualizacao(String versaoAtual) async {
    try {
      if (!await _verificarInternet()) {
        return {
          'podeAtualizar': false,
          'mensagem':
              'Sem conexão com a internet. Não foi possível verificar atualizações.',
          'erro': 'no_internet',
        };
      }

      final config = await _buscarConfigApp();
      final versaoServidor = (config['versao_atual'] ?? '').toString().trim();

      if (versaoServidor.isNotEmpty &&
          AppVersionModel.precisaAtualizar(
            versaoLocal: versaoAtual,
            versaoRemota: versaoServidor,
          )) {
        final info = await _resolverApkInfo(versaoServidor);

        return {
          'podeAtualizar': await apkExiste(versaoServidor),
          'versaoAtual': versaoAtual,
          'ultimaVersao': versaoServidor,
          'obrigatoria': config['atualizacao_obrigatoria'] == true,
          'apkPath': info.storagePath,
          'apkUrl': info.downloadUrl,
          'mensagem': 'Nova versão $versaoServidor disponível!',
        };
      }

      final apks = await listarApksDisponiveis();

      if (apks.isEmpty) {
        return {
          'podeAtualizar': false,
          'mensagem': 'Nenhuma atualização disponível no momento.',
        };
      }

      final versoesDisponiveis = apks
          .map((nome) {
            final regex = RegExp(r'uai_capoeira_(\d+\.\d+\.\d+)\.apk');
            final match = regex.firstMatch(nome);
            return match?.group(1) ?? '';
          })
          .where((v) => v.isNotEmpty)
          .toList();

      if (versoesDisponiveis.isEmpty) {
        return {
          'podeAtualizar': false,
          'mensagem': 'Nenhuma versão válida encontrada no servidor.',
        };
      }

      versoesDisponiveis.sort((a, b) {
        final aParts = a.split('.').map(int.parse).toList();
        final bParts = b.split('.').map(int.parse).toList();

        for (int i = 0; i < aParts.length; i++) {
          if (i >= bParts.length) return -1;
          if (aParts[i] != bParts[i]) return bParts[i].compareTo(aParts[i]);
        }

        return 0;
      });

      final ultimaVersao = versoesDisponiveis.first;

      final precisaAtualizar = AppVersionModel.precisaAtualizar(
        versaoLocal: versaoAtual,
        versaoRemota: ultimaVersao,
      );

      return {
        'podeAtualizar': precisaAtualizar,
        'versaoAtual': versaoAtual,
        'ultimaVersao': ultimaVersao,
        'versoesDisponiveis': versoesDisponiveis,
        'mensagem': precisaAtualizar
            ? 'Nova versão $ultimaVersao disponível!'
            : 'App está atualizado (versão $versaoAtual)',
      };
    } on FirebaseException catch (e) {
      debugPrint(
        '❌ Erro Firebase ao verificar atualização: ${e.code} - ${e.message}',
      );

      return {
        'podeAtualizar': false,
        'mensagem': 'Erro ao verificar atualizações: ${e.message ?? e.code}',
        'erro': e.code,
      };
    } catch (e) {
      debugPrint('❌ Erro ao verificar atualização: $e');

      return {
        'podeAtualizar': false,
        'mensagem':
            'Erro ao verificar atualizações. Tente novamente mais tarde.',
        'erro': e.toString(),
      };
    }
  }

  // =====================================================
  // 🔥 MÉTODO COM FEEDBACK VISUAL
  // =====================================================
  Future<void> baixarEInstalarComFeedback(
    BuildContext context,
    String versao,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _DownloadProgressDialog(versao: versao, service: this),
    );
  }

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }
}

// =====================================================
// 📦 INFO DO APK
// =====================================================
class WifiApkArtifact {
  final String url;
  final String sha256;
  final int bytes;

  const WifiApkArtifact({
    required this.url,
    required this.sha256,
    required this.bytes,
  });
}

class _ApkInfo {
  final String versao;
  final String nomeArquivo;
  final String storagePath;
  final String downloadUrl;
  final int tamanhoBytes;
  final String sha256;

  const _ApkInfo({
    required this.versao,
    required this.nomeArquivo,
    required this.storagePath,
    required this.downloadUrl,
    required this.tamanhoBytes,
    this.sha256 = '',
  });
}

// =====================================================
// 🚀 UAI UPDATE EXPERIENCE — TELA PREMIUM DE ATUALIZAÇÃO
// =====================================================
// Ocupa toda a área útil do app, mas NÃO ativa modo imersivo/tela cheia.
// Status bar/navigation bar do sistema continuam sob controle normal do app.
// A navegação é bloqueada durante a etapa crítica para evitar saída acidental.
class _DownloadProgressDialog extends StatefulWidget {
  final String versao;
  final AtualizacaoDiretaService service;

  const _DownloadProgressDialog({required this.versao, required this.service});

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog>
    with TickerProviderStateMixin {
  double _progress = 0.0;
  String _status = 'Preparando o motor de atualização...';
  bool _concluido = false;
  bool _cancelado = false;
  bool _erro = false;
  String? _erroMensagem;
  bool _recoveryBusy = false;
  int _recoveryPercent = -1;
  String _recoveryStage = '';
  String? _recoveryLocation;
  String? _recoveryError;
  bool _recoveryDifferentSignature = false;
  Timer? _recoveryPoller;

  late final AnimationController _pulseController;
  late final AnimationController _orbitController;
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    )..repeat();
    _iniciarDownload();
  }

  @override
  void dispose() {
    _recoveryPoller?.cancel();
    _pulseController.dispose();
    _orbitController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _iniciarDownload() async {
    try {
      await widget.service.baixarEInstalar(
        context: context,
        versao: widget.versao,
        isCancelled: () => _cancelado || !mounted,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress.clamp(0.0, 1.0));
        },
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );

      if (!mounted) return;
      setState(() {
        _concluido = true;
        _progress = 1;
        _status = 'Instalador do Android iniciado. Finalizando...';
      });

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = true;
        _erroMensagem = e.toString().replaceAll('Exception: ', '');
        _status = 'Não foi possível concluir a atualização.';
      });
    }
  }

  Future<void> _exportRecovery() async {
    if (_recoveryBusy || !UpdateWifiService.instance.isSupported) return;
    setState(() {
      _recoveryBusy = true;
      _recoveryError = null;
      _recoveryLocation = null;
      _recoveryPercent = 0;
      _recoveryStage = 'Conferindo release oficial...';
    });
    try {
      // Android 9 ou anterior: acesso à pasta Downloads pública precisa
      // ser autorizado explicitamente. Android 10+ usa MediaStore.
      final android = await DeviceInfoPlugin().androidInfo;
      if (android.version.sdkInt <= 28) {
        final permission = await Permission.storage.request();
        if (!permission.isGranted) {
          throw StateError(
            'Autorize o acesso ao armazenamento para salvar o APK em Downloads.',
          );
        }
      }
      _recoveryPoller?.cancel();
      _recoveryPoller = Timer.periodic(const Duration(milliseconds: 650), (
        timer,
      ) async {
        if (!mounted || !_recoveryBusy) {
          timer.cancel();
          return;
        }
        final info = await UpdateWifiService.instance.recoveryState();
        if (!mounted || !_recoveryBusy) return;
        final phase = (info['phase'] ?? '').toString();
        final progress = info['progress'];
        setState(() {
          _recoveryPercent = progress is num
              ? progress.toInt().clamp(0, 100).toInt()
              : -1;
          _recoveryStage = switch (phase) {
            'resolving' => 'Conferindo a release oficial...',
            'using_cache' => 'Reutilizando APK já baixado...',
            'downloading' => 'Baixando APK para recuperação...',
            'verifying' => 'Verificando assinatura, integridade e ABI...',
            'rechecking' => 'Confirmando a versão mais recente...',
            'saving' => 'Salvando em Downloads...',
            _ => 'Preparando recuperação...',
          };
        });
      });
      final response = await UpdateWifiService.instance.saveRecoveryApk(
        widget.versao,
      );
      if (!mounted) return;
      if (response['ok'] != true) {
        throw StateError(
          (response['error'] ?? 'Não foi possível salvar o APK.').toString(),
        );
      }
      setState(() {
        _recoveryLocation = (response['location'] ?? 'Downloads').toString();
        _recoveryDifferentSignature = response['signatureMismatch'] == true;
        _recoveryPercent = 100;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _recoveryError = e.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      _recoveryPoller?.cancel();
      _recoveryPoller = null;
      if (mounted) setState(() => _recoveryBusy = false);
    }
  }

  int get _stageIndex {
    final s = _status.toLowerCase();
    if (_concluido || s.contains('instalação iniciada')) return 4;
    if (s.contains('solicitando instalação') ||
        s.contains('método alternativo') ||
        s.contains('instalar')) {
      return 3;
    }
    if (s.contains('download concluído') ||
        s.contains('preparando para instalar') ||
        s.contains('valid')) {
      return 2;
    }
    if (s.contains('baixando apk') || _progress > 0) return 1;
    return 0;
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.24) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(background.computeLuminance() < 0.45 ? 0.70 : 0.34)
        .withSaturation((hsl.saturation + .08).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);
    final success = _ensureVisible(t.success, t.surface);
    final error = _ensureVisible(t.error, t.surface);
    final accent = _erro ? error : (_concluido ? success : primary);
    final percent = (_progress * 100).round().clamp(0, 100);

    return PopScope(
      // Durante download/validação/abertura do instalador não deixa o usuário
      // sair acidentalmente pelo botão voltar. Em erro, libera o fechamento.
      canPop: _erro,
      child: Dialog.fullscreen(
        backgroundColor: t.surface,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: _UpdateBackdrop(
                  color: accent,
                  surface: t.surface,
                  card: t.card,
                  animation: _orbitController,
                  scan: _scanController,
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final maxWidth = compact ? constraints.maxWidth : 920.0;
                  return Align(
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 18 : 34,
                        vertical: compact ? 20 : 28,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildHeader(t, accent, compact),
                            SizedBox(height: compact ? 26 : 34),
                            _buildCore(t, accent, percent, compact),
                            SizedBox(height: compact ? 24 : 32),
                            _buildStatusPanel(t, accent, compact),
                            const SizedBox(height: 18),
                            _buildStages(t, accent, compact),
                            const SizedBox(height: 20),
                            if (_erro) ...[
                              _buildErrorActions(t, error),
                              const SizedBox(height: 16),
                              _buildRecoveryCard(t),
                            ],
                            if (!_erro && !_concluido)
                              Text(
                                _status.toLowerCase().contains('wi-fi')
                                    ? 'O Android pode continuar o download pelo Wi-Fi em segundo plano. A instalação exigirá sua confirmação.'
                                    : 'Mantenha o UAI Capoeira aberto. O instalador será chamado quando o pacote estiver pronto.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: t.textMuted,
                                  fontSize: compact ? 11.5 : 12.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (!_erro && !_concluido)
                              TextButton.icon(
                                onPressed: _cancelado
                                    ? null
                                    : () {
                                        setState(() {
                                          _cancelado = true;
                                          _status = 'Cancelando download...';
                                        });
                                        unawaited(
                                          UpdateWifiService.instance
                                              .cancelReadyInstallation(),
                                        );
                                      },
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Cancelar'),
                              ),
                            if (_concluido)
                              Text(
                                'Pacote validado. Transferindo o controle para o instalador do Android…',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: success,
                                  fontSize: compact ? 12 : 13,
                                  height: 1.4,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(dynamic t, Color accent, bool compact) {
    return Row(
      children: [
        Container(
          width: compact ? 42 : 48,
          height: compact ? 42 : 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: accent.withAlpha(26),
            border: Border.all(color: accent.withAlpha(56)),
          ),
          child: Icon(
            Icons.sports_martial_arts_rounded,
            color: accent,
            size: compact ? 23 : 27,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UAI CAPOEIRA • UPDATE ENGINE',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .45,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Atualização segura • versão ${widget.versao}',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _LiveChip(color: accent, done: _concluido, error: _erro),
      ],
    );
  }

  Widget _buildCore(dynamic t, Color accent, int percent, bool compact) {
    final size = compact ? 210.0 : 250.0;
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _orbitController]),
      builder: (context, _) {
        final pulse = .94 + (_pulseController.value * .06);
        return Transform.scale(
          scale: pulse,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: _orbitController.value * 6.283185307179586,
                  child: CustomPaint(
                    size: Size.square(size),
                    painter: _UpdateOrbitPainter(color: accent),
                  ),
                ),
                Container(
                  width: size * .72,
                  height: size * .72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.alphaBlend(accent.withAlpha(14), t.card),
                    border: Border.all(color: accent.withAlpha(41)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withAlpha(
                          (255.0 * (.13 + (_pulseController.value * .09)))
                              .round(),
                        ),
                        blurRadius: 42,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: size * .58,
                        height: size * .58,
                        child: CircularProgressIndicator(
                          value: _erro
                              ? null
                              : (_concluido
                                    ? 1
                                    : (_progress <= 0 ? null : _progress)),
                          strokeWidth: compact ? 7 : 8,
                          strokeCap: StrokeCap.round,
                          color: accent,
                          backgroundColor: t.border.withAlpha(
                            (255.0 * (.42)).round(),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _erro
                                ? Icons.error_outline_rounded
                                : _concluido
                                ? Icons.verified_rounded
                                : Icons.system_update_alt_rounded,
                            color: accent,
                            size: compact ? 31 : 37,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _erro ? '!' : '$percent%',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: compact ? 34 : 42,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.6,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _erro
                                ? 'ATENÇÃO'
                                : (_concluido ? 'PRONTO' : 'PROCESSANDO'),
                            style: TextStyle(
                              color: accent,
                              fontSize: compact ? 9.5 : 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPanel(dynamic t, Color accent, bool compact) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 19),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(11), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius + 5),
        border: Border.all(color: accent.withAlpha(41)),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withAlpha(26),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _erro ? Icons.warning_amber_rounded : Icons.bolt_rounded,
              color: accent,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _erro ? 'Atualização interrompida' : 'Etapa atual',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _erro ? (_erroMensagem ?? _status) : _status,
                  style: TextStyle(
                    color: _erro ? accent : t.textPrimary,
                    fontSize: compact ? 13 : 14,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStages(dynamic t, Color accent, bool compact) {
    const items = <(IconData, String)>[
      (Icons.tune_rounded, 'Preparar'),
      (Icons.cloud_download_rounded, 'Baixar'),
      (Icons.verified_user_rounded, 'Validar'),
      (Icons.install_mobile_rounded, 'Instalar'),
    ];
    final current = _stageIndex;

    if (compact) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++)
            _UpdateStageChip(
              icon: items[i].$1,
              label: items[i].$2,
              color: accent,
              active: current == i,
              done: current > i || _concluido,
              muted: t.textMuted,
              card: t.card,
              border: t.border,
            ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _UpdateStageChip(
              icon: items[i].$1,
              label: items[i].$2,
              color: accent,
              active: current == i,
              done: current > i || _concluido,
              muted: t.textMuted,
              card: t.card,
              border: t.border,
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildRecoveryCard(dynamic t) {
    if (!UpdateWifiService.instance.isSupported) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.save_alt_rounded, color: t.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recuperação manual segura',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Se a instalação automática falhou, salve o APK oficial na pasta Downloads. '
            'O arquivo continuará lá mesmo se você precisar reinstalar o aplicativo.',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          if (_recoveryBusy) ...[
            LinearProgressIndicator(
              value: _recoveryPercent < 0 ? null : _recoveryPercent / 100,
            ),
            const SizedBox(height: 7),
            Text(
              '$_recoveryStage${_recoveryPercent >= 0 ? ' • $_recoveryPercent%' : ''}',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (_recoveryLocation != null) ...[
            Text(
              'APK validado e salvo em: $_recoveryLocation',
              style: TextStyle(color: t.success, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '1. Abra o gerenciador de arquivos do celular e entre em Downloads.\n'
              '2. Toque no APK salvo e tente atualizar por cima, sem desinstalar.\n'
              '3. Se o Android recusar, confirme que seus dados estão sincronizados. '
              'Só então considere desinstalar e instalar pelo arquivo salvo.',
              style: TextStyle(
                color: t.textPrimary,
                height: 1.55,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final opened = await UpdateWifiService.instance
                    .openRecoveryDownloads();
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Abra o gerenciador de arquivos do celular e entre na pasta Downloads.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Abrir pasta Downloads'),
            ),
            if (_recoveryDifferentSignature) ...[
              const SizedBox(height: 8),
              Text(
                'ATENÇÃO: a assinatura é diferente da instalada. A instalação por cima deve falhar. '
                'Não desinstale sem garantir backup/sincronização dos seus dados.',
                style: TextStyle(
                  color: t.error,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ] else ...[
            if (_recoveryError != null) ...[
              Text(
                _recoveryError!,
                style: TextStyle(color: t.error, fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _exportRecovery,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Salvar APK oficial em Downloads'),
              ),
            ),
          ],
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => OfficialApkWebsiteService.open(context),
              icon: const Icon(Icons.public_rounded),
              label: const Text('Ou baixar pelo site oficial'),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Nunca desinstale antes de salvar o APK e conferir seus dados. '
            'APK sem hash válido, incompatível ou não autorizado não será exportado.',
            style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorActions(dynamic t, Color error) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Fechar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: error,
              side: BorderSide(color: error.withAlpha(115)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _erro = false;
                _cancelado = false;
                _erroMensagem = null;
                _progress = 0;
                _status = 'Reiniciando atualização...';
              });
              _iniciarDownload();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: error,
              foregroundColor: error.computeLuminance() > .48
                  ? Colors.black
                  : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveChip extends StatelessWidget {
  final Color color;
  final bool done;
  final bool error;

  const _LiveChip({
    required this.color,
    required this.done,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(23),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(46)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            error ? 'ERRO' : (done ? 'CONCLUÍDO' : 'AO VIVO'),
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .45,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateStageChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final bool done;
  final Color muted;
  final Color card;
  final Color border;

  const _UpdateStageChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.active,
    required this.done,
    required this.muted,
    required this.card,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final visibleColor = done || active ? color : muted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? Color.alphaBlend(color.withAlpha(19), card)
            : card.withAlpha(209),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: active || done ? color.withAlpha(64) : border.withAlpha(184),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : icon,
            color: visibleColor,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: visibleColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateBackdrop extends StatelessWidget {
  final Color color;
  final Color surface;
  final Color card;
  final Animation<double> animation;
  final Animation<double> scan;

  const _UpdateBackdrop({
    required this.color,
    required this.surface,
    required this.card,
    required this.animation,
    required this.scan,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, scan]),
      builder: (context, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -.15 + (animation.value * .08)),
                    radius: 1.05,
                    colors: [
                      Color.alphaBlend(color.withAlpha(19), card),
                      surface,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _UpdateGridPainter(color: color.withAlpha(14)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: (MediaQuery.sizeOf(context).height - 90) * scan.value,
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      color.withAlpha(5),
                      color.withAlpha(17),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UpdateGridPainter extends CustomPainter {
  final Color color;
  const _UpdateGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .7;
    const step = 42.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _UpdateOrbitPainter extends CustomPainter {
  final Color color;
  const _UpdateOrbitPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * .45;
    final faint = Paint()
      ..color = color.withAlpha(31)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawCircle(c, r, faint);
    canvas.drawCircle(c, r * .82, faint..color = color.withAlpha(18));

    final dot = Paint()..color = color;
    for (final angle in <double>[0, 1.57, 3.14, 4.71]) {
      canvas.drawCircle(
        Offset(
          c.dx + (r * .98 * math.cos(angle)),
          c.dy + (r * .98 * math.sin(angle)),
        ),
        3.2,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateOrbitPainter oldDelegate) =>
      oldDelegate.color != color;
}
