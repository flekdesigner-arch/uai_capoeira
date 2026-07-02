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
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_lote_impressao_service.dart';

class CertificadoPdfDiretoService {
  CertificadoPdfDiretoService({CertificadoSvgService? svgService})
    : _svgService = svgService ?? const CertificadoSvgService();

  final CertificadoSvgService _svgService;

  static const double _viewBoxWidth = 297.0;
  static const double _viewBoxHeight = 210.0;
  static const String relatorioNomePadrao =
      'RELATORIO_CERTIFICADOS_GRAFICA.pdf';

  final Map<CertificadoTemplateTipo, String> _svgCache = {};
  final Map<CertificadoTemplateTipo, Map<String, CertificadoSlotModel>>
  _slotsCache = {};

  pw.Font? _arial;
  pw.Font? _arialBold;
  pw.Font? _arialItalic;
  pw.Font? _arialBoldItalic;
  pw.Font? _arialNarrow;
  pw.Font? _arialNarrowBold;
  pw.Font? _arialBlack;
  pw.Font? _arialRoundedBold;
  pw.Font? _engravers;
  pw.Font? _square;
  pw.Font? _squareBold;
  pw.Font? _squareCn;
  pw.Font? _squareCnBold;
  pw.Font? _autography;
  pw.Font? _photographSignature;
  pw.Font? _angelinaMalika;
  pw.Font? _bigTimes;

  final Map<String, pw.Font?> _fontesCertificado = {};

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

        archive.addFile(ArchiveFile(nomeArquivo, pdfBytes.length, pdfBytes));

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
      throw Exception(
        'Nenhum PDF foi gerado. Verifique as graduações e tente novamente.',
      );
    }

    final relatorioBytes = await gerarRelatorioGraficaPdf(
      evento: evento,
      itens: itens,
      erros: erros,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    archive.addFile(
      ArchiveFile(relatorioNomePadrao, relatorioBytes.length, relatorioBytes),
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
                child: pw.SvgImage(svg: svg, fit: pw.BoxFit.fill),
              ),
              ..._textosDoCertificado(
                evento: evento,
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
    required CertificadoEventoData evento,
    required Map<String, CertificadoSlotModel> slots,
    required double sx,
    required double sy,
    required CertificadoTemplateTipo tipo,
    required dynamic data,
    required CertificadoParticipanteData participante,
    required PdfColor textoPrincipal,
  }) {
    final widgets = <pw.Widget>[];

    final cfgNome = _configTextoCampo(
      evento: evento,
      participante: participante,
      campo: CertificadoTextoCampoConfig.campoNome,
      aliases: const ['aluno_nome', 'alunoNome', 'nome_aluno'],
      fontSize: 20.2,
      font: _arialBold,
      color: textoPrincipal,
      alignment: pw.Alignment.bottomCenter,
      textAlign: pw.TextAlign.center,
      minScale: 0.42,
      topOffsetMm: -1.0,
      heightExtraMm: 1.0,
    );

    final cfgCpf = _configTextoCampo(
      evento: evento,
      participante: participante,
      campo: 'cpf',
      aliases: const ['cpf_aluno', 'documento'],
      fontSize: 11.2,
      font: _arialBold ?? _arial ?? _squareBold ?? _square,
      color: textoPrincipal,
      alignment: pw.Alignment.centerLeft,
      textAlign: pw.TextAlign.left,
      minScale: 0.30,
    );

    final cfgGraduacao = _configTextoCampo(
      evento: evento,
      participante: participante,
      campo: CertificadoTextoCampoConfig.campoGraduacao,
      aliases: const ['graduacao_nova', 'graduacaoNova', 'corda'],
      fontSize: 17.4,
      font: _arialBold,
      color: textoPrincipal,
      alignment: pw.Alignment.bottomLeft,
      textAlign: pw.TextAlign.left,
      minScale: 0.38,
    );

    final cfgFrase = _configTextoCampo(
      evento: evento,
      participante: participante,
      campo: CertificadoTextoCampoConfig.campoFrase,
      aliases: const ['texto_frase', 'frase_certificado'],
      fontSize: 15.1,
      font: _engravers,
      color: textoPrincipal,
      alignment: pw.Alignment.topCenter,
      textAlign: pw.TextAlign.center,
      minScale: 0.70,
      lineHeight: 1.16,
      maxLines: 6,
    );

    final cfgLocalData = _configTextoCampo(
      evento: evento,
      participante: participante,
      campo: CertificadoTextoCampoConfig.campoLocalData,
      aliases: const ['localData', 'data_local'],
      fontSize: 13.2,
      font: _squareBold ?? _square,
      color: textoPrincipal,
      alignment: pw.Alignment.bottomCenter,
      textAlign: pw.TextAlign.center,
      minScale: 0.12,
      widthExtraMm: 90,
    );

    final cfgAssinaturaNome = _configTextoCampo(
      evento: evento,
      participante: participante,
      campo: CertificadoTextoCampoConfig.campoAssinaturaNome,
      aliases: const ['assinaturas_nome', 'nome_assinatura'],
      fontSize: 10.6,
      font: _arialBold ?? _arial,
      color: textoPrincipal,
      alignment: pw.Alignment.bottomCenter,
      textAlign: pw.TextAlign.center,
      minScale: 0.35,
    );

    final cfgAssinaturaApelido = _configTextoCampo(
      evento: evento,
      participante: participante,
      campo: CertificadoTextoCampoConfig.campoAssinaturaApelido,
      aliases: const ['assinaturas_apelido', 'apelido_assinatura'],
      fontSize: 9.4,
      font: _arial,
      color: textoPrincipal,
      alignment: pw.Alignment.bottomCenter,
      textAlign: pw.TextAlign.center,
      minScale: 0.35,
    );

    void addTextBox({
      required String text,
      required double xMm,
      required double yMm,
      required double widthMm,
      required double heightMm,
      required _CertificadoTextoConfig config,
    }) {
      final textoFinal = _textoAplicado(text, config);
      if (textoFinal.trim().isEmpty) return;

      final width = widthMm * sx;
      final fitted = config.autoAjustar
          ? _fitFontSize(
              textoFinal,
              config.fontSize,
              width,
              minFontSize: config.fontSize * config.minScale,
            )
          : config.fontSize;

      widgets.add(
        pw.Positioned(
          left: xMm * sx,
          top: yMm * sy,
          child: pw.Container(
            width: width,
            height: heightMm * sy,
            alignment: config.alignment,
            child: pw.Text(
              textoFinal,
              textAlign: config.textAlign,
              maxLines: 1,
              style: pw.TextStyle(
                font: config.font,
                fontSize: fitted,
                color: config.color,
                fontWeight: config.negrito ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ),
      );
    }

    void addSingle({
      required String id,
      required String text,
      required _CertificadoTextoConfig config,
      double rightPaddingMm = 0,
      double widthExtraMm = 0,
      double topOffsetMm = 0,
      double heightExtraMm = 0,
    }) {
      final slot = slots[id];
      if (slot == null || text.trim().isEmpty) return;

      final extraLeft = (widthExtraMm + config.widthExtraMm) / 2;
      final effectiveRightPadding = rightPaddingMm + config.rightPaddingMm;
      final xMm = (slot.x - extraLeft) + effectiveRightPadding;
      final yMm = slot.y + topOffsetMm + config.topOffsetMm;
      final widthMm =
          (slot.width + widthExtraMm + config.widthExtraMm) -
          effectiveRightPadding;
      final heightMm = slot.height + heightExtraMm + config.heightExtraMm;

      addTextBox(
        text: text,
        xMm: xMm,
        yMm: yMm,
        widthMm: widthMm,
        heightMm: heightMm,
        config: config,
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
          config: cfgCpf,
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
        config: cfgCpf,
      );
    }

    void addParagraph({
      required String id,
      required String text,
      required _CertificadoTextoConfig config,
    }) {
      final slot = slots[id];
      final textoFinal = _textoAplicado(text, config);
      if (slot == null || textoFinal.trim().isEmpty) return;

      final x = (slot.x - (config.widthExtraMm / 2)) * sx;
      final y = (slot.y + config.topOffsetMm) * sy;
      final width = (slot.width + config.widthExtraMm) * sx;
      final height = (slot.height + config.heightExtraMm) * sy;

      final paragraph = _layoutParagraphLines(
        textoFinal,
        fontSize: config.fontSize,
        width: width,
        maxHeight: height,
        maxLines: config.maxLines,
        minFontSize: config.fontSize * config.minScale,
        lineHeight: config.lineHeight,
      );

      if (paragraph.lines.isEmpty) return;

      final usedHeight =
          paragraph.lines.length * paragraph.fontSize * paragraph.lineHeight;

      double yOffset = 0;
      if (config.alignment.y == 0) {
        yOffset = ((height - usedHeight) / 2).clamp(0.0, height);
      } else if (config.alignment.y > 0) {
        yOffset = (height - usedHeight).clamp(0.0, height);
      }

      for (var index = 0; index < paragraph.lines.length; index++) {
        final line = paragraph.lines[index];

        widgets.add(
          pw.Positioned(
            left: x,
            top:
                y +
                yOffset +
                (index * paragraph.fontSize * paragraph.lineHeight),
            child: pw.Container(
              width: width,
              alignment: _horizontalAlignment(config.textAlign),
              child: pw.Text(
                line,
                textAlign: config.textAlign,
                maxLines: 1,
                style: pw.TextStyle(
                  font: config.font,
                  fontSize: paragraph.fontSize,
                  color: config.color,
                  fontWeight: config.negrito ? pw.FontWeight.bold : null,
                  height: 1.0,
                ),
              ),
            ),
          ),
        );
      }
    }

    addSingle(
      id: CertificadoSlotIds.alunoNome,
      text: data.alunoNome,
      config: cfgNome,
    );

    addCpf();

    addSingle(
      id: CertificadoSlotIds.graduacaoNova,
      text: _graduacaoExibidaComGenero(
        data.graduacaoNova,
        participante: participante,
        data: data,
      ),
      config: cfgGraduacao,
    );

    addParagraph(
      id: CertificadoSlotIds.frase,
      text: _fraseFinalComGenero(
        data: data,
        tipo: tipo,
        participante: participante,
      ),
      config: cfgFrase,
    );

    addSingle(
      id: CertificadoSlotIds.localData,
      text: data.localData,
      config: cfgLocalData,
    );

    final assinaturas = data.assinaturas;
    for (var i = 0; i < 5; i++) {
      if (i >= assinaturas.length) break;

      final a = assinaturas[i];
      addSingle(
        id: 'assinatura${i + 1}',
        text: a.nome,
        config: cfgAssinaturaNome,
      );
      addSingle(
        id: 'apelido${i + 1}',
        text: a.apelido,
        config: cfgAssinaturaApelido,
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
    _arialItalic = await _tryLoadFont('assets/fontes/ariali.ttf');
    _arialBoldItalic = await _tryLoadFont('assets/fontes/arialbi.ttf');
    _arialNarrow = await _tryLoadFont('assets/fontes/ARIALN.TTF');
    _arialNarrowBold = await _tryLoadFont('assets/fontes/ARIALNB.TTF');
    _arialBlack = await _tryLoadFont('assets/fontes/ariblk.ttf');
    _arialRoundedBold = await _tryLoadFont('assets/fontes/ARLRDBD.TTF');
    _engravers = await _tryLoadFont('assets/fontes/EngraversGothic BT.ttf');
    _square = await _tryLoadFont('assets/fontes/Square721 BT Roman.ttf');
    _squareBold = await _tryLoadFont('assets/fontes/Square721 BT Bold.ttf');
    _squareCn = await _tryLoadFont('assets/fontes/Square721 Cn BT Roman.ttf');
    _squareCnBold = await _tryLoadFont(
      'assets/fontes/Square721 Cn BT Bold.ttf',
    );
    _autography = await _tryLoadFont('assets/fontes/Autography.otf');
    _photographSignature = await _tryLoadFont(
      'assets/fontes/Photograph Signature.ttf',
    );
    _angelinaMalika = await _tryLoadFont(
      'assets/fontes/Angelina Malika Personal Use.ttf',
    );
    _bigTimes = await _tryLoadFont('assets/fontes/Bigtimes.otf');

    _fontesCertificado
      ..clear()
      ..addAll({
        'arial': _arial,
        'arialregular': _arial,
        'arial_regular': _arial,
        'arial_bold': _arialBold,
        'arialbold': _arialBold,
        'ArialBold': _arialBold,
        'arial_negrito': _arialBold,
        'arial_italic': _arialItalic,
        'arialitalic': _arialItalic,
        'arial_italico': _arialItalic,
        'arial_bold_italic': _arialBoldItalic,
        'arialbolditalic': _arialBoldItalic,
        'arial_black': _arialBlack,
        'arialblack': _arialBlack,
        'arial_preta': _arialBlack,
        'arial_narrow': _arialNarrow,
        'arialnarrow': _arialNarrow,
        'arial_narrow_bold': _arialNarrowBold,
        'arialnarrowbold': _arialNarrowBold,
        'arial_rounded': _arialRoundedBold,
        'arialrounded': _arialRoundedBold,
        'arialroundedbold': _arialRoundedBold,
        'arial_rounded_bold': _arialRoundedBold,
        'engravers': _engravers,
        'engravers_gothic': _engravers,
        'engravers_gothic_bt': _engravers,
        'engraversgothicbt': _engravers,
        'EngraversGothicBT': _engravers,
        'square': _square,
        'square721': _square,
        'square721_bt': _square,
        'square721bt': _square,
        'Square721BT': _square,
        'square_bold': _squareBold,
        'square721_bold': _squareBold,
        'square721_bt_bold': _squareBold,
        'square721btbold': _squareBold,
        'Square721BTBold': _squareBold,
        'square_cn': _squareCn,
        'square721_cn': _squareCn,
        'square721cnbt': _squareCn,
        'square721cnbtroman': _squareCn,
        'square721cnbtregular': _squareCn,
        'Square721CnBT': _squareCn,
        'square_cn_bold': _squareCnBold,
        'square721_cn_bold': _squareCnBold,
        'square721cnbtbold': _squareCnBold,
        'Square721CnBTBold': _squareCnBold,
        'autography': _autography,
        'Autography': _autography,
        'photograph_signature': _photographSignature,
        'photographsignature': _photographSignature,
        'PhotographSignature': _photographSignature,
        'angelina_malika': _angelinaMalika,
        'angelinamalika': _angelinaMalika,
        'AngelinaMalika': _angelinaMalika,
        'bigtimes': _bigTimes,
        'Bigtimes': _bigTimes,
        'big_times': _bigTimes,
      });
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

  _CertificadoTextoConfig _configTextoCampo({
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
    required String campo,
    List<String> aliases = const [],
    required double fontSize,
    required pw.Font? font,
    required PdfColor color,
    required pw.Alignment alignment,
    required pw.TextAlign textAlign,
    required double minScale,
    double lineHeight = 1.16,
    int maxLines = 1,
    double topOffsetMm = 0,
    double heightExtraMm = 0,
    double widthExtraMm = 0,
    double rightPaddingMm = 0,
  }) {
    final rawEvento = _configCampoEvento(
      evento,
      campo: campo,
      aliases: aliases,
    );

    final rawParticipante = _configCampoParticipante(
      participante,
      campo: campo,
      aliases: aliases,
    );

    final raw = <String, dynamic>{
      if (rawEvento != null) ...rawEvento,
      // Participante/graduação pode sobrescrever o evento futuramente.
      if (rawParticipante != null) ...rawParticipante,
    };

    final fonteNome = _readString(raw, const [
      'fonte',
      'font',
      'familia',
      'fontFamily',
      'family',
    ]);

    final corHex = _readString(raw, const [
      'cor',
      'color',
      'hex',
      'hexColor',
      'textColor',
      'corTexto',
    ]);

    final alinhamento = _readString(raw, const [
      'alinhamento',
      'align',
      'textAlign',
      'orientacao',
      'orientação',
    ]);

    final negrito = _readBool(raw, const [
      'negrito',
      'bold',
    ], font == _arialBold);
    final autoAjustar = _readBool(raw, const [
      'autoAjustar',
      'auto_ajustar',
      'autoFit',
      'auto_fit',
    ], true);
    final uppercase = _readBool(raw, const [
      'uppercase',
      'maiusculo',
      'maiuscula',
      'caixaAlta',
      'caixa_alta',
    ], true);

    final textCase = _normalizarTextCase(
      _readString(raw, const [
            'textCase',
            'text_case',
            'caixaTexto',
            'caixa_texto',
            'case',
          ]) ??
          (uppercase ? 'upper' : 'none'),
    );

    final tamanhoPdf = _normalizarTamanhoPt(
      _readDouble(raw, const ['tamanho', 'fontSize', 'size'], fontSize),
    );

    return _CertificadoTextoConfig(
      fontSize: tamanhoPdf,
      font: _fontByName(fonteNome, bold: negrito) ?? font,
      color: corHex == null ? color : _pdfColor(_hexToColor(corHex)),
      alignment: _alignmentFromString(alinhamento, fallback: alignment),
      textAlign: _textAlignFromString(alinhamento, fallback: textAlign),
      minScale: _readDouble(raw, const ['minScale', 'escalaMinima'], minScale),
      lineHeight: _readDouble(raw, const [
        'lineHeight',
        'line_height',
        'espacamento_linhas',
        'espacamentoLinha',
        'espacamento_linha',
        'alturaLinha',
      ], lineHeight),
      maxLines: _readInt(raw, const ['maxLines', 'linhasMaximas'], maxLines),
      topOffsetMm: _readDouble(raw, const [
        'verticalOffsetMm',
        'vertical_offset_mm',
        'topOffsetMm',
        'offsetY',
        'yOffset',
      ], topOffsetMm),
      heightExtraMm: _readDouble(raw, const [
        'heightExtraMm',
        'extraAltura',
      ], heightExtraMm),
      widthExtraMm: _readDouble(raw, const [
        'widthExtraMm',
        'extraLargura',
      ], widthExtraMm),
      rightPaddingMm: _readDouble(raw, const [
        'rightPaddingMm',
        'paddingDireita',
      ], rightPaddingMm),
      textCase: textCase,
      uppercase: uppercase,
      negrito: negrito,
      autoAjustar: autoAjustar,
    );
  }

  Map<String, dynamic>? _configCampoEvento(
    CertificadoEventoData evento, {
    required String campo,
    required List<String> aliases,
  }) {
    final keys = <String>{campo, ...aliases};

    for (final key in keys) {
      final config = evento.configuracoes.textos[key];
      if (config != null) return config.toMap();
    }

    final fallback = evento.configuracoes.textoConfig(campo);
    return fallback.toMap();
  }

  Map<String, dynamic>? _configCampoParticipante(
    CertificadoParticipanteData participante, {
    required String campo,
    required List<String> aliases,
  }) {
    final configRaiz = _readDynamicMap(participante, const [
      'configTextoCertificado',
      'config_texto_certificado',
      'configuracaoTextoCertificado',
      'configuracoesTextoCertificado',
      'textoConfig',
      'textConfig',
      'estilosTexto',
      'estilosCertificado',
      'certificadoTextoConfig',
      'certificado_texto_config',
    ]);

    final keys = <String>{campo, ...aliases};

    if (configRaiz != null) {
      for (final key in keys) {
        final value = configRaiz[key];
        if (value is Map) return Map<String, dynamic>.from(value);
      }

      // Aceita também um formato mais explícito:
      // { campos: { aluno_nome: {...}, frase: {...} } }
      final campos =
          configRaiz['campos'] ?? configRaiz['fields'] ?? configRaiz['textos'];
      if (campos is Map) {
        for (final key in keys) {
          final value = campos[key];
          if (value is Map) return Map<String, dynamic>.from(value);
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _readDynamicMap(
    Object object,
    List<String> propertyNames,
  ) {
    for (final propertyName in propertyNames) {
      try {
        final value = _readDynamicProperty(object, propertyName);
        if (value is Map) return Map<String, dynamic>.from(value);
      } catch (_) {}
    }
    return null;
  }

  dynamic _readDynamicProperty(Object object, String propertyName) {
    final d = object as dynamic;

    switch (propertyName) {
      case 'configTextoCertificado':
        return d.configTextoCertificado;
      case 'config_texto_certificado':
        return d.config_texto_certificado;
      case 'configuracaoTextoCertificado':
        return d.configuracaoTextoCertificado;
      case 'configuracoesTextoCertificado':
        return d.configuracoesTextoCertificado;
      case 'textoConfig':
        return d.textoConfig;
      case 'textConfig':
        return d.textConfig;
      case 'estilosTexto':
        return d.estilosTexto;
      case 'estilosCertificado':
        return d.estilosCertificado;
      case 'certificadoTextoConfig':
        return d.certificadoTextoConfig;
      case 'certificado_texto_config':
        return d.certificado_texto_config;
      case 'frase':
        return d.frase;
      case 'sexo':
        return d.sexo;
      case 'genero':
        return d.genero;
      case 'gênero':
        return d.genero;
      case 'alunoSexo':
        return d.alunoSexo;
      case 'sexoAluno':
        return d.sexoAluno;
      default:
        return null;
    }
  }

  String? _readString(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return null;

    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }

    return null;
  }

  double _readDouble(
    Map<String, dynamic>? data,
    List<String> keys,
    double fallback,
  ) {
    if (data == null) return fallback;

    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;

      if (value is num) return value.toDouble();

      final parsed = double.tryParse(
        value.toString().trim().replaceAll(',', '.'),
      );

      if (parsed != null) return parsed;
    }

    return fallback;
  }

  int _readInt(Map<String, dynamic>? data, List<String> keys, int fallback) {
    if (data == null) return fallback;

    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;

      if (value is int) return value;

      final parsed = int.tryParse(value.toString().trim());
      if (parsed != null) return parsed;
    }

    return fallback;
  }

  double _normalizarTamanhoPt(double tamanho) {
    if (tamanho <= 0) return tamanho;

    // Compatibilidade com configs antigas do Certificado 2.0 salvas como escala visual.
    if (tamanho < 9.0) return tamanho * 3.0;

    return tamanho;
  }

  bool _readBool(Map<String, dynamic>? data, List<String> keys, bool fallback) {
    if (data == null) return fallback;

    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;

      if (value is bool) return value;

      final text = value.toString().trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'sim' || text == 'yes') {
        return true;
      }
      if (text == 'false' ||
          text == '0' ||
          text == 'nao' ||
          text == 'não' ||
          text == 'no') {
        return false;
      }
    }

    return fallback;
  }

  pw.Font? _fontByName(String? name, {bool bold = false}) {
    if (name == null || name.trim().isEmpty) return null;

    final key = _normalizarFonteKey(name);

    if (bold) {
      if (key == 'arial') return _arialBold ?? _arial;
      if (key == 'arialnarrow' || key == 'arial_narrow') {
        return _arialNarrowBold ?? _arialNarrow;
      }
      if (key == 'square721bt' || key == 'square721_bt' || key == 'square721') {
        return _squareBold ?? _square;
      }
      if (key == 'square721cnbt' || key == 'square721_cn') {
        return _squareCnBold ?? _squareCn;
      }
    }

    return _fontesCertificado[key];
  }

  String _normalizarFonteKey(String value) {
    return value
        .trim()
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

  pw.Alignment _alignmentFromString(
    String? value, {
    required pw.Alignment fallback,
  }) {
    final key = (value ?? '').trim().toLowerCase();

    if (key.contains('left') || key.contains('esquerda')) {
      return pw.Alignment.centerLeft;
    }

    if (key.contains('right') || key.contains('direita')) {
      return pw.Alignment.centerRight;
    }

    if (key.contains('top') || key.contains('cima')) {
      return pw.Alignment.topCenter;
    }

    if (key.contains('bottom') || key.contains('baixo')) {
      return pw.Alignment.bottomCenter;
    }

    if (key.contains('center') ||
        key.contains('centro') ||
        key.contains('central')) {
      return pw.Alignment.center;
    }

    return fallback;
  }

  pw.TextAlign _textAlignFromString(
    String? value, {
    required pw.TextAlign fallback,
  }) {
    final key = (value ?? '').trim().toLowerCase();

    if (key.contains('left') || key.contains('esquerda')) {
      return pw.TextAlign.left;
    }

    if (key.contains('right') || key.contains('direita')) {
      return pw.TextAlign.right;
    }

    if (key.contains('justify') || key.contains('justificado')) {
      return pw.TextAlign.justify;
    }

    if (key.contains('center') ||
        key.contains('centro') ||
        key.contains('central')) {
      return pw.TextAlign.center;
    }

    return fallback;
  }

  String _fraseFinalComGenero({
    required dynamic data,
    required CertificadoTemplateTipo tipo,
    required CertificadoParticipanteData participante,
  }) {
    final sexo = _sexoParticipante(participante, data);
    final feminino = _isFeminino(sexo);

    // Se a frase usa tokens novos ({portador_cpf}, {reconhecido}, {apto}...),
    // o próprio CertificadoPreviewData.fraseFinal já resolve o gênero.
    // Não pode feminilizar de novo, senão PORTADORA vira PORTADORAA
    // e MONITORA vira MONITORAA/MONITORAAA.
    final fraseOriginal = _fraseOriginal(data);
    final usaTokensDeGenero = _usaTokensDeGenero(fraseOriginal);

    final titulo = usaTokensDeGenero
        ? participante.tituloGraduacao
        : _tituloGraduacaoPorGenero(
            participante.tituloGraduacao,
            feminino: feminino,
          );

    final frase = data.fraseFinal(
      tipo: tipo,
      tituloGraduacao: titulo,
      corda: participante.corda,
    );

    if (!feminino || usaTokensDeGenero) return frase;

    return _feminilizarFraseCertificado(frase);
  }

  String _fraseOriginal(dynamic data) {
    try {
      final value = _readDynamicProperty(data as Object, 'frase');
      return value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  bool _usaTokensDeGenero(String value) {
    final lower = value.toLowerCase();

    return lower.contains('{portador') ||
        lower.contains('{reconhecido}') ||
        lower.contains('{apto}') ||
        lower.contains('{aprovado}') ||
        lower.contains('{aluno}') ||
        lower.contains('{o_a}') ||
        lower.contains('{do_da}') ||
        lower.contains('{ao_a}') ||
        lower.contains('{titulo_graduacao}') ||
        lower.contains('{titulo}');
  }

  String? _sexoParticipante(
    CertificadoParticipanteData participante,
    dynamic data,
  ) {
    for (final object in [participante, data]) {
      for (final property in const [
        'sexo',
        'genero',
        'gênero',
        'alunoSexo',
        'sexoAluno',
      ]) {
        try {
          final value = _readDynamicProperty(object as Object, property);
          if (value != null) {
            final text = value.toString().trim();
            if (text.isNotEmpty) return text;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  bool _isFeminino(String? sexo) {
    if (sexo == null) return false;

    final s = sexo.trim().toLowerCase();

    return s == 'f' ||
        s == 'fem' ||
        s == 'feminino' ||
        s == 'mulher' ||
        s == 'menina' ||
        s.contains('femin');
  }

  String _graduacaoExibidaComGenero(
    String graduacao, {
    required CertificadoParticipanteData participante,
    required dynamic data,
  }) {
    final feminino = _isFeminino(_sexoParticipante(participante, data));
    if (!feminino) return graduacao;

    return _feminilizarTituloOuGraduacao(graduacao);
  }

  String _feminilizarTituloOuGraduacao(String value) {
    var out = value.trim().toUpperCase();
    if (out.isEmpty) return out;

    final substituicoes = <String, String>{
      'CONTRA-MESTRE': 'CONTRA-MESTRA',
      'CONTRA MESTRE': 'CONTRA MESTRA',
      'CONTRAMESTRE': 'CONTRAMESTRA',
      'C. MESTRE': 'C. MESTRA',
      'C.MESTRE': 'C.MESTRA',
      'CM. MESTRE': 'CM. MESTRA',
      'CM.MESTRE': 'CM.MESTRA',
      'MONITOR': 'MONITORA',
      'INSTRUTOR': 'INSTRUTORA',
      'PROFESSOR': 'PROFESSORA',
      'MESTRE': 'MESTRA',
      'FORMADO': 'FORMADA',
      'GRADUADO': 'GRADUADA',
    };

    for (final entry in substituicoes.entries) {
      out = out.replaceAll(
        RegExp('(?<![A-ZÀ-Ú])' + RegExp.escape(entry.key) + '(?![A-ZÀ-Ú])'),
        entry.value,
      );
    }

    return out;
  }

  String _tituloGraduacaoPorGenero(String titulo, {required bool feminino}) {
    if (!feminino) return titulo;

    final upper = titulo.trim().toUpperCase();

    const mapa = {
      'MONITOR': 'MONITORA',
      'INSTRUTOR': 'INSTRUTORA',
      'PROFESSOR': 'PROFESSORA',
      'CONTRA-MESTRE': 'CONTRA-MESTRA',
      'CONTRAMESTRE': 'CONTRAMESTRA',
      'MESTRE': 'MESTRA',
      'FORMADO': 'FORMADA',
    };

    for (final entry in mapa.entries) {
      if (upper == entry.key) return entry.value;
    }

    final feminilizado = _feminilizarTituloOuGraduacao(upper);
    if (feminilizado != upper) return feminilizado;

    // Regra conservadora para títulos terminados em OR.
    if (upper.endsWith('OR')) {
      return '${upper}A';
    }

    return upper;
  }

  String _feminilizarFraseCertificado(String frase) {
    var out = frase;

    final frases = <String, String>{
      'PORTADOR DO CPF': 'PORTADORA DO CPF',
      'PORTADOR(A) DO CPF': 'PORTADORA DO CPF',
      'RECONHECIDO COMO APTO E APROVADO': 'RECONHECIDA COMO APTA E APROVADA',
      'RECONHECIDO COMO APTO': 'RECONHECIDA COMO APTA',
      'APTO E APROVADO': 'APTA E APROVADA',
      'O ALUNO': 'A ALUNA',
      'DO ALUNO': 'DA ALUNA',
      'AO ALUNO': 'À ALUNA',
    };

    for (final entry in frases.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }

    final palavras = <String, String>{
      'APTO': 'APTA',
      'APROVADO': 'APROVADA',
      'FORMADO': 'FORMADA',
      'MONITOR': 'MONITORA',
      'INSTRUTOR': 'INSTRUTORA',
      'PROFESSOR': 'PROFESSORA',
      'CONTRA-MESTRE': 'CONTRA-MESTRA',
      'CONTRAMESTRE': 'CONTRAMESTRA',
      'MESTRE': 'MESTRA',
    };

    for (final entry in palavras.entries) {
      out = out.replaceAll(
        RegExp('(?<![A-ZÀ-Ú])' + RegExp.escape(entry.key) + '(?![A-ZÀ-Ú])'),
        entry.value,
      );
    }

    return out;
  }

  String _textoAplicado(String text, _CertificadoTextoConfig config) {
    final clean = text.trim();
    if (clean.isEmpty) return '';

    switch (config.textCase) {
      case 'lower':
        return clean.toLowerCase();
      case 'title':
        return _toTitleCase(clean);
      case 'none':
        return clean;
      case 'upper':
      default:
        return config.uppercase ? clean.toUpperCase() : clean;
    }
  }

  String _toTitleCase(String value) {
    final lower = value.toLowerCase();

    return lower.replaceAllMapped(
      RegExp(r'(^|[\s\-/])([a-záàâãäéèêëíìîïóòôõöúùûüç])'),
      (match) {
        final prefix = match.group(1) ?? '';
        final letter = match.group(2) ?? '';
        return '$prefix${letter.toUpperCase()}';
      },
    );
  }

  String _normalizarTextCase(String value) {
    final clean = value.trim().toLowerCase();

    if (clean == 'lower' ||
        clean == 'minusculo' ||
        clean == 'minúsculo' ||
        clean == 'minuscula' ||
        clean == 'minúscula') {
      return 'lower';
    }

    if (clean == 'title' ||
        clean == 'iniciais' ||
        clean == 'capitalizado' ||
        clean == 'capitalize') {
      return 'title';
    }

    if (clean == 'none' || clean == 'original' || clean == 'normal') {
      return 'none';
    }

    return 'upper';
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
          border: pw.Border(top: pw.BorderSide(color: bordaSuave, width: 0.8)),
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
            pw.Text('$label: ', style: st(size: 8, bold: true, color: color)),
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
      return graduacoesResumo.map((e) => [e.key, e.value.toString()]).toList();
    }

    List<List<String>> rowsResumoModelo() {
      return modelosResumo.map((e) => [e.key, e.value.toString()]).toList();
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
        theme: pw.ThemeData.withFont(base: _arial, bold: _arialBold),
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
                          style: st(
                            size: 11.5,
                            bold: true,
                            color: hex('#DCFCE7'),
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Relatório de conferência dos certificados enviados no arquivo ZIP.',
                          maxLines: 2,
                          style: st(
                            size: 8.8,
                            color: hex('#BBF7D0'),
                            height: 1.2,
                          ),
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
                          style: st(
                            size: 9.7,
                            bold: true,
                            color: vermelhoEscuro,
                          ),
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
              headers: const [
                '#',
                'Aluno',
                'Graduação',
                'Modelo',
                'Arquivo PDF',
              ],
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
                data: erros
                    .map((erro) => [erro.alunoNome, erro.mensagem])
                    .toList(),
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

  pw.Alignment _horizontalAlignment(pw.TextAlign align) {
    switch (align) {
      case pw.TextAlign.left:
      case pw.TextAlign.start:
        return pw.Alignment.centerLeft;
      case pw.TextAlign.right:
      case pw.TextAlign.end:
        return pw.Alignment.centerRight;
      case pw.TextAlign.center:
      case pw.TextAlign.justify:
      default:
        return pw.Alignment.center;
    }
  }

  _PdfParagraphLayout _layoutParagraphLines(
    String text, {
    required double fontSize,
    required double width,
    required double maxHeight,
    required int maxLines,
    required double minFontSize,
    required double lineHeight,
  }) {
    var currentFontSize = fontSize;
    final safeLineHeight = lineHeight <= 0 ? 1.16 : lineHeight;

    while (currentFontSize >= minFontSize) {
      final lines = _wrapPdfText(
        text,
        fontSize: currentFontSize,
        maxWidth: width,
      );

      final allowedByHeight = (maxHeight / (currentFontSize * safeLineHeight))
          .floor();

      final allowedLines = [
        if (maxLines > 0) maxLines,
        if (allowedByHeight > 0) allowedByHeight,
      ].reduce((a, b) => a < b ? a : b);

      if (lines.length <= allowedLines ||
          currentFontSize <= minFontSize + 0.1) {
        return _PdfParagraphLayout(
          lines: lines.take(allowedLines).toList(),
          fontSize: currentFontSize,
          lineHeight: safeLineHeight,
        );
      }

      currentFontSize -= 0.35;
    }

    final fallbackLines = _wrapPdfText(
      text,
      fontSize: minFontSize,
      maxWidth: width,
    );

    return _PdfParagraphLayout(
      lines: fallbackLines.take(maxLines).toList(),
      fontSize: minFontSize,
      lineHeight: safeLineHeight,
    );
  }

  List<String> _wrapPdfText(
    String text, {
    required double fontSize,
    required double maxWidth,
  }) {
    final words = text.trim().replaceAll(RegExp(r'\s+'), ' ').split(' ');
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';

      if (_estimatedPdfTextWidth(candidate, fontSize) <= maxWidth ||
          current.isEmpty) {
        current = candidate;
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  double _estimatedPdfTextWidth(String text, double fontSize) {
    double units = 0;

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);

      if (char == ' ') {
        units += 0.34;
      } else if ('MW@#%&'.contains(char)) {
        units += 0.86;
      } else if ('IÍÌÎÏ1!|.,:;'.contains(char)) {
        units += 0.34;
      } else if (RegExp(r'[A-ZÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ0-9]').hasMatch(char)) {
        units += 0.62;
      } else {
        units += 0.54;
      }
    }

    return units * fontSize;
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
    final safeBase = base.isEmpty
        ? 'CERTIFICADO_${participante.participacaoId}'
        : base;

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

class _PdfParagraphLayout {
  final List<String> lines;
  final double fontSize;
  final double lineHeight;

  const _PdfParagraphLayout({
    required this.lines,
    required this.fontSize,
    required this.lineHeight,
  });
}

class _CertificadoTextoConfig {
  final double fontSize;
  final pw.Font? font;
  final PdfColor color;
  final pw.Alignment alignment;
  final pw.TextAlign textAlign;
  final double minScale;
  final double lineHeight;
  final int maxLines;
  final double topOffsetMm;
  final double heightExtraMm;
  final double widthExtraMm;
  final double rightPaddingMm;
  final String textCase;
  final bool uppercase;
  final bool negrito;
  final bool autoAjustar;

  const _CertificadoTextoConfig({
    required this.fontSize,
    required this.font,
    required this.color,
    required this.alignment,
    required this.textAlign,
    required this.minScale,
    required this.lineHeight,
    required this.maxLines,
    required this.topOffsetMm,
    required this.heightExtraMm,
    required this.widthExtraMm,
    required this.rightPaddingMm,
    required this.textCase,
    required this.uppercase,
    required this.negrito,
    required this.autoAjustar,
  });
}

typedef CertificadoZipDiretoProgress =
    void Function(int atual, int total, String alunoNome);

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
