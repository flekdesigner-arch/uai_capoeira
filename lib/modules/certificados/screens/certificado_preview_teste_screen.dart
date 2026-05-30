import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/certificados/data/certificado_template_assets.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_export_service.dart';
import 'package:uai_capoeira/modules/certificados/widgets/certificado_preview_widget.dart';

class CertificadoPreviewTesteScreen extends StatefulWidget {
  const CertificadoPreviewTesteScreen({super.key});

  @override
  State<CertificadoPreviewTesteScreen> createState() =>
      _CertificadoPreviewTesteScreenState();
}

class _CertificadoPreviewTesteScreenState
    extends State<CertificadoPreviewTesteScreen> {
  final GlobalKey _exportPreviewKey = GlobalKey();
  final CertificadoExportService _exportService =
  const CertificadoExportService();

  CertificadoTemplateTipo _tipoSelecionado =
      CertificadoTemplateTipo.certificadoSemCpf;

  Color _cor1 = const Color(0xFF0000FF);
  Color _cor2 = const Color(0xFF0000FF);
  Color _corContorno = const Color(0xFF1A0202);
  bool _mostrarTextos = true;
  bool _exportando = false;
  String? _acaoAtual;

  final List<_GraduacaoPreviewPreset> _presets = const [
    _GraduacaoPreviewPreset(
      nome: 'Azul',
      subtitle: '6° adulto',
      cor1: Color(0xFF0000FF),
      cor2: Color(0xFF0000FF),
      contorno: Color(0xFF1A0202),
    ),
    _GraduacaoPreviewPreset(
      nome: 'Crua / Amarela',
      subtitle: 'Infantil',
      cor1: Color(0xFFFFFF00),
      cor2: Color(0xFFFFFFFF),
      contorno: Color(0xFF1A0202),
    ),
    _GraduacaoPreviewPreset(
      nome: 'Roxa',
      subtitle: 'Instrutor',
      cor1: Color(0xFF9200AC),
      cor2: Color(0xFF9200AC),
      contorno: Color(0xFF1A0202),
    ),
    _GraduacaoPreviewPreset(
      nome: 'Marrom',
      subtitle: 'Professor',
      cor1: Color(0xFF402A20),
      cor2: Color(0xFF402A20),
      contorno: Color(0xFF1A0202),
    ),
  ];

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

  Color _onPrimary() {
    final t = context.uai;
    final temaEscuro =
        t.background.computeLuminance() < 0.45 || t.surface.computeLuminance() < 0.45;

    if (temaEscuro) return Colors.white;

    return _readableOn(t.primary);
  }

  void _aplicarPreset(_GraduacaoPreviewPreset preset) {
    setState(() {
      _cor1 = preset.cor1;
      _cor2 = preset.cor2;
      _corContorno = preset.contorno;
    });
  }

  CertificadoPreviewData get _previewData =>
      CertificadoPreviewData.exemplo(_tipoSelecionado);

  String _slugify(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _nomeArquivoBase() {
    final modelo = _slugify(_tipoSelecionado.nome);
    final aluno = _slugify(_previewData.alunoNome);
    return 'certificado_${modelo}_$aluno';
  }

  void _mostrarSucesso(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarErro(Object error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro: $error'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _executarExportacao(
      String label,
      Future<void> Function() action,
      ) async {
    if (_exportando) return;

    setState(() {
      _exportando = true;
      _acaoAtual = label;
    });

    try {
      await action();
      _mostrarSucesso('$label concluído com sucesso.');
    } catch (e) {
      _mostrarErro(e);
    } finally {
      if (!mounted) return;

      setState(() {
        _exportando = false;
        _acaoAtual = null;
      });
    }
  }

  Future<void> _gerarPng() async {
    final png = await _exportService.capturarPreviewComoPng(
      _exportPreviewKey,
      pixelRatio: 4.0,
    );

    await _exportService.salvarPng(
      bytes: png,
      nomeBase: _nomeArquivoBase(),
    );
  }

  Future<void> _gerarPdf() async {
    final png = await _exportService.capturarPreviewComoPng(
      _exportPreviewKey,
      pixelRatio: 4.0,
    );

    final pdf = await _exportService.gerarPdfA4Paisagem(png);

    await _exportService.salvarPdf(
      bytes: pdf,
      nomeBase: _nomeArquivoBase(),
    );
  }

  Future<void> _imprimirPdf() async {
    final png = await _exportService.capturarPreviewComoPng(
      _exportPreviewKey,
      pixelRatio: 4.0,
    );

    final pdf = await _exportService.gerarPdfA4Paisagem(png);
    await _exportService.imprimirPdf(pdf);
  }

  Future<void> _compartilharPdf() async {
    final png = await _exportService.capturarPreviewComoPng(
      _exportPreviewKey,
      pixelRatio: 4.0,
    );

    final pdf = await _exportService.gerarPdfA4Paisagem(png);

    await _exportService.compartilharPdf(
      bytes: pdf,
      nomeBase: _nomeArquivoBase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Configurar Certificados',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;
          final horizontal = constraints.maxWidth < 600 ? 14.0 : 18.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 14),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 340,
                              child: Column(
                                children: [
                                  _buildTemplateSelector(),
                                  const SizedBox(height: 12),
                                  _buildPresetSelector(),
                                  const SizedBox(height: 12),
                                  _buildTextToggleCard(),
                                  const SizedBox(height: 12),
                                  _buildExportActionsCard(),
                                  const SizedBox(height: 12),
                                  _buildStatusCard(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: _buildPreviewCard()),
                          ],
                        )
                      else ...[
                        _buildTemplateSelector(),
                        const SizedBox(height: 12),
                        _buildPresetSelector(),
                        const SizedBox(height: 12),
                        _buildTextToggleCard(),
                        const SizedBox(height: 12),
                        _buildExportActionsCard(),
                        const SizedBox(height: 12),
                        _buildPreviewCard(),
                        const SizedBox(height: 12),
                        _buildStatusCard(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard() {
    final t = context.uai;
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;

          final icon = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.cardRadius - 2),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.history_edu_rounded,
              color: onPrimary,
              size: 35,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Templates de Certificados',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Agora o painel já gera PDF A4, PNG, impressão e compartilhamento a partir da prévia.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.picture_as_pdf_rounded, 'PDF A4'),
                  _heroChip(Icons.image_rounded, 'PNG'),
                  _heroChip(Icons.print_rounded, 'Imprimir'),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateSelector() {
    final t = context.uai;

    return _sectionCard(
      title: 'Modelo',
      subtitle: 'Escolha qual SVG será testado agora.',
      icon: Icons.layers_rounded,
      child: Column(
        children: CertificadoTemplateAssets.tiposDisponiveis.map((tipo) {
          final selected = tipo == _tipoSelecionado;
          final accent = _ensureVisible(
            selected ? t.primary : t.textSecondary,
            t.card,
          );

          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Material(
              color: selected
                  ? Color.alphaBlend(t.primary.withOpacity(0.09), t.card)
                  : t.cardAlt,
              borderRadius: BorderRadius.circular(t.buttonRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _tipoSelecionado = tipo),
                borderRadius: BorderRadius.circular(t.buttonRadius + 2),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.buttonRadius + 2),
                    border: Border.all(
                      color: selected ? accent.withOpacity(0.28) : t.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(tipo.icon, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tipo.nome,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tipo.subtitulo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11,
                                height: 1.24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
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

  Widget _buildPresetSelector() {
    final t = context.uai;

    return _sectionCard(
      title: 'Graduação de teste',
      subtitle: 'Simula as cores que virão da coleção graduações.',
      icon: Icons.palette_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _presets.map((preset) {
          final selected = preset.cor1 == _cor1 && preset.cor2 == _cor2;
          final accent = _ensureVisible(preset.cor1, t.card);

          return InkWell(
            onTap: () => _aplicarPreset(preset),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 148,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? Color.alphaBlend(accent.withOpacity(0.11), t.card)
                    : t.cardAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? accent.withOpacity(0.35) : t.border,
                ),
              ),
              child: Row(
                children: [
                  _DoubleColorDot(cor1: preset.cor1, cor2: preset.cor2),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          preset.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextToggleCard() {
    final t = context.uai;

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
          value: _mostrarTextos,
          onChanged: (value) => setState(() => _mostrarTextos = value),
          activeColor: t.primary,
          title: Text(
            'Mostrar textos de teste',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          subtitle: Text(
            'Usa os retângulos do SVG guia como posição.',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportActionsCard() {
    final t = context.uai;

    return _sectionCard(
      title: 'Exportação',
      subtitle: 'Gera arquivos reais da prévia atual.',
      icon: Icons.download_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _actionButton(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Gerar PDF A4',
                onTap: () => _executarExportacao('PDF A4', _gerarPdf),
              ),
              _actionButton(
                icon: Icons.image_rounded,
                label: 'Gerar PNG',
                onTap: () => _executarExportacao('PNG', _gerarPng),
              ),
              _actionButton(
                icon: Icons.print_rounded,
                label: 'Imprimir PDF',
                onTap: () => _executarExportacao('Impressão', _imprimirPdf),
              ),
              _actionButton(
                icon: Icons.share_rounded,
                label: 'Compartilhar',
                onTap: () =>
                    _executarExportacao('Compartilhamento', _compartilharPdf),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                if (_exportando) ...[
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.3,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  Icon(
                    Icons.info_outline_rounded,
                    color: t.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _exportando
                        ? 'Processando: ${_acaoAtual ?? 'aguarde...'}'
                        : 'A exportação usa a prévia visível, sem o cabeçalho do painel.',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11.7,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return SizedBox(
      width: 145,
      child: ElevatedButton.icon(
        onPressed: _exportando ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          backgroundColor: accent,
          foregroundColor: _readableOn(accent),
          disabledBackgroundColor: t.cardAlt,
          disabledForegroundColor: t.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return CertificadoPreviewWidget(
      tipo: _tipoSelecionado,
      cor1: _cor1,
      cor2: _cor2,
      corContorno: _corContorno,
      data: _previewData,
      exportKey: _exportPreviewKey,
      showHeader: true,
      showDebugInfo: true,
      showTextOverlay: _mostrarTextos,
    );
  }

  Widget _buildStatusCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.success, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
              Icon(Icons.check_circle_rounded, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Painel pronto para saída real',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Agora você já consegue baixar PDF A4, gerar PNG, imprimir e compartilhar direto dessa tela de teste.',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withOpacity(0.11),
                    t.cardAlt,
                  ),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withOpacity(0.13)),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
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

class _GraduacaoPreviewPreset {
  final String nome;
  final String subtitle;
  final Color cor1;
  final Color cor2;
  final Color contorno;

  const _GraduacaoPreviewPreset({
    required this.nome,
    required this.subtitle,
    required this.cor1,
    required this.cor2,
    required this.contorno,
  });
}

class _DoubleColorDot extends StatelessWidget {
  final Color cor1;
  final Color cor2;

  const _DoubleColorDot({
    required this.cor1,
    required this.cor2,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: t.border, width: 1.4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(child: Container(color: cor1)),
          Expanded(child: Container(color: cor2)),
        ],
      ),
    );
  }
}
