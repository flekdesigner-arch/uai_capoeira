import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:uai_capoeira/modules/certificados/models/certificado_slot_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_lote_impressao_service.dart';

class CertificadoPdfDiretoService {
  CertificadoPdfDiretoService({
    CertificadoSvgService? svgService,
  }) : _svgService = svgService ?? const CertificadoSvgService();

  final CertificadoSvgService _svgService;

  static const double _viewBoxWidth = 297.0;
  static const double _viewBoxHeight = 210.0;
  static const String relatorioNomePadrao = 'RELATORIO_CERTIFICADOS_GRAFICA.pdf';

  final Map<CertificadoTemplateTipo, String> _svgCache = {};
  final Map<CertificadoTemplateTipo, Map<String, CertificadoSlotModel>> _slotsCache = {};

  pw.Font? _arial;
  pw.Font? _arialBold;
  pw.Font? _engravers;
  pw.Font? _square;
  pw.Font? _squareBold;
  pw.Font? _sitka;

  Future<CertificadoZipDiretoResultado> gerarZipGraficaPdfsDireto({
    required CertificadoEventoData evento,
    required List<CertificadoParticipanteData> participantes,
    CertificadoZipDiretoProgress? onProgress,
  }) async {
    if (participantes.isEmpty) {
      throw Exception('Nenhum participante selecionado.');
    }

    final archive = Archive();
    final itens = <CertificadoPacoteGraficaItem>[];
    final erros = <CertificadoPacoteGraficaErro>[];
    final nomesUsados = <String, int>{};

    for (var i = 0; i < participantes.length; i++) {
      final participante = participantes[i];

      if (!participante.estaProntoParaGerar) {
        erros.add(
          CertificadoPacoteGraficaErro(
            alunoNome: participante.alunoNome,
            mensagem: 'Participante sem graduação nova ou nome válido.',
          ),
        );
        continue;
      }

      try {
        final pdfBytes = await gerarPdfParticipante(
          evento: evento,
          participante: participante,
        );

        final nomeArquivo = _nomeArquivoAlunoPdf(
          participante,
          nomesUsados: nomesUsados,
        );

        archive.addFile(
          ArchiveFile(
            nomeArquivo,
            pdfBytes.length,
            pdfBytes,
          ),
        );

        itens.add(
          CertificadoPacoteGraficaItem(
            numero: itens.length + 1,
            participacaoId: participante.participacaoId,
            alunoNome: participante.alunoNome,
            graduacao: participante.graduacaoNova,
            modelo: participante.certificadoOuDiploma,
            nomeArquivo: nomeArquivo,
          ),
        );

        onProgress?.call(i + 1, participantes.length, participante.alunoNome);
      } catch (e) {
        erros.add(
          CertificadoPacoteGraficaErro(
            alunoNome: participante.alunoNome,
            mensagem: e.toString(),
          ),
        );
      }

      // Dá respiro real para a interface pintar o overlay/progresso entre um PDF e outro.
      await Future<void>.delayed(const Duration(milliseconds: 45));
    }

    if (itens.isEmpty) {
      throw Exception('Nenhum PDF foi gerado. Verifique as graduações e tente novamente.');
    }

    final relatorioBytes = await gerarRelatorioGraficaPdf(
      evento: evento,
      itens: itens,
      erros: erros,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    archive.addFile(
      ArchiveFile(
        relatorioNomePadrao,
        relatorioBytes.length,
        relatorioBytes,
      ),
    );

    final zipBytes = Uint8List.fromList(
      ZipEncoder().encode(archive) ?? <int>[],
    );

    return CertificadoZipDiretoResultado(
      zipBytes: zipBytes,
      relatorioBytes: relatorioBytes,
      itens: itens,
      erros: erros,
    );
  }

  Future<Uint8List> gerarPdfParticipante({
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    await _ensureFonts();

    final tipo = participante.tipoTemplate(evento);
    final data = participante.toPreviewData(evento);
    final slots = await _slots(tipo);
    final svg = await _svgColorido(tipo, participante);

    final documento = pw.Document(compress: true);
    final page = PdfPageFormat.a4.landscape;
    final sx = page.width / _viewBoxWidth;
    final sy = page.height / _viewBoxHeight;

    final textoPrincipal = _pdfColor(const Color(0xFF1A0202));

    documento.addPage(
      pw.Page(
        pageFormat: page,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.SvgImage(
                  svg: svg,
                  fit: pw.BoxFit.fill,
                ),
              ),
              ..._textosDoCertificado(
                slots: slots,
                sx: sx,
                sy: sy,
                tipo: tipo,
                data: data,
                participante: participante,
                textoPrincipal: textoPrincipal,
              ),
            ],
          );
        },
      ),
    );

    return documento.save();
  }

  List<pw.Widget> _textosDoCertificado({
    required Map<String, CertificadoSlotModel> slots,
    required double sx,
    required double sy,
    required CertificadoTemplateTipo tipo,
    required dynamic data,
    required CertificadoParticipanteData participante,
    required PdfColor textoPrincipal,
  }) {
    final widgets = <pw.Widget>[];

    void addTextBox({
      required String text,
      required double xMm,
      required double yMm,
      required double widthMm,
      required double heightMm,
      required double fontSize,
      required pw.Font? font,
      PdfColor? color,
      pw.Alignment alignment = pw.Alignment.bottomCenter,
      pw.TextAlign textAlign = pw.TextAlign.center,
      double minScale = 0.35,
    }) {
      if (text.trim().isEmpty) return;

      final width = widthMm * sx;
      final fitted = _fitFontSize(
        text,
        fontSize,
        width,
        minFontSize: fontSize * minScale,
      );

      widgets.add(
        pw.Positioned(
          left: xMm * sx,
          top: yMm * sy,
          child: pw.Container(
            width: width,
            height: heightMm * sy,
            alignment: alignment,
            child: pw.Text(
              text,
              textAlign: textAlign,
              maxLines: 1,
              style: pw.TextStyle(
                font: font,
                fontSize: fitted,
                color: color ?? textoPrincipal,
                fontWeight: font == null ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ),
      );
    }

    void addSingle({
      required String id,
      required String text,
      required double fontSize,
      required pw.Font? font,
      PdfColor? color,
      pw.Alignment alignment = pw.Alignment.bottomCenter,
      double rightPaddingMm = 0,
      double widthExtraMm = 0,
      double topOffsetMm = 0,
      double heightExtraMm = 0,
      double minScale = 0.35,
    }) {
      final slot = slots[id];
      if (slot == null || text.trim().isEmpty) return;

      final extraLeft = widthExtraMm / 2;
      final xMm = (slot.x - extraLeft) + rightPaddingMm;
      final yMm = slot.y + topOffsetMm;
      final widthMm = (slot.width + widthExtraMm) - rightPaddingMm;
      final heightMm = slot.height + heightExtraMm;

      addTextBox(
        text: text,
        xMm: xMm,
        yMm: yMm,
        widthMm: widthMm,
        heightMm: heightMm,
        fontSize: fontSize,
        font: font,
        color: color,
        alignment: alignment,
        minScale: minScale,
      );
    }

    void addCpf() {
      // CPF só deve aparecer nos modelos que realmente exigem CPF:
      // CERTIFICADOCOMCPF e DIPLOMA.
      // No certificado simples, mesmo que o aluno tenha CPF cadastrado,
      // o campo não deve ser desenhado.
      if (!tipo.exigeCpf) return;

      final cpf = data.cpfFormatado.trim();
      if (cpf.isEmpty) return;

      final slot = slots[CertificadoSlotIds.cpf];

      if (slot != null) {
        addTextBox(
          text: cpf,
          xMm: slot.x + 1.1,
          yMm: slot.y - 0.42,
          widthMm: slot.width + 10.0,
          heightMm: slot.height + 1.7,
          fontSize: 11.2,
          font: _arialBold ?? _arial ?? _squareBold ?? _square,
          alignment: pw.Alignment.centerLeft,
          minScale: 0.30,
        );
        return;
      }

      // Os SVGs de CERTIFICADOCOMCPF e DIPLOMA têm a caixa-guia do CPF,
      // mas ela veio sem id="cpf". A prévia Flutter usa coordenada manual,
      // por isso aparece na tela; o PDF direto precisa desse fallback.
      //
      // Caixa-guia real identificada no SVG:
      // <polygon points="133.2307,91.3142 170.8651,91.3142 ..."/>
      // O texto fixo "CPF:" já faz parte do SVG, então aqui vai só o número.
      // O número fica alinhado da esquerda para a direita dentro da caixa-guia.
      addTextBox(
        text: cpf,
        xMm: 132.9,
        yMm: 90.62,
        widthMm: 47.0,
        heightMm: 5.7,
        fontSize: 11.2,
        font: _arialBold ?? _arial ?? _squareBold ?? _square,
        alignment: pw.Alignment.centerLeft,
        minScale: 0.30,
      );
    }

    void addParagraph({
      required String id,
      required String text,
      required double fontSize,
      required pw.Font? font,
      PdfColor? color,
    }) {
      final slot = slots[id];
      if (slot == null || text.trim().isEmpty) return;

      widgets.add(
        pw.Positioned(
          left: slot.x * sx,
          top: slot.y * sy,
          child: pw.Container(
            width: slot.width * sx,
            height: slot.height * sy,
            alignment: pw.Alignment.topCenter,
            child: pw.Text(
              text,
              textAlign: pw.TextAlign.center,
              maxLines: 6,
              style: pw.TextStyle(
                font: font,
                fontSize: fontSize,
                color: color ?? textoPrincipal,
                height: 1.16,
              ),
            ),
          ),
        ),
      );
    }

    addSingle(
      id: CertificadoSlotIds.alunoNome,
      text: data.alunoNome,
      fontSize: 20.2,
      font: _arialBold,
      topOffsetMm: -1.0,
      heightExtraMm: 1.0,
      minScale: 0.42,
    );

    addCpf();

    addSingle(
      id: CertificadoSlotIds.graduacaoNova,
      text: data.graduacaoNova,
      fontSize: 17.4,
      font: _arialBold,
      alignment: pw.Alignment.bottomLeft,
      rightPaddingMm: 0,
      minScale: 0.38,
    );

    addParagraph(
      id: CertificadoSlotIds.frase,
      text: data.fraseFinal(
        tipo: tipo,
        tituloGraduacao: participante.tituloGraduacao,
        corda: participante.corda,
      ),
      fontSize: 15.1,
      font: _engravers,
    );

    addSingle(
      id: CertificadoSlotIds.localData,
      text: data.localData,
      fontSize: 13.2,
      font: _squareBold ?? _square,
      minScale: 0.12,
      widthExtraMm: 90,
    );

    final assinaturas = data.assinaturas;
    for (var i = 0; i < 5; i++) {
      if (i >= assinaturas.length) break;

      final a = assinaturas[i];
      addSingle(
        id: 'assinatura${i + 1}',
        text: a.nome,
        fontSize: 10.6,
        font: _arialBold ?? _arial,
      );
      addSingle(
        id: 'apelido${i + 1}',
        text: a.apelido,
        fontSize: 9.4,
        font: _arial,
      );
    }

    return widgets;
  }

  Future<String> _svgColorido(
      CertificadoTemplateTipo tipo,
      CertificadoParticipanteData participante,
      ) async {
    final base = _svgCache[tipo] ?? await _svgService.carregarTemplate(tipo);
    _svgCache[tipo] = base;

    return _svgService.colorirSvg(
      base,
      cor1: _hexToColor(participante.cor1),
      cor2: _hexToColor(participante.cor2),
      corContorno: const Color(0xFF1A0202),
    );
  }

  Future<Map<String, CertificadoSlotModel>> _slots(
      CertificadoTemplateTipo tipo,
      ) async {
    final cached = _slotsCache[tipo];
    if (cached != null) return cached;

    final slots = await _svgService.carregarSlotsDoGuia(tipo);
    _slotsCache[tipo] = slots;
    return slots;
  }

  Future<void> _ensureFonts() async {
    if (_arial != null) return;

    _arial = await _tryLoadFont('assets/fontes/arial.ttf');
    _arialBold = await _tryLoadFont('assets/fontes/arialbd.ttf');
    _engravers = await _tryLoadFont('assets/fontes/EngraversGothic BT.ttf');
    _square = await _tryLoadFont('assets/fontes/Square721 BT Roman.ttf');
    _squareBold = await _tryLoadFont('assets/fontes/Square721 BT Bold.ttf');
    // O pacote pdf não suporta arquivos .ttc. Mantém fallback seguro.
    _sitka = null;
  }

  Future<pw.Font?> _tryLoadFont(String path) async {
    try {
      if (path.toLowerCase().endsWith('.ttc')) {
        return null;
      }

      final bytes = await rootBundle.load(path);
      return pw.Font.ttf(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> gerarRelatorioGraficaPdf({
    required CertificadoEventoData evento,
    required List<CertificadoPacoteGraficaItem> itens,
    List<CertificadoPacoteGraficaErro> erros = const [],
  }) async {
    await _ensureFonts();

    final doc = pw.Document(compress: true);

    PdfColor hex(String value) {
      final clean = value.replaceAll('#', '').trim();
      final intValue = int.parse(
        clean.length == 6 ? 'FF$clean' : clean,
        radix: 16,
      );

      return PdfColor(
        ((intValue >> 16) & 0xFF) / 255,
        ((intValue >> 8) & 0xFF) / 255,
        (intValue & 0xFF) / 255,
        ((intValue >> 24) & 0xFF) / 255,
      );
    }

    String dois(int value) => value.toString().padLeft(2, '0');

    final agora = DateTime.now();
    final geradoEm =
        '${dois(agora.day)}/${dois(agora.month)}/${agora.year} às ${dois(agora.hour)}:${dois(agora.minute)}';
    final dataCurta = '${dois(agora.day)}/${dois(agora.month)}/${agora.year}';

    final verdeEscuro = hex('#14532D');
    final verde = hex('#166534');
    final verdeClaro = hex('#ECFDF3');
    final vermelhoEscuro = hex('#7F1D1D');
    final vermelho = hex('#B91C1C');
    final vermelhoClaro = hex('#FEF2F2');
    final texto = hex('#111827');
    final textoSuave = hex('#4B5563');
    final textoMuted = hex('#6B7280');
    final borda = hex('#D1D5DB');
    final bordaSuave = hex('#E5E7EB');
    final fundo = hex('#F9FAFB');
    final branco = PdfColors.white;

    pw.TextStyle st({
      double size = 9,
      pw.Font? font,
      PdfColor? color,
      bool bold = false,
      double? height,
    }) {
      return pw.TextStyle(
        font: font ?? (bold ? (_arialBold ?? _arial) : _arial),
        fontSize: size,
        color: color ?? texto,
        fontWeight: font == null && bold ? pw.FontWeight.bold : null,
        height: height,
      );
    }

    pw.Widget miniHeader(pw.Context context) {
      if (context.pageNumber == 1) return pw.SizedBox();

      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: bordaSuave, width: 0.8),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 28,
              height: 22,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: verdeEscuro,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'UAI',
                style: st(size: 8.5, bold: true, color: branco),
              ),
            ),
            pw.SizedBox(width: 9),
            pw.Expanded(
              child: pw.Text(
                evento.eventoNome,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: st(size: 8.4, bold: true, color: textoSuave),
              ),
            ),
            pw.Text(
              dataCurta,
              style: st(size: 7.6, bold: true, color: textoMuted),
            ),
          ],
        ),
      );
    }

    pw.Widget rodape(pw.Context context) {
      return pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: bordaSuave, width: 0.8),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'TODOS CERTIFICADOS GERADOS AUTOMATICAMENTE PELO SISTEMA UAICAPOEIRA.COM.BR',
                    maxLines: 1,
                    style: st(size: 7.2, bold: true, color: verdeEscuro),
                  ),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: st(size: 7.0, bold: true, color: textoMuted),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Sistema desenvolvido por João Lucas Silva Rabelo',
              maxLines: 1,
              style: st(size: 6.8, bold: true, color: vermelhoEscuro),
            ),
          ],
        ),
      );
    }

    pw.Widget logoUai() {
      return pw.Container(
        width: 56,
        height: 48,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: branco,
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(
          'UAI',
          style: st(size: 18, bold: true, color: vermelhoEscuro),
        ),
      );
    }

    pw.Widget metricBox({
      required String titulo,
      required String valor,
      required PdfColor color,
    }) {
      return pw.Expanded(
        child: pw.Container(
          height: 62,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: branco,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: bordaSuave, width: 0.7),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                valor,
                maxLines: 1,
                style: st(size: 19, bold: true, color: color),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                titulo.toUpperCase(),
                maxLines: 2,
                style: st(size: 6.8, bold: true, color: textoMuted),
              ),
            ],
          ),
        ),
      );
    }

    pw.Widget infoLine({
      required String label,
      required String value,
      required PdfColor color,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: pw.BoxDecoration(
          color: fundo,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: bordaSuave, width: 0.7),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$label: ',
              style: st(size: 8, bold: true, color: color),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: st(size: 8, bold: true, color: texto),
              ),
            ),
          ],
        ),
      );
    }

    final porModelo = <String, int>{};
    final porGraduacao = <String, int>{};

    for (final item in itens) {
      final modelo = item.modelo.trim().isEmpty
          ? 'CERTIFICADO'
          : item.modelo.trim().toUpperCase();
      final grad = item.graduacao.trim().isEmpty
          ? 'NÃO INFORMADA'
          : item.graduacao.trim().toUpperCase();

      porModelo[modelo] = (porModelo[modelo] ?? 0) + 1;
      porGraduacao[grad] = (porGraduacao[grad] ?? 0) + 1;
    }

    final graduacoesResumo = porGraduacao.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final modelosResumo = porModelo.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    List<List<String>> rowsResumoGraduacao() {
      return graduacoesResumo
          .map((e) => [e.key, e.value.toString()])
          .toList();
    }

    List<List<String>> rowsResumoModelo() {
      return modelosResumo
          .map((e) => [e.key, e.value.toString()])
          .toList();
    }

    final listaRows = itens.map((item) {
      return <String>[
        item.numero.toString().padLeft(2, '0'),
        item.alunoNome,
        item.graduacao,
        item.modelo,
        item.nomeArquivo,
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 32),
        theme: pw.ThemeData.withFont(
          base: _arial,
          bold: _arialBold,
        ),
        header: miniHeader,
        footer: rodape,
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: verdeEscuro,
                borderRadius: pw.BorderRadius.circular(16),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  logoUai(),
                  pw.SizedBox(width: 14),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'PACOTE PARA GRÁFICA',
                          maxLines: 1,
                          style: st(size: 20, bold: true, color: branco),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          evento.eventoNome,
                          maxLines: 2,
                          style: st(size: 11.5, bold: true, color: hex('#DCFCE7')),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Relatório de conferência dos certificados enviados no arquivo ZIP.',
                          maxLines: 2,
                          style: st(size: 8.8, color: hex('#BBF7D0'), height: 1.2),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Container(
                    width: 78,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: pw.BoxDecoration(
                      color: branco,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          itens.length.toString(),
                          style: st(size: 27, bold: true, color: verde),
                        ),
                        pw.Text(
                          'PDFs',
                          style: st(size: 8, bold: true, color: textoMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            pw.Row(
              children: [
                metricBox(
                  titulo: 'Certificados no ZIP',
                  valor: itens.length.toString(),
                  color: verde,
                ),
                pw.SizedBox(width: 8),
                metricBox(
                  titulo: 'Erros ou pulados',
                  valor: erros.length.toString(),
                  color: erros.isEmpty ? verde : vermelho,
                ),
                pw.SizedBox(width: 8),
                metricBox(
                  titulo: 'Modelo(s)',
                  valor: porModelo.length.toString(),
                  color: vermelhoEscuro,
                ),
              ],
            ),
            pw.SizedBox(height: 9),
            infoLine(
              label: 'Local/Data',
              value: evento.localData,
              color: verdeEscuro,
            ),
            pw.SizedBox(height: 5),
            infoLine(
              label: 'Gerado em',
              value: geradoEm,
              color: vermelhoEscuro,
            ),
            pw.SizedBox(height: 10),

            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: vermelhoClaro,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: hex('#FCA5A5'), width: 0.7),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 22,
                    height: 22,
                    decoration: pw.BoxDecoration(
                      color: vermelho,
                      borderRadius: pw.BorderRadius.circular(7),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      '!',
                      style: st(size: 13, bold: true, color: branco),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Orientação para conferência da gráfica',
                          style: st(size: 9.7, bold: true, color: vermelhoEscuro),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Cada arquivo PDF dentro do ZIP corresponde a um certificado individual. '
                              'Os nomes abaixo devem bater exatamente com os arquivos recebidos.',
                          style: st(size: 8.0, color: texto, height: 1.22),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 12),
            pw.Text(
              'Resumo por modelo',
              style: st(size: 12, bold: true, color: texto),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: const ['Modelo', 'Quantidade'],
              data: rowsResumoModelo(),
              border: pw.TableBorder.all(color: bordaSuave, width: 0.5),
              headerDecoration: pw.BoxDecoration(color: verdeEscuro),
              headerStyle: st(size: 8, bold: true, color: branco),
              cellStyle: st(size: 7.7, color: texto),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              oddRowDecoration: pw.BoxDecoration(color: verdeClaro),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FixedColumnWidth(80),
              },
            ),

            if (graduacoesResumo.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                'Resumo por graduação',
                style: st(size: 12, bold: true, color: texto),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: const ['Graduação', 'Quantidade'],
                data: rowsResumoGraduacao(),
                border: pw.TableBorder.all(color: bordaSuave, width: 0.5),
                headerDecoration: pw.BoxDecoration(color: verdeEscuro),
                headerStyle: st(size: 8, bold: true, color: branco),
                cellStyle: st(size: 7.4, color: texto),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4.5,
                ),
                oddRowDecoration: pw.BoxDecoration(color: verdeClaro),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FixedColumnWidth(80),
                },
              ),
            ],

            pw.SizedBox(height: 14),
            pw.Text(
              'Lista de certificados no pacote',
              style: st(size: 12, bold: true, color: texto),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: const ['#', 'Aluno', 'Graduação', 'Modelo', 'Arquivo PDF'],
              data: listaRows,
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: bordaSuave, width: 0.4),
                verticalInside: pw.BorderSide(color: bordaSuave, width: 0.3),
                top: pw.BorderSide(color: verdeEscuro, width: 0.8),
                bottom: pw.BorderSide(color: bordaSuave, width: 0.7),
                left: pw.BorderSide(color: bordaSuave, width: 0.7),
                right: pw.BorderSide(color: bordaSuave, width: 0.7),
              ),
              headerDecoration: pw.BoxDecoration(color: verdeEscuro),
              headerStyle: st(size: 7.2, bold: true, color: branco),
              headerAlignment: pw.Alignment.centerLeft,
              cellStyle: st(size: 6.4, color: texto, height: 1.12),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 3.5,
                vertical: 3.7,
              ),
              oddRowDecoration: pw.BoxDecoration(color: verdeClaro),
              columnWidths: {
                0: const pw.FixedColumnWidth(22),
                1: const pw.FlexColumnWidth(2.45),
                2: const pw.FlexColumnWidth(1.85),
                3: const pw.FixedColumnWidth(58),
                4: const pw.FlexColumnWidth(2.25),
              },
            ),

            if (erros.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Certificados com erro ou ignorados',
                style: st(size: 12, bold: true, color: vermelhoEscuro),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: const ['Aluno', 'Motivo'],
                data: erros.map((erro) => [erro.alunoNome, erro.mensagem]).toList(),
                border: pw.TableBorder.all(color: hex('#FCA5A5'), width: 0.45),
                headerDecoration: pw.BoxDecoration(color: vermelho),
                headerStyle: st(size: 8, bold: true, color: branco),
                cellStyle: st(size: 7, color: texto),
                cellAlignment: pw.Alignment.centerLeft,
                oddRowDecoration: pw.BoxDecoration(color: vermelhoClaro),
              ),
            ],
          ];
        },
      ),
    );

    return doc.save();
  }


  double _fitFontSize(
      String text,
      double base,
      double maxWidth, {
        required double minFontSize,
      }) {
    final clean = text.trim();
    if (clean.isEmpty) return base;

    // Estimativa conservadora para evitar corte no PDF.
    // Todos os campos simples devem caber em uma linha.
    // A única exceção de quebra em várias linhas é a frase do certificado.
    double units = 0;

    for (final rune in clean.runes) {
      final char = String.fromCharCode(rune);

      if (char == ' ') {
        units += 0.34;
      } else if ('MW@#%&'.contains(char)) {
        units += 0.86;
      } else if ('IÍÌÎÏ1!|'.contains(char)) {
        units += 0.34;
      } else if (RegExp(r'[A-ZÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ0-9]').hasMatch(char)) {
        units += 0.66;
      } else {
        units += 0.58;
      }
    }

    final estimated = units * base;

    if (estimated <= maxWidth) return base;

    final fitted = base * (maxWidth / estimated) * 0.92;
    return fitted.clamp(minFontSize, base);
  }

  Color _hexToColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
      if (clean.length == 8) return Color(int.parse(clean, radix: 16));
    } catch (_) {}
    return const Color(0xFFFFFFFF);
  }

  PdfColor _pdfColor(Color color) {
    return PdfColor(
      color.red / 255,
      color.green / 255,
      color.blue / 255,
      color.alpha / 255,
    );
  }

  String _nomeArquivoAlunoPdf(
      CertificadoParticipanteData participante, {
        required Map<String, int> nomesUsados,
      }) {
    final base = _limparNomeArquivo(participante.alunoNome).trim();
    final safeBase = base.isEmpty ? 'CERTIFICADO_${participante.participacaoId}' : base;

    final count = (nomesUsados[safeBase] ?? 0) + 1;
    nomesUsados[safeBase] = count;

    if (count == 1) return '$safeBase.pdf';
    return '${safeBase}_$count.pdf';
  }

  String _limparNomeArquivo(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÂÃÄ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'[^A-Z0-9 ]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

typedef CertificadoZipDiretoProgress = void Function(
    int atual,
    int total,
    String alunoNome,
    );

class CertificadoZipDiretoResultado {
  final Uint8List zipBytes;
  final Uint8List relatorioBytes;
  final List<CertificadoPacoteGraficaItem> itens;
  final List<CertificadoPacoteGraficaErro> erros;

  const CertificadoZipDiretoResultado({
    required this.zipBytes,
    required this.relatorioBytes,
    required this.itens,
    required this.erros,
  });
}
