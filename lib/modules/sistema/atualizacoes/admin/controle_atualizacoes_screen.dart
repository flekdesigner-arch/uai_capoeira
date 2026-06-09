// lib/modules/sistema/atualizacoes/admin/controle_atualizacoes_screen.dart
//
// =====================================================
// 🧪 LABORATÓRIO DE ATUALIZAÇÕES - UAI CAPOEIRA
// =====================================================
//
// Tela administrativa profissional para:
// - visualizar a versão publicada;
// - cadastrar changelog;
// - enviar APK;
// - publicar atualização opcional/obrigatória;
// - acompanhar histórico.
//
// Ajustes desta versão:
// - visual mais forte/profissional;
// - TabBar corrigida no tema vermelho;
// - removido SwitchListTile para acabar com o warning de ListTile/DecoratedBox;
// - layout mais limpo no mobile/web;
// - cards com hierarquia melhor.
// =====================================================

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/app_update_admin_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/local_publish_automation_models.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_apk_file_loader_factory.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_base.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_factory.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/widgets/local_publish_automation_panel.dart';

class ControleAtualizacoesScreen extends StatefulWidget {
  const ControleAtualizacoesScreen({super.key});

  @override
  State<ControleAtualizacoesScreen> createState() =>
      _ControleAtualizacoesScreenState();
}

class _ControleAtualizacoesScreenState extends State<ControleAtualizacoesScreen>
    with SingleTickerProviderStateMixin {
  final AppUpdateAdminService _service = AppUpdateAdminService();
  final LocalPublishPlatformInfo _platformInfo =
  const LocalPublishPlatformService().getInfo();
  final StringBuffer _automationLogBuffer = StringBuffer();

  late final TabController _tabController;

  LocalPublishAutomationState? _automationState;
  bool _automationRunning = false;
  String _automationLogText = '';

  final TextEditingController _versaoController = TextEditingController();
  final TextEditingController _buildController = TextEditingController(text: '1');
  final TextEditingController _tituloController = TextEditingController();
  final TextEditingController _resumoController = TextEditingController();
  final TextEditingController _melhoriasController = TextEditingController();
  final TextEditingController _correcoesController = TextEditingController();
  final TextEditingController _implementacoesController = TextEditingController();
  final TextEditingController _removidosController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  bool _obrigatoria = false;
  bool _salvando = false;
  bool _enviandoApk = false;
  bool _notificando = false;
  double _uploadProgress = 0;
  String? _statusUpload;
  AppVersionModel? _rascunhoAtual;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _automationState = LocalPublishAutomationState.initial(
      available: _platformInfo.canRunLocalAutomation,
      platformLabel: _platformInfo.platformLabel,
    );
    _preencherProximaVersaoSugerida();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _versaoController.dispose();
    _buildController.dispose();
    _tituloController.dispose();
    _resumoController.dispose();
    _melhoriasController.dispose();
    _correcoesController.dispose();
    _implementacoesController.dispose();
    _removidosController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _preencherProximaVersaoSugerida() async {
    try {
      final config = await _service.getConfigApp();
      final atual = (config['versao_atual'] ?? '2.0.60').toString();
      final proxima = _service.proximaVersaoPatch(atual);

      if (!mounted) return;

      _versaoController.text = proxima;
      _tituloController.text = 'Versão $proxima disponível';
      _resumoController.text = 'Melhorias no sistema de atualização e notificações.';
    } catch (_) {
      if (!mounted) return;

      _versaoController.text = '2.0.61';
      _tituloController.text = 'Versão 2.0.61 disponível';
      _resumoController.text = 'Melhorias no sistema de atualização e notificações.';
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.25) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.12).clamp(0.0, 1.0))
        .toColor();
  }

  Color _softFill(Color color, Color base, [double opacity = 0.10]) {
    return Color.alphaBlend(color.withOpacity(opacity), base);
  }

  List<String> _linhas(TextEditingController controller) {
    return controller.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;

    final t = context.uai;
    final bg = color ?? t.primary;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: _readableOn(bg),
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  Future<void> _garantirFirestoreOnline({
    bool registrarLogAutomacao = false,
  }) async {
    try {
      if (registrarLogAutomacao) {
        _addAutomationLog('Ativando conexão do Firestore...');
      }

      await FirebaseFirestore.instance
          .enableNetwork()
          .timeout(const Duration(seconds: 10));

      await Future.delayed(const Duration(milliseconds: 350));

      if (registrarLogAutomacao) {
        _addAutomationLog('Firestore online. Continuando automação...');
      }
    } catch (e) {
      if (registrarLogAutomacao) {
        _addAutomationLog('Aviso: não foi possível confirmar Firestore online: $e');
      }

      // Não bloqueia aqui. A tentativa real de salvar/publicar ainda vai
      // retornar o erro correto caso a conexão esteja indisponível.
    }
  }

  String _erroAmigavelAtualizacao(Object e) {
    final raw = e.toString();

    if (raw.contains('client is offline') ||
        raw.contains('unavailable') ||
        raw.contains('offline')) {
      return 'O Firestore está offline neste momento. Verifique sua internet, '
          'aguarde alguns segundos e tente novamente. Se o app acabou de abrir '
          'no Windows, espere a sincronização terminar antes de executar a automação.';
    }

    return raw;
  }


  Future<AppVersionModel?> _salvarRascunhoInterno({bool mostrarSnack = true}) async {
    final t = context.uai;
    final versao = _versaoController.text.trim();

    if (!AppVersionModel.versaoValida(versao)) {
      _snack('Use uma versão válida, exemplo: 2.0.61', color: t.error);
      return null;
    }

    await _garantirFirestoreOnline();

    final model = await _service.salvarRascunho(
      versao: versao,
      build: int.tryParse(_buildController.text.trim()) ?? 1,
      titulo: _tituloController.text,
      resumo: _resumoController.text,
      obrigatoria: _obrigatoria,
      melhorias: _linhas(_melhoriasController),
      correcoes: _linhas(_correcoesController),
      implementacoes: _linhas(_implementacoesController),
      removidos: _linhas(_removidosController),
      observacoes: _observacoesController.text,
    );

    if (!mounted) return model;

    setState(() => _rascunhoAtual = model);

    if (mostrarSnack) {
      _snack(
        'Rascunho da versão ${model.versao} salvo com sucesso!',
        color: t.success,
      );
    }

    return model;
  }

  Future<void> _salvarRascunho() async {
    if (_salvando) return;

    setState(() => _salvando = true);

    try {
      await _salvarRascunhoInterno();
    } catch (e) {
      _snack('Erro ao salvar rascunho: ${_erroAmigavelAtualizacao(e)}', color: context.uai.error);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _selecionarEEnviarApk() async {
    if (_enviandoApk || _salvando) return;

    final t = context.uai;
    final versao = _versaoController.text.trim();

    if (!AppVersionModel.versaoValida(versao)) {
      _snack('Informe a versão antes de enviar o APK. Ex: 2.0.61',
          color: t.error);
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['apk'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final Uint8List? bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        _snack(
          'Não foi possível ler o arquivo. Tente selecionar novamente.',
          color: t.error,
        );
        return;
      }

      final esperado = AppVersionModel.gerarNomeArquivo(versao);

      if (!file.name.toLowerCase().endsWith('.apk')) {
        _snack('Selecione um arquivo .apk válido.', color: t.error);
        return;
      }

      if (file.name != esperado) {
        final continuar = await _confirmarNomeArquivoDiferente(
          nomeSelecionado: file.name,
          nomeEsperado: esperado,
        );

        if (continuar != true) return;
      }

      setState(() {
        _enviandoApk = true;
        _uploadProgress = 0;
        _statusUpload = 'Salvando rascunho...';
      });

      await _salvarRascunhoInterno(mostrarSnack: false);

      if (!mounted) return;

      setState(() {
        _statusUpload = 'Preparando upload...';
      });

      final model = await _service.uploadApkBytes(
        versao: versao,
        bytes: bytes,
        onProgress: (progress) {
          if (!mounted) return;

          setState(() {
            _uploadProgress = progress;
            _statusUpload =
            'Enviando APK... ${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _rascunhoAtual = model;
        _statusUpload = 'APK enviado: ${model.nomeArquivo}';
      });

      _snack('APK enviado com sucesso!', color: t.success);
    } catch (e) {
      _snack('Erro ao enviar APK: $e', color: t.error);
    } finally {
      if (mounted) setState(() => _enviandoApk = false);
    }
  }

  Future<bool?> _confirmarNomeArquivoDiferente({
    required String nomeSelecionado,
    required String nomeEsperado,
  }) {
    final t = context.uai;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Text(
            'Nome do APK diferente',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Você selecionou:\n$nomeSelecionado\n\n'
                'O nome esperado para esta versão é:\n$nomeEsperado\n\n'
                'Pode continuar. O sistema salva no Storage com o nome correto.',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Continuar'),
            ),
          ],
        );
      },
    );
  }



  void _addAutomationLog(String line) {
    if (line.trim().isEmpty) return;

    _automationLogBuffer.writeln(line);

    if (!mounted) return;

    setState(() {
      _automationLogText = _automationLogBuffer.toString();
    });
  }

  void _clearAutomationLog() {
    _automationLogBuffer.clear();

    if (!mounted) return;

    setState(() {
      _automationLogText = '';
    });
  }

  Future<bool?> _confirmarAutomacaoCompleta() {
    final t = context.uai;
    final versao = _versaoController.text.trim();

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Text(
            'Fazer tudo automaticamente?',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Essa ação vai salvar o rascunho da versão $versao, publicar o PWA, '
                'gerar o APK, enviar o APK para o Storage e publicar a versão.\n\n'
                'A notificação para os usuários NÃO será enviada automaticamente. '
                'Depois de testar o APK, você pode notificar manualmente pelo botão da tela.',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.rocket_launch_rounded),
              label: const Text('Executar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executarAutomacaoCompletaWindows() async {
    if (_automationRunning || _salvando || _enviandoApk || _notificando) return;

    final t = context.uai;
    final versao = _versaoController.text.trim();

    if (!_platformInfo.canRunLocalAutomation) {
      _snack(
        'Automação disponível apenas no Windows Desktop.',
        color: t.warning,
      );
      return;
    }

    if (!AppVersionModel.versaoValida(versao)) {
      _snack('Informe uma versão válida antes de executar.', color: t.error);
      return;
    }

    final confirmar = await _confirmarAutomacaoCompleta();
    if (confirmar != true) return;

    _clearAutomationLog();

    setState(() {
      _automationRunning = true;
      _salvando = true;
      _automationState = LocalPublishAutomationState.initial(
        available: _platformInfo.canRunLocalAutomation,
        platformLabel: _platformInfo.platformLabel,
      ).copyWith(
        running: true,
        startedAt: DateTime.now(),
        clearError: true,
        clearFinalApkPath: true,
      );
    });

    try {
      await _garantirFirestoreOnline(registrarLogAutomacao: true);

      _addAutomationLog('Salvando rascunho da versão $versao...');

      final draft = await _salvarRascunhoInterno(mostrarSnack: false);

      if (draft == null) {
        throw Exception('Não foi possível salvar o rascunho da versão.');
      }

      if (!mounted) return;

      setState(() {
        _automationState = _automationState?.updateStep(
          stepId: 'save_draft',
          status: LocalPublishStepStatus.success,
          log: 'Rascunho salvo: ${draft.versao}',
        );
        _salvando = false;
      });

      final runner = getLocalPublishRunner();

      final config = LocalPublishRunnerConfig(
        projectDir: r'C:\Dev\projects\uai_capoeira',
        scriptPath: r'C:\Dev\projects\uai_capoeira\tools\deploy_pwa_e_gerar_apk_uai.ps1',
        version: versao,
      );

      final runnerResult = await runner.run(
        config: config,
        onLog: _addAutomationLog,
        onState: (state) {
          if (!mounted) return;

          final current = _automationState;
          LocalPublishStep? saveDraftStep;

          if (current != null) {
            for (final step in current.steps) {
              if (step.id == 'save_draft') {
                saveDraftStep = step;
                break;
              }
            }
          }

          setState(() {
            if (saveDraftStep == null) {
              _automationState = state;
            } else {
              final mergedSteps = state.steps.map((step) {
                if (step.id == 'save_draft') return saveDraftStep!;
                return step;
              }).toList();

              _automationState = state.copyWith(steps: mergedSteps);
            }
          });
        },
      );

      if (!runnerResult.success) {
        throw Exception(
          runnerResult.errorOutput.trim().isNotEmpty
              ? runnerResult.errorOutput.trim()
              : 'Falha ao executar script local.',
        );
      }

      final apkPath = runnerResult.finalApkPath;
      _addAutomationLog('Lendo APK local: $apkPath');

      setState(() {
        _automationState = _automationState?.updateStep(
          stepId: 'upload_apk',
          status: LocalPublishStepStatus.running,
        );
        _enviandoApk = true;
        _uploadProgress = 0;
        _statusUpload = 'Lendo APK gerado localmente...';
      });

      final apkLoader = getLocalApkFileLoader();
      final apkResult = await apkLoader.readApk(apkPath);

      if (!apkResult.success || apkResult.bytes == null) {
        throw Exception(
          apkResult.errorMessage ?? 'Não foi possível ler o APK gerado.',
        );
      }

      _addAutomationLog(
        'APK lido com sucesso: ${apkResult.fileName} (${apkResult.sizeFormatted})',
      );

      final model = await _service.uploadApkBytes(
        versao: versao,
        bytes: apkResult.bytes!,
        onProgress: (progress) {
          if (!mounted) return;

          setState(() {
            _uploadProgress = progress;
            _statusUpload =
            'Enviando APK... ${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _rascunhoAtual = model;
        _statusUpload = 'APK enviado: ${model.nomeArquivo}';
        _enviandoApk = false;
        _automationState = _automationState?.updateStep(
          stepId: 'upload_apk',
          status: LocalPublishStepStatus.success,
          log: model.nomeArquivo,
        );
      });

      _addAutomationLog('APK enviado para o Storage: ${model.nomeArquivo}');
      _addAutomationLog('Publicando versão ${model.versao}...');

      setState(() {
        _salvando = true;
        _automationState = _automationState?.updateStep(
          stepId: 'publish_version',
          status: LocalPublishStepStatus.running,
        );
      });

      final published = await _service.publicarVersao(
        versionId: AppVersionModel.gerarVersionId(versao),
        obrigatoria: _obrigatoria,
      );

      if (!mounted) return;

      setState(() {
        _rascunhoAtual = published;
        _salvando = false;
        _automationState = _automationState?.updateStep(
          stepId: 'publish_version',
          status: LocalPublishStepStatus.success,
          log: 'Versão publicada: ${published.versao}',
        );
      });

      _addAutomationLog('Versão publicada com sucesso.');
      _addAutomationLog(
        'Notificação automática ignorada. Teste o APK e notifique manualmente quando quiser.',
      );

      if (!mounted) return;

      setState(() {
        _notificando = false;
        _automationRunning = false;
        _automationState = _automationState
            ?.updateStep(
          stepId: 'notify_users',
          status: LocalPublishStepStatus.skipped,
          log: 'Notificação manual. Nenhum usuário foi notificado automaticamente.',
        )
            .copyWith(
          running: false,
          finalApkPath: apkPath,
          finishedAt: DateTime.now(),
          clearError: true,
        );
      });

      _snack(
        'Automação concluída! PWA publicado, APK enviado e versão publicada. Notificação ficou manual.',
        color: t.success,
      );

      _tabController.animateTo(0);
    } catch (e) {
      if (!mounted) return;

      final erroAmigavel = _erroAmigavelAtualizacao(e);
      _addAutomationLog('ERRO: $erroAmigavel');

      setState(() {
        _automationRunning = false;
        _salvando = false;
        _enviandoApk = false;
        _notificando = false;
        _automationState = _automationState?.copyWith(
          running: false,
          errorMessage: erroAmigavel,
          finishedAt: DateTime.now(),
        );
      });

      _snack('Erro na automação: $erroAmigavel', color: t.error);
    }
  }


  Future<void> _notificarUsuariosNovaVersao({
    required String versao,
    required bool obrigatoria,
    required String titulo,
    required String mensagem,
  }) async {
    if (_notificando) return;

    final t = context.uai;
    final versaoLimpa = versao.trim();

    if (!AppVersionModel.versaoValida(versaoLimpa)) {
      _snack('Não foi possível notificar: versão inválida.', color: t.error);
      return;
    }

    final confirmar = await _confirmarNotificacaoVersao(
      versao: versaoLimpa,
      obrigatoria: obrigatoria,
    );

    if (confirmar != true) return;

    setState(() => _notificando = true);

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('notifyNewAppVersion');

      final result = await callable.call<Map<String, dynamic>>({
        'versao': versaoLimpa,
        'obrigatoria': obrigatoria,
        'titulo': titulo.trim().isNotEmpty
            ? titulo.trim()
            : '🚀 Nova versão $versaoLimpa disponível!',
        'mensagem': mensagem.trim().isNotEmpty
            ? mensagem.trim()
            : obrigatoria
            ? 'Atualização obrigatória disponível. Atualize para continuar usando o UAI Capoeira.'
            : 'Atualize o UAI Capoeira para receber as melhorias e correções.',
      });

      final data = Map<String, dynamic>.from(result.data);

      final successCount = data['successCount'] ?? 0;
      final failureCount = data['failureCount'] ?? 0;
      final tokensEncontrados = data['tokensEncontrados'] ?? 0;

      if (!mounted) return;

      _snack(
        'Notificação enviada! Sucesso: $successCount | Falhas: $failureCount | Tokens: $tokensEncontrados',
        color: t.success,
      );
    } on FirebaseFunctionsException catch (e) {
      _snack(
        'Erro na função: ${e.message ?? e.code}',
        color: t.error,
      );
    } catch (e) {
      _snack('Erro ao notificar usuários: $e', color: t.error);
    } finally {
      if (mounted) setState(() => _notificando = false);
    }
  }

  Future<bool?> _confirmarNotificacaoVersao({
    required String versao,
    required bool obrigatoria,
  }) {
    final t = context.uai;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Text(
            'Notificar usuários?',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            obrigatoria
                ? 'Enviar notificação para avisar que a versão $versao é obrigatória?'
                : 'Enviar notificação para avisar que a versão $versao está disponível?',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.notifications_active_rounded),
              label: const Text('Enviar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _publicarRascunho() async {
    if (_salvando || _enviandoApk) return;

    final t = context.uai;
    final versao = _versaoController.text.trim();
    final versionId = AppVersionModel.gerarVersionId(versao);

    if (versionId.isEmpty) {
      _snack('Informe uma versão válida.', color: t.error);
      return;
    }

    final confirmar = await _confirmarPublicacao();
    if (confirmar != true) return;

    setState(() => _salvando = true);

    try {
      await _salvarRascunhoInterno(mostrarSnack: false);

      final model = await _service.publicarVersao(
        versionId: versionId,
        obrigatoria: _obrigatoria,
      );

      if (!mounted) return;

      setState(() => _rascunhoAtual = model);

      _snack(
        _obrigatoria
            ? 'Versão ${model.versao} publicada como obrigatória!'
            : 'Versão ${model.versao} publicada como opcional!',
        color: _obrigatoria ? t.warning : t.success,
      );

      _tabController.animateTo(0);
    } catch (e) {
      _snack('Erro ao publicar versão: $e', color: t.error);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<bool?> _confirmarPublicacao() {
    final t = context.uai;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Text(
            _obrigatoria
                ? 'Publicar atualização obrigatória?'
                : 'Publicar atualização opcional?',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            _obrigatoria
                ? 'Usuários com versão antiga serão bloqueados até instalar a versão publicada.'
                : 'Usuários verão o aviso de nova versão, mas poderão continuar usando o app.',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.rocket_launch_rounded),
              label: const Text('Publicar'),
            ),
          ],
        );
      },
    );
  }

  void _carregarVersaoNoFormulario(AppVersionModel version) {
    setState(() {
      _rascunhoAtual = version;
      _versaoController.text = version.versao;
      _buildController.text = version.build.toString();
      _tituloController.text = version.titulo;
      _resumoController.text = version.resumo;
      _melhoriasController.text = version.melhorias.join('\n');
      _correcoesController.text = version.correcoes.join('\n');
      _implementacoesController.text = version.implementacoes.join('\n');
      _removidosController.text = version.removidos.join('\n');
      _observacoesController.text = version.observacoes;
      _obrigatoria = version.obrigatoria;
      _statusUpload = version.temApk
          ? 'APK atual: ${version.nomeArquivo} (${version.tamanhoFormatado})'
          : null;
    });

    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Controle de Atualizações',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            height: 58,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.20)),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withOpacity(0.72),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_rounded), text: 'Atual'),
                Tab(icon: Icon(Icons.rocket_launch_rounded), text: 'Nova versão'),
                Tab(icon: Icon(Icons.history_rounded), text: 'Histórico'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAbaAtual(context),
          _buildAbaNovaVersao(context),
          _buildAbaHistorico(context),
        ],
      ),
    );
  }

  Widget _buildAbaAtual(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _service.watchConfigApp(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};

        final versaoAtual = (data['versao_atual'] ?? 'Não definida').toString();
        final obrigatoria = data['atualizacao_obrigatoria'] == true;
        final minima =
        (data['versao_minima_obrigatoria'] ?? 'Não definida').toString();
        final apkPath = (data['apk_path'] ?? '').toString();
        final titulo =
        (data['titulo_atualizacao'] ?? 'Nova versão disponível').toString();
        final mensagem = (data['mensagem_atualizacao'] ?? '').toString();

        return _page(
          children: [
            _currentHero(
              versaoAtual: versaoAtual,
              obrigatoria: obrigatoria,
              minima: minima,
              apkPath: apkPath,
              titulo: titulo,
              mensagem: mensagem,
            ),
            const SizedBox(height: 14),
            _notificationPanel(
              versao: versaoAtual,
              obrigatoria: obrigatoria,
              titulo: titulo,
              mensagem: mensagem,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final cards = [
                  _metricCard(
                    icon: Icons.phone_android_rounded,
                    label: 'Versão publicada',
                    value: versaoAtual,
                    color: context.uai.primary,
                  ),
                  _metricCard(
                    icon: obrigatoria
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    label: 'Status',
                    value: obrigatoria ? 'Obrigatória' : 'Opcional',
                    color: obrigatoria ? context.uai.warning : context.uai.success,
                  ),
                  _metricCard(
                    icon: Icons.verified_user_rounded,
                    label: 'Versão mínima',
                    value: minima,
                    color: context.uai.info,
                  ),
                  _metricCard(
                    icon: Icons.folder_zip_rounded,
                    label: 'APK publicado',
                    value: apkPath.isEmpty ? 'Não informado' : apkPath,
                    color: context.uai.primary,
                  ),
                ];

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final card in cards)
                      SizedBox(
                        width: isWide ? (constraints.maxWidth - 10) / 2 : double.infinity,
                        child: card,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _premiumInfo(
              icon: Icons.auto_awesome_rounded,
              title: 'Próxima etapa do laboratório',
              text:
              'A publicação já atualiza configuracoes/app e cria histórico em versoes_app. Depois vamos ligar o botão de notificar usuários sobre a nova versão.',
              color: context.uai.info,
            ),
          ],
        );
      },
    );
  }


  Widget _notificationPanel({
    required String versao,
    required bool obrigatoria,
    required String titulo,
    required String mensagem,
  }) {
    final t = context.uai;
    final color = _ensureVisible(
      obrigatoria ? t.warning : t.primary,
      t.card,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: color.withOpacity(0.16)),
        boxShadow: t.softShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;

          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _softFill(color, t.cardAlt, 0.14),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: color.withOpacity(0.12)),
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notificar nova versão',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Envia push para os usuários ativos avisando que a versão $versao está disponível.',
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final button = ElevatedButton.icon(
            onPressed: _notificando
                ? null
                : () => _notificarUsuariosNovaVersao(
              versao: versao,
              obrigatoria: obrigatoria,
              titulo: titulo,
              mensagem: mensagem,
            ),
            icon: _notificando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _readableOn(color),
              ),
            )
                : const Icon(Icons.send_rounded),
            label: Text(_notificando ? 'Enviando...' : 'Notificar usuários'),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: _readableOn(color),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                button,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }

  Widget _currentHero({
    required String versaoAtual,
    required bool obrigatoria,
    required String minima,
    required String apkPath,
    required String titulo,
    required String mensagem,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final statusColor = _ensureVisible(
      obrigatoria ? t.warning : t.success,
      primary,
    );
    final onPrimary = _readableOn(primary);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.cardRadius + 8),
        boxShadow: t.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.cardRadius + 8),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primary,
                Color.alphaBlend(Colors.black.withOpacity(0.16), primary),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: onPrimary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(t.buttonRadius + 5),
                        border: Border.all(color: onPrimary.withOpacity(0.20)),
                      ),
                      child: Icon(
                        Icons.system_update_alt_rounded,
                        color: onPrimary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Laboratório de Atualizações',
                            style: TextStyle(
                              color: onPrimary,
                              fontSize: 21,
                              height: 1.08,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Publicação, APK, changelog, histórico e bloqueio obrigatório em um só lugar.',
                            style: TextStyle(
                              color: onPrimary.withOpacity(0.84),
                              height: 1.25,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: onPrimary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(t.cardRadius),
                    border: Border.all(color: onPrimary.withOpacity(0.16)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 560;

                      final version = _heroMiniData(
                        icon: Icons.tag_rounded,
                        label: 'VERSÃO',
                        value: versaoAtual,
                        color: onPrimary,
                      );

                      final status = _heroMiniData(
                        icon: obrigatoria
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        label: 'STATUS',
                        value: obrigatoria ? 'Obrigatória' : 'Opcional',
                        color: statusColor,
                      );

                      final apk = _heroMiniData(
                        icon: Icons.folder_zip_rounded,
                        label: 'APK',
                        value: apkPath.isEmpty ? 'Não informado' : 'Pronto',
                        color: onPrimary,
                      );

                      if (!wide) {
                        return Column(
                          children: [
                            version,
                            const SizedBox(height: 10),
                            status,
                            const SizedBox(height: 10),
                            apk,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: version),
                          const SizedBox(width: 10),
                          Expanded(child: status),
                          const SizedBox(width: 10),
                          Expanded(child: apk),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.campaign_rounded, color: onPrimary, size: 21),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '$titulo\n${mensagem.isEmpty ? "Nenhuma mensagem cadastrada." : mensagem}',
                        style: TextStyle(
                          color: onPrimary.withOpacity(0.90),
                          height: 1.28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroMiniData({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final onColor = _readableOn(color);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color.withOpacity(0.78),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaNovaVersao(BuildContext context) {
    final t = context.uai;
    final versaoDigitada = _versaoController.text.trim().isEmpty
        ? '2.0.61'
        : _versaoController.text.trim();

    return _page(
      children: [
        _formHero(),
        const SizedBox(height: 14),
        _sectionCard(
          title: 'Identificação da versão',
          icon: Icons.edit_note_rounded,
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 560;

                  final versaoField = _textField(
                    controller: _versaoController,
                    label: 'Versão',
                    hint: 'Ex: 2.0.61',
                    icon: Icons.numbers_rounded,
                    keyboardType: TextInputType.text,
                    onChanged: (value) {
                      final v = value.trim();
                      if (AppVersionModel.versaoValida(v)) {
                        _tituloController.text = 'Versão $v disponível';
                      }
                    },
                  );

                  final buildField = _textField(
                    controller: _buildController,
                    label: 'Build',
                    hint: 'Ex: 1',
                    icon: Icons.tag_rounded,
                    keyboardType: TextInputType.number,
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        versaoField,
                        const SizedBox(height: 10),
                        buildField,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 2, child: versaoField),
                      const SizedBox(width: 10),
                      Expanded(child: buildField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              _textField(
                controller: _tituloController,
                label: 'Título da atualização',
                hint: 'Ex: Versão 2.0.61 disponível',
                icon: Icons.title_rounded,
              ),
              const SizedBox(height: 10),
              _textField(
                controller: _resumoController,
                label: 'Resumo para o usuário',
                hint: 'Ex: Melhorias nas notificações e controle de atualização.',
                icon: Icons.short_text_rounded,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              _toggleObrigatoriaCard(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: 'Changelog da versão',
          icon: Icons.fact_check_rounded,
          child: Column(
            children: [
              _textField(
                controller: _implementacoesController,
                label: 'Implementações',
                hint: 'Uma implementação por linha',
                icon: Icons.add_circle_outline_rounded,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _textField(
                controller: _melhoriasController,
                label: 'Melhorias',
                hint: 'Uma melhoria por linha',
                icon: Icons.trending_up_rounded,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _textField(
                controller: _correcoesController,
                label: 'Correções',
                hint: 'Uma correção por linha',
                icon: Icons.bug_report_rounded,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _textField(
                controller: _removidosController,
                label: 'Removidos',
                hint: 'Algo removido por linha, se houver',
                icon: Icons.remove_circle_outline_rounded,
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _textField(
                controller: _observacoesController,
                label: 'Observações internas',
                hint: 'Notas para você ou para a equipe',
                icon: Icons.notes_rounded,
                maxLines: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: 'APK da versão',
          icon: Icons.android_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _premiumInfo(
                icon: Icons.drive_file_rename_outline_rounded,
                title: 'Renomeação automática',
                text:
                'Pode selecionar app-release.apk. O sistema salva no Storage como ${AppVersionModel.gerarNomeArquivo(versaoDigitada)}.',
                color: t.info,
              ),
              if (_statusUpload != null) ...[
                const SizedBox(height: 10),
                Text(
                  _statusUpload!,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (_enviandoApk) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _uploadProgress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildActionButtons(),
              if (_platformInfo.canRunLocalAutomation) ...[
                const SizedBox(height: 14),
                LocalPublishAutomationPanel(
                  platformInfo: _platformInfo,
                  state: _automationState ??
                      LocalPublishAutomationState.initial(
                        available: _platformInfo.canRunLocalAutomation,
                        platformLabel: _platformInfo.platformLabel,
                      ),
                  logText: _automationLogText,
                  canStart: !_automationRunning &&
                      !_salvando &&
                      !_enviandoApk &&
                      !_notificando,
                  onRunFullAutomation: _executarAutomacaoCompletaWindows,
                  onClearLog: _clearAutomationLog,
                ),
              ],
            ],
          ),
        ),
        if (_rascunhoAtual != null) ...[
          const SizedBox(height: 14),
          _versionCard(version: _rascunhoAtual!, onTap: null),
        ],
      ],
    );
  }

  Widget _formHero() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final onPrimary = _readableOn(primary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.alphaBlend(Colors.black.withOpacity(0.14), primary),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(t.cardRadius + 6),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius + 4),
              border: Border.all(color: onPrimary.withOpacity(0.18)),
            ),
            child: Icon(
              _obrigatoria ? Icons.lock_rounded : Icons.rocket_launch_rounded,
              color: onPrimary,
              size: 30,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              _obrigatoria
                  ? 'Preparando uma atualização obrigatória'
                  : 'Preparando uma atualização opcional',
              style: TextStyle(
                color: onPrimary,
                fontWeight: FontWeight.w900,
                height: 1.15,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleObrigatoriaCard() {
    final t = context.uai;
    final color = _ensureVisible(_obrigatoria ? t.warning : t.success, t.card);
    final fill = _softFill(color, t.card, 0.08);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(t.cardRadius),
      child: InkWell(
        onTap: () => setState(() => _obrigatoria = !_obrigatoria),
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: color.withOpacity(0.16)),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                child: Icon(
                  _obrigatoria ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: _readableOn(color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _obrigatoria
                          ? 'Atualização obrigatória'
                          : 'Atualização opcional',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _obrigatoria
                          ? 'Usuários antigos serão bloqueados até instalar a nova versão.'
                          : 'Usuários recebem aviso, mas podem continuar usando.',
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: _obrigatoria,
                onChanged: (value) => setState(() => _obrigatoria = value),
                activeColor: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 650;

        final salvar = OutlinedButton.icon(
          onPressed: _salvando ? null : _salvarRascunho,
          icon: _salvando
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.save_rounded),
          label: const Text('Salvar rascunho'),
        );

        final upload = OutlinedButton.icon(
          onPressed: _enviandoApk ? null : _selecionarEEnviarApk,
          icon: _enviandoApk
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.upload_file_rounded),
          label: const Text('Enviar APK'),
        );

        final publicar = ElevatedButton.icon(
          onPressed: _salvando || _enviandoApk ? null : _publicarRascunho,
          icon: const Icon(Icons.rocket_launch_rounded),
          label: Text(
            _obrigatoria ? 'Publicar obrigatória' : 'Publicar opcional',
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              salvar,
              const SizedBox(height: 8),
              upload,
              const SizedBox(height: 8),
              publicar,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: salvar),
            const SizedBox(width: 8),
            Expanded(child: upload),
            const SizedBox(width: 8),
            Expanded(child: publicar),
          ],
        );
      },
    );
  }

  Widget _buildAbaHistorico(BuildContext context) {
    final t = context.uai;

    return StreamBuilder<List<AppVersionModel>>(
      stream: _service.watchVersoes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: t.primary));
        }

        if (snapshot.hasError) {
          return _page(
            children: [
              _premiumInfo(
                icon: Icons.error_outline_rounded,
                title: 'Erro ao carregar histórico',
                text: '${snapshot.error}',
                color: t.error,
              ),
            ],
          );
        }

        final versoes = snapshot.data ?? [];

        if (versoes.isEmpty) {
          return _page(
            children: [
              _premiumInfo(
                icon: Icons.history_rounded,
                title: 'Nenhuma versão cadastrada',
                text:
                'Crie a primeira versão na aba Nova versão para iniciar o laboratório.',
                color: t.info,
              ),
            ],
          );
        }

        return _page(
          children: [
            _sectionTitle(
              icon: Icons.history_rounded,
              title: 'Histórico publicado',
              subtitle: '${versoes.length} versão(ões) cadastrada(s)',
            ),
            const SizedBox(height: 10),
            for (final version in versoes) ...[
              _versionCard(
                version: version,
                onTap: () => _carregarVersaoNoFormulario(version),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _page({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 640 ? 14.0 : 22.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final t = context.uai;

    return Row(
      children: [
        Icon(icon, color: t.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.13)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _softFill(accent, t.cardAlt, 0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: accent.withOpacity(0.12)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  Widget _premiumInfo({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _softFill(accent, t.card, 0.07),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    final t = context.uai;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(
        color: t.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: t.primary),
        filled: true,
        fillColor: t.cardAlt,
        labelStyle: TextStyle(color: t.textSecondary),
        hintStyle: TextStyle(color: t.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _versionCard({
    required AppVersionModel version,
    required VoidCallback? onTap,
  }) {
    final t = context.uai;
    final color = version.publicada
        ? (version.obrigatoria ? t.warning : t.success)
        : t.info;
    final accent = _ensureVisible(color, t.card);

    final criado = version.criadoEm == null
        ? 'Sem data'
        : '${version.criadoEm!.day.toString().padLeft(2, '0')}/'
        '${version.criadoEm!.month.toString().padLeft(2, '0')}/'
        '${version.criadoEm!.year}';

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: accent.withOpacity(0.16)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _softFill(accent, t.cardAlt, 0.14),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withOpacity(0.12)),
                ),
                child: Icon(
                  version.obrigatoria
                      ? Icons.lock_rounded
                      : version.publicada
                      ? Icons.verified_rounded
                      : Icons.edit_document,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${version.titulo}  •  ${version.statusLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'v${version.versao} • ${version.tamanhoFormatado} • $criado',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (version.resumo.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        version.resumo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.edit_rounded, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
