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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class AtualizacaoDiretaService {
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

  Future<_ApkInfo> _resolverApkInfo(String versao) async {
    final versaoLimpa = versao.trim();

    if (!AppVersionModel.versaoValida(versaoLimpa)) {
      throw Exception('Versão inválida: $versaoLimpa');
    }

    final historico = await _buscarVersaoNoHistorico(versaoLimpa);

    if (historico != null && historico.storagePath.trim().isNotEmpty) {
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

    final config = await _buscarConfigApp();
    final configVersao = (config['versao_atual'] ?? '').toString().trim();
    final configPath = (config['apk_path'] ?? '').toString().trim();
    final configNome = (config['apk_nome_arquivo'] ?? '').toString().trim();
    final configUrl = (config['apk_url'] ?? '').toString().trim();
    final configTamanho = _asInt(config['apk_tamanho_bytes']);

    if (configVersao == versaoLimpa && configPath.isNotEmpty) {
      return _ApkInfo(
        versao: versaoLimpa,
        nomeArquivo: configNome.isNotEmpty
            ? configNome
            : AppVersionModel.gerarNomeArquivo(versaoLimpa),
        storagePath: configPath,
        downloadUrl: configUrl,
        tamanhoBytes: configTamanho,
      );
    }

    return _ApkInfo(
      versao: versaoLimpa,
      nomeArquivo: AppVersionModel.gerarNomeArquivo(versaoLimpa),
      storagePath: AppVersionModel.gerarStoragePath(versaoLimpa),
      downloadUrl: '',
      tamanhoBytes: 0,
    );
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

      if (sdkInt < 30) {
        debugPrint('📱 Android < 11 - Verificando permissão de storage');

        var status = await Permission.storage.status;

        if (status.isGranted) {
          debugPrint('✅ Permissão de storage já concedida');
        } else {
          debugPrint('📱 Solicitando permissão de storage...');
          status = await Permission.storage.request();

          if (!status.isGranted && context.mounted) {
            debugPrint('❌ Permissão de storage negada');

            final shouldOpenSettings = await _confirmarAbrirConfiguracoes(
              context: context,
              titulo: 'Permissão necessária',
              mensagem:
                  'Para baixar o APK, precisamos de permissão para acessar o armazenamento.\n\n'
                  'Deseja abrir as configurações e conceder a permissão manualmente?',
            );

            if (shouldOpenSettings == true) {
              await openAppSettings();
            }

            return false;
          }
        }
      } else {
        debugPrint(
          '📱 Android 11+ - Usando scoped storage, não precisa de permissão storage',
        );
      }

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
  // 📁 OBTER DIRETÓRIO APROPRIADO POR VERSÃO DO ANDROID
  // =====================================================
  Future<Directory?> _getDownloadDirectory() async {
    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 30) {
        debugPrint('📱 Android 11+ - Usando diretório do app');

        final dir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${dir.path}/downloads');

        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }

        return downloadDir;
      } else {
        debugPrint('📱 Android < 11 - Tentando diretório Downloads');

        final downloadsDir = Directory('/storage/emulated/0/Download');

        if (await downloadsDir.exists()) {
          return downloadsDir;
        }

        final externalDir = await getExternalStorageDirectory();

        if (externalDir != null) {
          final downloadDir = Directory('${externalDir.path}/Download');

          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }

          return downloadDir;
        }
      }

      debugPrint('📱 Usando diretório temporário como fallback');
      return await getTemporaryDirectory();
    } catch (e) {
      debugPrint('❌ Erro ao obter diretório: $e');
      return await getTemporaryDirectory();
    }
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
  }) async {
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

      if (!await _solicitarPermissoes(context)) {
        throw Exception(
          'Permissões necessárias negadas. Conceda as permissões nas configurações.',
        );
      }

      onStatus('🔍 Verificando disponibilidade...');

      final info = await _resolverApkInfo(versao);

      if (!await apkExiste(info.versao)) {
        throw Exception('APK versão ${info.versao} não encontrado no servidor');
      }

      onStatus('📥 Preparando download...');

      final downloadDir = await _getDownloadDirectory();

      if (downloadDir == null) {
        throw Exception('Não foi possível acessar o diretório de download');
      }

      final filePath = '${downloadDir.path}/${info.nomeArquivo}';
      final file = File(filePath);

      debugPrint('📁 Arquivo será salvo em: $filePath');

      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ Arquivo antigo removido');
      }

      onStatus('📥 Baixando APK...');

      final ref = _storage.ref().child(info.storagePath);

      final downloadCompleter = Completer<void>();
      Timer? timeoutTimer;

      try {
        timeoutTimer = Timer(const Duration(minutes: 5), () {
          if (!downloadCompleter.isCompleted) {
            downloadCompleter.completeError(
              TimeoutException(
                'Tempo limite excedido. Verifique sua conexão com a internet.',
              ),
            );
          }
        });

        final task = ref.writeToFile(file);

        task.snapshotEvents.listen(
          (event) {
            if (event.totalBytes > 0) {
              final progress = event.bytesTransferred / event.totalBytes;
              onProgress(progress.clamp(0.0, 1.0));
              debugPrint(
                '📊 Download: ${(progress * 100).toStringAsFixed(1)}%',
              );
            }
          },
          onError: (error) {
            if (!downloadCompleter.isCompleted) {
              downloadCompleter.completeError(error);
            }
          },
        );

        await task;

        if (!downloadCompleter.isCompleted) {
          downloadCompleter.complete();
        }

        await downloadCompleter.future;

        timeoutTimer.cancel();
      } catch (_) {
        timeoutTimer?.cancel();
        rethrow;
      }

      onStatus('✅ Download concluído!');

      if (!await file.exists()) {
        throw Exception('Falha ao baixar o arquivo');
      }

      final fileSize = await file.length();

      if (fileSize == 0) {
        throw Exception('Arquivo baixado está vazio');
      }

      if (fileSize < 1024 * 1024) {
        throw Exception(
          'Arquivo baixado está muito pequeno (${(fileSize / 1024).toStringAsFixed(0)} KB)',
        );
      }

      debugPrint(
        '📦 Tamanho do arquivo: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );

      onStatus('📦 Preparando para instalar...');

      await Future.delayed(const Duration(milliseconds: 500));

      onStatus('📱 Solicitando instalação...');

      final result = await OpenFilex.open(filePath);

      if (result.type == ResultType.done) {
        onStatus('✅ Instalação iniciada!');
        debugPrint('✅ Arquivo aberto com sucesso');
      } else {
        debugPrint('⚠️ Falha ao abrir com OpenFilex: ${result.message}');

        if (Platform.isAndroid) {
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
      rethrow;
    }
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
class _ApkInfo {
  final String versao;
  final String nomeArquivo;
  final String storagePath;
  final String downloadUrl;
  final int tamanhoBytes;

  const _ApkInfo({
    required this.versao,
    required this.nomeArquivo,
    required this.storagePath,
    required this.downloadUrl,
    required this.tamanhoBytes,
  });
}

// =====================================================
// 🎨 DIALOG DE PROGRESSO DO DOWNLOAD
// =====================================================
class _DownloadProgressDialog extends StatefulWidget {
  final String versao;
  final AtualizacaoDiretaService service;

  const _DownloadProgressDialog({required this.versao, required this.service});

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  String _status = 'Iniciando...';
  bool _concluido = false;
  bool _erro = false;
  String? _erroMensagem;

  @override
  void initState() {
    super.initState();
    _iniciarDownload();
  }

  Future<void> _iniciarDownload() async {
    try {
      await widget.service.baixarEInstalar(
        context: context,
        versao: widget.versao,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
        onStatus: (status) {
          if (mounted) {
            setState(() => _status = status);
          }
        },
      );

      if (mounted) {
        setState(() {
          _concluido = true;
          _status = '✅ Download concluído!';
        });

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = true;
          _erroMensagem = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final success = _ensureVisible(t.success, t.card);
    final error = _ensureVisible(t.error, t.card);
    final currentColor = _erro
        ? error
        : _concluido
        ? success
        : primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.cardRadius + 4),
            border: Border.all(color: t.border),
            boxShadow: t.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(currentColor),
              const SizedBox(height: 16),
              Text(
                _erro
                    ? 'Erro na atualização'
                    : _concluido
                    ? 'Download concluído'
                    : 'Atualizando UAI Capoeira',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Versão ${widget.versao}',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (!_concluido && !_erro) ...[
                LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress,
                  color: currentColor,
                  backgroundColor: t.border,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(_progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: currentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ] else if (_erro) ...[
                Text(
                  _erroMensagem ?? 'Erro desconhecido',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: error,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Fechar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: error,
                    foregroundColor: _readableOn(error),
                  ),
                ),
              ] else ...[
                Text(
                  'O instalador será aberto em instantes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _erro ? error : t.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Color color) {
    if (!_concluido && !_erro) {
      return SizedBox(
        width: 58,
        height: 58,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(color),
          strokeWidth: 5,
        ),
      );
    }

    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Icon(
        _erro ? Icons.error_outline_rounded : Icons.check_circle_rounded,
        color: color,
        size: 38,
      ),
    );
  }
}
