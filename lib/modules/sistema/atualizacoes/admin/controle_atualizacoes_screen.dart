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

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/app_update_admin_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/atualizacoes_callable_client.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/local_publish_automation_models.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_apk_file_loader_factory.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/release_notes_reader.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_base.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_factory.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/widgets/local_publish_automation_panel.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/release_v3_admin_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/widgets/release_v3_admin_panel.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/widgets/release_storage_admin_panel.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/admin/versao_detalhes_screen.dart';

class ControleAtualizacoesScreen extends StatefulWidget {
  const ControleAtualizacoesScreen({super.key});

  @override
  State<ControleAtualizacoesScreen> createState() =>
      _ControleAtualizacoesScreenState();
}

class _ControleAtualizacoesScreenState extends State<ControleAtualizacoesScreen>
    with TickerProviderStateMixin {
  static const String _permissaoControleAtualizacoes =
      'pode_controle_atualizacoes';

  final AppUpdateAdminService _service = AppUpdateAdminService();
  final ReleaseV3AdminService _v3Service = ReleaseV3AdminService();
  final PermissaoService _permissaoService = PermissaoService();
  final LocalPublishPlatformInfo _platformInfo =
      const LocalPublishPlatformService().getInfo();
  final StringBuffer _automationLogBuffer = StringBuffer();

  late final TabController _tabController;
  late final AnimationController _releaseFxController;

  LocalPublishAutomationState? _automationState;
  bool _automationRunning = false;
  String _automationLogText = '';

  final TextEditingController _versaoController = TextEditingController();
  final TextEditingController _buildController = TextEditingController(
    text: '1',
  );
  final TextEditingController _tituloController = TextEditingController();
  final TextEditingController _resumoController = TextEditingController();
  final TextEditingController _melhoriasController = TextEditingController();
  final TextEditingController _correcoesController = TextEditingController();
  final TextEditingController _implementacoesController =
      TextEditingController();
  final TextEditingController _removidosController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();
  final TextEditingController _historySearchController = TextEditingController();

  bool _obrigatoria = false;
  bool _salvando = false;
  bool _enviandoApk = false;
  bool _notificando = false;
  bool _verificandoAcesso = true;
  bool _acessoPermitido = false;
  double _uploadProgress = 0;
  String? _statusUpload;
  AppVersionModel? _rascunhoAtual;
  bool _usarVersaoAutomatica = true;
  LocalProjectVersionPlan? _versionPlan;
  bool _retomandoVersaoPendente = false;
  int _historyLimit = 24;
  static const int _historyPageSize = 24;
  String _releaseCanal = 'producao';
  String _audienciaModo = 'usuarios';
  final Set<String> _audienciaBetaUids = <String>{};
  final Set<String> _audienciaBetaGrupos = <String>{};
  String _historyCanal = 'todos';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _releaseFxController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _automationState = LocalPublishAutomationState.initial(
      available: _platformInfo.canRunLocalAutomation,
      platformLabel: _platformInfo.platformLabel,
    );
    _verificarAcesso();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _releaseFxController.dispose();
    _versaoController.dispose();
    _buildController.dispose();
    _tituloController.dispose();
    _resumoController.dispose();
    _melhoriasController.dispose();
    _correcoesController.dispose();
    _implementacoesController.dispose();
    _removidosController.dispose();
    _observacoesController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  Future<bool> _usuarioPodeAcessarControleAtualizacoes() async {
    if (await _permissaoService.usuarioAtualEhAdmin()) return true;
    return _permissaoService.temPermissao(_permissaoControleAtualizacoes);
  }

  Future<void> _verificarAcesso() async {
    final permitido = await _usuarioPodeAcessarControleAtualizacoes();

    if (!mounted) return;

    setState(() {
      _verificandoAcesso = false;
      _acessoPermitido = permitido;
    });

    if (permitido) {
      await _preencherProximaVersaoSugerida();
    }
  }

  Future<bool> _revalidarAcessoParaAcao() async {
    final permitido = await _usuarioPodeAcessarControleAtualizacoes();

    if (!mounted) return false;

    if (!permitido) {
      setState(() {
        _acessoPermitido = false;
        _verificandoAcesso = false;
      });

      _snack(
        'Você não tem permissão para acessar o Controle de Atualizações.',
        color: context.uai.error,
      );
    }

    return permitido;
  }

  Future<void> _preencherProximaVersaoSugerida() async {
    if (_platformInfo.canRunLocalAutomation) {
      final ok = await _carregarVersaoAutomaticaDoPubspec();
      if (ok) return;
    }

    try {
      final config = await _service.getConfigApp();
      final atual = (config['versao_atual'] ?? '2.0.60').toString();
      final proxima = _service.proximaVersaoPatch(atual);

      if (!mounted) return;

      _versaoController.text = proxima;
      final buildAtual = int.tryParse('${config['build_atual'] ?? ''}') ?? 0;
      final patchSugerido = int.tryParse(proxima.split('.').last) ?? 1;
      _buildController.text = '${buildAtual > 0 ? buildAtual + 1 : patchSugerido}';
      _tituloController.text = 'Versão $proxima disponível';
      _resumoController.text =
          'Melhorias no sistema de atualização e notificações.';
    } catch (_) {
      if (!mounted) return;

      _versaoController.text = '2.0.61';
      _buildController.text = '61';
      _tituloController.text = 'Versão 2.0.61 disponível';
      _resumoController.text =
          'Melhorias no sistema de atualização e notificações.';
    }
  }

  Future<bool> _carregarVersaoAutomaticaDoPubspec({
    bool mostrarSnack = false,
  }) async {
    if (!_platformInfo.canRunLocalAutomation) return false;

    try {
      final runner = getLocalPublishRunner();
      final plan = await runner.readProjectVersionPlan(
        projectDir: r'C:\Dev\projects\uai_capoeira',
      );
      if (plan == null || !mounted) return false;

      // REGRA V3.1: a numeração é GLOBAL entre produção/BETA/teste.
      // Exemplo: produção 146 -> BETA 147 -> produção 148.
      // configuracoes/app aponta somente para produção, portanto não pode ser
      // usado sozinho para decidir a próxima versão.
      final releases = await _service.listarVersoesParaSequenciamento();
      final config = await _service.getConfigApp();
      final productionVersion = (config['versao_atual'] ?? '').toString().trim();
      final productionBuild = int.tryParse('${config['build_atual'] ?? ''}') ?? 0;

      AppVersionModel? currentDoc;
      AppVersionModel? highestRegistered;
      var maxPublishedBuild = productionBuild;

      for (final release in releases) {
        if (release.versao == plan.currentVersion) currentDoc = release;
        if (highestRegistered == null ||
            AppVersionModel.compararVersoes(
                  highestRegistered.versao,
                  release.versao,
                ) ==
                1) {
          highestRegistered = release;
        }
        if (release.publicada && release.build > maxPublishedBuild) {
          maxPublishedBuild = release.build;
        }
      }

      String targetVersion;
      int targetBuild;
      var retomando = false;

      // Se o pubspec já aponta para uma release NÃO publicada, a automação
      // anterior provavelmente falhou depois de sincronizar o version:.
      // Nesse único caso retomamos exatamente a mesma versão/build.
      if (currentDoc != null && !currentDoc.publicada) {
        targetVersion = currentDoc.versao;
        targetBuild = currentDoc.build > 0 ? currentDoc.build : plan.currentBuild;
        retomando = true;
      } else {
        // Descobre a maior versão já consumida pela sequência global.
        var baseVersion = plan.currentVersion;
        if (highestRegistered != null &&
            AppVersionModel.compararVersoes(baseVersion, highestRegistered.versao) == 1) {
          baseVersion = highestRegistered.versao;
        }
        if (productionVersion.isNotEmpty &&
            AppVersionModel.compararVersoes(baseVersion, productionVersion) == 1) {
          baseVersion = productionVersion;
        }

        // Caso especial: pubspec foi avançado manualmente para um número que
        // ainda não existe no Firestore. Ele já é uma reserva válida e não
        // devemos pular mais uma versão.
        final pubspecIsUnregisteredAhead = currentDoc == null &&
            (highestRegistered == null ||
                AppVersionModel.compararVersoes(
                      highestRegistered.versao,
                      plan.currentVersion,
                    ) ==
                    1);

        if (pubspecIsUnregisteredAhead) {
          targetVersion = plan.currentVersion;
          targetBuild = plan.currentBuild > maxPublishedBuild
              ? plan.currentBuild
              : maxPublishedBuild + 1;
        } else {
          targetVersion = _service.proximaVersaoPatch(baseVersion);
          final maxKnownBuild = <int>[
            plan.currentBuild,
            highestRegistered?.build ?? 0,
            maxPublishedBuild,
            productionBuild,
          ].reduce((a, b) => a > b ? a : b);
          targetBuild = maxKnownBuild + 1;
        }
      }

      if (!mounted) return false;
      setState(() {
        _versionPlan = plan;
        _retomandoVersaoPendente = retomando;
        _usarVersaoAutomatica = true;
        _versaoController.text = targetVersion;
        _buildController.text = '$targetBuild';
        _tituloController.text = 'Versão $targetVersion disponível';
        if (_resumoController.text.trim().isEmpty) {
          _resumoController.text =
              'Melhorias no sistema de atualização e notificações.';
        }
      });

      if (mostrarSnack) {
        final highestLabel = highestRegistered?.versao ?? productionVersion;
        _snack(
          retomando
              ? 'Release pendente detectada: retomando $targetVersion+$targetBuild.'
              : 'Sequência global ${highestLabel.isEmpty ? plan.currentVersion : highestLabel} → $targetVersion+$targetBuild (${_releaseCanal.toUpperCase()}).',
          color: context.uai.success,
        );
      }
      return true;
    } catch (e) {
      if (mostrarSnack && mounted) {
        _snack(
          'Não foi possível calcular a próxima versão global: $e',
          color: context.uai.error,
        );
      }
      return false;
    }
  }


  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _softFill(Color color, Color base, [double opacity = 0.10]) {
    return Color.alphaBlend(color.withAlpha((255.0 * (opacity)).round()), base);
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
          style: TextStyle(color: _readableOn(bg), fontWeight: FontWeight.w800),
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

      await FirebaseFirestore.instance.enableNetwork().timeout(
        const Duration(seconds: 10),
      );

      await Future.delayed(const Duration(milliseconds: 350));

      if (registrarLogAutomacao) {
        _addAutomationLog('Firestore online. Continuando automação...');
      }
    } catch (e) {
      if (registrarLogAutomacao) {
        _addAutomationLog(
          'Aviso: não foi possível confirmar Firestore online: $e',
        );
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

  Future<AppVersionModel?> _salvarRascunhoInterno({
    bool mostrarSnack = true,
  }) async {
    final t = context.uai;
    final versao = _versaoController.text.trim();

    if (!await _revalidarAcessoParaAcao()) return null;

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
      canal: _releaseCanal,
    );

    if (_releaseCanal != 'producao') {
      await _v3Service.salvarAudiencia(
        versao: model.versao,
        canal: _releaseCanal,
        modo: _audienciaModo,
        uids: _audienciaBetaUids.toList(),
        grupos: _audienciaBetaGrupos.toList(),
      );
    }

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

    final t = context.uai;

    setState(() => _salvando = true);

    try {
      await _salvarRascunhoInterno();
    } catch (e) {
      _snack(
        'Erro ao salvar rascunho: ${_erroAmigavelAtualizacao(e)}',
        color: t.error,
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _selecionarEEnviarApk() async {
    if (_enviandoApk || _salvando) return;

    final t = context.uai;
    final versao = _versaoController.text.trim();

    if (!await _revalidarAcessoParaAcao()) return;

    if (!AppVersionModel.versaoValida(versao)) {
      _snack(
        'Informe a versão antes de enviar o APK. Ex: 2.0.61',
        color: t.error,
      );
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
      if (!await _revalidarAcessoParaAcao()) return;

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
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
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

  Future<bool?> _confirmarAutomacaoCompleta({required String canal}) {
    final t = context.uai;
    final versao = _versaoController.text.trim();
    final restrita = canal != 'producao';

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
            restrita ? 'Gerar release BETA restrita?' : 'Lançar release completa?',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          content: Text(
            restrita
                ? 'A Central vai gerar somente os APKs Android ARM32/ARM64/x86_64 da versão $versao, validar SHA-256, executar o Health Check e publicar no canal BETA apenas para a audiência selecionada.\n\nA produção atual, o PWA e o Windows NÃO serão substituídos.'
                : 'A Central vai sincronizar versão/build, publicar o PWA, gerar Android ARM32/ARM64/x86_64, organizar os APKs no Storage, gerar e instalar o Windows release e atualizar o atalho da Área de Trabalho.\n\nA notificação para os usuários NÃO será enviada automaticamente. Você testa primeiro e só depois notifica pelo botão da tela.',
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

  Future<void> _executarAutomacaoCompletaWindows({String canal = 'producao'}) async {
    if (_automationRunning || _salvando || _enviandoApk || _notificando) return;

    final t = context.uai;

    if (!await _revalidarAcessoParaAcao()) return;
    if (_usarVersaoAutomatica) {
      final carregou = await _carregarVersaoAutomaticaDoPubspec();
      if (!carregou) {
        _snack(
          'Não consegui ler a versão atual do pubspec.yaml. Use o modo manual ou confira o arquivo.',
          color: t.error,
        );
        return;
      }
    }

    final versao = _versaoController.text.trim();
    final build = int.tryParse(_buildController.text.trim()) ?? 0;
    _releaseCanal = canal;

    if (canal != 'producao' && _audienciaModo == 'usuarios' && _audienciaBetaUids.isEmpty) {
      final selected = await _selecionarAudienciaBeta();
      if (selected != true) return;
    }

    if (!_platformInfo.canRunLocalAutomation) {
      _snack('Central de Release local disponível apenas no Windows Desktop.', color: t.warning);
      return;
    }
    if (!AppVersionModel.versaoValida(versao) || build <= 0) {
      _snack('Informe versão e build válidos antes de publicar.', color: t.error);
      return;
    }

    // Guardrail de sequência: uma release publicada é imutável em relação a
    // versão/build/canal. Isso impede uma BETA 147 de ser sobrescrita por uma
    // produção 147. Depois de BETA 147, a próxima produção obrigatoriamente é
    // 148 (ou superior).
    final existingRelease = await _service.getVersaoPorId(
      AppVersionModel.gerarVersionId(versao),
    );
    if (existingRelease != null && existingRelease.publicada) {
      _snack(
        'A versão $versao já foi publicada no canal ${existingRelease.canalLabel}. Atualize a sugestão: a próxima release deve usar um número novo.',
        color: t.error,
      );
      await _carregarVersaoAutomaticaDoPubspec(mostrarSnack: true);
      return;
    }
    if (existingRelease != null &&
        existingRelease.canal != canal &&
        (existingRelease.androidArtifacts.isNotEmpty ||
            existingRelease.platformArtifacts.isNotEmpty)) {
      _snack(
        'A versão $versao já possui artefatos do canal ${existingRelease.canalLabel}. Para evitar conflito Android, use uma nova versão.',
        color: t.error,
      );
      return;
    }

    final releasesSequencia = await _service.listarVersoesParaSequenciamento();
    final maiorBuildPublicado = releasesSequencia
        .where((v) => v.publicada)
        .fold<int>(0, (max, v) => v.build > max ? v.build : max);
    if (existingRelease == null && build <= maiorBuildPublicado) {
      _snack(
        'Build $build já foi consumido. Android exige versionCode crescente. Use build ${maiorBuildPublicado + 1} ou superior.',
        color: t.error,
      );
      await _carregarVersaoAutomaticaDoPubspec(mostrarSnack: true);
      return;
    }

    final confirmar = await _confirmarAutomacaoCompleta(canal: canal);
    if (confirmar != true) return;
    _clearAutomationLog();

    setState(() {
      _automationRunning = true;
      _salvando = true;
      _automationState = LocalPublishAutomationState.initial(
        available: _platformInfo.canRunLocalAutomation,
        platformLabel: _platformInfo.platformLabel,
      ).copyWith(running: true, startedAt: DateTime.now(), clearError: true, clearFinalApkPath: true);
    });

    try {
      await _garantirFirestoreOnline(registrarLogAutomacao: true);
      _addAutomationLog('🚀 Preparando release UAI $versao+$build');
      final draft = await _salvarRascunhoInterno(mostrarSnack: false);
      if (draft == null) throw Exception('Não foi possível salvar o rascunho da versão.');
      if (!mounted) return;
      setState(() {
        _automationState = _automationState?.updateStep(
          stepId: 'save_draft', status: LocalPublishStepStatus.success,
          log: 'Release $versao+$build preparada.',
        );
        _salvando = false;
      });

      final runner = getLocalPublishRunner();

      // ==============================================================
      // 🚀 RELEASE EM BLOCOS INDEPENDENTES
      // ============================================================== 
      // PWA termina e fica publicado antes do Android.
      // Android termina, inicia o upload imediatamente e, em produção,
      // o Windows começa EM PARALELO. Assim o Storage não fica esperando
      // o build/ZIP/instalação do Windows para receber os APKs.
      const preparationStepIds = <String>{
        'preflight',
        'sync_version',
        'flutter_clean',
        'flutter_pub_get',
      };
      const pwaStepIds = <String>{'build_web', 'deploy_hosting'};
      const androidStepIds = <String>{
        'deploy_storage_rules',
        'build_android',
        'locate_apk',
      };
      const windowsStepIds = <String>{'build_windows', 'install_windows'};

      void mergeRunnerState(
        LocalPublishAutomationState incoming,
        Set<String> acceptedStepIds,
      ) {
        if (!mounted) return;
        final current = _automationState;
        if (current == null) {
          setState(() => _automationState = incoming);
          return;
        }
        final incomingById = <String, LocalPublishStep>{
          for (final step in incoming.steps) step.id: step,
        };
        setState(() {
          _automationState = current.copyWith(
            steps: current.steps.map<LocalPublishStep>((step) {
              if (!acceptedStepIds.contains(step.id)) return step;
              return incomingById[step.id] ?? step;
            }).toList(),
          );
        });
      }

      Future<LocalPublishRunnerResult> runBlock({
        required String label,
        required LocalPublishRunnerConfig config,
        required Set<String> acceptedStepIds,
      }) async {
        _addAutomationLog('');
        _addAutomationLog('━━━━━━━━━━ $label ━━━━━━━━━━');
        final result = await runner.run(
          config: config,
          onLog: _addAutomationLog,
          onState: (state) => mergeRunnerState(state, acceptedStepIds),
        );
        if (!result.success) {
          final detail = result.errorOutput.trim().isNotEmpty
              ? result.errorOutput.trim()
              : 'O bloco $label falhou.';
          throw Exception('$label: $detail');
        }
        _addAutomationLog('✅ $label concluído.');
        return result;
      }

      void markBlockSkipped(Set<String> ids, String reason) {
        if (!mounted) return;
        setState(() {
          var next = _automationState!;
          for (final id in ids) {
            next = next.updateStep(
              stepId: id,
              status: LocalPublishStepStatus.skipped,
              log: reason,
            );
          }
          _automationState = next;
        });
      }

      LocalPublishRunnerResult? pwaResult;
      if (canal == 'producao') {
        final pwaBlockResult = await runBlock(
          label: '🌐 BLOCO PWA',
          config: LocalPublishRunnerConfig(
            projectDir: r'C:\Dev\projects\uai_capoeira',
            scriptPath: r'C:\Dev\projects\uai_capoeira\tools\deploy_pwa_e_gerar_apk_uai.ps1',
            version: versao,
            build: build,
            deployPwa: true,
            buildAndroid: false,
            buildWindows: false,
          ),
          acceptedStepIds: {...preparationStepIds, ...pwaStepIds},
        );
        pwaResult = pwaBlockResult;

        // Registra o PWA assim que o bloco acaba. O Windows ainda nem precisa
        // ter começado para o histórico saber que o Hosting já está pronto.
        await _service.registrarPlataformasRelease(
          versao: versao,
          pwaPublicado: true,
          pwaTamanhoBytes: pwaBlockResult.pwaBuildSizeBytes,
          windowsGerado: false,
          windowsTamanhoBytes: 0,
        );
        _addAutomationLog('🌐 PWA já está publicado e disponível.');
      } else {
        markBlockSkipped(pwaStepIds, 'Canal BETA: PWA não é alterado.');
      }

      final androidResult = await runBlock(
        label: '🤖 BLOCO ANDROID',
        config: LocalPublishRunnerConfig(
          projectDir: r'C:\Dev\projects\uai_capoeira',
          scriptPath: r'C:\Dev\projects\uai_capoeira\tools\deploy_pwa_e_gerar_apk_uai.ps1',
          version: versao,
          build: build,
          deployPwa: false,
          buildAndroid: true,
          buildWindows: false,
          skipPrepare: canal == 'producao',
        ),
        acceptedStepIds: canal == 'producao'
            ? androidStepIds
            : {...preparationStepIds, ...androidStepIds},
      );

      const abiOrder = ['armeabi-v7a', 'arm64-v8a', 'x86_64'];
      if (!abiOrder.every(androidResult.androidApkPaths.containsKey)) {
        throw Exception('O bloco Android não retornou os três APKs esperados.');
      }

      // Em produção o Windows começa AGORA, mas não bloqueia o envio Android.
      // Enquanto ele compila/compacta/instala, os três APKs sobem ao Storage.
      Future<LocalPublishRunnerResult>? windowsFuture;
      if (canal == 'producao') {
        _addAutomationLog('🖥️ Iniciando Windows em paralelo ao upload Android...');
        _addAutomationLog('');
        _addAutomationLog('━━━━━━━━━━ 🖥️ BLOCO WINDOWS ━━━━━━━━━━');
        windowsFuture = runner.run(
          config: LocalPublishRunnerConfig(
            projectDir: r'C:\Dev\projects\uai_capoeira',
            scriptPath: r'C:\Dev\projects\uai_capoeira\tools\deploy_pwa_e_gerar_apk_uai.ps1',
            version: versao,
            build: build,
            deployPwa: false,
            buildAndroid: false,
            buildWindows: true,
            skipPrepare: true,
          ),
          onLog: _addAutomationLog,
          onState: (state) => mergeRunnerState(state, windowsStepIds),
        );
      } else {
        markBlockSkipped(windowsStepIds, 'Canal BETA: Windows não é alterado.');
      }

      // ==============================================================
      // 📦 ANDROID -> STORAGE IMEDIATAMENTE
      // ============================================================== 
      setState(() {
        _automationState = _automationState?.updateStep(
          stepId: 'upload_apk',
          status: LocalPublishStepStatus.running,
          log: 'Enviando APKs enquanto o bloco Windows continua em paralelo...',
        );
        _enviandoApk = true;
        _uploadProgress = 0;
        _statusUpload = 'Enviando Android multi-ABI...';
      });

      final apkLoader = getLocalApkFileLoader();
      AppVersionModel model = draft;
      for (var i = 0; i < abiOrder.length; i++) {
        final abi = abiOrder[i];
        final path = androidResult.androidApkPaths[abi]!;
        _addAutomationLog('📦 Lendo $abi: $path');
        final apk = await apkLoader.readApk(path);
        if (!apk.success || apk.bytes == null) {
          throw Exception(apk.errorMessage ?? 'Não foi possível ler o APK $abi.');
        }
        if (!await _revalidarAcessoParaAcao()) {
          throw Exception('Permissão administrativa removida durante a publicação.');
        }

        model = await _service.uploadAndroidArtifactBytes(
          versao: versao,
          architecture: abi,
          bytes: apk.bytes!,
          onProgress: (progress) {
            if (!mounted) return;
            final combined = (i + progress) / abiOrder.length;
            setState(() {
              _uploadProgress = combined;
              _statusUpload =
                  'Enviando $abi... ${(progress * 100).toStringAsFixed(0)}%';
            });
          },
        );
        _addAutomationLog('✅ $abi enviado ao Storage: ${apk.sizeFormatted}');
      }

      if (!mounted) return;
      setState(() {
        _rascunhoAtual = model;
        _enviandoApk = false;
        _uploadProgress = 1;
        _statusUpload = canal == 'producao'
            ? 'Android no Storage. Windows continua/finaliza em paralelo.'
            : '3 arquiteturas Android enviadas.';
        _automationState = _automationState?.updateStep(
          stepId: 'upload_apk',
          status: LocalPublishStepStatus.success,
          log: 'ARM32 + ARM64 + x86_64 já estão em releases/$versao/android/.',
        );
      });
      _addAutomationLog('🚀 Android já está disponível no Storage; não esperou o Windows.');

      // Só aguardamos o Windows daqui para frente porque o Health Check de
      // produção valida as três plataformas antes de publicar o manifesto.
      LocalPublishRunnerResult? windowsResult;
      if (windowsFuture != null) {
        windowsResult = await windowsFuture;
        if (!windowsResult.success) {
          final detail = windowsResult.errorOutput.trim().isNotEmpty
              ? windowsResult.errorOutput.trim()
              : 'O bloco Windows falhou.';
          throw Exception('🖥️ BLOCO WINDOWS: $detail');
        }
        _addAutomationLog('✅ 🖥️ BLOCO WINDOWS concluído.');
        model = await _service.registrarPlataformasRelease(
          versao: versao,
          pwaPublicado: true,
          pwaTamanhoBytes: pwaResult?.pwaBuildSizeBytes ?? 0,
          windowsGerado: windowsResult.windowsInstallDir.isNotEmpty ||
              windowsResult.windowsPackagePath.isNotEmpty,
          windowsTamanhoBytes: windowsResult.windowsPackageSizeBytes,
          windowsInstallDir: windowsResult.windowsInstallDir,
          windowsPackagePath: windowsResult.windowsPackagePath,
        );
        _addAutomationLog('📊 Windows registrado no histórico da release.');
      }

      _addAutomationLog('🩺 Executando Health Check da release antes da publicação...');
      final healthResult = await _v3Service.healthCheck(versao);
      final health = healthResult['health'] is Map
          ? Map<String, dynamic>.from(healthResult['health'] as Map)
          : const <String, dynamic>{};
      final healthOk = health['ok'] == true;
      final healthScore = (health['score'] as num?)?.toInt() ?? 0;
      if (!healthOk) {
        final issues = health['issues'] is List
            ? (health['issues'] as List)
                .whereType<Map>()
                .map((e) => (e['detail'] ?? e['id'] ?? 'Falha de validação').toString())
                .join(' • ')
            : 'Falha crítica detectada.';
        throw Exception('Health Check bloqueou a publicação ($healthScore%): $issues');
      }
      _addAutomationLog('✅ Health Check aprovado: $healthScore%.');

      if (!mounted) return;
      setState(() {
        _rascunhoAtual = model;
        _salvando = true;
        _automationState = _automationState?.updateStep(
          stepId: 'publish_version',
          status: LocalPublishStepStatus.running,
          log: 'Publicando manifesto final da release...',
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
        _automationRunning = false;
        _automationState = _automationState
            ?.updateStep(
              stepId: 'publish_version',
              status: LocalPublishStepStatus.success,
              log: 'Manifesto publicado com ${published.androidArtifacts.length} APKs Android.',
            )
            .updateStep(
              stepId: 'notify_users',
              status: LocalPublishStepStatus.skipped,
              log: 'Notificação manual para permitir teste antes do aviso geral.',
            )
            .copyWith(
              running: false,
              finalApkPath: androidResult.finalApkPath,
              finishedAt: DateTime.now(),
              clearError: true,
            );
      });

      if (canal == 'producao') _addAutomationLog('🌐 PWA publicado.');
      _addAutomationLog(
        canal == 'producao'
            ? '🤖 Android multi-ABI publicado.'
            : '🧪 BETA Android multi-ABI publicada apenas para a audiência selecionada.',
      );
      if (windowsResult != null && windowsResult.windowsInstallDir.isNotEmpty) {
        _addAutomationLog('🖥️ Windows instalado em: ${windowsResult.windowsInstallDir}');
        _addAutomationLog('🔗 Atalho da Área de Trabalho atualizado.');
      }
      _addAutomationLog('🔕 Usuários NÃO foram notificados automaticamente.');
      _snack(canal == 'producao' ? 'Release $versao+$build concluída: PWA + Android + Windows.' : 'BETA $versao+$build concluída e restrita aos testadores selecionados.', color: t.success);
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
      _snack(erroAmigavel, color: t.error);
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

    if (!await _revalidarAcessoParaAcao()) return;

    if (!AppVersionModel.versaoValida(versaoLimpa)) {
      _snack('Não foi possível notificar: versão inválida.', color: t.error);
      return;
    }

    final confirmar = await _confirmarNotificacaoVersao(
      versao: versaoLimpa,
      obrigatoria: obrigatoria,
    );

    if (confirmar != true) return;

    if (!await _revalidarAcessoParaAcao()) return;

    setState(() => _notificando = true);

    try {
      final data = await callNotifyNewAppVersion({
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

      final successCount = data['successCount'] ?? 0;
      final failureCount = data['failureCount'] ?? 0;
      final tokensEncontrados = data['tokensEncontrados'] ?? 0;

      if (!mounted) return;

      _snack(
        'Notificação enviada! Sucesso: $successCount | Falhas: $failureCount | Tokens: $tokensEncontrados',
        color: t.success,
      );
    } on FirebaseFunctionsException catch (e) {
      _snack('Erro na função: ${e.message ?? e.code}', color: t.error);
    } on AtualizacoesCallableException catch (e) {
      _snack('Erro ao notificar usuários: ${e.message}', color: t.error);
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
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
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

    if (!await _revalidarAcessoParaAcao()) return;

    if (versionId.isEmpty) {
      _snack('Informe uma versão válida.', color: t.error);
      return;
    }

    final confirmar = await _confirmarPublicacao();
    if (confirmar != true) return;

    setState(() => _salvando = true);

    try {
      await _salvarRascunhoInterno(mostrarSnack: false);

      if (!await _revalidarAcessoParaAcao()) return;

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
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
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

  Future<void> _abrirDetalhesVersao(AppVersionModel version) async {
    final acao = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VersaoDetalhesScreen(version: version),
      ),
    );

    if (!mounted) return;

    if (acao == 'editar') {
      _carregarVersaoNoFormulario(version);
    }
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
      _releaseCanal = version.canal;
      _statusUpload = version.temApk
          ? 'APK atual: ${version.nomeArquivo} (${version.tamanhoFormatado})'
          : null;
    });

    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAcesso) {
      return _buildLoadingAcesso();
    }

    if (!_acessoPermitido) {
      return _buildAcessoNegado();
    }

    final t = context.uai;

    if (_automationRunning) {
      return _buildAutomationFullscreen(context);
    }

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
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Colors.white.withAlpha(41),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withAlpha(51)),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withAlpha(184),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              tabs: const [
                Tab(height: 42, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.dashboard_rounded, size: 18, color: Colors.white), SizedBox(width: 7), Text('Dashboard', style: TextStyle(color: Colors.white))])),
                Tab(height: 42, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.rocket_launch_rounded, size: 18, color: Colors.white), SizedBox(width: 7), Text('Nova versão', style: TextStyle(color: Colors.white))])),
                Tab(height: 42, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_rounded, size: 18, color: Colors.white), SizedBox(width: 7), Text('Histórico', style: TextStyle(color: Colors.white))])),
                Tab(height: 42, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_rounded, size: 18, color: Colors.white), SizedBox(width: 7), Text('Storage', style: TextStyle(color: Colors.white))])),
                Tab(height: 42, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.hub_rounded, size: 18, color: Colors.white), SizedBox(width: 7), Text('V3', style: TextStyle(color: Colors.white))])),
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
          const ReleaseStorageAdminPanel(),
          const ReleaseV3AdminPanel(),
        ],
      ),
    );
  }

  Widget _buildAutomationFullscreen(BuildContext context) {
    final t = context.uai;
    final state = _automationState;
    final progress = state?.progress ?? 0;
    LocalPublishStep? current;
    for (final step in state?.steps ?? const <LocalPublishStep>[]) {
      if (step.status == LocalPublishStepStatus.running) { current = step; break; }
    }
    final completed = state?.steps.where((e) => e.status == LocalPublishStepStatus.success).length ?? 0;
    final total = state?.steps.length ?? 0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: t.background,
        body: AnimatedBuilder(
          animation: _releaseFxController,
          builder: (context, child) {
            final pulse = .5 + (_releaseFxController.value * .5);
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ReleaseGridPainter(
                        color: t.primary.withAlpha((255.0 * (.045 + .025 * pulse)).round()),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Transform.scale(
                              scale: .96 + .05 * pulse,
                              child: Container(
                                width: 82,
                                height: 82,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.primary.withAlpha(26),
                                  border: Border.all(color: t.primary.withAlpha(89), width: 2),
                                  boxShadow: [BoxShadow(color: t.primary.withAlpha((255.0 * (.12 + .10 * pulse)).round()), blurRadius: 32, spreadRadius: 6)],
                                ),
                                child: Icon(Icons.rocket_launch_rounded, size: 38, color: t.primary),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('UAI RELEASE ENGINE', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: 1.2)),
                            const SizedBox(height: 5),
                            Text('Não feche esta tela. A Central está sincronizando, compilando e publicando sua nova versão.', textAlign: TextAlign.center, style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(t.cardRadius), border: Border.all(color: t.primary.withAlpha(51)), boxShadow: t.softShadow),
                              child: Column(children: [
                                Row(children: [
                                  Expanded(child: Text(current?.title ?? 'Processando release...', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
                                  Text('${(progress * 100).toStringAsFixed(0)}%', style: TextStyle(color: t.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                                ]),
                                const SizedBox(height: 10),
                                ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 9, backgroundColor: t.cardAlt, color: t.primary)),
                                const SizedBox(height: 8),
                                Row(children: [Text('$completed de $total etapas concluídas', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)), const Spacer(), Text(current?.description ?? '', style: TextStyle(color: t.textMuted, fontWeight: FontWeight.w600, fontSize: 11))]),
                              ]),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: LayoutBuilder(builder: (context, c) {
                                final wide = c.maxWidth >= 820;
                                final steps = _automationStepsFuturistic(state);
                                final log = _automationLogFuturistic();
                                return wide
                                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 6, child: steps), const SizedBox(width: 12), Expanded(flex: 4, child: log)])
                                    : Column(children: [Expanded(flex: 6, child: steps), const SizedBox(height: 10), Expanded(flex: 4, child: log)]);
                              }),
                            ),
                            const SizedBox(height: 8),
                            Text('Navegação temporariamente bloqueada por segurança até a automação terminar.', style: TextStyle(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _automationStepsFuturistic(LocalPublishAutomationState? state) {
    final t = context.uai;
    final steps = state?.steps ?? const <LocalPublishStep>[];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.card.withAlpha(245), borderRadius: BorderRadius.circular(t.cardRadius), border: Border.all(color: t.border)),
      child: ListView.separated(
        itemCount: steps.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final step = steps[index];
          final color = step.status == LocalPublishStepStatus.success ? t.success : step.status == LocalPublishStepStatus.error ? t.error : step.status == LocalPublishStepStatus.running ? t.primary : t.textMuted;
          final icon = step.status == LocalPublishStepStatus.success ? Icons.check_circle_rounded : step.status == LocalPublishStepStatus.error ? Icons.error_rounded : step.status == LocalPublishStepStatus.running ? Icons.sync_rounded : Icons.radio_button_unchecked_rounded;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(color: step.status == LocalPublishStepStatus.running ? color.withAlpha(20) : t.cardAlt.withAlpha(140), borderRadius: BorderRadius.circular(12), border: Border.all(color: step.status == LocalPublishStepStatus.running ? color.withAlpha(77) : t.border.withAlpha(179))),
            child: Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(step.title, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 12.5)), if ((step.log ?? '').trim().isNotEmpty) Text(step.log!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600, fontSize: 10.5))])), Text(step.status.label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10))]),
          );
        },
      ),
    );
  }

  Widget _automationLogFuturistic() {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.card.withAlpha(245), borderRadius: BorderRadius.circular(t.cardRadius), border: Border.all(color: t.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.terminal_rounded, color: t.primary, size: 18), const SizedBox(width: 7), Text('Telemetria da release', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 12.5))]),
        const SizedBox(height: 8),
        Expanded(child: SingleChildScrollView(reverse: true, child: SelectableText(_automationLogText.trim().isEmpty ? 'Aguardando telemetria...' : _automationLogText, style: TextStyle(color: t.textSecondary, fontFamily: 'monospace', fontSize: 10.5, height: 1.35)))),
      ]),
    );
  }

  Widget _buildLoadingAcesso() {
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
      ),
      body: Center(child: CircularProgressIndicator(color: t.primary)),
    );
  }

  Widget _buildAcessoNegado() {
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
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, color: t.error, size: 52),
                const SizedBox(height: 12),
                Text(
                  'Você não tem permissão para acessar o Controle de Atualizações.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: Navigator.of(context).canPop()
                      ? () => Navigator.of(context).pop()
                      : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
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
        final minima = (data['versao_minima_obrigatoria'] ?? 'Não definida')
            .toString();
        final apkPath = (data['apk_path'] ?? '').toString();
        final platformArtifactsRaw = data['platform_artifacts'];
        final platformArtifacts = platformArtifactsRaw is Map
            ? Map<String, dynamic>.from(platformArtifactsRaw)
            : <String, dynamic>{};
        final pwaData = platformArtifacts['pwa'] is Map
            ? Map<String, dynamic>.from(platformArtifacts['pwa'] as Map)
            : <String, dynamic>{};
        final windowsData = platformArtifacts['windows'] is Map
            ? Map<String, dynamic>.from(platformArtifacts['windows'] as Map)
            : <String, dynamic>{};
        final titulo = (data['titulo_atualizacao'] ?? 'Nova versão disponível')
            .toString();
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
                    color: obrigatoria
                        ? context.uai.warning
                        : context.uai.success,
                  ),
                  _metricCard(
                    icon: Icons.verified_user_rounded,
                    label: 'Versão mínima',
                    value: minima,
                    color: context.uai.info,
                  ),
                  _metricCard(
                    icon: Icons.android_rounded,
                    label: 'Android',
                    value: apkPath.isEmpty ? 'Não informado' : 'Publicado',
                    color: context.uai.success,
                  ),
                  _metricCard(
                    icon: Icons.language_rounded,
                    label: 'PWA',
                    value: pwaData['publicado'] == true ? 'Publicado' : 'Sem metadados',
                    color: context.uai.info,
                  ),
                  _metricCard(
                    icon: Icons.desktop_windows_rounded,
                    label: 'Windows',
                    value: windowsData['gerado'] == true || windowsData['instalado'] == true
                        ? 'Gerado'
                        : 'Sem metadados',
                    color: context.uai.primary,
                  ),
                ];

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final card in cards)
                      SizedBox(
                        width: isWide
                            ? (constraints.maxWidth - 10) / 2
                            : double.infinity,
                        child: card,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _premiumInfo(
              icon: Icons.auto_awesome_rounded,
              title: 'Central de releases 2.0',
              text:
                  'O dashboard acompanha Android, PWA e Windows. A aba Storage mostra o consumo real das releases, permite limpeza manual e controla o robô diário de retenção com auditoria.',
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
    final color = _ensureVisible(obrigatoria ? t.warning : t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: color.withAlpha(41)),
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
                  border: Border.all(color: color.withAlpha(31)),
                ),
                child: Icon(Icons.notifications_active_rounded, color: color),
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
              children: [info, const SizedBox(height: 12), button],
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
                Color.alphaBlend(Colors.black.withAlpha(41), primary),
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
                        color: onPrimary.withAlpha(36),
                        borderRadius: BorderRadius.circular(t.buttonRadius + 5),
                        border: Border.all(color: onPrimary.withAlpha(51)),
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
                              color: onPrimary.withAlpha(214),
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
                    color: onPrimary.withAlpha(26),
                    borderRadius: BorderRadius.circular(t.cardRadius),
                    border: Border.all(color: onPrimary.withAlpha(41)),
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
                          color: onPrimary.withAlpha(230),
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

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(31),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: Colors.white.withAlpha(36)),
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
                    color: color.withAlpha(199),
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

  Future<bool?> _selecionarAudienciaBeta() async {
    final t = context.uai;
    try {
      final users = await _v3Service.listarUsuarios();
      final groups = await _v3Service.listarGrupos();
      if (!mounted) return false;
      final selected = Set<String>.from(_audienciaBetaUids);
      final selectedGroups = Set<String>.from(_audienciaBetaGrupos);
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            backgroundColor: t.surface,
            surfaceTintColor: Colors.transparent,
            title: const Row(children: [Icon(Icons.science_rounded), SizedBox(width: 8), Text('Audiência da BETA')]),
            content: SizedBox(
              width: 680,
              height: 560,
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'usuarios', icon: Icon(Icons.person_search_rounded), label: Text('Usuários')),
                      ButtonSegment(value: 'grupos', icon: Icon(Icons.groups_rounded), label: Text('Grupos')),
                      ButtonSegment(value: 'todos_testadores', icon: Icon(Icons.science_rounded), label: Text('Todos testadores')),
                    ],
                    selected: {_audienciaModo},
                    onSelectionChanged: (v) => setLocal(() => _audienciaModo = v.first),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _audienciaModo == 'grupos'
                        ? ListView.builder(
                            itemCount: groups.length,
                            itemBuilder: (_, i) {
                              final g = groups[i]; final id = '${g['id'] ?? ''}';
                              return CheckboxListTile(
                                value: selectedGroups.contains(id),
                                onChanged: (_) => setLocal(() => selectedGroups.contains(id) ? selectedGroups.remove(id) : selectedGroups.add(id)),
                                title: Text('${g['nome'] ?? id}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text('${g['quantidadeMembros'] ?? 0} membro(s)'),
                              );
                            },
                          )
                        : _audienciaModo == 'todos_testadores'
                            ? const Center(child: Text('A BETA aparecerá para todos os usuários marcados como testadores internos.', textAlign: TextAlign.center))
                            : ListView.builder(
                                itemCount: users.length,
                                itemBuilder: (_, i) {
                                  final u = users[i]; final uid = '${u['uid'] ?? ''}';
                                  return CheckboxListTile(
                                    value: selected.contains(uid),
                                    onChanged: (_) => setLocal(() => selected.contains(uid) ? selected.remove(uid) : selected.add(uid)),
                                    title: Text('${u['nome'] ?? 'Sem nome'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    subtitle: Text('${u['email'] ?? ''}${u['testador'] == true ? ' • TESTADOR' : ''}'),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
              FilledButton.icon(onPressed: () { _audienciaBetaUids..clear()..addAll(selected); _audienciaBetaGrupos..clear()..addAll(selectedGroups); Navigator.pop(dialogContext, true); }, icon: const Icon(Icons.check_rounded), label: const Text('Usar audiência')),
            ],
          ),
        ),
      );
      if (mounted) setState(() {});
      return result;
    } catch (e) {
      _snack('Erro ao carregar audiência: ${ReleaseV3AdminService.friendlyError(e)}', color: t.error);
      return false;
    }
  }

  Widget _buildReleaseChannelCard() {
    final t = context.uai;
    final beta = _releaseCanal == 'beta';
    return _sectionCard(
      title: 'Canal e distribuição',
      icon: Icons.hub_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'producao', icon: Icon(Icons.public_rounded), label: Text('Produção')),
              ButtonSegment(value: 'beta', icon: Icon(Icons.science_rounded), label: Text('BETA')),
              ButtonSegment(value: 'teste_interno', icon: Icon(Icons.engineering_rounded), label: Text('Teste interno')),
            ],
            selected: {_releaseCanal},
            onSelectionChanged: (value) => setState(() => _releaseCanal = value.first),
          ),
          if (_releaseCanal != 'producao') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.warning.withAlpha(20), borderRadius: BorderRadius.circular(t.cardRadius), border: Border.all(color: t.warning.withAlpha(56))),
              child: Row(children: [Icon(Icons.science_rounded, color: t.warning), const SizedBox(width: 10), Expanded(child: Text(beta ? 'BETA: não altera a produção geral. Só os usuários/grupos escolhidos recebem esta versão.' : 'TESTE INTERNO: distribuição restrita e destacada como experimental.', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w700))), const SizedBox(width: 8), OutlinedButton.icon(onPressed: _selecionarAudienciaBeta, icon: const Icon(Icons.group_add_rounded), label: Text(_audienciaModo == 'usuarios' ? '${_audienciaBetaUids.length} usuário(s)' : _audienciaModo == 'grupos' ? '${_audienciaBetaGrupos.length} grupo(s)' : 'Testadores'))]),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _importarNotasDoProjeto() async {
    try {
      final notas = await lerNotasReleaseProjeto();
      if (!mounted) return;
      if (notas == null) {
        _snack('Manifesto nao encontrado. Execute a Central na pasta do projeto ou confira release_notes/proxima_versao.json.', color: context.uai.warning);
        return;
      }
      String texto(String campo) => ((notas[campo] as List).cast<String>()).join('\n');
      setState(() {
        _resumoController.text = (notas['resumo'] as String? ?? '').trim();
        _implementacoesController.text = texto('implementacoes');
        _melhoriasController.text = texto('melhorias');
        _correcoesController.text = texto('correcoes');
        _removidosController.text = texto('removidos');
        _observacoesController.text = texto('observacoes_internas');
      });
      _snack('Notas importadas. Revise o texto antes de publicar.', color: context.uai.success);
    } catch (e) {
      if (mounted) _snack('Falha ao ler notas: $e', color: context.uai.error);
    }
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
        _buildReleaseChannelCard(),
        const SizedBox(height: 14),
        if (_platformInfo.canRunLocalAutomation) ...[
          _sectionCard(
            title: 'Notas automáticas da próxima versão',
            icon: Icons.auto_awesome_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('O gerador ZIP leva o manifesto para as IAs. Depois de aplicar os patches, importe as notas locais e revise antes de lançar.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _automationRunning || _salvando ? null : _importarNotasDoProjeto,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Importar notas do projeto'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _sectionCard(
          title: 'Identificação da versão',
          icon: Icons.edit_note_rounded,
          child: Column(
            children: [
              if (_platformInfo.canRunLocalAutomation) ...[
                _versionAutomationCard(),
                const SizedBox(height: 12),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 560;

                  final versaoField = _textField(
                    controller: _versaoController,
                    label: 'Versão',
                    hint: 'Ex: 2.0.61',
                    icon: Icons.numbers_rounded,
                    keyboardType: TextInputType.text,
                    readOnly: _usarVersaoAutomatica && _platformInfo.canRunLocalAutomation,
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
                    readOnly: _usarVersaoAutomatica && _platformInfo.canRunLocalAutomation,
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
                hint:
                    'Ex: Melhorias nas notificações e controle de atualização.',
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
                  state:
                      _automationState ??
                      LocalPublishAutomationState.initial(
                        available: _platformInfo.canRunLocalAutomation,
                        platformLabel: _platformInfo.platformLabel,
                      ),
                  logText: _automationLogText,
                  canStart:
                      !_automationRunning &&
                      !_salvando &&
                      !_enviandoApk &&
                      !_notificando,
                  onRunFullAutomation: () => _executarAutomacaoCompletaWindows(canal: 'producao'),
                  onRunBetaAutomation: () => _executarAutomacaoCompletaWindows(canal: 'beta'),
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

  Widget _versionAutomationCard() {
    final t = context.uai;
    final plan = _versionPlan;
    final accent = _ensureVisible(t.info, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _softFill(accent, t.card, 0.07),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withAlpha(38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_mode_rounded, color: accent),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versão automática pelo pubspec.yaml',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan == null
                          ? 'A Central lê a versão real do projeto antes da publicação.'
                          : _retomandoVersaoPendente
                              ? 'Release pendente: mantendo ${_versaoController.text}+${_buildController.text}'
                              : '${plan.currentFullVersion}  →  ${_versaoController.text}+${_buildController.text}',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _usarVersaoAutomatica,
                onChanged: (value) async {
                  setState(() => _usarVersaoAutomatica = value);
                  if (value) {
                    await _carregarVersaoAutomaticaDoPubspec();
                  }
                },
              ),
            ],
          ),
          if (_usarVersaoAutomatica) ...[
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: () => _carregarVersaoAutomaticaDoPubspec(mostrarSnack: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reler versão do pubspec.yaml'),
            ),
          ] else ...[
            const SizedBox(height: 7),
            Text(
              'Modo manual ativo: use para saltos como 2.0.x → 2.1.0 ou 3.0.0.',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
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
            Color.alphaBlend(Colors.black.withAlpha(36), primary),
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
              color: onPrimary.withAlpha(36),
              borderRadius: BorderRadius.circular(t.buttonRadius + 4),
              border: Border.all(color: onPrimary.withAlpha(46)),
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
            border: Border.all(color: color.withAlpha(41)),
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
                activeThumbColor: switch (Theme.of(context).platform) {
                  TargetPlatform.iOS || TargetPlatform.macOS => null,
                  _ => color,
                },
                activeTrackColor: switch (Theme.of(context).platform) {
                  TargetPlatform.iOS || TargetPlatform.macOS => color,
                  _ => null,
                },
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
      stream: _service.watchVersoes(limit: _historyLimit),
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

        final versoesTodas = snapshot.data ?? [];
        final busca = _historySearchController.text.trim().toLowerCase();
        final versoes = versoesTodas.where((v) {
          final canalOk = _historyCanal == 'todos' || v.canal == _historyCanal;
          final texto = '${v.versao} ${v.titulo} ${v.resumo} ${v.canal}'.toLowerCase();
          final buscaOk = busca.isEmpty || texto.contains(busca);
          return canalOk && buscaOk;
        }).toList();

        if (versoesTodas.isEmpty) {
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

        final content = _page(
          children: [
            _sectionTitle(
              icon: Icons.history_rounded,
              title: 'Histórico publicado',
              subtitle: '${versoes.length} versão(ões) carregada(s) • paginação silenciosa',
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final search = TextField(
                  controller: _historySearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Buscar versão, título ou descrição',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                );
                final channel = DropdownButtonFormField<String>(
                  initialValue: _historyCanal,
                  decoration: const InputDecoration(labelText: 'Canal', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'producao', child: Text('Produção')),
                    DropdownMenuItem(value: 'beta', child: Text('BETA')),
                    DropdownMenuItem(value: 'teste_interno', child: Text('Teste interno')),
                  ],
                  onChanged: (v) => setState(() => _historyCanal = v ?? 'todos'),
                );
                if (constraints.maxWidth < 700) {
                  return Column(children: [search, const SizedBox(height: 8), channel]);
                }
                return Row(children: [Expanded(flex: 3, child: search), const SizedBox(width: 8), Expanded(child: channel)]);
              },
            ),
            const SizedBox(height: 10),
            if (versoes.isEmpty)
              _premiumInfo(icon: Icons.filter_alt_off_rounded, title: 'Nenhuma release com esses filtros', text: 'Limpe a busca ou altere o canal.', color: t.info)
            else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1180
                    ? 3
                    : constraints.maxWidth >= 760
                        ? 2
                        : 1;
                final gap = 10.0;
                final width = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final version in versoes)
                      SizedBox(
                        width: width,
                        child: _versionCard(
                          version: version,
                          onTap: () => _abrirDetalhesVersao(version),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 520 && versoes.length >= _historyLimit) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && versoes.length >= _historyLimit) {
                  setState(() => _historyLimit += _historyPageSize);
                }
              });
            }
            return false;
          },
          child: content,
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
                constraints: const BoxConstraints(maxWidth: 1480),
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
        border: Border.all(color: accent.withAlpha(33)),
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
              border: Border.all(color: accent.withAlpha(31)),
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
        border: Border.all(color: accent.withAlpha(36)),
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
    bool readOnly = false,
  }) {
    final t = context.uai;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      readOnly: readOnly,
      onChanged: onChanged,
      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final mb = bytes / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  Widget _releasePlatformBadge(IconData icon, String label, Color color) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(46)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: t.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ]),
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
            border: Border.all(color: accent.withAlpha(41)),
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
                  border: Border.all(color: accent.withAlpha(31)),
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
                      'v${version.versao} • Android ${_formatBytes(version.tamanhoAndroidTotal > 0 ? version.tamanhoAndroidTotal : version.tamanhoBytes)} • $criado',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (version.isBeta)
                          _releasePlatformBadge(Icons.science_rounded, 'BETA', t.warning),
                        if (version.isTesteInterno)
                          _releasePlatformBadge(Icons.science_outlined, 'TESTE INTERNO', t.info),
                        if (version.temApk || version.androidArtifacts.isNotEmpty)
                          _releasePlatformBadge(Icons.android_rounded, 'Android', t.success),
                        if (version.pwaPublicado)
                          _releasePlatformBadge(Icons.language_rounded, 'PWA', t.info),
                        if (version.windowsGerado)
                          _releasePlatformBadge(Icons.desktop_windows_rounded, 'Windows', t.primary),
                        _releasePlatformBadge(Icons.download_rounded, '${version.totalDownloads} downloads', t.info),
                        _releasePlatformBadge(Icons.system_update_alt_rounded, '${version.totalInstalacoes} instalações', t.primary),
                      ],
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
                Icon(Icons.chevron_right_rounded, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _ReleaseGridPainter extends CustomPainter {
  final Color color;
  const _ReleaseGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    const gap = 34.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReleaseGridPainter oldDelegate) => oldDelegate.color != color;
}
