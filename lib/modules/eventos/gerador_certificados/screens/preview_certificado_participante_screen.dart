import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_service.dart';
import 'package:uai_capoeira/modules/certificados/widgets/certificado_preview_widget.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_file_share_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_pdf_direto_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/gerador_certificado_evento_service.dart';

class PreviewCertificadoParticipanteScreen extends StatefulWidget {
  final CertificadoEventoData evento;
  final CertificadoParticipanteData participante;

  const PreviewCertificadoParticipanteScreen({
    super.key,
    required this.evento,
    required this.participante,
  });

  @override
  State<PreviewCertificadoParticipanteScreen> createState() =>
      _PreviewCertificadoParticipanteScreenState();
}

class _PreviewCertificadoParticipanteScreenState
    extends State<PreviewCertificadoParticipanteScreen> {
  final GlobalKey _exportKey = GlobalKey();
  final CertificadoSvgService _svgService = const CertificadoSvgService();
  final GeradorCertificadoEventoService _geradorService =
  GeradorCertificadoEventoService();
  final CertificadoFileShareService _fileShareService =
  const CertificadoFileShareService();
  final CertificadoPdfDiretoService _pdfDiretoService =
  CertificadoPdfDiretoService();

  bool _processando = false;
  String? _acaoAtual;

  CertificadoParticipanteData get participante => widget.participante;
  CertificadoEventoData get evento => widget.evento;

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _cor(String hex, {Color fallback = const Color(0xFF9E9E9E)}) {
    return _svgService.colorFromHex(hex, fallback: fallback);
  }

  String _nomeArquivoSomenteAluno() {
    final nome = participante.alunoNome.trim();

    if (nome.isEmpty) {
      return 'certificado';
    }

    return nome
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÂÃÄ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'[^A-Z0-9 ]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _garantirExportPronto() async {
    for (var i = 0; i < 24; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await WidgetsBinding.instance.endOfFrame;

      final context = _exportKey.currentContext;
      final renderObject = context?.findRenderObject();

      if (context != null && renderObject != null && renderObject.attached) {
        return;
      }
    }

    throw Exception(
      'A prévia ainda não está pronta para exportação. '
          'Aguarde a imagem aparecer completamente e tente novamente.',
    );
  }

  Future<Uint8List> _gerarPdfDireto() {
    return _pdfDiretoService.gerarPdfParticipante(
      evento: evento,
      participante: participante,
    );
  }

  Future<void> _executar(
      String label,
      Future<void> Function() action,
      ) async {
    if (_processando) return;

    setState(() {
      _processando = true;
      _acaoAtual = label;
    });

    try {
      await action();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label concluído com sucesso.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro em $label: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _processando = false;
        _acaoAtual = null;
      });
    }
  }

  Future<void> _baixarPdf() async {
    final pdfBytes = await _gerarPdfDireto();

    await _fileShareService.salvarOuCompartilharPdf(
      bytes: pdfBytes,
      nomeArquivo: _nomeArquivoSomenteAluno(),
      texto: 'Certificado de ${participante.alunoNome}.',
    );
  }



  Future<void> _baixarPng() async {
    await _garantirExportPronto();

    final pngBytes = await _geradorService.capturarPngDaPreview(
      _exportKey,
      pixelRatio: 4.0,
    );

    await _fileShareService.salvarOuCompartilharPng(
      bytes: pngBytes,
      nomeArquivo: _nomeArquivoSomenteAluno(),
      texto: 'Certificado de ${participante.alunoNome}.',
    );
  }



  Future<void> _imprimirPdf() async {
    final pdfBytes = await _gerarPdfDireto();

    await Printing.layoutPdf(
      onLayout: (_) async =>
      pdfBytes,
      name: '${_nomeArquivoSomenteAluno()}.pdf',
      usePrinterSettings: true,
      dynamicLayout: false,
    );
  }


  Future<void> _compartilharPdf() async {
    final pdfBytes = await _gerarPdfDireto();

    await _fileShareService.compartilharPdf(
      bytes: pdfBytes,
      nomeArquivo: _nomeArquivoSomenteAluno(),
      texto: 'Certificado de ${participante.alunoNome}.',
    );
  }



  Future<void> _salvarVinculo() async {
    await _garantirExportPronto();

    final link = await _geradorService.gerarUploadERegistrarPdf(
      repaintKey: _exportKey,
      evento: evento,
      participante: participante,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Certificado vinculado: $link'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    final tipo = participante.tipoTemplate(evento);
    final data = participante.toPreviewData(evento);
    final cor1 = _cor(participante.cor1);
    final cor2 = _cor(participante.cor2);
    final contorno = const Color(0xFF1A0202);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Prévia do Certificado',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (_processando)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: _readableOn(t.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1050;
                final horizontal = constraints.maxWidth < 620 ? 12.0 : 18.0;

                return ListView(
                  padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 28),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1260),
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
                                    width: 330,
                                    child: Column(
                                      children: [
                                        _buildInfoCard(),
                                        const SizedBox(height: 12),
                                        _buildActionsCard(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _buildPreview(
                                      tipo: tipo,
                                      data: data,
                                      cor1: cor1,
                                      cor2: cor2,
                                      contorno: contorno,
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              _buildInfoCard(),
                              const SizedBox(height: 12),
                              _buildActionsCard(),
                              const SizedBox(height: 12),
                              _buildPreview(
                                tipo: tipo,
                                data: data,
                                cor1: cor1,
                                cor2: cor2,
                                contorno: contorno,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildExportPreviewOculta(
            tipo: tipo,
            data: data,
            cor1: cor1,
            cor2: cor2,
            contorno: contorno,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final onPrimary = _readableOn(primary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;

          final icon = Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: onPrimary,
              size: 31,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                participante.alunoNome,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 20 : 24,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${participante.graduacaoNova} • ${evento.localData}',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 12),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCard() {
    final t = context.uai;

    return _sectionCard(
      icon: Icons.info_rounded,
      title: 'Dados usados',
      subtitle: 'Dados reais do evento, participação e graduação.',
      color: t.info,
      child: Column(
        children: [
          _infoLine('Evento', evento.eventoNome),
          _infoLine('Aluno', participante.alunoNome),
          _infoLine('CPF', participante.temCpf ? participante.cpf : 'Não informado'),
          _infoLine('Graduação', participante.graduacaoNova),
          _infoLine('Modelo', participante.certificadoOuDiploma),
          _infoLine('Cidade/Data', evento.localData),
          _infoLine('Assinaturas', '${evento.assinaturas.length} configurada(s)'),
          _infoLine(
            'Status',
            participante.temCertificadoGerado
                ? 'Já possui certificado vinculado'
                : 'Ainda não vinculado',
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    final t = context.uai;

    return _sectionCard(
      icon: Icons.bolt_rounded,
      title: 'Ações',
      subtitle: _processando
          ? 'Processando: ${_acaoAtual ?? 'aguarde...'}'
          : 'Gere, imprima, compartilhe ou vincule o PDF.',
      color: t.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _actionButton(
            icon: Icons.picture_as_pdf_rounded,
            label: 'BAIXAR PDF',
            color: t.error,
            onTap: () => _executar('Baixar PDF', _baixarPdf),
          ),
          const SizedBox(height: 9),
          _actionButton(
            icon: Icons.image_rounded,
            label: 'BAIXAR PNG',
            color: t.info,
            onTap: () => _executar('Baixar PNG', _baixarPng),
          ),
          const SizedBox(height: 9),
          _actionButton(
            icon: Icons.print_rounded,
            label: 'IMPRIMIR PDF',
            color: t.associacao,
            onTap: () => _executar('Imprimir PDF', _imprimirPdf),
          ),
          const SizedBox(height: 9),
          _actionButton(
            icon: Icons.share_rounded,
            label: 'COMPARTILHAR PDF',
            color: t.warning,
            onTap: () => _executar('Compartilhar PDF', _compartilharPdf),
          ),
          const SizedBox(height: 9),
          _actionButton(
            icon: Icons.cloud_upload_rounded,
            label: 'SALVAR E VINCULAR',
            color: t.success,
            onTap: () => _executar('Salvar e vincular', _salvarVinculo),
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPreview({
    required dynamic tipo,
    required dynamic data,
    required Color cor1,
    required Color cor2,
    required Color contorno,
  }) {
    return CertificadoPreviewWidget(
      tipo: tipo,
      cor1: cor1,
      cor2: cor2,
      corContorno: contorno,
      data: data,
      exportKey: null,
      showHeader: true,
      showDebugInfo: false,
      showTextOverlay: true,
      maxHeight: 720,
    );
  }

  Widget _buildExportPreviewOculta({
    required dynamic tipo,
    required dynamic data,
    required Color cor1,
    required Color cor2,
    required Color contorno,
  }) {
    return Positioned(
      left: -6000,
      top: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 1200,
              child: CertificadoPreviewWidget(
                tipo: tipo,
                cor1: cor1,
                cor2: cor2,
                corContorno: contorno,
                data: data,
                exportKey: _exportKey,
                showHeader: false,
                showDebugInfo: false,
                showTextOverlay: true,
                maxHeight: 850,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 11.8,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    final onAccent = _readableOn(accent);

    if (filled) {
      return ElevatedButton.icon(
        onPressed: _processando ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: t.cardAlt,
          disabledForegroundColor: t.textMuted,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.2,
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: _processando ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        disabledForegroundColor: t.textMuted,
        side: BorderSide(color: accent.withOpacity(0.26)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12.2,
        ),
      ),
    );
  }
}
