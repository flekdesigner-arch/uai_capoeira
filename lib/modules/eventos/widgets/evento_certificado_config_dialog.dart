import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_slot_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_studio_model.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_import_service.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_service.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_studio_validator_service.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_template_repository.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/certificados/widgets/certificado_preview_widget.dart';
import 'package:uai_capoeira/modules/certificados/widgets/certificado_action_feedback.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_file_share_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_pdf_direto_service.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

class EventoCertificadoConfigDialog extends StatefulWidget {
  final ConfiguracoesCertificadoEvento configuracaoInicial;

  /// Quando true, o Studio foi aberto pela área global "Configurar Certificados".
  /// Nesse modo o botão principal salva na biblioteca de templates, e não tenta
  /// devolver configuração para um evento inexistente.
  final bool modoBiblioteca;

  const EventoCertificadoConfigDialog({
    super.key,
    required this.configuracaoInicial,
    this.modoBiblioteca = false,
  });

  static Future<ConfiguracoesCertificadoEvento?> show({
    required BuildContext context,
    required ConfiguracoesCertificadoEvento configuracaoInicial,
    bool modoBiblioteca = false,
  }) {
    return Navigator.of(context).push<ConfiguracoesCertificadoEvento>(
      MaterialPageRoute<ConfiguracoesCertificadoEvento>(
        fullscreenDialog: true,
        builder: (_) => EventoCertificadoConfigDialog(
          configuracaoInicial: configuracaoInicial,
          modoBiblioteca: modoBiblioteca,
        ),
      ),
    );
  }

  @override
  State<EventoCertificadoConfigDialog> createState() =>
      _EventoCertificadoConfigDialogState();
}

class _EventoCertificadoConfigDialogState
    extends State<EventoCertificadoConfigDialog> {
  // Atualiza somente a prévia quando nomes/cargos das assinaturas mudam.
  // Evita reconstruir o Dialog inteiro a cada tecla no Windows, o que pode
  // causar corrida de hit-test/MouseTracker durante eventos do mouse.
  final ValueNotifier<int> _assinaturasPreviewRevision = ValueNotifier<int>(0);

  late bool _ativo;
  late String _modeloPadrao;
  late bool _usarCidadeDoEvento;
  late bool _usarDataDoEvento;
  late Map<String, CertificadoTextoCampoConfig> _textos;
  late CertificadoVisualConfig _visual;
  late CertificadoStudioConfig _studio;
  bool _importandoSvg = false;
  String? _selectedLayerId;
  String? _selectedTextId;
  bool _qrSelected = false;
  int _mobileStudioPane = 0;

  bool get _podeImportarSvgCorel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  final CertificadoFileShareService _fileShareService =
      const CertificadoFileShareService();
  final CertificadoPdfDiretoService _pdfDiretoService =
      CertificadoPdfDiretoService();
  final CertificadoSvgImportService _svgImportService = CertificadoSvgImportService();
  final CertificadoSvgService _svgService = const CertificadoSvgService();
  final CertificadoTemplateRepository _templateRepository = CertificadoTemplateRepository();
  final CertificadoStudioValidatorService _validator = const CertificadoStudioValidatorService();
  bool _compartilhandoPreview = false;

  late final List<TextEditingController> _nomeControllers;
  late final List<TextEditingController> _apelidoControllers;

  final List<_ModeloCertificadoOption> _modelos = const [
    _ModeloCertificadoOption(
      id: ConfiguracoesCertificadoEvento.modeloAutomatico,
      title: 'Automático pela graduação',
      subtitle:
          'Usa CERTIFICADO, CERTIFICADO COM CPF ou DIPLOMA conforme a graduação do aluno.',
      icon: Icons.auto_awesome_rounded,
    ),
    _ModeloCertificadoOption(
      id: 'CERTIFICADO',
      title: 'Forçar certificado simples',
      subtitle: 'Usa o modelo sem CPF para todos os participantes.',
      icon: Icons.card_membership_rounded,
    ),
    _ModeloCertificadoOption(
      id: 'CERTIFICADOCOMCPF',
      title: 'Forçar certificado com CPF',
      subtitle: 'Usa o modelo com CPF para todos os participantes.',
      icon: Icons.badge_rounded,
    ),
    _ModeloCertificadoOption(
      id: 'DIPLOMA',
      title: 'Forçar diploma',
      subtitle: 'Usa o modelo de diploma para todos os participantes.',
      icon: Icons.history_edu_rounded,
    ),
  ];

  final List<_CampoTextoOption> _camposTexto = const [
    _CampoTextoOption(
      id: CertificadoTextoCampoConfig.campoNome,
      title: 'Nome do aluno',
      subtitle: 'Texto principal abaixo do título do certificado.',
      icon: Icons.person_rounded,
    ),
    _CampoTextoOption(
      id: CertificadoTextoCampoConfig.campoCpf,
      title: 'CPF',
      subtitle: 'Linha do CPF nos modelos com CPF e diploma.',
      icon: Icons.badge_rounded,
    ),
    _CampoTextoOption(
      id: CertificadoTextoCampoConfig.campoGraduacao,
      title: 'Graduação',
      subtitle: 'Texto da graduação ou título recebido.',
      icon: Icons.workspace_premium_rounded,
    ),
    _CampoTextoOption(
      id: CertificadoTextoCampoConfig.campoFrase,
      title: 'Frase',
      subtitle:
          'Texto principal do certificado. Permite espaçamento entre linhas.',
      icon: Icons.notes_rounded,
      mostrarLineHeight: true,
      autoAjustarEditavel: false,
    ),
    _CampoTextoOption(
      id: CertificadoTextoCampoConfig.campoAssinaturaNome,
      title: 'Nome das assinaturas',
      subtitle: 'Nomes dos mestres/professores na parte inferior.',
      icon: Icons.draw_rounded,
    ),
    _CampoTextoOption(
      id: CertificadoTextoCampoConfig.campoAssinaturaApelido,
      title: 'Cargo/apelido das assinaturas',
      subtitle: 'Texto entre parênteses abaixo de cada assinatura.',
      icon: Icons.military_tech_rounded,
    ),
    _CampoTextoOption(
      id: CertificadoTextoCampoConfig.campoLocalData,
      title: 'Local e data',
      subtitle: 'Texto final com cidade e data do evento.',
      icon: Icons.event_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();

    final config = widget.configuracaoInicial;
    final assinaturas = config.assinaturasPorSlot;

    _ativo = config.ativo;
    _modeloPadrao = config.modeloPadrao;
    _usarCidadeDoEvento = config.usarCidadeDoEvento;
    _usarDataDoEvento = config.usarDataDoEvento;
    _textos = Map<String, CertificadoTextoCampoConfig>.from(config.textos);
    _visual = config.visual;
    _studio = config.studio;

    _nomeControllers = List.generate(
      5,
      (index) => TextEditingController(text: assinaturas[index].nome),
    );

    _apelidoControllers = List.generate(
      5,
      (index) => TextEditingController(text: assinaturas[index].apelido),
    );
  }

  @override
  void dispose() {
    _assinaturasPreviewRevision.dispose();
    for (final controller in _nomeControllers) {
      controller.dispose();
    }
    for (final controller in _apelidoControllers) {
      controller.dispose();
    }
    super.dispose();
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

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  Color _colorFromHex(
    String? hexColor, {
    Color fallback = const Color(0xFF1A0202),
  }) {
    if (hexColor == null || hexColor.trim().isEmpty) return fallback;

    try {
      final cleaned = hexColor.replaceAll('#', '').trim();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }

  Future<void> _pickTextoColor({
    required String titulo,
    required Color corAtual,
    required ValueChanged<Color> onColorChanged,
  }) async {
    Color pickedColor = corAtual;
    final hexController = TextEditingController(text: _colorToHex(corAtual));

    await showDialog<void>(
      context: context,
      builder: (context) {
        final t = context.uai;
        final accent = _ensureVisible(t.primary, t.surface);

        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setDialogState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: accent.withAlpha(31),
                              borderRadius: BorderRadius.circular(
                                t.buttonRadius,
                              ),
                            ),
                            child: Icon(Icons.palette_rounded, color: accent),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              titulo,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: hexController,
                        textCapitalization: TextCapitalization.characters,
                        style: TextStyle(color: t.textPrimary),
                        decoration: _inputDecoration(
                          label: 'Código HEX',
                          hint: '#RRGGBB',
                          icon: Icons.tag_rounded,
                        ),
                        onChanged: (value) {
                          if (value.trim().length >= 7) {
                            final color = _colorFromHex(
                              value,
                              fallback: pickedColor,
                            );
                            setDialogState(() => pickedColor = color);
                            setState(() => onColorChanged(color));
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: t.cardAlt,
                          borderRadius: BorderRadius.circular(t.cardRadius),
                          border: Border.all(color: t.border),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // flutter_colorpicker usa uma Row interna relativamente
                            // larga. No Windows, dentro de dialogs estreitos, isso
                            // estourava horizontalmente. Mantemos uma área-base
                            // confortável e reduzimos visualmente quando necessário.
                            // O flutter_colorpicker 1.1.0 monta internamente uma Row que
                            // precisa de ~640 px antes de qualquer transformação visual.
                            // Se a base for menor, o RenderFlex acusa overflow mesmo que
                            // o FittedBox vá reduzir o widget depois. Por isso damos uma
                            // largura virtual folgada e deixamos o FittedBox encaixar tudo
                            // no espaço real do modal.
                            const pickerWidth = 700.0;
                            const pickerHeight = 320.0;

                            return Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: pickerWidth,
                                  height: pickerHeight,
                                  child: ColorPicker(
                                    pickerColor: pickedColor,
                                    onColorChanged: (color) {
                                      setDialogState(() {
                                        pickedColor = color;
                                        hexController.text = _colorToHex(color);
                                      });
                                      setState(() => onColorChanged(color));
                                    },
                                    pickerAreaHeightPercent: 0.72,
                                    labelTypes: const [],
                                    displayThumbColor: true,
                                    enableAlpha: false,
                                    hexInputBar: false,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: t.textSecondary,
                                side: BorderSide(color: t.border),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    t.buttonRadius,
                                  ),
                                ),
                              ),
                              child: const Text('CANCELAR'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.primary,
                                foregroundColor: _readableOn(t.primary),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    t.buttonRadius,
                                  ),
                                ),
                              ),
                              onPressed: () {
                                setState(() => onColorChanged(pickedColor));
                                Navigator.of(context).pop();
                              },
                              child: const Text('OK'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    hexController.dispose();
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: Icon(icon, color: primary),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  void _salvar() {
    final assinaturas = <AssinaturaCertificadoEvento>[];

    for (var i = 0; i < 5; i++) {
      final nome = _nomeControllers[i].text.trim();
      final apelido = _apelidoControllers[i].text.trim();

      // Mantém sempre o slot físico original, inclusive quando estiver vazio.
      assinaturas.add(
        AssinaturaCertificadoEvento(
          slot: i + 1,
          nome: nome,
          apelido: apelido,
        ),
      );
    }

    final exigeAssinatura =
        _studio.blocoAtivo('assinatura_nome') ||
        _studio.blocoAtivo('assinatura_apelido');
    if (_ativo && exigeAssinatura && !assinaturas.any((item) => item.preenchida)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('O bloco de assinaturas está ativo. Informe ao menos uma assinatura ou desative esse bloco no Studio.'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      ConfiguracoesCertificadoEvento(
        ativo: _ativo,
        modeloPadrao: _modeloPadrao,
        assinaturas: assinaturas,
        usarCidadeDoEvento: _usarCidadeDoEvento,
        usarDataDoEvento: _usarDataDoEvento,
        visual: _visual,
        studio: _studio,
        textos: _textos,
      ),
    );
  }

  Future<void> _novoCanvasEmBranco() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo canvas em branco'),
        content: const Text(
          'Você pode apenas trocar a base por uma folha A4 branca mantendo suas camadas, '
          'ou começar realmente do zero com todos os blocos dinâmicos desligados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'manter'),
            child: const Text('MANTER ELEMENTOS'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'zerar'),
            child: const Text('COMEÇAR DO ZERO'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    final blocosOff = <String, bool>{
      for (final key in CertificadoStudioConfig.blocosPadrao.keys) key: false,
    };
    setState(() {
      _studio = _studio.copyWith(
        limparBaseSvg: true,
        baseEmBranco: true,
        substituicoesCor: const {},
        finalidade: mode == 'zerar' ? 'livre' : _studio.finalidade,
        blocosAtivos: mode == 'zerar' ? blocosOff : _studio.blocosAtivos,
        blocosLayout: mode == 'zerar' ? const {} : _studio.blocosLayout,
        camadas: mode == 'zerar' ? const [] : _studio.camadas,
        textosLivres: mode == 'zerar' ? const [] : _studio.textosLivres,
      );
      _selectedLayerId = null;
      _selectedTextId = null;
    });
  }


  Future<CertificadoSvgImportOptions?> _escolherOpcoesImportacaoSvg() async {
    var orientacao = 'auto';
    var ajuste = 'contain';
    return showDialog<CertificadoSvgImportOptions>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final t = context.uai;
            return AlertDialog(
              title: const Text('IMPORTAR SVG • COREL → A4'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'O Studio preserva a arte e cria uma página A4 externa normalizada. Nada é esticado no modo CONTER.',
                        style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.35),
                      ),
                      const SizedBox(height: 16),
                      Text('ORIENTAÇÃO DO DOCUMENTO', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 11.5)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'auto', label: Text('AUTO'), icon: Icon(Icons.auto_awesome_rounded)),
                          ButtonSegment(value: 'portrait', label: Text('RETRATO'), icon: Icon(Icons.stay_current_portrait_rounded)),
                          ButtonSegment(value: 'landscape', label: Text('PAISAGEM'), icon: Icon(Icons.stay_current_landscape_rounded)),
                        ],
                        selected: {orientacao},
                        onSelectionChanged: (value) => setLocalState(() => orientacao = value.first),
                      ),
                      const SizedBox(height: 16),
                      Text('AJUSTE DA ARTE NA FOLHA', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 11.5)),
                      const SizedBox(height: 8),
                      RadioGroup<String>(
                        groupValue: ajuste,
                        onChanged: (v) {
                          if (v == null) return;
                          setLocalState(() => ajuste = v);
                        },
                        child: Column(
                          children: [
                      RadioListTile<String>(
                        value: 'contain',
                        title: const Text('CONTER • recomendado'),
                        subtitle: const Text('Mantém 100% da arte, proporção original e centraliza no A4.'),
                      ),
                      RadioListTile<String>(
                        value: 'cover',
                        title: const Text('COBRIR'),
                        subtitle: const Text('Preenche toda a folha sem deformar; pode cortar pequenas bordas.'),
                      ),
                      RadioListTile<String>(
                        value: 'center',
                        title: const Text('TAMANHO ORIGINAL / CENTRALIZAR'),
                        subtitle: const Text('Não amplia a arte; posiciona o tamanho original no centro do A4.'),
                      ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    CertificadoSvgImportOptions(orientacao: orientacao, ajuste: ajuste),
                  ),
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: const Text('NORMALIZAR E IMPORTAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _definirDocumentoA4(String orientacao) {
    final portrait = orientacao == 'portrait';
    setState(() {
      _studio = _studio.copyWith(
        orientacaoPagina: portrait ? 'portrait' : 'landscape',
        paginaLarguraMm: portrait ? 210 : 297,
        paginaAlturaMm: portrait ? 297 : 210,
      );
    });
  }

  Future<void> _importarSvgComoBase() async {
    if (!_podeImportarSvgCorel) {
      _snackStudio('A importação de SVG/Corel fica disponível no Windows. Neste dispositivo você pode editar e salvar normalmente os templates já importados.');
      return;
    }
    if (_importandoSvg) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['svg'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _snackStudio('Não foi possível ler o SVG selecionado.', erro: true);
      return;
    }

    final options = await _escolherOpcoesImportacaoSvg();
    if (options == null || !mounted) return;

    setState(() => _importandoSvg = true);
    try {
      final imported = await CertificadoActionFeedback.run(
        context: context,
        title: 'Importando SVG',
        detail: 'Sanitizando a arte, normalizando para A4 e preparando a prévia do certificado...',
        icon: Icons.upload_file_rounded,
        action: () => _svgImportService.importar(
          bytes: bytes,
          nomeArquivo: file.name,
          pasta: 'certificados/studio/bases',
          options: options,
        ),
      );
      if (!mounted) return;
      setState(() {
        _studio = _studio.copyWith(
          baseSvgStoragePath: imported.storagePath,
          basePreviewStoragePath: imported.previewStoragePath,
          baseSvgNome: imported.nomeArquivo,
          baseEmBranco: false,
          substituicoesCor: const {},
          orientacaoPagina: imported.orientacao,
          ajusteBaseSvg: imported.ajuste,
          paginaLarguraMm: imported.paginaLarguraMm,
          paginaAlturaMm: imported.paginaAlturaMm,
          baseOrigemLargura: imported.inspection.larguraOrigem,
          baseOrigemAltura: imported.inspection.alturaOrigem,
        );

      });
      _snackStudio('SVG sanitizado e aplicado como base do certificado.');
      await _mostrarInspectorSvg(imported.inspection);
    } catch (e) {
      _snackStudio('Erro ao importar SVG: $e', erro: true);
    } finally {
      if (mounted) setState(() => _importandoSvg = false);
    }
  }

  Future<void> _adicionarCamadaSvg() async {
    if (!_podeImportarSvgCorel) {
      _snackStudio('Adicionar SVG é uma ferramenta do Studio Windows. As camadas já salvas continuam disponíveis neste dispositivo.');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['svg'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || !mounted) return;

    setState(() => _importandoSvg = true);
    try {
      final imported = await CertificadoActionFeedback.run(
        context: context,
        title: 'Adicionando camada SVG',
        detail: 'Preparando a camada e gerando uma prévia compatível com o Canvas e o PDF...',
        icon: Icons.layers_rounded,
        action: () => _svgImportService.importar(
          bytes: bytes,
          nomeArquivo: file.name,
          pasta: 'certificados/studio/camadas',
          options: CertificadoSvgImportOptions(
            orientacao: _studio.orientacaoPagina,
            ajuste: 'contain',
          ),
        ),
      );
      if (!mounted) return;
      final layer = CertificadoStudioLayer(
        id: 'layer_${DateTime.now().microsecondsSinceEpoch}',
        nome: file.name.replaceAll(RegExp(r'\.svg$', caseSensitive: false), ''),
        tipo: 'svg_fixo',
        storagePath: imported.storagePath,
        previewStoragePath: imported.previewStoragePath,
        x: 0,
        y: 0,
        largura: _studio.larguraDocumentoMm,
        altura: _studio.alturaDocumentoMm,
      );
      setState(() {
        _studio = _studio.copyWith(camadas: [..._studio.camadas, layer]);

      });
      _snackStudio('Camada SVG adicionada ao canvas.');
    } catch (e) {
      _snackStudio('Erro ao adicionar camada: $e', erro: true);
    } finally {
      if (mounted) setState(() => _importandoSvg = false);
    }
  }

  Future<void> _inspecionarBaseAtual() async {
    final path = _studio.baseSvgStoragePath;
    if (path == null || path.trim().isEmpty) {
      _snackStudio('Importe um SVG do Corel primeiro.');
      return;
    }
    try {
      final svg = await CertificadoActionFeedback.run(
        context: context,
        title: 'Analisando SVG',
        detail: 'Carregando a arte e identificando dimensões, cores e estrutura do arquivo...',
        icon: Icons.manage_search_rounded,
        action: () => _svgService.carregarSvgStorage(path),
      );
      final inspection = _svgImportService.inspecionar(original: svg, sanitized: svg);
      if (!mounted) return;

      await _mostrarInspectorSvg(inspection);
    } catch (e) {
      _snackStudio('Não foi possível inspecionar o SVG: $e', erro: true);
    }
  }

  Future<void> _mostrarInspectorSvg(
    CertificadoSvgInspection inspection, {
    CertificadoStudioLayer? layerAlvo,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.hub_rounded, color: t.info),
                    const SizedBox(width: 9),
                    Expanded(child: Text(layerAlvo == null ? 'INSPECTOR SVG • BASE' : 'INSPECTOR SVG • ${layerAlvo.nome}', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 17))),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                  ]),
                  Text('Origem: ${inspection.larguraOrigem?.toStringAsFixed(2) ?? '?'} × ${inspection.alturaOrigem?.toStringAsFixed(2) ?? '?'} • ${inspection.orientacaoDetectada.toUpperCase()} • viewBox A4: ${inspection.viewBoxNormalizado ?? inspection.viewBox ?? 'não encontrado'} • ${inspection.ids.length} ids • ${inspection.cores.length} cores', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                  const SizedBox(height: 12),
                  if (inspection.avisos.isNotEmpty)
                    ...inspection.avisos.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('⚠ $e', style: TextStyle(color: t.warning, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    )),
                  const SizedBox(height: 8),
                  Text('CORES DETECTADAS', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 12)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: inspection.cores.map((hex) {
                        final targetMap = layerAlvo?.substituicoesCor ?? _studio.substituicoesCor;
                        final atualHex = targetMap[hex] ?? hex;
                        final color = _colorFromHex(atualHex);
                        return ListTile(
                          dense: true,
                          leading: Container(width: 30, height: 30, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7), border: Border.all(color: t.border))),
                          title: Text(hex, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
                          subtitle: targetMap.containsKey(hex) ? Text('→ $atualHex', style: TextStyle(color: t.textSecondary)) : null,
                          trailing: TextButton(
                            onPressed: () async {
                              await _pickTextoColor(
                                titulo: 'Recolorir $hex',
                                corAtual: color,
                                onColorChanged: (nova) {
                                  if (layerAlvo == null) {
                                    final map = Map<String, String>.from(_studio.substituicoesCor);
                                    map[hex] = _colorToHex(nova);
                                    setState(() => _studio = _studio.copyWith(substituicoesCor: map));
                                  } else {
                                    final map = Map<String, String>.from(layerAlvo.substituicoesCor);
                                    map[hex] = _colorToHex(nova);
                                    final atualizado = layerAlvo.copyWith(substituicoesCor: map);
                                    final layers = _studio.camadas.map((e) => e.id == atualizado.id ? atualizado : e).toList();
                                    setState(() => _studio = _studio.copyWith(camadas: layers));
                                  }
                                },
                              );
                              if (dialogContext.mounted) Navigator.pop(dialogContext);
                              if (mounted) {
                                if (layerAlvo == null) {
                                  await _inspecionarBaseAtual();
                                } else {
                                  await _inspecionarCamada(layerAlvo.id);
                                }
                              }
                            },
                            child: const Text('RECOLORIR'),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _inspecionarCamada(String layerId) async {
    CertificadoStudioLayer? layer;
    for (final item in _studio.camadas) {
      if (item.id == layerId) {
        layer = item;
        break;
      }
    }
    if (layer == null) return;
    try {
      final svg = await _svgService.carregarSvgStorage(layer.storagePath);
      final inspection = _svgImportService.inspecionar(original: svg, sanitized: svg);
      if (!mounted) return;
      await _mostrarInspectorSvg(inspection, layerAlvo: layer);
    } catch (e) {
      _snackStudio('Não foi possível inspecionar a camada: $e', erro: true);
    }
  }

  Future<void> _editarCamada(CertificadoStudioLayer layer) async {
    final x = TextEditingController(text: layer.x.toStringAsFixed(1));
    final y = TextEditingController(text: layer.y.toStringAsFixed(1));
    final w = TextEditingController(text: layer.largura.toStringAsFixed(1));
    final h = TextEditingController(text: layer.altura.toStringAsFixed(1));
    final nome = TextEditingController(text: layer.nome);

    final novo = await showDialog<CertificadoStudioLayer>(
      context: context,
      builder: (context) {
        final t = context.uai;
        return AlertDialog(
          title: const Text('Editar camada SVG'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(children: [
                TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome da camada')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: x, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'X (mm)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: y, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Y (mm)'))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: w, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Largura (mm)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Altura (mm)'))),
                ]),
                const SizedBox(height: 10),
                Text('Canvas A4: ${_studio.larguraDocumentoMm.toStringAsFixed(0)} × ${_studio.alturaDocumentoMm.toStringAsFixed(0)} mm', style: TextStyle(color: t.textSecondary, fontSize: 11)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
            FilledButton(
              onPressed: () {
                double d(TextEditingController c, double f) => double.tryParse(c.text.replaceAll(',', '.')) ?? f;
                Navigator.pop(context, layer.copyWith(
                  nome: nome.text.trim().isEmpty ? layer.nome : nome.text.trim(),
                  x: d(x, layer.x), y: d(y, layer.y),
                  largura: d(w, layer.largura).clamp(1.0, 600.0).toDouble(),
                  altura: d(h, layer.altura).clamp(1.0, 600.0).toDouble(),
                ));
              },
              child: const Text('APLICAR'),
            ),
          ],
        );
      },
    );
    x.dispose(); y.dispose(); w.dispose(); h.dispose(); nome.dispose();
    if (novo == null || !mounted) return;
    final layers = _studio.camadas.map((e) => e.id == layer.id ? novo : e).toList();
    setState(() => _studio = _studio.copyWith(camadas: layers));
  }

  String _slotIdDoBloco(String bloco) {
    switch (bloco) {
      case 'nome': return CertificadoSlotIds.alunoNome;
      case 'cpf': return CertificadoSlotIds.cpf;
      case 'graduacao': return CertificadoSlotIds.graduacaoNova;
      case 'frase': return CertificadoSlotIds.frase;
      case 'local_data': return CertificadoSlotIds.localData;
      default: return bloco;
    }
  }

  Future<void> _editarLayoutBloco(String bloco, String titulo) async {
    final slotId = _slotIdDoBloco(bloco);
    CertificadoStudioRect? atual = _studio.blocosLayout[slotId];
    if (atual == null) {
      final slots = await _svgService.carregarSlotsDoGuia(_previewTipo());
      final slot = slots[slotId];
      if (slot != null) {
        atual = CertificadoStudioRect(x: slot.x, y: slot.y, largura: slot.width, altura: slot.height);
      }
    }
    if (!mounted) return;
    atual ??= const CertificadoStudioRect(x: 20, y: 20, largura: 100, altura: 10);

    final ctrls = [
      TextEditingController(text: atual.x.toStringAsFixed(1)),
      TextEditingController(text: atual.y.toStringAsFixed(1)),
      TextEditingController(text: atual.largura.toStringAsFixed(1)),
      TextEditingController(text: atual.altura.toStringAsFixed(1)),
    ];
    final result = await showDialog<CertificadoStudioRect>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Posicionar • $titulo'),
        content: SizedBox(
          width: 500,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: TextField(controller: ctrls[0], decoration: const InputDecoration(labelText: 'X (mm)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ctrls[1], decoration: const InputDecoration(labelText: 'Y (mm)'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: ctrls[2], decoration: const InputDecoration(labelText: 'Largura (mm)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ctrls[3], decoration: const InputDecoration(labelText: 'Altura (mm)'))),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          FilledButton(onPressed: () {
            double d(int i, double f) => double.tryParse(ctrls[i].text.replaceAll(',', '.')) ?? f;
            Navigator.pop(context, CertificadoStudioRect(
              x: d(0, atual!.x), y: d(1, atual.y),
              largura: d(2, atual.largura).clamp(1.0, _studio.larguraDocumentoMm).toDouble(),
              altura: d(3, atual.altura).clamp(1.0, _studio.alturaDocumentoMm).toDouble(),
            ));
          }, child: const Text('APLICAR')),
        ],
      ),
    );
    for (final c in ctrls) {
      c.dispose();
    }
    if (result == null || !mounted) return;
    final layouts = Map<String, CertificadoStudioRect>.from(_studio.blocosLayout);
    layouts[slotId] = result;
    setState(() => _studio = _studio.copyWith(blocosLayout: layouts));
  }

  Future<void> _editarTextoLivre([CertificadoStudioTextLayer? original]) async {
    final base = original ?? CertificadoStudioTextLayer(
      id: 'text_${DateTime.now().microsecondsSinceEpoch}',
      nome: 'Texto livre',
      textoTemplate: '{nome}',
    );
    final nome = TextEditingController(text: base.nome);
    final texto = TextEditingController(text: base.textoTemplate);
    final x = TextEditingController(text: base.x.toStringAsFixed(1));
    final y = TextEditingController(text: base.y.toStringAsFixed(1));
    final w = TextEditingController(text: base.largura.toStringAsFixed(1));
    final h = TextEditingController(text: base.altura.toStringAsFixed(1));
    final size = TextEditingController(text: base.tamanho.toStringAsFixed(1));
    final color = TextEditingController(text: base.corHex);
    var alinhamento = base.alinhamento;
    var negrito = base.negrito;
    var fonte = base.fonte;

    final result = await showDialog<CertificadoStudioTextLayer>(
      context: context,
      builder: (context) {
        final t = context.uai;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(original == null ? 'Adicionar texto ao canvas' : 'Editar texto do canvas'),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome da camada de texto')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: texto,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Texto / template dinâmico',
                        hintText: 'Ex.: Parabéns, {nome}! Você foi destaque no {evento}.',
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Variáveis: {nome}  {cpf}  {graduacao}  {frase}  {local_data}  {evento}',
                      style: TextStyle(color: t.info, fontSize: 10.8, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: TextField(controller: x, decoration: const InputDecoration(labelText: 'X (mm)'))),
                      const SizedBox(width: 7),
                      Expanded(child: TextField(controller: y, decoration: const InputDecoration(labelText: 'Y (mm)'))),
                      const SizedBox(width: 7),
                      Expanded(child: TextField(controller: w, decoration: const InputDecoration(labelText: 'Largura'))),
                      const SizedBox(width: 7),
                      Expanded(child: TextField(controller: h, decoration: const InputDecoration(labelText: 'Altura'))),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextField(controller: size, decoration: const InputDecoration(labelText: 'Tamanho pt'))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: color,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'Cor HEX',
                            suffixIcon: IconButton(
                              tooltip: 'Abrir seletor de cores',
                              icon: const Icon(Icons.palette_rounded),
                              onPressed: () async {
                                final atual = _hexToColor(color.text, _hexToColor(base.corHex, const Color(0xFF1A0202)));
                                await _pickTextoColor(
                                  titulo: 'Cor do texto • ${nome.text.trim().isEmpty ? base.nome : nome.text.trim()}',
                                  corAtual: atual,
                                  onColorChanged: (novaCor) {
                                    color.text = _colorToHex(novaCor);
                                    setDialogState(() {});
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: CertificadoTextoCampoConfig.fontesDisponiveis.contains(fonte) ? fonte : 'Arial',
                          decoration: const InputDecoration(labelText: 'Fonte'),
                          items: CertificadoTextoCampoConfig.fontesDisponiveis
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setDialogState(() => fonte = v ?? 'Arial'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: alinhamento,
                          decoration: const InputDecoration(labelText: 'Alinhamento'),
                          items: const [
                            DropdownMenuItem(value: 'left', child: Text('Esquerda')),
                            DropdownMenuItem(value: 'center', child: Text('Centro')),
                            DropdownMenuItem(value: 'right', child: Text('Direita')),
                          ],
                          onChanged: (v) => setDialogState(() => alinhamento = v ?? 'center'),
                        ),
                      ),
                    ]),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: negrito,
                      onChanged: (v) => setDialogState(() => negrito = v ?? false),
                      title: const Text('Negrito'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
              FilledButton(
                onPressed: () {
                  double d(TextEditingController c, double f) => double.tryParse(c.text.replaceAll(',', '.')) ?? f;
                  final hex = color.text.trim().toUpperCase();
                  Navigator.pop(
                    context,
                    base.copyWith(
                      nome: nome.text.trim().isEmpty ? 'Texto livre' : nome.text.trim(),
                      textoTemplate: texto.text,
                      x: d(x, base.x),
                      y: d(y, base.y),
                      largura: d(w, base.largura).clamp(4.0, 594.0).toDouble(),
                      altura: d(h, base.altura).clamp(3.0, 420.0).toDouble(),
                      tamanho: d(size, base.tamanho).clamp(5.0, 120.0).toDouble(),
                      corHex: RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex) ? hex : base.corHex,
                      alinhamento: alinhamento,
                      negrito: negrito,
                      fonte: fonte,
                    ),
                  );
                },
                child: const Text('APLICAR'),
              ),
            ],
          ),
        );
      },
    );
    for (final c in [nome, texto, x, y, w, h, size, color]) {
      c.dispose();
    }
    if (result == null || !mounted) return;
    final exists = _studio.textosLivres.any((e) => e.id == result.id);
    final texts = exists
        ? _studio.textosLivres.map((e) => e.id == result.id ? result : e).toList()
        : [..._studio.textosLivres, result];
    setState(() {
      _studio = _studio.copyWith(textosLivres: texts);
      _selectedTextId = result.id;
      _selectedLayerId = null;
    });
  }

  void _validarStudio() {
    final issues = _validator.validar(_configuracaoAtualParaPreview());
    showDialog<void>(
      context: context,
      builder: (context) {
        final t = context.uai;
        return AlertDialog(
          title: const Text('Validador pré-impressão'),
          content: SizedBox(
            width: 620,
            child: ListView(
              shrinkWrap: true,
              children: issues.map((issue) {
                final color = issue.nivel == 'erro' ? t.error : issue.nivel == 'aviso' ? t.warning : issue.nivel == 'ok' ? t.success : t.info;
                return ListTile(
                  leading: Icon(issue.bloqueia ? Icons.error_rounded : Icons.verified_rounded, color: color),
                  title: Text(issue.titulo, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
                  subtitle: Text(issue.detalhe, style: TextStyle(color: t.textSecondary)),
                );
              }).toList(),
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        );
      },
    );
  }

  Future<bool> _salvarComoTemplate({bool salvarComoNovo = false}) async {
    final nomeInicial = salvarComoNovo && _studio.templateNome != null
        ? '${_studio.templateNome} - cópia'
        : (_studio.templateNome ?? 'Novo template');
    final nome = TextEditingController(text: nomeInicial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salvar na biblioteca de templates'),
        content: TextField(controller: nome, autofocus: true, decoration: const InputDecoration(labelText: 'Nome do template')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          FilledButton(onPressed: () => Navigator.pop(context, nome.text.trim()), child: const Text('SALVAR')),
        ],
      ),
    );
    nome.dispose();
    if (result == null || result.trim().isEmpty || !mounted) return false;
    try {
      final config = _configuracaoAtualParaPreview();
      final id = await CertificadoActionFeedback.run(
        context: context,
        title: salvarComoNovo ? 'Criando template' : 'Salvando template',
        detail: salvarComoNovo
            ? 'Criando uma nova cópia na biblioteca de certificados...'
            : 'Gravando as alterações do template na biblioteca...',
        icon: Icons.save_rounded,
        action: () => _templateRepository.salvar(
          id: salvarComoNovo ? null : _studio.templateId,
          nome: result.trim(),
          configuracao: config,
        ),
      );
      if (!mounted) return false;
      setState(() => _studio = _studio.copyWith(templateId: id, templateNome: result.trim()));
      _snackStudio(
        salvarComoNovo
            ? 'Novo template criado na biblioteca.'
            : 'Template salvo na biblioteca.',
      );
      return true;
    } catch (e) {
      _snackStudio('Erro ao salvar template: $e', erro: true);
      return false;
    }
  }

  Future<void> _acaoSalvarPrincipal() async {
    if (widget.modoBiblioteca) {
      // No Studio global não existe evento-pai para receber Navigator.pop(config).
      // O comportamento correto é persistir o documento na biblioteca.
      await _salvarComoTemplate();
      return;
    }

    _salvar();
  }

  Future<void> _abrirBibliotecaTemplates() async {
    try {
      var templates = await CertificadoActionFeedback.run(
        context: context,
        title: 'Carregando templates',
        detail: 'Buscando sua biblioteca de modelos de certificados...',
        icon: Icons.folder_open_rounded,
        action: _templateRepository.listar,
      );
      if (!mounted) return;

      final searchController = TextEditingController();
      var filtroFinalidade = 'todos';
      var filtroOrientacao = 'todas';
      var processandoId = <String>{};

      CertificadoTemplateResumo? escolhido;

      try {
        escolhido = await showDialog<CertificadoTemplateResumo>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                final t = context.uai;
                final viewport = MediaQuery.sizeOf(context);
                final compact = viewport.width < 760;
                final dialogWidth = viewport.width < 1040 ? viewport.width * 0.88 : 920.0;
                final dialogHeight = viewport.height < 760 ? viewport.height * 0.72 : 610.0;

                bool combina(CertificadoTemplateResumo item) {
                  final busca = searchController.text.trim().toLowerCase();
                  final studio = item.configuracao.studio;
                  final textoBusca = <String>[
                    item.nome,
                    item.descricao ?? '',
                    studio.baseSvgNome ?? '',
                    studio.finalidadeLabel,
                  ].join(' ').toLowerCase();

                  if (busca.isNotEmpty && !textoBusca.contains(busca)) {
                    return false;
                  }

                  if (filtroFinalidade != 'todos' &&
                      studio.finalidade != filtroFinalidade) {
                    return false;
                  }

                  final retrato = studio.alturaDocumentoMm >= studio.larguraDocumentoMm;
                  if (filtroOrientacao == 'retrato' && !retrato) return false;
                  if (filtroOrientacao == 'paisagem' && retrato) return false;
                  return true;
                }

                final filtrados = templates.where(combina).toList();

                Future<void> duplicar(CertificadoTemplateResumo item) async {
                  if (processandoId.contains(item.id)) return;
                  setDialogState(() => processandoId.add(item.id));
                  try {
                    final novoNome = '${item.nome} - cópia';
                    final novoId = await _templateRepository.salvar(
                      nome: novoNome,
                      descricao: item.descricao,
                      configuracao: item.configuracao.copyWith(
                        studio: item.configuracao.studio.copyWith(
                          limparTemplateId: true,
                          templateNome: novoNome,
                        ),
                      ),
                    );
                    templates = await _templateRepository.listar();
                    if (!context.mounted) return;
                    setDialogState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Template duplicado: $novoNome'),
                        backgroundColor: context.uai.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    debugPrint('Template duplicado: ${item.id} -> $novoId');
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao duplicar template: $e'),
                        backgroundColor: context.uai.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } finally {
                    if (context.mounted) {
                      setDialogState(() => processandoId.remove(item.id));
                    }
                  }
                }

                Future<void> excluir(CertificadoTemplateResumo item) async {
                  final confirmar = await showDialog<bool>(
                    context: context,
                    builder: (confirmContext) => AlertDialog(
                      title: const Text('Excluir template?'),
                      content: Text(
                        '"${item.nome}" será removido da biblioteca.\n\n'
                        'Eventos já salvos não serão alterados, pois guardam uma cópia da configuração do certificado.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmContext, false),
                          child: const Text('CANCELAR'),
                        ),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(confirmContext, true),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('EXCLUIR'),
                        ),
                      ],
                    ),
                  );
                  if (confirmar != true || !context.mounted) return;

                  setDialogState(() => processandoId.add(item.id));
                  try {
                    await _templateRepository.excluir(item.id);
                    templates.removeWhere((t) => t.id == item.id);
                    if (!context.mounted) return;
                    setDialogState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Template excluído: ${item.nome}'),
                        backgroundColor: context.uai.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao excluir template: $e'),
                        backgroundColor: context.uai.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } finally {
                    if (context.mounted) {
                      setDialogState(() => processandoId.remove(item.id));
                    }
                  }
                }

                Widget filtroChip({
                  required String label,
                  required bool selected,
                  required VoidCallback onTap,
                }) {
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => onTap(),
                  );
                }

                return AlertDialog(
                  titlePadding: const EdgeInsets.fromLTRB(24, 20, 18, 10),
                  contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  title: Row(
                    children: [
                      const Icon(Icons.folder_copy_rounded),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gerenciador de templates'),
                            SizedBox(height: 2),
                            Text(
                              'Use, edite, duplique ou exclua modelos da biblioteca.',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: dialogWidth,
                    height: dialogHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: searchController,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Buscar template, finalidade ou nome do SVG...',
                            suffixIcon: searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Limpar busca',
                                    onPressed: () {
                                      searchController.clear();
                                      setDialogState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              filtroChip(
                                label: 'Todos',
                                selected: filtroFinalidade == 'todos',
                                onTap: () => setDialogState(() => filtroFinalidade = 'todos'),
                              ),
                              const SizedBox(width: 6),
                              filtroChip(
                                label: 'Graduação',
                                selected: filtroFinalidade == 'graduacao',
                                onTap: () => setDialogState(() => filtroFinalidade = 'graduacao'),
                              ),
                              const SizedBox(width: 6),
                              filtroChip(
                                label: 'Destaque',
                                selected: filtroFinalidade == 'destaque',
                                onTap: () => setDialogState(() => filtroFinalidade = 'destaque'),
                              ),
                              const SizedBox(width: 6),
                              filtroChip(
                                label: 'Participação',
                                selected: filtroFinalidade == 'participacao',
                                onTap: () => setDialogState(() => filtroFinalidade = 'participacao'),
                              ),
                              const SizedBox(width: 6),
                              filtroChip(
                                label: 'Curso',
                                selected: filtroFinalidade == 'curso',
                                onTap: () => setDialogState(() => filtroFinalidade = 'curso'),
                              ),
                              const SizedBox(width: 6),
                              filtroChip(
                                label: 'Homenagem',
                                selected: filtroFinalidade == 'homenagem',
                                onTap: () => setDialogState(() => filtroFinalidade = 'homenagem'),
                              ),
                              const SizedBox(width: 6),
                              filtroChip(
                                label: 'Livre',
                                selected: filtroFinalidade == 'livre',
                                onTap: () => setDialogState(() => filtroFinalidade = 'livre'),
                              ),
                              const SizedBox(width: 18),
                              filtroChip(
                                label: 'Retrato',
                                selected: filtroOrientacao == 'retrato',
                                onTap: () => setDialogState(() => filtroOrientacao = filtroOrientacao == 'retrato' ? 'todas' : 'retrato'),
                              ),
                              const SizedBox(width: 6),
                              filtroChip(
                                label: 'Paisagem',
                                selected: filtroOrientacao == 'paisagem',
                                onTap: () => setDialogState(() => filtroOrientacao = filtroOrientacao == 'paisagem' ? 'todas' : 'paisagem'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: templates.isEmpty
                              ? const Center(child: Text('Nenhum template salvo ainda.'))
                              : filtrados.isEmpty
                                  ? const Center(child: Text('Nenhum template corresponde aos filtros.'))
                                  : ListView.separated(
                                      itemCount: filtrados.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                                      itemBuilder: (_, i) {
                                        final item = filtrados[i];
                                        final studio = item.configuracao.studio;
                                        final retrato = studio.alturaDocumentoMm >= studio.larguraDocumentoMm;
                                        final ocupado = processandoId.contains(item.id);
                                        final selecionado = _studio.templateId == item.id;

                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: selecionado ? t.primary.withAlpha(20) : t.cardAlt,
                                            borderRadius: BorderRadius.circular(t.inputRadius),
                                            border: Border.all(
                                              color: selecionado ? t.primary.withAlpha(115) : t.border,
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: t.card,
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: t.border),
                                                ),
                                                child: Icon(
                                                  retrato ? Icons.stay_current_portrait_rounded : Icons.stay_current_landscape_rounded,
                                                  color: t.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            item.nome,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              color: t.textPrimary,
                                                              fontWeight: FontWeight.w900,
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                        ),
                                                        if (selecionado) ...[
                                                          const SizedBox(width: 8),
                                                          const Icon(Icons.check_circle_rounded, size: 16),
                                                        ],
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      studio.finalidadeLabel,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(color: t.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      '${retrato ? 'A4 retrato' : 'A4 paisagem'} • ${studio.baseSvgNome ?? (studio.baseEmBranco ? 'Canvas em branco' : 'Modelo UAI interno')}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(color: t.textSecondary, fontSize: 10.5),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              if (ocupado)
                                                const SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              else if (compact)
                                                PopupMenuButton<String>(
                                                  tooltip: 'Ações do template',
                                                  onSelected: (value) {
                                                    if (value == 'abrir') {
                                                      Navigator.pop(dialogContext, item);
                                                    } else if (value == 'duplicar') {
                                                      duplicar(item);
                                                    } else if (value == 'excluir') {
                                                      excluir(item);
                                                    }
                                                  },
                                                  itemBuilder: (_) => [
                                                    PopupMenuItem(
                                                      value: 'abrir',
                                                      child: ListTile(
                                                        dense: true,
                                                        leading: Icon(widget.modoBiblioteca ? Icons.edit_rounded : Icons.check_rounded),
                                                        title: Text(widget.modoBiblioteca ? 'Editar' : 'Usar'),
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'duplicar',
                                                      child: ListTile(
                                                        dense: true,
                                                        leading: Icon(Icons.copy_all_rounded),
                                                        title: Text('Duplicar'),
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'excluir',
                                                      child: ListTile(
                                                        dense: true,
                                                        leading: Icon(Icons.delete_outline_rounded, color: t.error),
                                                        title: const Text('Excluir'),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              else ...[
                                                Tooltip(
                                                  message: widget.modoBiblioteca ? 'Editar no Studio' : 'Usar neste certificado',
                                                  child: FilledButton.icon(
                                                    onPressed: () => Navigator.pop(dialogContext, item),
                                                    icon: Icon(widget.modoBiblioteca ? Icons.edit_rounded : Icons.check_rounded, size: 17),
                                                    label: Text(widget.modoBiblioteca ? 'EDITAR' : 'USAR'),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                IconButton(
                                                  tooltip: 'Duplicar',
                                                  onPressed: () => duplicar(item),
                                                  icon: const Icon(Icons.copy_all_rounded),
                                                ),
                                                IconButton(
                                                  tooltip: 'Excluir',
                                                  onPressed: () => excluir(item),
                                                  icon: Icon(Icons.delete_outline_rounded, color: t.error),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${filtrados.length} de ${templates.length} template(s)',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: t.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('FECHAR'),
                    ),
                  ],
                );
              },
            );
          },
        );
      } finally {
        searchController.dispose();
      }

      if (escolhido != null && mounted) {
        _aplicarConfiguracao(
          escolhido.configuracao.copyWith(
            studio: escolhido.configuracao.studio.copyWith(
              templateId: escolhido.id,
              templateNome: escolhido.nome,
            ),
          ),
        );
        _snackStudio(
          widget.modoBiblioteca
              ? 'Template aberto para edição: ${escolhido.nome}'
              : 'Template aplicado ao certificado: ${escolhido.nome}',
        );
      }
    } catch (e) {
      _snackStudio('Erro ao carregar templates: $e', erro: true);
    }
  }

  void _aplicarConfiguracao(ConfiguracoesCertificadoEvento config) {
    final assinaturas = config.assinaturasPorSlot;
    setState(() {
      _ativo = config.ativo;
      _modeloPadrao = config.modeloPadrao;
      _usarCidadeDoEvento = config.usarCidadeDoEvento;
      _usarDataDoEvento = config.usarDataDoEvento;
      _visual = config.visual;
      _studio = config.studio;
      _selectedLayerId = null;
      _selectedTextId = null;
      _textos = Map<String, CertificadoTextoCampoConfig>.from(config.textos);
      for (var i = 0; i < 5; i++) {
        _nomeControllers[i].text = assinaturas[i].nome;
        _apelidoControllers[i].text = assinaturas[i].apelido;
      }
    });
    _assinaturasPreviewRevision.value++;
  }

  void _snackStudio(String text, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: erro ? context.uai.error : context.uai.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);
    final onPrimary = _readableOn(primary);

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildStudioTopBar(primary, onPrimary),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Studio multiplataforma:
                    // - desktop amplo: 3 colunas;
                    // - desktop/tablet: 2 colunas;
                    // - celular deitado: canvas + ferramentas lado a lado;
                    // - celular em pe: canvas/ferramentas/inspector em abas inferiores.
                    final isWide = constraints.maxWidth >= 1450;
                    final isMedium = constraints.maxWidth >= 980;
                    final phoneLandscape = constraints.maxWidth >= 680 &&
                        constraints.maxWidth < 980 &&
                        constraints.maxHeight < 720;

                    if (!isMedium) {
                      if (phoneLandscape) {
                        return _buildPhoneLandscapeStudio(constraints);
                      }
                      return _buildPhonePortraitStudio();
                    }

                    final controls = ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                      children: _configSectionWidgets(
                        includeInlinePreview: false,
                      ),
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: isWide ? 390 : 330,
                          child: controls,
                        ),
                        VerticalDivider(width: 1, thickness: 1, color: t.border),
                        Expanded(
                          child: Container(
                            color: t.surface,
                            child: _buildCanvasWorkspace(isWide: isWide),
                          ),
                        ),
                        if (isWide) ...[
                          VerticalDivider(width: 1, thickness: 1, color: t.border),
                          SizedBox(
                            width: 270,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                              children: [
                                _buildPaletaVisualCard(compact: true),
                                const SizedBox(height: 12),
                                _buildInspectorResumoCard(),
                                const SizedBox(height: 12),
                                _buildStudioInfoCard(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhonePortraitStudio() {
    final t = context.uai;

    Widget page;
    switch (_mobileStudioPane) {
      case 1:
        page = ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
          children: _configSectionWidgets(includeInlinePreview: false),
        );
        break;
      case 2:
        page = ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
          children: [
            _buildPaletaVisualCard(compact: false),
            const SizedBox(height: 10),
            _buildInspectorResumoCard(),
            const SizedBox(height: 10),
            _buildStudioInfoCard(),
          ],
        );
        break;
      default:
        page = Container(
          color: t.surface,
          child: _buildCanvasWorkspace(isWide: false),
        );
    }

    return Column(
      children: [
        Expanded(child: page),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: NavigationBar(
            height: 66,
            selectedIndex: _mobileStudioPane,
            onDestinationSelected: (index) =>
                setState(() => _mobileStudioPane = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.design_services_outlined),
                selectedIcon: Icon(Icons.design_services_rounded),
                label: 'Canvas',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Ferramentas',
              ),
              NavigationDestination(
                icon: Icon(Icons.dashboard_customize_outlined),
                selectedIcon: Icon(Icons.dashboard_customize_rounded),
                label: 'Inspector',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneLandscapeStudio(BoxConstraints constraints) {
    final t = context.uai;
    final sideWidth = (constraints.maxWidth * .39).clamp(280.0, 360.0).toDouble();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: t.surface,
            child: _buildCanvasWorkspace(isWide: false),
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: t.border),
        SizedBox(
          width: sideWidth,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(bottom: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment<int>(
                            value: 0,
                            icon: Icon(Icons.tune_rounded, size: 16),
                            label: Text('Ferramentas'),
                          ),
                          ButtonSegment<int>(
                            value: 1,
                            icon: Icon(Icons.dashboard_customize_rounded, size: 16),
                            label: Text('Inspector'),
                          ),
                        ],
                        selected: {_mobileStudioPane == 2 ? 1 : 0},
                        onSelectionChanged: (value) => setState(() {
                          _mobileStudioPane = value.first == 1 ? 2 : 1;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _mobileStudioPane == 2
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(9, 9, 9, 20),
                        children: [
                          _buildPaletaVisualCard(compact: false),
                          const SizedBox(height: 10),
                          _buildInspectorResumoCard(),
                          const SizedBox(height: 10),
                          _buildStudioInfoCard(),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(9, 9, 9, 20),
                        children: _configSectionWidgets(
                          includeInlinePreview: false,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudioTopBar(Color primary, Color onPrimary) {
    final t = context.uai;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1120;
        final veryCompact = constraints.maxWidth < 680;

        Widget actionIcon({
          required String tooltip,
          required IconData icon,
          required VoidCallback? onPressed,
          bool primaryAction = false,
        }) {
          return IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 19, color: primaryAction ? onPrimary : null),
            style: primaryAction
                ? IconButton.styleFrom(backgroundColor: primary)
                : null,
          );
        }

        return Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(bottom: BorderSide(color: t.border)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Voltar sem salvar',
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
              ),
              const SizedBox(width: 4),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: t.primaryGradient,
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                child: Icon(Icons.design_services_rounded, color: onPrimary),
              ),
              if (!veryCompact) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STUDIO DE CERTIFICADOS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          letterSpacing: .3,
                        ),
                      ),
                      Text(
                        'Super Canvas • camadas, SVG, blocos dinâmicos e templates',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                const Spacer(),
              if (compact) ...[
                actionIcon(
                  tooltip: 'Biblioteca de templates',
                  icon: Icons.folder_copy_rounded,
                  onPressed: _abrirBibliotecaTemplates,
                ),
                actionIcon(
                  tooltip: 'Validar antes de imprimir',
                  icon: Icons.fact_check_rounded,
                  onPressed: _validarStudio,
                ),
                actionIcon(
                  tooltip: 'Testar PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  onPressed: _compartilhandoPreview ? null : _compartilharPreviaPdf,
                ),
                actionIcon(
                  tooltip: widget.modoBiblioteca ? 'Salvar template' : 'Salvar Studio',
                  icon: Icons.save_rounded,
                  onPressed: _acaoSalvarPrincipal,
                  primaryAction: true,
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _abrirBibliotecaTemplates,
                  icon: const Icon(Icons.folder_copy_rounded, size: 18),
                  label: const Text('TEMPLATES'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _validarStudio,
                  icon: const Icon(Icons.fact_check_rounded, size: 18),
                  label: const Text('VALIDAR'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _compartilhandoPreview ? null : _compartilharPreviaPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: Text(_compartilhandoPreview ? 'GERANDO...' : 'TESTAR PDF'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _acaoSalvarPrincipal,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(widget.modoBiblioteca ? 'SALVAR TEMPLATE' : 'SALVAR STUDIO'),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvasWorkspace({required bool isWide}) {
    final t = context.uai;
    final compactWorkspace = MediaQuery.sizeOf(context).width < 680;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(compactWorkspace ? 9 : 16, compactWorkspace ? 7 : 12, compactWorkspace ? 9 : 16, compactWorkspace ? 6 : 10),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _studioChip(Icons.auto_awesome_rounded, 'Canvas ao vivo', t.success),
              if (!compactWorkspace) ...[
                _studioChip(Icons.palette_rounded, 'Paleta SVG', t.warning),
                _studioChip(Icons.text_fields_rounded, 'Textos 2.0', t.info),
                _studioChip(Icons.draw_rounded, '5 assinaturas', t.primary),
              ] else
                _studioChip(
                  Icons.qr_code_2_rounded,
                  _studio.qrCode.ativo ? 'QR ativo' : 'QR opcional',
                  _studio.qrCode.ativo ? t.success : t.textMuted,
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(isWide ? 24 : compactWorkspace ? 7 : 14),
            decoration: BoxDecoration(
              color: Color.alphaBlend(t.textPrimary.withAlpha(9), t.background),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: _buildCanvasHero(expanded: true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCanvasHero({required bool expanded}) {
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        // O centro do Studio agora é um canvas de verdade: sem um segundo
        // card de "prévia ao vivo", sem botão PDF duplicado e sem aviso
        // ocupando altura. O certificado usa somente o espaço disponível.
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : (expanded ? 720.0 : 480.0);

        final previewMaxHeight = (availableHeight - 54.0).clamp(
          expanded ? 260.0 : 220.0,
          expanded ? 720.0 : 460.0,
        );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius + 2),
            border: Border.all(color: t.border),
            boxShadow: t.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.preview_rounded,
                    color: _ensureVisible(t.primary, t.card),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CANVAS DO CERTIFICADO',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    _studio.ehGraduacao ? _previewTipo().nome : _studio.finalidadeLabel,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (constraints.maxHeight.isFinite)
                Expanded(
                  child: Center(
                    child: _buildCanvasCertificate(previewMaxHeight),
                  ),
                )
              else
                _buildCanvasCertificate(previewMaxHeight),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvasCertificate(double maxHeight) {
    return ValueListenableBuilder<int>(
      valueListenable: _assinaturasPreviewRevision,
      builder: (context, _, _) {
        return CertificadoPreviewWidget(
          tipo: _previewTipo(),
          cor1: const Color(0xFF0047FF),
          cor2: const Color(0xFF7B00A8),
          corContorno: const Color(0xFF1A0202),
          data: _previewData(),
          textosConfig: _textos,
          visualConfig: _visual,
          studioConfig: _studio,
          studioInteractive: true,
          selectedStudioLayerId: _selectedLayerId,
          onStudioLayerSelected: (id) => setState(() {
            _selectedLayerId = id;
            _selectedTextId = null;
            _qrSelected = false;
          }),
          onStudioLayerChanged: (updated) {
            final layers = _studio.camadas
                .map((e) => e.id == updated.id ? updated : e)
                .toList();
            setState(() => _studio = _studio.copyWith(camadas: layers));
          },
          selectedStudioTextId: _selectedTextId,
          onStudioTextSelected: (id) => setState(() {
            _selectedTextId = id;
            _selectedLayerId = null;
            _qrSelected = false;
          }),
          onStudioTextChanged: (updated) {
            final texts = _studio.textosLivres
                .map((e) => e.id == updated.id ? updated : e)
                .toList();
            setState(() => _studio = _studio.copyWith(textosLivres: texts));
          },
          studioQrSelected: _qrSelected,
          onStudioQrSelected: () => setState(() {
            _qrSelected = true;
            _selectedLayerId = null;
            _selectedTextId = null;
          }),
          onStudioQrChanged: (updated) => setState(() {
            _studio = _studio.copyWith(qrCode: updated);
            _qrSelected = true;
          }),
          exportKey: null,
          showHeader: false,
          showDebugInfo: false,
          showTextOverlay: true,
          maxHeight: maxHeight,
        );
      },
    );
  }

  Widget _studioChip(IconData icon, String label, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(26), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(51)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildFinalidadeCertificadoCard() {
    final t = context.uai;
    const opcoes = <(String, String, String, IconData)>[
      ('graduacao', 'Graduação', 'Batizado e troca de cordas. Mantém AUTO / com CPF / sem CPF / diploma.', Icons.workspace_premium_rounded),
      ('destaque', 'Aluno destaque', 'Reconhecimento individual. Graduação e CPF não são obrigatórios.', Icons.star_rounded),
      ('participacao', 'Participação', 'Eventos, rodas, apresentações, projetos e atividades.', Icons.card_membership_rounded),
      ('curso', 'Curso / oficina', 'Cursos, oficinas, seminários e formações.', Icons.school_rounded),
      ('homenagem', 'Homenagem', 'Reconhecimento, agradecimento ou mérito.', Icons.emoji_events_rounded),
      ('livre', 'Livre', 'Você decide todos os blocos e regras do certificado.', Icons.auto_fix_high_rounded),
    ];

    return _dialogSection(
      icon: Icons.category_rounded,
      title: 'Finalidade do certificado',
      subtitle: 'Diz ao sistema o que este template representa. Isso controla validações e emissão sem prender o layout.',
      color: t.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...opcoes.map((opcao) {
            final selecionado = _studio.finalidade == opcao.$1;
            return InkWell(
              onTap: () => setState(() => _studio = _studio.copyWith(finalidade: opcao.$1)),
              borderRadius: BorderRadius.circular(t.inputRadius),
              child: Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: selecionado
                      ? Color.alphaBlend(t.warning.withAlpha(26), t.cardAlt)
                      : t.cardAlt,
                  borderRadius: BorderRadius.circular(t.inputRadius),
                  border: Border.all(color: selecionado ? t.warning : t.border),
                ),
                child: Row(children: [
                  Icon(opcao.$4, size: 19, color: selecionado ? t.warning : t.textMuted),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(opcao.$2, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 11.5)),
                    const SizedBox(height: 2),
                    Text(opcao.$3, style: TextStyle(color: t.textSecondary, fontSize: 9.8, height: 1.25)),
                  ])),
                  RadioGroup<String>(
                    groupValue: _studio.finalidade,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _studio = _studio.copyWith(finalidade: v));
                      }
                    },
                    child: Radio<String>(value: opcao.$1),
                  ),
                ]),
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: t.border),
            ),
            child: Text(
              _studio.ehGraduacao
                  ? 'Modo graduação mantém intacta a lógica histórica: certificado simples, certificado com CPF, diploma e automático pela graduação.'
                  : 'Modo ${_studio.finalidadeLabel}: o template é genérico. CPF, graduação e assinaturas só entram se você ativar esses blocos.',
              style: TextStyle(color: t.textSecondary, fontSize: 10.2, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNASAFoundationCard() {
    final t = context.uai;
    final hasBase = _studio.baseSvgStoragePath?.trim().isNotEmpty == true;
    final blank = _studio.baseEmBranco;
    return _dialogSection(
      icon: Icons.rocket_launch_rounded,
      title: 'Studio NASA • Base visual',
      subtitle: 'Studio universal • importe a arte pronta do Corel como fundo fixo A4 e reutilize no Windows/PWA/APK.',
      color: t.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasBase || blank)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: t.cardAlt,
                borderRadius: BorderRadius.circular(t.inputRadius),
                border: Border.all(color: t.border),
              ),
              child: Row(children: [
                Icon(Icons.insert_drive_file_rounded, color: t.success),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(blank ? 'Canvas A4 em branco' : (_studio.baseSvgNome ?? 'SVG importado'), style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
                  Text(blank ? 'Documento livre ${_studio.larguraDocumentoMm.toStringAsFixed(0)} × ${_studio.alturaDocumentoMm.toStringAsFixed(0)} mm' : 'A4 ${_studio.paginaRetrato ? 'RETRATO' : 'PAISAGEM'} • ${_studio.ajusteBaseSvg.toUpperCase()} • SVG normalizado no Storage', style: TextStyle(color: t.textSecondary, fontSize: 10.5)),
                ])),
                IconButton(tooltip: 'Inspecionar SVG', onPressed: blank ? null : _inspecionarBaseAtual, icon: const Icon(Icons.manage_search_rounded)),
                IconButton(
                  tooltip: 'Voltar ao template UAI original',
                  onPressed: () => setState(() => _studio = _studio.copyWith(limparBaseSvg: true, baseEmBranco: false, substituicoesCor: const {})),
                  icon: Icon(Icons.restore_rounded, color: t.warning),
                ),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(9),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DOCUMENTO A4', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 10.5)),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('RETRATO 210×297'),
                      selected: _studio.paginaRetrato,
                      onSelected: hasBase ? null : (_) => _definirDocumentoA4('portrait'),
                    ),
                    ChoiceChip(
                      label: const Text('PAISAGEM 297×210'),
                      selected: !_studio.paginaRetrato,
                      onSelected: hasBase ? null : (_) => _definirDocumentoA4('landscape'),
                    ),
                  ],
                ),
                if (hasBase) ...[
                  const SizedBox(height: 5),
                  Text('Para trocar a orientação de uma arte importada, use TROCAR SVG BASE e escolha AUTO/RETRATO/PAISAGEM. Assim a arte é recalculada sem deformar.', style: TextStyle(color: t.textSecondary, fontSize: 9.8, height: 1.3)),
                ],
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _importandoSvg || !_podeImportarSvgCorel ? null : _importarSvgComoBase,
                icon: Icon(_podeImportarSvgCorel ? Icons.file_upload_rounded : Icons.desktop_windows_rounded),
                label: Text(!_podeImportarSvgCorel
                    ? 'SVG: SOMENTE WINDOWS'
                    : _importandoSvg
                        ? 'IMPORTANDO...'
                        : hasBase
                            ? 'TROCAR SVG BASE'
                            : 'IMPORTAR SVG DO COREL'),
              ),
              OutlinedButton.icon(
                onPressed: _novoCanvasEmBranco,
                icon: const Icon(Icons.note_add_rounded),
                label: const Text('CANVAS EM BRANCO'),
              ),
              OutlinedButton.icon(
                onPressed: () => _salvarComoTemplate(salvarComoNovo: true),
                icon: const Icon(Icons.save_as_rounded),
                label: const Text('SALVAR COMO TEMPLATE'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Modo Fundo Corel: preserva a arte pronta, normaliza para A4 e gera um fundo fixo universal. Edições artísticas continuam no Corel; dados dinâmicos ficam no Studio.',
            style: TextStyle(color: t.textSecondary, fontSize: 10.8, height: 1.35),
          ),
          if (!_podeImportarSvgCorel) ...[
            const SizedBox(height: 6),
            Text(
              'Neste dispositivo: use normalmente bases SVG já salvas no template. A importação/troca do arquivo Corel fica concentrada no Windows para manter estabilidade.',
              style: TextStyle(color: t.info, fontSize: 10.3, height: 1.3, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editarQrStudio() async {
    final atual = _studio.qrCode;
    final x = TextEditingController(text: atual.x.toStringAsFixed(1));
    final y = TextEditingController(text: atual.y.toStringAsFixed(1));
    final size = TextEditingController(text: atual.tamanhoMm.toStringAsFixed(1));
    final margin = TextEditingController(text: atual.margemMm.toStringAsFixed(1));
    final radius = TextEditingController(text: atual.raioMm.toStringAsFixed(1));
    final border = TextEditingController(text: atual.bordaMm.toStringAsFixed(1));
    final legenda = TextEditingController(text: atual.legenda);
    final legendaPt = TextEditingController(text: atual.legendaPt.toStringAsFixed(1));
    var draft = atual;

    double d(TextEditingController c, double fallback) =>
        double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;

    final result = await showDialog<CertificadoStudioQrConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final t = context.uai;
            Widget corButton(String label, String hex, ValueChanged<Color> apply) {
              final color = _colorFromHex(hex, fallback: Colors.black);
              return OutlinedButton.icon(
                onPressed: () async {
                  await _pickTextoColor(
                    titulo: label,
                    corAtual: color,
                    onColorChanged: (picked) {
                      apply(picked);
                      setDialogState(() {});
                    },
                  );
                },
                icon: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: t.border),
                  ),
                ),
                label: Text(label),
              );
            }

            return AlertDialog(
              title: const Text('QR Code do template'),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.cardAlt,
                          borderRadius: BorderRadius.circular(t.inputRadius),
                          border: Border.all(color: t.border),
                        ),
                        child: Row(children: [
                          Icon(Icons.qr_code_2_rounded, color: t.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            'Aqui você configura apenas o espaço visual. O QR oficial com código único será carimbado somente na emissão V2.',
                            style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.3),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(width: 150, child: TextField(controller: x, decoration: const InputDecoration(labelText: 'X (mm)'))),
                          SizedBox(width: 150, child: TextField(controller: y, decoration: const InputDecoration(labelText: 'Y (mm)'))),
                          SizedBox(width: 150, child: TextField(controller: size, decoration: const InputDecoration(labelText: 'Tamanho (mm)'))),
                          SizedBox(width: 150, child: TextField(controller: margin, decoration: const InputDecoration(labelText: 'Margem (mm)'))),
                          SizedBox(width: 150, child: TextField(controller: radius, decoration: const InputDecoration(labelText: 'Raio (mm)'))),
                          SizedBox(width: 150, child: TextField(controller: border, decoration: const InputDecoration(labelText: 'Borda (mm)'))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          corButton('Cor do QR', draft.corQrHex, (c) => draft = draft.copyWith(corQrHex: _colorToHex(c))),
                          corButton('Fundo', draft.corFundoHex, (c) => draft = draft.copyWith(corFundoHex: _colorToHex(c))),
                          corButton('Borda', draft.corBordaHex, (c) => draft = draft.copyWith(corBordaHex: _colorToHex(c))),
                          corButton('Legenda', draft.corLegendaHex, (c) => draft = draft.copyWith(corLegendaHex: _colorToHex(c))),
                        ],
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fundo transparente'),
                        value: draft.fundoTransparente,
                        onChanged: (v) => setDialogState(() => draft = draft.copyWith(fundoTransparente: v)),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar legenda'),
                        value: draft.mostrarLegenda,
                        onChanged: (v) => setDialogState(() => draft = draft.copyWith(mostrarLegenda: v)),
                      ),
                      if (draft.mostrarLegenda) ...[
                        TextField(controller: legenda, decoration: const InputDecoration(labelText: 'Texto da legenda')),
                        const SizedBox(height: 10),
                        SizedBox(width: 180, child: TextField(controller: legendaPt, decoration: const InputDecoration(labelText: 'Legenda (pt)'))),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCELAR')),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, draft.copyWith(
                      x: d(x, draft.x).clamp(0.0, 594.0).toDouble(),
                      y: d(y, draft.y).clamp(0.0, 420.0).toDouble(),
                      tamanhoMm: d(size, draft.tamanhoMm).clamp(14.0, 60.0).toDouble(),
                      margemMm: d(margin, draft.margemMm).clamp(0.0, 6.0).toDouble(),
                      raioMm: d(radius, draft.raioMm).clamp(0.0, 8.0).toDouble(),
                      bordaMm: d(border, draft.bordaMm).clamp(0.0, 2.5).toDouble(),
                      legenda: legenda.text.trim().isEmpty ? 'Verificar autenticidade' : legenda.text.trim(),
                      legendaPt: d(legendaPt, draft.legendaPt).clamp(5.0, 16.0).toDouble(),
                    ));
                  },
                  child: const Text('APLICAR'),
                ),
              ],
            );
          },
        );
      },
    );
    for (final c in [x, y, size, margin, radius, border, legenda, legendaPt]) {
      c.dispose();
    }
    if (result == null || !mounted) return;
    setState(() {
      _studio = _studio.copyWith(qrCode: result);
      _qrSelected = true;
      _selectedLayerId = null;
      _selectedTextId = null;
    });
  }

  Widget _buildQrStudioCard() {
    final t = context.uai;
    final qr = _studio.qrCode;
    return _dialogSection(
      icon: Icons.qr_code_2_rounded,
      title: 'QR Code de autenticidade',
      subtitle: 'O template guarda posição e aparência. O código real só nasce na emissão oficial V2.',
      color: t.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _qrSelected ? Color.alphaBlend(t.success.withAlpha(20), t.cardAlt) : t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: _qrSelected ? t.success : t.border),
            ),
            child: Row(children: [
              Icon(Icons.qr_code_scanner_rounded, color: qr.ativo ? t.success : t.textMuted),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(qr.ativo ? 'QR preparado neste template' : 'QR desativado neste template', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 11.5)),
                Text('x ${qr.x.toStringAsFixed(1)} • y ${qr.y.toStringAsFixed(1)} • ${qr.tamanhoMm.toStringAsFixed(1)} mm', style: TextStyle(color: t.textSecondary, fontSize: 9.8)),
              ])),
              IconButton(
                tooltip: qr.bloqueado ? 'Desbloquear posição' : 'Bloquear posição',
                onPressed: qr.ativo ? () => setState(() => _studio = _studio.copyWith(qrCode: qr.copyWith(bloqueado: !qr.bloqueado))) : null,
                icon: Icon(qr.bloqueado ? Icons.lock_rounded : Icons.lock_open_rounded, size: 18),
              ),
              Switch(
                value: qr.ativo,
                onChanged: (v) => setState(() {
                  _studio = _studio.copyWith(qrCode: qr.copyWith(ativo: v));
                  _qrSelected = v;
                  if (v) { _selectedLayerId = null; _selectedTextId = null; }
                }),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: qr.ativo ? _editarQrStudio : null,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('PERSONALIZAR QR'),
          ),
          if (qr.ativo) ...[
            const SizedBox(height: 6),
            Text('Dica: clique no QR no Canvas e arraste para posicionar. Use a alça azul no canto para redimensionar.', style: TextStyle(color: t.textSecondary, fontSize: 10.2, height: 1.3)),
          ],
        ],
      ),
    );
  }

  Widget _buildBlocosDinamicosCard() {
    final t = context.uai;
    const blocks = [
      ('nome', 'Nome do participante', Icons.person_rounded, true),
      ('cpf', 'CPF', Icons.badge_rounded, true),
      ('graduacao', 'Graduação / título', Icons.workspace_premium_rounded, true),
      ('frase', 'Frase dinâmica', Icons.notes_rounded, true),
      ('local_data', 'Local e data', Icons.event_rounded, true),
      ('assinatura_nome', 'Nomes das assinaturas', Icons.draw_rounded, false),
      ('assinatura_apelido', 'Cargos das assinaturas', Icons.military_tech_rounded, false),
    ];
    return _dialogSection(
      icon: Icons.data_object_rounded,
      title: 'Blocos dinâmicos',
      subtitle: _studio.ehGraduacao
          ? 'Batizado/troca de cordas mantém graduação obrigatória. Os demais blocos seguem configuráveis.'
          : 'Você decide o que existe neste certificado. Graduação, CPF e assinaturas são opcionais.',
      color: t.info,
      child: Column(
        children: blocks.map((b) {
          final ativo = _studio.blocoAtivo(b.$1);
          return Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: t.cardAlt, borderRadius: BorderRadius.circular(t.inputRadius), border: Border.all(color: t.border)),
            child: Row(children: [
              Icon(b.$3, color: ativo ? _ensureVisible(t.info, t.cardAlt) : t.textMuted, size: 19),
              const SizedBox(width: 8),
              Expanded(child: Text(b.$2, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800, fontSize: 11.5))),
              if (b.$4)
                TextButton(
                  onPressed: () => _editarLayoutBloco(b.$1, b.$2),
                  child: const Text('POSIÇÃO'),
                ),
              Switch(
                value: ativo,
                onChanged: (value) {
                  final map = Map<String, bool>.from(_studio.blocosAtivos);
                  map[b.$1] = value;
                  setState(() => _studio = _studio.copyWith(blocosAtivos: map));
                },
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextosLivresCard() {
    final t = context.uai;
    return _dialogSection(
      icon: Icons.text_fields_rounded,
      title: 'Textos livres do canvas',
      subtitle: 'Crie textos estáticos ou use variáveis dinâmicas. Arraste diretamente no canvas.',
      color: t.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => _editarTextoLivre(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('ADICIONAR TEXTO LIVRE'),
          ),
          if (_studio.textosLivres.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._studio.textosLivres.reversed.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _selectedTextId == item.id
                    ? Color.alphaBlend(t.info.withAlpha(20), t.cardAlt)
                    : t.cardAlt,
                borderRadius: BorderRadius.circular(t.inputRadius),
                border: Border.all(color: _selectedTextId == item.id ? t.info : t.border),
              ),
              child: Row(children: [
                Icon(Icons.title_rounded, color: item.visivel ? t.info : t.textMuted, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800, fontSize: 11.5)),
                  Text(item.textoTemplate, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textSecondary, fontSize: 9.8)),
                ])),
                IconButton(
                  tooltip: item.visivel ? 'Ocultar' : 'Mostrar',
                  onPressed: () {
                    final updated = _studio.textosLivres.map((e) => e.id == item.id ? e.copyWith(visivel: !e.visivel) : e).toList();
                    setState(() => _studio = _studio.copyWith(textosLivres: updated));
                  },
                  icon: Icon(item.visivel ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                ),
                IconButton(
                  tooltip: item.bloqueada ? 'Desbloquear' : 'Bloquear',
                  onPressed: () {
                    final updated = _studio.textosLivres.map((e) => e.id == item.id ? e.copyWith(bloqueada: !e.bloqueada) : e).toList();
                    setState(() => _studio = _studio.copyWith(textosLivres: updated));
                  },
                  icon: Icon(item.bloqueada ? Icons.lock_rounded : Icons.lock_open_rounded, size: 18),
                ),
                IconButton(onPressed: () => _editarTextoLivre(item), icon: const Icon(Icons.tune_rounded, size: 18), tooltip: 'Editar'),
                IconButton(
                  onPressed: () => setState(() {
                    _studio = _studio.copyWith(textosLivres: _studio.textosLivres.where((e) => e.id != item.id).toList());
                    if (_selectedTextId == item.id) _selectedTextId = null;
                  }),
                  icon: Icon(Icons.delete_outline_rounded, color: t.error, size: 18),
                  tooltip: 'Remover',
                ),
              ]),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildCamadasCard() {
    final t = context.uai;
    return _dialogSection(
      icon: Icons.layers_rounded,
      title: 'Camadas fixas SVG',
      subtitle: 'Adicione logos, molduras, selos e ornamentos independentes sobre a base.',
      color: t.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _importandoSvg || !_podeImportarSvgCorel ? null : _adicionarCamadaSvg,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: Text(_podeImportarSvgCorel ? 'ADICIONAR CAMADA SVG' : 'CAMADA SVG: WINDOWS'),
          ),
          if (_studio.camadas.isEmpty) ...[
            const SizedBox(height: 8),
            Text('Nenhuma camada extra. A base continua funcionando normalmente.', style: TextStyle(color: t.textSecondary, fontSize: 10.8)),
          ] else ...[
            const SizedBox(height: 8),
            ..._studio.camadas.reversed.map((layer) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: t.cardAlt, borderRadius: BorderRadius.circular(t.inputRadius), border: Border.all(color: t.border)),
              child: Row(children: [
                Icon(layer.visivel ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: layer.visivel ? t.success : t.textMuted, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(layer.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800, fontSize: 11.5)),
                  Text('x ${layer.x.toStringAsFixed(1)} • y ${layer.y.toStringAsFixed(1)} • ${layer.largura.toStringAsFixed(1)}×${layer.altura.toStringAsFixed(1)} mm', style: TextStyle(color: t.textSecondary, fontSize: 9.5)),
                ])),
                IconButton(
                  tooltip: layer.visivel ? 'Ocultar' : 'Mostrar',
                  onPressed: () {
                    final updated = _studio.camadas.map((e) => e.id == layer.id ? e.copyWith(visivel: !e.visivel) : e).toList();
                    setState(() => _studio = _studio.copyWith(camadas: updated));
                  },
                  icon: Icon(layer.visivel ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                ),
                IconButton(
                  tooltip: layer.bloqueada ? 'Desbloquear camada' : 'Bloquear camada',
                  onPressed: () {
                    final updated = _studio.camadas.map((e) => e.id == layer.id ? e.copyWith(bloqueada: !e.bloqueada) : e).toList();
                    setState(() => _studio = _studio.copyWith(camadas: updated));
                  },
                  icon: Icon(layer.bloqueada ? Icons.lock_rounded : Icons.lock_open_rounded, size: 18),
                ),
                IconButton(tooltip: 'Inspecionar/recolorir SVG', onPressed: () => _inspecionarCamada(layer.id), icon: const Icon(Icons.manage_search_rounded, size: 18)),
                IconButton(tooltip: 'Posição e tamanho', onPressed: () => _editarCamada(layer), icon: const Icon(Icons.tune_rounded, size: 18)),
                IconButton(
                  tooltip: 'Remover camada',
                  onPressed: () => setState(() {
                    _studio = _studio.copyWith(camadas: _studio.camadas.where((e) => e.id != layer.id).toList());
                    if (_selectedLayerId == layer.id) _selectedLayerId = null;
                  }),
                  icon: Icon(Icons.delete_outline_rounded, color: t.error, size: 18),
                ),
              ]),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildInspectorResumoCard() {
    final t = context.uai;
    final base = _studio.baseEmBranco
        ? 'Canvas A4 em branco'
        : (_studio.baseSvgNome ?? 'Modelo UAI interno');
    final ativos = CertificadoStudioConfig.blocosPadrao.keys.where(_studio.blocoAtivo).length;
    return _dialogSection(
      icon: Icons.account_tree_rounded,
      title: 'Inspector do Studio',
      subtitle: 'Estrutura atual do documento.',
      color: t.success,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _miniInspectorLine('Finalidade', _studio.finalidadeLabel),
        _miniInspectorLine('Base', base),
        _miniInspectorLine('Camadas SVG', '${_studio.camadas.length}'),
        _miniInspectorLine('Textos livres', '${_studio.textosLivres.length}'),
        _miniInspectorLine('Blocos dinâmicos', '$ativos ativos'),
        _miniInspectorLine('QR autenticidade', _studio.qrCode.ativo ? '${_studio.qrCode.tamanhoMm.toStringAsFixed(0)} mm' : 'desativado'),
        _miniInspectorLine('Layouts livres', '${_studio.blocosLayout.length}'),
        _miniInspectorLine('Cores remapeadas', '${_studio.substituicoesCor.length}'),
        if (_studio.templateNome != null) _miniInspectorLine('Template', _studio.templateNome!),
      ]),
    );
  }

  Widget _miniInspectorLine(String label, String value) {
    final t = context.uai;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: t.textSecondary, fontSize: 10.5))),
        Flexible(child: Text(value, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  Widget _buildStudioInfoCard() {
    final t = context.uai;
    return _dialogSection(
      icon: Icons.layers_rounded,
      title: 'Motor do Studio',
      subtitle: 'A prévia e o PDF usam a mesma paleta persistida no evento.',
      color: t.info,
      child: Text(
        'O fundo, estrutura, destaques e detalhes agora fazem parte da configuração do certificado. Os dados antigos continuam usando a paleta original automaticamente.',
        style: TextStyle(color: t.textSecondary, fontSize: 11.7, height: 1.35),
      ),
    );
  }

  List<Widget> _configSectionWidgets({
    required bool includeInlinePreview,
  }) {
    return [
      _buildAtivacaoCard(),
      const SizedBox(height: 12),
      _buildFinalidadeCertificadoCard(),
      const SizedBox(height: 12),
      _buildNASAFoundationCard(),
      const SizedBox(height: 12),
      _buildBlocosDinamicosCard(),
      const SizedBox(height: 12),
      _buildQrStudioCard(),
      const SizedBox(height: 12),
      _buildTextosLivresCard(),
      const SizedBox(height: 12),
      _buildCamadasCard(),
      const SizedBox(height: 12),
      if (_studio.ehGraduacao) ...[
        _buildModeloCard(),
        const SizedBox(height: 12),
      ],
      _buildPaletaVisualCard(compact: false),
      const SizedBox(height: 12),
      _buildOrigemLocalDataCard(),
      const SizedBox(height: 12),
      _buildTextosCard(),
      const SizedBox(height: 12),
      _buildAssinaturasCard(),
      if (includeInlinePreview) ...[
        const SizedBox(height: 12),
        _buildPreviewCertificadoCardReactive(expanded: false),
      ],
    ];
  }


  Widget _buildAtivacaoCard() {
    final t = context.uai;
    final accent = _ensureVisible(_ativo ? t.success : t.warning, t.card);

    return _dialogSection(
      icon: _ativo ? Icons.check_circle_rounded : Icons.block_rounded,
      title: 'Status do certificado',
      subtitle: _ativo
          ? 'As configurações serão salvas junto com o evento.'
          : 'O evento ficará sem configuração personalizada de certificado.',
      color: accent,
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _ativo,
          activeThumbColor: switch (Theme.of(context).platform) {
            TargetPlatform.iOS || TargetPlatform.macOS => null,
            _ => accent,
          },
          activeTrackColor: switch (Theme.of(context).platform) {
            TargetPlatform.iOS || TargetPlatform.macOS => accent,
            _ => null,
          },
          onChanged: (value) => setState(() => _ativo = value),
          title: Text(
            _ativo ? 'Certificados ativos' : 'Certificados desativados',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            'Esse controle acompanha o botão principal de certificados do evento.',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildModeloCard() {
    final t = context.uai;

    return _dialogSection(
      icon: Icons.view_quilt_rounded,
      title: 'Modelo do certificado',
      subtitle: 'O recomendado é deixar automático pela graduação.',
      color: t.info,
      child: Column(
        children: _modelos.map((modelo) {
          final selected = _modeloPadrao == modelo.id;
          final accent = _ensureVisible(
            selected ? t.primary : t.textSecondary,
            t.card,
          );

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: selected
                  ? Color.alphaBlend(accent.withAlpha(26), t.cardAlt)
                  : t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _modeloPadrao = modelo.id),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.inputRadius),
                    border: Border.all(
                      color: selected ? accent.withAlpha(71) : t.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(modelo.icon, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modelo.title,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              modelo.subtitle,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11.6,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPaletaVisualCard({required bool compact}) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    final itens = <({String titulo, String subtitulo, String hex, IconData icon, ValueChanged<String> onChanged})>[
      (
        titulo: 'Fundo do certificado',
        subtitulo: 'Substitui o cinza original do papel.',
        hex: _visual.corFundo,
        icon: Icons.format_color_fill_rounded,
        onChanged: (hex) => _visual = _visual.copyWith(corFundo: hex),
      ),
      (
        titulo: 'Estrutura / moldura',
        subtitulo: 'Tons escuros da arte e dos gradientes.',
        hex: _visual.corEstrutura,
        icon: Icons.crop_square_rounded,
        onChanged: (hex) => _visual = _visual.copyWith(corEstrutura: hex),
      ),
      (
        titulo: 'Destaques da arte',
        subtitulo: 'Vermelhos, vinhos e destaques fixos do SVG.',
        hex: _visual.corDestaque,
        icon: Icons.auto_awesome_rounded,
        onChanged: (hex) => _visual = _visual.copyWith(corDestaque: hex),
      ),
      (
        titulo: 'Detalhes',
        subtitulo: 'Pequenos ornamentos e cinzas auxiliares.',
        hex: _visual.corDetalhe,
        icon: Icons.blur_on_rounded,
        onChanged: (hex) => _visual = _visual.copyWith(corDetalhe: hex),
      ),
    ];

    return _dialogSection(
      icon: Icons.palette_rounded,
      title: 'Paleta do canvas',
      subtitle: 'Recolore a arte fixa do SVG sem alterar a graduação dinâmica.',
      color: t.warning,
      child: Column(
        children: [
          for (var i = 0; i < itens.length; i++) ...[
            _buildVisualColorTile(
              titulo: itens[i].titulo,
              subtitulo: itens[i].subtitulo,
              hex: itens[i].hex,
              icon: itens[i].icon,
              compact: compact,
              onChanged: itens[i].onChanged,
            ),
            if (i != itens.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _visual = const CertificadoVisualConfig());
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('RESTAURAR PALETA ORIGINAL'),
              style: OutlinedButton.styleFrom(foregroundColor: primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualColorTile({
    required String titulo,
    required String subtitulo,
    required String hex,
    required IconData icon,
    required bool compact,
    required ValueChanged<String> onChanged,
  }) {
    final t = context.uai;
    final color = _colorFromHex(hex, fallback: t.primary);
    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await _pickTextoColor(
            titulo: titulo,
            corAtual: color,
            onColorChanged: (novaCor) => onChanged(_colorToHex(novaCor)),
          );
        },
        child: Container(
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(t.inputRadius),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.border, width: 1.5),
                ),
                child: Icon(icon, color: _readableOn(color), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800, fontSize: compact ? 11.5 : 12.5)),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(subtitulo, style: TextStyle(color: t.textSecondary, fontSize: 10.8, height: 1.2)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(hex.toUpperCase(), style: TextStyle(color: t.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrigemLocalDataCard() {
    final t = context.uai;

    return _dialogSection(
      icon: Icons.location_on_rounded,
      title: 'Local e data',
      subtitle: 'O certificado usa cidade e data cadastradas no evento.',
      color: t.warning,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _usarCidadeDoEvento,
              activeColor: _ensureVisible(t.primary, t.card),
              onChanged: (value) {
                setState(() => _usarCidadeDoEvento = value ?? true);
              },
              title: Text(
                'Usar cidade do evento',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Ex.: BOCAIUVA-MG',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _usarDataDoEvento,
              activeColor: _ensureVisible(t.primary, t.card),
              onChanged: (value) {
                setState(() => _usarDataDoEvento = value ?? true);
              },
              title: Text(
                'Usar data do evento',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Ex.: 20 DE JUNHO DE 2026',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Color _hexToColor(String value, Color fallback) {
    final clean = value.trim().replaceAll('#', '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) return fallback;
    return Color(int.parse('FF$clean', radix: 16));
  }


  void _atualizarTexto(
    String campo,
    CertificadoTextoCampoConfig Function(CertificadoTextoCampoConfig atual)
    update,
  ) {
    setState(() {
      final atual =
          _textos[campo] ??
          CertificadoTextoCampoConfig.defaults[campo] ??
          CertificadoTextoCampoConfig.padraoGenerico;

      _textos[campo] = update(atual);
    });
  }

  void _resetarTextosPadrao() {
    setState(() {
      _textos = Map<String, CertificadoTextoCampoConfig>.from(
        CertificadoTextoCampoConfig.defaults,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Configurações de texto restauradas para o padrão.',
        ),
        backgroundColor: context.uai.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildTextosCard() {
    final t = context.uai;

    return _dialogSection(
      icon: Icons.format_size_rounded,
      title: 'Visual dos textos',
      subtitle:
          'Configure fonte, tamanho em pt real, cor, alinhamento, espaçamento e posição vertical.',
      color: t.primary,
      child: Column(
        children: [
          _textosInfoBox(),
          const SizedBox(height: 12),
          _resetTextosButton(),
          const SizedBox(height: 12),
          ..._camposTexto.map((campo) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _textoConfigCard(campo),
            );
          }),
        ],
      ),
    );
  }

  Widget _textosInfoBox() {
    final t = context.uai;
    final info = _ensureVisible(t.info, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(info.withAlpha(23), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: info.withAlpha(41)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_rounded, color: info, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Os campos simples continuam se autoajustando dentro da caixa-guia. '
              'A frase quebra linha normalmente e usa o espaçamento vertical configurado.',
              style: TextStyle(
                color: info,
                fontSize: 12,
                height: 1.28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resetTextosButton() {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.cardAlt);

    return Material(
      color: Color.alphaBlend(danger.withAlpha(20), t.cardAlt),
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _resetarTextosPadrao,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: danger.withAlpha(51)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: danger.withAlpha(31),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: danger.withAlpha(41)),
                ),
                child: Icon(Icons.restart_alt_rounded, color: danger, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resetar textos para o padrão',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Volta fonte, tamanho, cor, alinhamento e espaçamento para o padrão de fábrica do UAI.',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.2,
                        height: 1.22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: danger),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textoConfigCard(_CampoTextoOption campo) {
    final t = context.uai;
    final config =
        _textos[campo.id] ??
        CertificadoTextoCampoConfig.defaults[campo.id] ??
        CertificadoTextoCampoConfig.padraoGenerico;

    final accent = _ensureVisible(t.primary, t.cardAlt);
    final corTexto = _hexToColor(config.corHex, const Color(0xFF1A0202));
    final fonteValue =
        CertificadoTextoCampoConfig.fontesDisponiveis.contains(config.fonte)
        ? config.fonte
        : CertificadoTextoCampoConfig.fontesDisponiveis.first;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withAlpha(36)),
                ),
                child: Icon(campo.icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campo.title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      campo.subtitle,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.3,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: corTexto,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.border, width: 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;

              final fonte = DropdownButtonFormField<String>(
                initialValue: fonteValue,
                isExpanded: true,
                dropdownColor: t.surface,
                style: TextStyle(color: t.textPrimary),
                decoration: _inputDecoration(
                  label: 'Fonte',
                  icon: Icons.font_download_rounded,
                ),
                items: CertificadoTextoCampoConfig.fontesDisponiveis.map((
                  fonte,
                ) {
                  return DropdownMenuItem<String>(
                    value: fonte,
                    child: Text(
                      fonte,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textPrimary, fontFamily: fonte),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  _atualizarTexto(
                    campo.id,
                    (atual) => atual.copyWith(fonte: value),
                  );
                },
              );

              final tamanho = _fontSizePtSelector(campo: campo, config: config);

              if (narrow) {
                return Column(
                  children: [fonte, const SizedBox(height: 10), tamanho],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 2, child: fonte),
                  const SizedBox(width: 10),
                  Expanded(child: tamanho),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;

              final cor = _textoColorButton(campo: campo, config: config);

              final lineHeight = _lineHeightSlider(
                campo: campo,
                config: config,
              );

              if (narrow) {
                return Column(
                  children: [cor, const SizedBox(height: 10), lineHeight],
                );
              }

              return Row(
                children: [
                  Expanded(child: cor),
                  const SizedBox(width: 10),
                  Expanded(child: lineHeight),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _verticalOffsetSlider(campo: campo, config: config),
          const SizedBox(height: 10),
          _alignmentSelector(campo.id, config),
          const SizedBox(height: 10),
          _caseSelector(campo.id, config),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tinyToggleChip(
                label: 'Negrito',
                icon: Icons.format_bold_rounded,
                value: config.negrito,
                onTap: () {
                  _atualizarTexto(
                    campo.id,
                    (atual) => atual.copyWith(negrito: !atual.negrito),
                  );
                },
              ),
              if (campo.autoAjustarEditavel)
                _tinyToggleChip(
                  label: 'Autoajustar',
                  icon: Icons.fit_screen_rounded,
                  value: config.autoAjustar,
                  onTap: () {
                    _atualizarTexto(
                      campo.id,
                      (atual) =>
                          atual.copyWith(autoAjustar: !atual.autoAjustar),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          _textoPreviewLinha(campo, config),
        ],
      ),
    );
  }

  List<double> _fontSizeOptions(double current) {
    final base = <double>[
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      22,
      24,
      26,
      28,
      30,
      32,
      36,
      40,
      44,
      48,
      56,
      64,
      72,
    ];

    final normalized = current <= 0 ? 12.0 : current;
    final rounded = double.parse(normalized.toStringAsFixed(1));

    final values = <double>{...base, rounded}.toList()..sort();
    return values;
  }

  Widget _fontSizePtSelector({
    required _CampoTextoOption campo,
    required CertificadoTextoCampoConfig config,
  }) {
    final t = context.uai;
    final current = double.parse(config.tamanho.toStringAsFixed(1));
    final values = _fontSizeOptions(current);

    return DropdownButtonFormField<double>(
      initialValue: values.contains(current) ? current : values.first,
      isExpanded: true,
      dropdownColor: t.surface,
      style: TextStyle(color: t.textPrimary),
      decoration:
          _inputDecoration(
            label: 'Tamanho',
            icon: Icons.format_size_rounded,
            hint: 'pt',
          ).copyWith(
            suffixText: 'pt',
            helperText: 'Tamanho real do PDF',
            helperStyle: TextStyle(color: t.textMuted, fontSize: 10.5),
          ),
      items: values.map((value) {
        final label = value % 1 == 0
            ? value.toInt().toString()
            : value.toStringAsFixed(1);

        return DropdownMenuItem<double>(
          value: value,
          child: Text(
            '$label pt',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: value == current ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        _atualizarTexto(campo.id, (atual) => atual.copyWith(tamanho: value));
      },
    );
  }

  Widget _lineHeightSlider({
    required _CampoTextoOption campo,
    required CertificadoTextoCampoConfig config,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    final value = config.lineHeight.clamp(0.75, 1.80).toDouble();

    return _sliderBox(
      icon: Icons.format_line_spacing_rounded,
      title: campo.mostrarLineHeight
          ? 'Espaçamento entre linhas'
          : 'Altura da linha',
      subtitle:
          'Padrão ${_defaultConfig(campo.id).lineHeight.toStringAsFixed(2)}',
      valueLabel: value.toStringAsFixed(2),
      value: value,
      min: 0.75,
      max: 1.80,
      divisions: 105,
      activeColor: primary,
      onChanged: (newValue) {
        _atualizarTexto(
          campo.id,
          (atual) => atual.copyWith(
            lineHeight: double.parse(newValue.toStringAsFixed(2)),
          ),
        );
      },
    );
  }

  Widget _verticalOffsetSlider({
    required _CampoTextoOption campo,
    required CertificadoTextoCampoConfig config,
  }) {
    final t = context.uai;
    final warning = _ensureVisible(t.warning, t.cardAlt);
    final value = config.verticalOffsetMm.clamp(-4.0, 4.0).toDouble();

    return _sliderBox(
      icon: Icons.vertical_align_center_rounded,
      title: 'Posição vertical',
      subtitle: '0 é o padrão. Negativo sobe, positivo desce.',
      valueLabel: '${value.toStringAsFixed(1)} mm',
      value: value,
      min: -4.0,
      max: 4.0,
      divisions: 80,
      activeColor: warning,
      onChanged: (newValue) {
        _atualizarTexto(
          campo.id,
          (atual) => atual.copyWith(
            verticalOffsetMm: double.parse(newValue.toStringAsFixed(1)),
          ),
        );
      },
    );
  }

  CertificadoTextoCampoConfig _defaultConfig(String campoId) {
    return CertificadoTextoCampoConfig.defaults[campoId] ??
        CertificadoTextoCampoConfig.padraoGenerico;
  }

  Widget _sliderBox({
    required IconData icon,
    required String title,
    required String subtitle,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(activeColor, t.cardAlt);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 12.3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 10.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withAlpha(26), t.card),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: accent.withAlpha(46)),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: accent,
            inactiveColor: t.border,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _textoColorButton({
    required _CampoTextoOption campo,
    required CertificadoTextoCampoConfig config,
  }) {
    final t = context.uai;
    final color = _hexToColor(config.corHex, const Color(0xFF1A0202));
    final visibleColor = _ensureVisible(color, t.cardAlt);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _pickTextoColor(
          titulo: 'Cor do texto • ${campo.title}',
          corAtual: color,
          onColorChanged: (newColor) {
            _atualizarTexto(
              campo.id,
              (atual) => atual.copyWith(corHex: _colorToHex(newColor)),
            );
          },
        ),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.surface, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: visibleColor.withAlpha(56),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cor do texto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      config.corHex,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.palette_rounded,
                color: _ensureVisible(t.primary, t.card),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _caseSelector(String campoId, CertificadoTextoCampoConfig config) {
    final t = context.uai;

    final items = const [
      ('upper', 'MAIÚSCULAS', Icons.text_fields_rounded),
      ('lower', 'minúsculas', Icons.keyboard_arrow_down_rounded),
      ('title', 'Iniciais', Icons.title_rounded),
      ('none', 'Original', Icons.format_clear_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Formato das letras',
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 11.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 480;

            final chips = items.map((item) {
              final selected = config.textCase == item.$1;
              final accent = _ensureVisible(
                selected ? t.primary : t.textSecondary,
                t.cardAlt,
              );

              return Material(
                color: selected
                    ? Color.alphaBlend(accent.withAlpha(26), t.cardAlt)
                    : t.card,
                borderRadius: BorderRadius.circular(t.inputRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    _atualizarTexto(
                      campoId,
                      (atual) => atual.copyWith(textCase: item.$1),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.inputRadius),
                      border: Border.all(
                        color: selected ? accent.withAlpha(82) : t.border,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item.$3, color: accent, size: 16),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? accent : t.textSecondary,
                              fontSize: 10.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList();

            if (narrow) {
              return Wrap(
                spacing: 7,
                runSpacing: 7,
                children: chips
                    .map(
                      (chip) => SizedBox(
                        width: (constraints.maxWidth - 7) / 2,
                        child: chip,
                      ),
                    )
                    .toList(),
              );
            }

            return Row(
              children: List.generate(chips.length, (index) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == chips.length - 1 ? 0 : 7,
                    ),
                    child: chips[index],
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _alignmentSelector(
    String campoId,
    CertificadoTextoCampoConfig config,
  ) {
    final t = context.uai;

    final items = const [
      ('left', 'Esquerda', Icons.format_align_left_rounded),
      ('center', 'Centro', Icons.format_align_center_rounded),
      ('right', 'Direita', Icons.format_align_right_rounded),
    ];

    return Row(
      children: items.map((item) {
        final selected = config.alinhamento == item.$1;
        final accent = _ensureVisible(
          selected ? t.primary : t.textSecondary,
          t.cardAlt,
        );

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: item.$1 == 'right' ? 0 : 7),
            child: Material(
              color: selected
                  ? Color.alphaBlend(accent.withAlpha(26), t.cardAlt)
                  : t.card,
              borderRadius: BorderRadius.circular(t.inputRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  _atualizarTexto(
                    campoId,
                    (atual) => atual.copyWith(alinhamento: item.$1),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.inputRadius),
                    border: Border.all(
                      color: selected ? accent.withAlpha(82) : t.border,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(item.$3, color: accent, size: 18),
                      const SizedBox(height: 4),
                      Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? accent : t.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _tinyToggleChip({
    required String label,
    required IconData icon,
    required bool value,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(
      value ? t.primary : t.textSecondary,
      t.cardAlt,
    );

    return Material(
      color: value
          ? Color.alphaBlend(accent.withAlpha(26), t.cardAlt)
          : t.card,
      borderRadius: BorderRadius.circular(99),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: value ? accent.withAlpha(77) : t.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 15),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: value ? accent : t.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textoPreviewLinha(
    _CampoTextoOption campo,
    CertificadoTextoCampoConfig config,
  ) {
    final t = context.uai;
    final color = _hexToColor(config.corHex, t.textPrimary);
    final align = switch (config.alinhamento) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };

    final sample = switch (campo.id) {
      CertificadoTextoCampoConfig.campoNome => 'MARIA ELISA PEREIRA DE FREITAS',
      CertificadoTextoCampoConfig.campoCpf => 'CPF: 142.760.696-02',
      CertificadoTextoCampoConfig.campoGraduacao => 'MONITORA - AZUL / ROXO',
      CertificadoTextoCampoConfig.campoFrase =>
        'CERTIFICAMOS QUE, {nome}, {portador_cpf}, {cpf}, CONCLUIU COM ÊXITO...',
      CertificadoTextoCampoConfig.campoAssinaturaNome =>
        'JOÃO LUCAS SILVA RABELO',
      CertificadoTextoCampoConfig.campoAssinaturaApelido =>
        '(PROFESSOR TICO-TICO)',
      CertificadoTextoCampoConfig.campoLocalData =>
        'BOCAIUVA-MG, 21 DE JUNHO DE 2026',
      _ => 'EXEMPLO DE TEXTO',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Text(
        config.aplicarCaixa(sample),
        textAlign: align,
        maxLines: campo.mostrarLineHeight ? 3 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontFamily: config.fonte,
          fontSize: config.tamanho.clamp(8.0, 28.0),
          height: config.lineHeight,
          fontWeight: config.negrito ? FontWeight.w900 : FontWeight.w500,
        ),
      ),
    );
  }

  CertificadoTemplateTipo _previewTipo() {
    switch (_modeloPadrao) {
      case 'DIPLOMA':
        return CertificadoTemplateTipo.diploma;
      case 'CERTIFICADOCOMCPF':
        return CertificadoTemplateTipo.certificadoComCpf;
      case 'CERTIFICADO':
        return CertificadoTemplateTipo.certificadoSemCpf;
      case ConfiguracoesCertificadoEvento.modeloAutomatico:
      default:
        return CertificadoTemplateTipo.certificadoComCpf;
    }
  }

  List<CertificadoAssinaturaData> _previewAssinaturas() {
    // A prévia usa exatamente os 5 slots que serão enviados ao PDF final.
    // Não compacta lacunas e não inventa placeholders que não serão impressos.
    return List.generate(5, (i) {
      return CertificadoAssinaturaData(
        nome: _nomeControllers[i].text.trim(),
        apelido: _apelidoControllers[i].text.trim(),
      );
    });
  }

  CertificadoPreviewData _previewData() {
    final tipo = _previewTipo();
    final graduacao = switch (tipo) {
      CertificadoTemplateTipo.diploma => 'PROFESSORA - MARROM',
      CertificadoTemplateTipo.certificadoComCpf => 'MONITORA - AZUL / ROXO',
      CertificadoTemplateTipo.certificadoSemCpf => '6° ADULTO - AZUL',
    };

    return CertificadoPreviewData(
      alunoNome: 'MARIA ELISA PEREIRA DE FREITAS',
      cpf: tipo == CertificadoTemplateTipo.certificadoSemCpf
          ? null
          : '14276069602',
      sexo: 'FEMININO',
      graduacaoNova: graduacao,
      frase: tipo == CertificadoTemplateTipo.certificadoSemCpf
          ? 'CERTIFICAMOS QUE O(A) ALUNO(A) ACIMA ESTÁ APTO(A) E APROVADO(A) PARA RECEBER A GRADUAÇÃO EM CAPOEIRA, POR DEMONSTRAR INTERESSE NA ARTE E CULTURA BRASILEIRA, SENDO RECONHECIDO(A) PELOS MESTRES, CONTRAMESTRES, PROFESSORES E FORMADOS DO GRUPO.'
          : 'CERTIFICAMOS QUE, {nome}, {portador_cpf}, {cpf}, CONCLUIU COM ÊXITO O CURSO DE CAPOEIRA, DEMONSTRANDO PLENO DOMÍNIO E HABILIDADE NESSA ARTE. COMO RESULTADO DE SEU DESEMPENHO EXCEPCIONAL, É {reconhecido} COMO {apto} E {aprovado} PARA EXERCER A FUNÇÃO DE PROFISSIONAL NESSA ÁREA, OSTENTANDO O TÍTULO DE {titulo_graduacao}, SENDO ATRIBUÍDA A CORDA AZUL / ROXO EM SUA GRADUAÇÃO.',
      localData: 'BOCAIUVA-MG, 21 DE JUNHO DE 2026',
      assinaturas: _previewAssinaturas(),
    );
  }

  ConfiguracoesCertificadoEvento _configuracaoAtualParaPreview() {
    final assinaturas = <AssinaturaCertificadoEvento>[];

    for (var i = 0; i < 5; i++) {
      assinaturas.add(
        AssinaturaCertificadoEvento(
          slot: i + 1,
          nome: _nomeControllers[i].text.trim(),
          apelido: _apelidoControllers[i].text.trim(),
        ),
      );
    }

    return ConfiguracoesCertificadoEvento(
      ativo: _ativo,
      modeloPadrao: _modeloPadrao,
      assinaturas: assinaturas,
      usarCidadeDoEvento: _usarCidadeDoEvento,
      usarDataDoEvento: _usarDataDoEvento,
      visual: _visual,
      studio: _studio,
      textos: Map<String, CertificadoTextoCampoConfig>.from(_textos),
    );
  }

  CertificadoEventoData _eventoFicticioParaPreview() {
    final config = _configuracaoAtualParaPreview();

    return CertificadoEventoData(
      eventoId: 'PREVIEW_CONFIGURACAO',
      eventoNome: 'PRÉVIA DA CONFIGURAÇÃO',
      tipoEvento: 'PREVIEW',
      dataEvento: DateTime(2026, 6, 21),
      horario: '',
      local: '',
      cidade: 'BOCAIUVA-MG',
      localData: 'BOCAIUVA-MG, 21 DE JUNHO DE 2026',
      temCertificado: true,
      geraCertificado: true,
      modeloPadrao: config.modeloPadrao,
      configuracoes: config,
      // Mantém os cinco slots físicos. O motor direto ignora os vazios ao
      // desenhar, mas não muda a posição dos slots preenchidos.
      assinaturas: config.assinaturas,
    );
  }

  CertificadoParticipanteData _participanteFicticiaParaPreview() {
    final tipo = _previewTipo();

    final graduacao = switch (tipo) {
      CertificadoTemplateTipo.diploma => 'PROFESSORA - MARROM',
      CertificadoTemplateTipo.certificadoComCpf => 'MONITORA - AZUL / ROXO',
      CertificadoTemplateTipo.certificadoSemCpf => '6° ADULTO - AZUL',
    };

    final certificadoOuDiploma = switch (tipo) {
      CertificadoTemplateTipo.diploma => 'DIPLOMA',
      CertificadoTemplateTipo.certificadoComCpf => 'CERTIFICADOCOMCPF',
      CertificadoTemplateTipo.certificadoSemCpf => 'CERTIFICADO',
    };

    final frase = tipo == CertificadoTemplateTipo.certificadoSemCpf
        ? 'CERTIFICAMOS QUE O(A) ALUNO(A) ACIMA ESTÁ APTO(A) E APROVADO(A) PARA RECEBER A GRADUAÇÃO EM CAPOEIRA, POR DEMONSTRAR INTERESSE NA ARTE E CULTURA BRASILEIRA, SENDO RECONHECIDO(A) PELOS MESTRES, CONTRAMESTRES, PROFESSORES E FORMADOS DO GRUPO.'
        : 'CERTIFICAMOS QUE, {nome}, {portador_cpf}, {cpf}, CONCLUIU COM ÊXITO O CURSO DE CAPOEIRA, DEMONSTRANDO PLENO DOMÍNIO E HABILIDADE NESSA ARTE. COMO RESULTADO DE SEU DESEMPENHO EXCEPCIONAL, É {reconhecido} COMO {apto} E {aprovado} PARA EXERCER A FUNÇÃO DE PROFISSIONAL NESSA ÁREA, OSTENTANDO O TÍTULO DE {titulo_graduacao}, SENDO ATRIBUÍDA A CORDA AZUL / ROXO EM SUA GRADUAÇÃO.';

    return CertificadoParticipanteData(
      participacaoId: 'PREVIEW_CONFIGURACAO',
      eventoId: 'PREVIEW_CONFIGURACAO',
      alunoId: 'PREVIEW_ALUNA',
      alunoNome: 'MARIA ELISA PEREIRA DE FREITAS',
      cpf: tipo == CertificadoTemplateTipo.certificadoSemCpf
          ? ''
          : '14276069602',
      sexo: 'FEMININO',
      alunoFoto: '',
      eventoNome: 'PRÉVIA DA CONFIGURAÇÃO',
      tipoEvento: 'PREVIEW',
      graduacaoAtual: '',
      graduacaoAtualId: '',
      graduacaoNova: graduacao,
      graduacaoNovaId: 'PREVIEW_GRADUACAO',
      tituloGraduacao: graduacao.split(' - ').first,
      corda: graduacao,
      frase: frase,
      certificadoOuDiploma: certificadoOuDiploma,
      // Mesmas cores usadas hoje pela prévia visual do Studio.
      cor1: '#0047FF',
      cor2: '#7B00A8',
      ponta1: '#0047FF',
      ponta2: '#7B00A8',
      presente: true,
      aguardandoFinalizacao: false,
      statusPagamento: 'quitado',
    );
  }

  Future<void> _compartilharPreviaPdf() async {
    if (_compartilhandoPreview) return;

    // IMPORTANTE:
    // Não capturamos mais o RepaintBoundary do preview.
    // O PDF é gerado diretamente pelo mesmo motor usado nos certificados
    // reais. Isso evita exportações vazias/incompletas no Windows quando o
    // flutter_svg ainda está compondo layers na tela.
    setState(() => _compartilhandoPreview = true);

    try {
      final evento = _eventoFicticioParaPreview();
      final participante = _participanteFicticiaParaPreview();

      await CertificadoActionFeedback.run<void>(
        context: context,
        title: 'Gerando prévia em PDF',
        detail: 'Montando o certificado com o mesmo motor usado na emissão e preparando o compartilhamento...',
        icon: Icons.picture_as_pdf_rounded,
        action: () async {
          final pdfBytes = await _pdfDiretoService.gerarPdfParticipante(
            evento: evento,
            participante: participante,
          );

          if (pdfBytes.isEmpty) {
            throw Exception('O motor direto retornou um PDF vazio.');
          }

          await _fileShareService.compartilharPdf(
            bytes: pdfBytes,
            nomeArquivo: 'previa_certificado_configuracao.pdf',
            texto: 'Prévia em PDF da configuração do certificado.',
          );
        },
      );

      if (mounted) {
        _snackStudio('Prévia em PDF pronta para compartilhar.');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao compartilhar prévia: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _compartilhandoPreview = false);
      }
    }
  }

  Widget _buildPreviewCertificadoCardReactive({required bool expanded}) {
    return _buildPreviewCertificadoCard(expanded: expanded);
  }

  Widget _buildPreviewCertificadoCard({required bool expanded}) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return _dialogSection(
      icon: Icons.preview_rounded,
      title: 'Prévia ao vivo',
      subtitle:
          'Veja fonte, cor, tamanho, alinhamento, frase e assinaturas sem sair da configuração.',
      color: t.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewTips(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: t.border),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: _assinaturasPreviewRevision,
              builder: (context, _, _) {
                return CertificadoPreviewWidget(
                  tipo: _previewTipo(),
                  cor1: const Color(0xFF0047FF),
                  cor2: const Color(0xFF7B00A8),
                  corContorno: const Color(0xFF1A0202),
                  data: _previewData(),
                  textosConfig: _textos,
                  visualConfig: _visual,
                  exportKey: null,
                  showHeader: false,
                  showDebugInfo: false,
                  showTextOverlay: true,
                  maxHeight: expanded ? 610 : 420,
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _sharePreviewPdfButton(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(primary.withAlpha(20), t.cardAlt),
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: primary.withAlpha(36)),
            ),
            child: Text(
              'Esta prévia usa uma aluna fictícia para testar automaticamente MONITORA/PROFESSORA/C. MESTRA, CPF, frase dinâmica e as 5 assinaturas.',
              style: TextStyle(
                color: primary,
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sharePreviewPdfButton() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _compartilhandoPreview ? null : _compartilharPreviaPdf,
        icon: _compartilhandoPreview
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _readableOn(primary),
                ),
              )
            : const Icon(Icons.picture_as_pdf_rounded),
        label: Text(
          _compartilhandoPreview
              ? 'GERANDO PRÉVIA...'
              : 'COMPARTILHAR PRÉVIA PDF',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: _readableOn(primary),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ),
    );
  }

  Widget _previewTips() {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.cardAlt);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _miniPreviewChip(Icons.text_fields_rounded, 'Textos 2.0', success),
        _miniPreviewChip(Icons.palette_rounded, 'Cores ao vivo', t.warning),
        _miniPreviewChip(Icons.draw_rounded, 'Assinaturas', t.associacao),
        _miniPreviewChip(Icons.female_rounded, 'Gênero dinâmico', t.info),
      ],
    );
  }

  Widget _miniPreviewChip(IconData icon, String label, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(23), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10.8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssinaturasCard() {
    final t = context.uai;

    return _dialogSection(
      icon: Icons.draw_rounded,
      title: 'Assinaturas',
      subtitle: 'Configure até 5 nomes e apelidos/cargos.',
      color: t.associacao,
      child: Column(
        children: List.generate(5, (index) {
          return _assinaturaFields(index);
        }),
      ),
    );
  }

  Widget _assinaturaFields(int index) {
    final t = context.uai;
    final number = index + 1;

    return Container(
      margin: EdgeInsets.only(bottom: index == 4 ? 0 : 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final nome = TextFormField(
            controller: _nomeControllers[index],
            onChanged: (_) => _assinaturasPreviewRevision.value++,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(color: t.textPrimary),
            decoration: _inputDecoration(
              label: 'Nome assinatura $number',
              icon: Icons.person_rounded,
              hint: 'Ex.: JOÃO LUCAS SILVA RABELO',
            ),
          );

          final apelido = TextFormField(
            controller: _apelidoControllers[index],
            onChanged: (_) => _assinaturasPreviewRevision.value++,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(color: t.textPrimary),
            decoration: _inputDecoration(
              label: 'Apelido/Cargo $number',
              icon: Icons.workspace_premium_rounded,
              hint: 'Ex.: PROFESSOR TICO-TICO',
            ),
          );

          if (narrow) {
            return Column(
              children: [nome, const SizedBox(height: 10), apelido],
            );
          }

          return Row(
            children: [
              Expanded(child: nome),
              const SizedBox(width: 10),
              Expanded(child: apelido),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withAlpha(41)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withAlpha(36)),
                ),
                child: Icon(icon, color: accent),
              ),
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
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.7,
                        height: 1.25,
                      ),
                    ),
                  ],
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

}

class _ModeloCertificadoOption {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  const _ModeloCertificadoOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _CampoTextoOption {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool mostrarLineHeight;
  final bool autoAjustarEditavel;

  const _CampoTextoOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.mostrarLineHeight = false,
    this.autoAjustarEditavel = true,
  });
}
