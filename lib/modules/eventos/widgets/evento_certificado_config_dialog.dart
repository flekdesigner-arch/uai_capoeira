import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/certificados/widgets/certificado_preview_widget.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_file_share_service.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

class EventoCertificadoConfigDialog extends StatefulWidget {
  final ConfiguracoesCertificadoEvento configuracaoInicial;

  const EventoCertificadoConfigDialog({
    super.key,
    required this.configuracaoInicial,
  });

  static Future<ConfiguracoesCertificadoEvento?> show({
    required BuildContext context,
    required ConfiguracoesCertificadoEvento configuracaoInicial,
  }) {
    return showDialog<ConfiguracoesCertificadoEvento>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return EventoCertificadoConfigDialog(
          configuracaoInicial: configuracaoInicial,
        );
      },
    );
  }

  @override
  State<EventoCertificadoConfigDialog> createState() =>
      _EventoCertificadoConfigDialogState();
}

class _EventoCertificadoConfigDialogState
    extends State<EventoCertificadoConfigDialog> {
  late bool _ativo;
  late String _modeloPadrao;
  late bool _usarCidadeDoEvento;
  late bool _usarDataDoEvento;
  late Map<String, CertificadoTextoCampoConfig> _textos;

  final GlobalKey _previewExportKey = GlobalKey();
  final CertificadoFileShareService _fileShareService =
      const CertificadoFileShareService();
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
    final assinaturas = List<AssinaturaCertificadoEvento>.from(
      config.assinaturas.isEmpty
          ? ConfiguracoesCertificadoEvento.padrao().assinaturas
          : config.assinaturas,
    );

    while (assinaturas.length < 5) {
      assinaturas.add(const AssinaturaCertificadoEvento(nome: '', apelido: ''));
    }

    _ativo = config.ativo;
    _modeloPadrao = config.modeloPadrao;
    _usarCidadeDoEvento = config.usarCidadeDoEvento;
    _usarDataDoEvento = config.usarDataDoEvento;
    _textos = Map<String, CertificadoTextoCampoConfig>.from(config.textos);

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
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
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
            constraints: const BoxConstraints(maxWidth: 560),
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
                              color: accent.withOpacity(0.12),
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
                        child: ColorPicker(
                          pickerColor: pickedColor,
                          onColorChanged: (color) {
                            setDialogState(() {
                              pickedColor = color;
                              hexController.text = _colorToHex(color);
                            });
                            setState(() => onColorChanged(color));
                          },
                          pickerAreaHeightPercent: 0.75,
                          labelTypes: const [],
                          displayThumbColor: true,
                          enableAlpha: false,
                          hexInputBar: false,
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

      if (nome.isEmpty && apelido.isEmpty) continue;

      assinaturas.add(
        AssinaturaCertificadoEvento(nome: nome, apelido: apelido),
      );
    }

    if (_ativo && assinaturas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Informe pelo menos uma assinatura.'),
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
        textos: _textos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);
    final onPrimary = _readableOn(primary);

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1220, maxHeight: 820),
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 4),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              children: [
                _buildHeader(primary, onPrimary),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1040;
                      final leftContent = ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                        children: _configSectionWidgets(),
                      );

                      if (!isWide) {
                        return leftContent;
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 515, child: leftContent),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: t.border,
                          ),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                18,
                              ),
                              children: [
                                _buildPreviewCertificadoCard(expanded: true),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                _buildFooter(primary, onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _configSectionWidgets() {
    return [
      _buildAtivacaoCard(),
      const SizedBox(height: 12),
      _buildModeloCard(),
      const SizedBox(height: 12),
      _buildOrigemLocalDataCard(),
      const SizedBox(height: 12),
      _buildTextosCard(),
      const SizedBox(height: 12),
      _buildAssinaturasCard(),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) return const SizedBox.shrink();
          return _buildPreviewCertificadoCard(expanded: false);
        },
      ),
    ];
  }

  Widget _buildHeader(Color primary, Color onPrimary) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(Icons.card_membership_rounded, color: onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurações do certificado',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Defina modelo, assinaturas, local/data e visual dos textos.',
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.80),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: onPrimary),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
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
          activeColor: accent,
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
                  ? Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt)
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
                      color: selected ? accent.withOpacity(0.28) : t.border,
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

  double _asDouble(String value, double fallback) {
    final clean = value.trim().replaceAll(',', '.');
    if (clean.isEmpty) return fallback;
    return double.tryParse(clean) ?? fallback;
  }

  Color _hexToColor(String value, Color fallback) {
    final clean = value.trim().replaceAll('#', '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) return fallback;
    return Color(int.parse('FF$clean', radix: 16));
  }

  String _normalizarHexInput(String value, String fallback) {
    final clean = value.trim().toUpperCase();
    if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(clean)) return clean;

    final without = clean.replaceAll('#', '');
    if (RegExp(r'^[0-9A-F]{6}$').hasMatch(without)) {
      return '#$without';
    }

    return fallback;
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
        color: Color.alphaBlend(info.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: info.withOpacity(0.16)),
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
      color: Color.alphaBlend(danger.withOpacity(0.08), t.cardAlt),
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _resetarTextosPadrao,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: danger.withOpacity(0.20)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: danger.withOpacity(0.16)),
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
                  color: accent.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withOpacity(0.14)),
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
                value: fonteValue,
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
      value: values.contains(current) ? current : values.first,
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
                  color: Color.alphaBlend(accent.withOpacity(0.10), t.card),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: accent.withOpacity(0.18)),
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
                      color: visibleColor.withOpacity(0.22),
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
                    ? Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt)
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
                        color: selected ? accent.withOpacity(0.32) : t.border,
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
                  ? Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt)
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
                      color: selected ? accent.withOpacity(0.32) : t.border,
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
          ? Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt)
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
              color: value ? accent.withOpacity(0.30) : t.border,
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
    final assinaturas = <CertificadoAssinaturaData>[];

    for (var i = 0; i < 5; i++) {
      final nome = _nomeControllers[i].text.trim();
      final apelido = _apelidoControllers[i].text.trim();

      if (nome.isEmpty && apelido.isEmpty) continue;

      assinaturas.add(
        CertificadoAssinaturaData(
          nome: nome.isEmpty ? 'ASSINATURA ${i + 1}' : nome,
          apelido: apelido.isEmpty ? 'CARGO / APELIDO' : apelido,
        ),
      );
    }

    if (assinaturas.isNotEmpty) return assinaturas.take(5).toList();

    return ConfiguracoesCertificadoEvento.padrao().assinaturas
        .map(
          (item) =>
              CertificadoAssinaturaData(nome: item.nome, apelido: item.apelido),
        )
        .take(5)
        .toList();
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

  Future<void> _compartilharPreviaPdf() async {
    if (_compartilhandoPreview) return;

    setState(() => _compartilhandoPreview = true);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final boundary =
          _previewExportKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('Prévia ainda não está pronta para exportar.');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();

      if (pngBytes == null || pngBytes.isEmpty) {
        throw Exception('Não foi possível capturar a prévia.');
      }

      final pdfBytes = await _gerarPdfPreviewBytes(pngBytes);

      await _fileShareService.compartilharPdf(
        bytes: pdfBytes,
        nomeArquivo: 'previa_certificado_configuracao.pdf',
        texto: 'Prévia em PDF da configuração do certificado.',
      );
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

  Future<Uint8List> _gerarPdfPreviewBytes(Uint8List pngBytes) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Center(
            child: pw.Image(
              image,
              fit: pw.BoxFit.contain,
              width: PdfPageFormat.a4.landscape.availableWidth,
              height: PdfPageFormat.a4.landscape.availableHeight,
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Widget _buildPreviewCertificadoCard({required bool expanded}) {
    final t = context.uai;
    final tipo = _previewTipo();
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
            child: CertificadoPreviewWidget(
              tipo: tipo,
              cor1: const Color(0xFF0047FF),
              cor2: const Color(0xFF7B00A8),
              corContorno: const Color(0xFF1A0202),
              data: _previewData(),
              textosConfig: _textos,
              exportKey: _previewExportKey,
              showHeader: false,
              showDebugInfo: false,
              showTextOverlay: true,
              maxHeight: expanded ? 610 : 420,
            ),
          ),
          const SizedBox(height: 10),
          _sharePreviewPdfButton(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(primary.withOpacity(0.08), t.cardAlt),
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: primary.withOpacity(0.14)),
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
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.16)),
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
        border: Border.all(color: accent.withOpacity(0.16)),
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
                  color: accent.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withOpacity(0.14)),
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

  Widget _buildFooter(Color primary, Color onPrimary) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.textPrimary,
                side: BorderSide(color: t.border),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
              child: const Text(
                'CANCELAR',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_rounded),
              label: const Text('SALVAR CONFIG.'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
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
