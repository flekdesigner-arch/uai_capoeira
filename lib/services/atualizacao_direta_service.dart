// services/atualizacao_direta_service.dart
import 'dart:io';
import 'dart:async';


import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AtualizacaoDiretaService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Connectivity _connectivity = Connectivity();

  // 🔥 VERIFICAR CONECTIVIDADE
  Future<bool> _verificarInternet() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      final hasInternet = connectivityResult != ConnectivityResult.none;

      if (!hasInternet) {
        debugPrint('❌ Sem conexão com a internet');
      } else {
        debugPrint('✅ Conexão com internet disponível: $connectivityResult');
      }

      return hasInternet;
    } catch (e) {
      debugPrint('❌ Erro ao verificar conectividade: $e');
      return false;
    }
  }

  // 🔥 VERIFICAR PERMISSÕES POR VERSÃO DO ANDROID
  Future<bool> _solicitarPermissoes(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      debugPrint('📱 Android SDK: $sdkInt');

      // 🔥 PERMISSÃO DE INSTALAÇÃO (para todas as versões)
      final installStatus = await Permission.requestInstallPackages.status;
      if (installStatus.isGranted) {
        debugPrint('✅ Permissão de instalação já concedida');
      } else {
        debugPrint('📱 Solicitando permissão de instalação...');
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          debugPrint('❌ Permissão de instalação negada');

          // Se for Android 8+ (API 26+), podemos abrir as configurações
          if (sdkInt >= 26 && context.mounted) {
            final shouldOpenSettings = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Permissão necessária'),
                content: const Text(
                    'Para instalar o aplicativo, precisamos de permissão para instalar apps desconhecidos.\n\n'
                        'Deseja abrir as configurações e conceder a permissão manualmente?'
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Abrir configurações'),
                  ),
                ],
              ),
            );

            if (shouldOpenSettings == true) {
              await openAppSettings();
            }
          }
          return false;
        }
      }

      // 🔥 PERMISSÃO DE ARMAZENAMENTO (apenas para Android 10 e inferior)
      if (sdkInt < 30) { // Android 10 (API 29) e inferior
        debugPrint('📱 Android < 11 - Verificando permissão de storage');

        var status = await Permission.storage.status;

        if (status.isGranted) {
          debugPrint('✅ Permissão de storage já concedida');
        } else {
          debugPrint('📱 Solicitando permissão de storage...');
          status = await Permission.storage.request();

          if (!status.isGranted && context.mounted) {
            debugPrint('❌ Permissão de storage negada');

            final shouldOpenSettings = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Permissão necessária'),
                content: const Text(
                    'Para baixar o APK, precisamos de permissão para acessar o armazenamento.\n\n'
                        'Deseja abrir as configurações e conceder a permissão manualmente?'
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Abrir configurações'),
                  ),
                ],
              ),
            );

            if (shouldOpenSettings == true) {
              await openAppSettings();
            }
            return false;
          }
        }
      } else {
        debugPrint('📱 Android 11+ - Usando scoped storage, não precisa de permissão storage');
      }

      return true;

    } catch (e) {
      debugPrint('❌ Erro ao verificar permissões: $e');
      return false;
    }
  }

  // 🔥 OBTER DIRETÓRIO APROPRIADO POR VERSÃO DO ANDROID
  Future<Directory?> _getDownloadDirectory() async {
    try {
      final androidInfo = await _deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // Para Android 11+ (API 30+) - Usar diretório específico do app
      if (sdkInt >= 30) {
        debugPrint('📱 Android 11+ - Usando diretório do app');
        final dir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${dir.path}/downloads');

        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }

        return downloadDir;
      }
      // Para Android 10 e inferior - Tentar Downloads público
      else {
        debugPrint('📱 Android < 11 - Tentando diretório Downloads');

        // Tentar diretório Downloads público
        Directory? downloadsDir = Directory('/storage/emulated/0/Download');

        if (await downloadsDir.exists()) {
          return downloadsDir;
        }

        // Fallback: Diretório externo do app
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final downloadDir = Directory('${externalDir.path}/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir;
        }
      }

      // Fallback final: diretório temporário
      debugPrint('📱 Usando diretório temporário como fallback');
      return await getTemporaryDirectory();

    } catch (e) {
      debugPrint('❌ Erro ao obter diretório: $e');
      return await getTemporaryDirectory();
    }
  }

  // 🔥 VERIFICAR SE APK EXISTE (COM TIMEOUT)
  Future<bool> apkExiste(String versao) async {
    try {
      final ref = _storage.ref().child('apks/uai_capoeira_$versao.apk');

      // Adicionar timeout de 30 segundos
      final metadata = await ref.getMetadata().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Timeout ao verificar APK');
        },
      );

      debugPrint('✅ APK versão $versao encontrado - Tamanho: ${metadata.size} bytes');
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

  // 🔥 LISTAR APKS DISPONÍVEIS (COM TIMEOUT)
  Future<List<String>> listarApksDisponiveis() async {
    try {
      final ref = _storage.ref().child('apks');

      // Adicionar timeout de 30 segundos
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

  // 🔥 BAIXAR E INSTALAR APK
  Future<void> baixarEInstalar({
    required BuildContext context,
    required String versao,
    required Function(double progress) onProgress,
    required Function(String status) onStatus,
  }) async {
    try {
      // Verificar conectividade primeiro
      onStatus('🔍 Verificando conexão...');
      if (!await _verificarInternet()) {
        throw Exception('Sem conexão com a internet. Verifique sua rede e tente novamente.');
      }

      onStatus('🔍 Verificando permissões...');

      // 1. Verificar permissões
      if (!await _solicitarPermissoes(context)) {
        throw Exception('Permissões necessárias negadas. Conceda as permissões nas configurações.');
      }

      onStatus('🔍 Verificando disponibilidade...');

      // 2. Verificar se APK existe
      if (!await apkExiste(versao)) {
        throw Exception('APK versão $versao não encontrado no servidor');
      }

      onStatus('📥 Preparando download...');

      // 3. Obter diretório
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null) {
        throw Exception('Não foi possível acessar o diretório de download');
      }

      final fileName = 'uai_capoeira_$versao.apk';
      final filePath = '${downloadDir.path}/$fileName';
      final file = File(filePath);

      debugPrint('📁 Arquivo será salvo em: $filePath');

      // 4. Remover arquivo antigo se existir
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ Arquivo antigo removido');
      }

      onStatus('📥 Baixando APK...');

      // 5. Baixar do Firebase Storage com timeout
      final ref = _storage.ref().child('apks/uai_capoeira_$versao.apk');

      // Criar um Completer para controlar o timeout
      final downloadCompleter = Completer<void>();
      Timer? timeoutTimer;

      try {
        // Configurar timeout de 5 minutos para download
        timeoutTimer = Timer(const Duration(minutes: 5), () {
          if (!downloadCompleter.isCompleted) {
            downloadCompleter.completeError(
                TimeoutException('Tempo limite excedido. Verifique sua conexão com a internet.')
            );
          }
        });

        // Download com acompanhamento de progresso
        final task = ref.writeToFile(file);

        task.snapshotEvents.listen((event) {
          if (event.totalBytes != null && event.totalBytes! > 0) {
            final progress = event.bytesTransferred / event.totalBytes!;
            onProgress(progress.clamp(0.0, 1.0));
            debugPrint('📊 Download: ${(progress * 100).toStringAsFixed(1)}%');
          }
        });

        await task;
        downloadCompleter.complete();
        await downloadCompleter.future;

        timeoutTimer?.cancel();

      } catch (e) {
        timeoutTimer?.cancel();
        rethrow;
      }

      onStatus('✅ Download concluído!');

      // 6. Verificar se o arquivo foi baixado
      if (!await file.exists()) {
        throw Exception('Falha ao baixar o arquivo');
      }

      // 7. Verificar tamanho do arquivo
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Arquivo baixado está vazio');
      }

      if (fileSize < 1024 * 1024) { // Menos de 1MB
        throw Exception('Arquivo baixado está muito pequeno (${(fileSize / 1024).toStringAsFixed(0)} KB)');
      }

      debugPrint('📦 Tamanho do arquivo: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      onStatus('📦 Preparando para instalar...');

      // 8. Pequena pausa para garantir que o arquivo foi salvo
      await Future.delayed(const Duration(milliseconds: 500));

      // 9. Solicitar instalação
      onStatus('📱 Solicitando instalação...');

      final result = await OpenFilex.open(filePath);

      if (result.type == ResultType.done) {
        onStatus('✅ Instalação iniciada!');
        debugPrint('✅ Arquivo aberto com sucesso');
      } else {
        // Se falhar, tentar com Intent explícita
        debugPrint('⚠️ Falha ao abrir com OpenFilex: ${result.message}');

        // Para Android, tentar com método alternativo
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
      String mensagemErro;
      switch (e.code) {
        case 'permission-denied':
          mensagemErro = 'Permissão negada no Firebase Storage. Contate o suporte.';
          break;
        case 'object-not-found':
          mensagemErro = 'APK não encontrado no servidor.';
          break;
        case 'unauthenticated':
          mensagemErro = 'Erro de autenticação. Contate o suporte.';
          break;
        default:
          mensagemErro = 'Erro no Firebase: ${e.message ?? e.code}';
      }
      onStatus('❌ $mensagemErro');
      debugPrint('❌ FirebaseException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      onStatus('❌ Erro: ${e.toString()}');
      debugPrint('❌ Erro detalhado: $e');
      rethrow;
    }
  }

  // 🔥 MÉTODO ALTERNATIVO PARA ABRIR APK (caso OpenFilex falhe)
  Future<void> _abrirComIntentAlternativa(String filePath) async {
    try {
      // Método alternativo usando Android Intent
      await Process.run('am', [
        'start',
        '-a', 'android.intent.action.VIEW',
        '-t', 'application/vnd.android.package-archive',
        '-d', 'file://$filePath'
      ]);
      debugPrint('✅ Intent alternativa executada');
    } catch (e) {
      debugPrint('❌ Erro na intent alternativa: $e');
      throw Exception('Não foi possível abrir o instalador. Tente abrir manualmente o arquivo em: $filePath');
    }
  }

  // 🔥 VERIFICAR SE PODE ATUALIZAR
  Future<Map<String, dynamic>> verificarAtualizacao(String versaoAtual) async {
    try {
      // Verificar conectividade primeiro
      if (!await _verificarInternet()) {
        return {
          'podeAtualizar': false,
          'mensagem': 'Sem conexão com a internet. Não foi possível verificar atualizações.',
          'erro': 'no_internet',
        };
      }

      final apks = await listarApksDisponiveis();

      if (apks.isEmpty) {
        return {
          'podeAtualizar': false,
          'mensagem': 'Nenhuma atualização disponível no momento.',
        };
      }

      // Extrair versões dos nomes dos arquivos
      final versoesDisponiveis = apks.map((nome) {
        final regex = RegExp(r'uai_capoeira_(\d+\.\d+\.\d+)\.apk');
        final match = regex.firstMatch(nome);
        return match?.group(1) ?? '';
      }).where((v) => v.isNotEmpty).toList();

      if (versoesDisponiveis.isEmpty) {
        return {
          'podeAtualizar': false,
          'mensagem': 'Nenhuma versão válida encontrada no servidor.',
        };
      }

      // Ordenar versões (da mais nova para a mais antiga)
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
      final precisaAtualizar = _compararVersoes(versaoAtual, ultimaVersao);

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
      debugPrint('❌ Erro Firebase ao verificar atualização: ${e.code} - ${e.message}');
      return {
        'podeAtualizar': false,
        'mensagem': 'Erro ao verificar atualizações: ${e.message ?? e.code}',
        'erro': e.code,
      };
    } catch (e) {
      debugPrint('❌ Erro ao verificar atualização: $e');
      return {
        'podeAtualizar': false,
        'mensagem': 'Erro ao verificar atualizações. Tente novamente mais tarde.',
        'erro': e.toString(),
      };
    }
  }

  bool _compararVersoes(String atual, String nova) {
    try {
      final atualParts = atual.split('.').map(int.parse).toList();
      final novaParts = nova.split('.').map(int.parse).toList();

      for (int i = 0; i < novaParts.length; i++) {
        if (i >= atualParts.length) return true;
        if (novaParts[i] > atualParts[i]) return true;
        if (novaParts[i] < atualParts[i]) return false;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Erro ao comparar versões: $e');
      return false;
    }
  }

  // 🔥 MÉTODO SIMPLIFICADO (com feedback visual)
  Future<void> baixarEInstalarComFeedback(
      BuildContext context,
      String versao
      ) async {
    // Mostrar diálogo de progresso
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(
        versao: versao,
        service: this,
      ),
    );
  }
}

// =====================================================
// DIALOG DE PROGRESSO DO DOWNLOAD
// =====================================================
class _DownloadProgressDialog extends StatefulWidget {
  final String versao;
  final AtualizacaoDiretaService service;

  const _DownloadProgressDialog({
    required this.versao,
    required this.service,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
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
            setState(() {
              _progress = progress;
            });
          }
        },
        onStatus: (status) {
          if (mounted) {
            setState(() {
              _status = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _concluido = true;
          _status = '✅ Download concluído!';
        });

        // Fechar o diálogo após 2 segundos
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_concluido && !_erro) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ] else if (_erro) ...[
              const Icon(Icons.error_outline, color: Colors.red, size: 50),
              const SizedBox(height: 16),
              Text(
                _erroMensagem ?? 'Erro desconhecido',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
            ] else ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 50),
              const SizedBox(height: 16),
              const Text(
                'Download concluído!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _erro ? Colors.red : Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}