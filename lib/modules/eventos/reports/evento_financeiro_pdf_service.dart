import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class EventoFinanceiroPdfService {
  static final PdfColor verdeEscuro = PdfColor.fromHex('#1B5E20');
  static final PdfColor verdeMedio = PdfColor.fromHex('#2E7D32');
  static final PdfColor verdeClaro = PdfColor.fromHex('#E8F5E9');

  static final PdfColor vermelhoEscuro = PdfColor.fromHex('#7F1D1D');
  static final PdfColor vermelhoMedio = PdfColor.fromHex('#B91C1C');
  static final PdfColor vermelhoClaro = PdfColor.fromHex('#FEE2E2');

  static final PdfColor azulEscuro = PdfColor.fromHex('#1E3A8A');
  static final PdfColor azulMedio = PdfColor.fromHex('#2563EB');
  static final PdfColor azulClaro = PdfColor.fromHex('#DBEAFE');

  static final PdfColor laranjaEscuro = PdfColor.fromHex('#9A3412');
  static final PdfColor laranjaMedio = PdfColor.fromHex('#EA580C');
  static final PdfColor laranjaClaro = PdfColor.fromHex('#FFEDD5');

  static final PdfColor roxoEscuro = PdfColor.fromHex('#581C87');
  static final PdfColor roxoMedio = PdfColor.fromHex('#7E22CE');
  static final PdfColor roxoClaro = PdfColor.fromHex('#F3E8FF');

  static final PdfColor cinza900 = PdfColor.fromHex('#111827');
  static final PdfColor cinza700 = PdfColor.fromHex('#374151');
  static final PdfColor cinza600 = PdfColor.fromHex('#4B5563');
  static final PdfColor cinza300 = PdfColor.fromHex('#D1D5DB');
  static final PdfColor cinza200 = PdfColor.fromHex('#E5E7EB');
  static final PdfColor cinza100 = PdfColor.fromHex('#F3F4F6');
  static final PdfColor cinza50 = PdfColor.fromHex('#F9FAFB');

  static final PdfColor dourado = PdfColor.fromHex('#F59E0B');

  static final NumberFormat _realFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  static Future<pw.MemoryImage?> _carregarLogo() async {
    try {
      final Uint8List bytes = await rootBundle
          .load('assets/images/logo_uai.png')
          .then((data) => data.buffer.asUint8List());

      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _fmt(dynamic value) {
    if (value == null) return _realFormat.format(0);

    if (value is num) {
      return _realFormat.format(value);
    }

    final parsed = double.tryParse(value.toString().replaceAll(',', '.'));

    if (parsed != null) {
      return _realFormat.format(parsed);
    }

    return value.toString();
  }

  static String _safe(dynamic value, {String fallback = '---'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _arquivoSeguro(String? nome) {
    final base = (nome ?? 'evento')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áàâãéèêíïóôõöúçñ _-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');

    return base.isEmpty ? 'evento' : base;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse((value?.toString() ?? '').replaceAll(',', '.')) ?? 0;
  }

  static String _normalizarModelagemCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'BABYLOOK' ||
        clean == 'BABY_LOOK' ||
        clean == 'BABY_LOOK_FEMININA' ||
        clean == 'FEMININA') {
      return 'BABY_LOOK';
    }

    return 'NORMAL';
  }

  static String _normalizarTipoCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'MANGA_LONGA' ||
        clean == 'LONGA' ||
        clean == 'MANGA_COMPRIDA') {
      return 'MANGA_LONGA';
    }

    if (clean == 'REGATA') {
      return 'REGATA';
    }

    return 'MANGA';
  }

  static String _modelagemLabel(dynamic value) {
    switch (_normalizarModelagemCamisa(value)) {
      case 'BABY_LOOK':
        return 'Baby Look';
      case 'NORMAL':
      default:
        return 'Normal';
    }
  }

  static String _tipoCamisaLabel(dynamic value) {
    switch (_normalizarTipoCamisa(value)) {
      case 'MANGA_LONGA':
        return 'Manga Longa';
      case 'REGATA':
        return 'Regata';
      case 'MANGA':
      default:
        return 'Manga';
    }
  }

  static int _ordemTamanhoCamisa(String value) {
    final clean = value.trim().toUpperCase().replaceAll(' ', '');

    const ordem = {
      '1A': 1,
      '2A': 2,
      '4A': 4,
      '6A': 6,
      '8A': 8,
      '10A': 10,
      '12A': 12,
      '14A': 14,
      'PP': 100,
      'P': 101,
      'M': 102,
      'G': 103,
      'GG': 104,
      'EGG': 105,
      'XG': 106,
      'XXG': 107,
      'XGG': 108,
      'EXG': 109,
      'EXGG': 110,
    };

    return ordem[clean] ?? 999;
  }

  static int _ordemModelagemCamisa(String value) {
    final clean = _normalizarModelagemCamisa(value);

    switch (clean) {
      case 'NORMAL':
        return 0;
      case 'BABY_LOOK':
        return 1;
      default:
        return 99;
    }
  }

  static int _ordemTipoCamisa(String value) {
    final clean = _normalizarTipoCamisa(value);

    switch (clean) {
      case 'MANGA':
        return 0;
      case 'MANGA_LONGA':
        return 1;
      case 'REGATA':
        return 2;
      default:
        return 99;
    }
  }

  static List<List<String>> _linhasCamisasDetalhadas(
      Map<String, dynamic> bloco,
      ) {
    final porDetalheRaw = bloco['por_detalhe'] ??
        bloco['por_modelagem_tipo_tamanho'] ??
        bloco['por_grade_detalhada'];

    final unitariosRaw = bloco['por_detalhe_valor_unitario'] ??
        bloco['por_valor_unitario'] ??
        bloco['valores_unitarios'];

    final totaisRaw = bloco['por_detalhe_total'] ??
        bloco['por_total'] ??
        bloco['totais_por_detalhe'];

    double valorUnitarioDaChave(String chave, int quantidade) {
      if (unitariosRaw is Map && unitariosRaw.containsKey(chave)) {
        return _asDouble(unitariosRaw[chave]);
      }

      if (totaisRaw is Map && totaisRaw.containsKey(chave) && quantidade > 0) {
        return _asDouble(totaisRaw[chave]) / quantidade;
      }

      return 0;
    }

    double valorTotalDaChave(String chave, int quantidade, double unitario) {
      if (totaisRaw is Map && totaisRaw.containsKey(chave)) {
        return _asDouble(totaisRaw[chave]);
      }

      return quantidade * unitario;
    }

    final rows = <List<String>>[];

    if (porDetalheRaw is Map && porDetalheRaw.isNotEmpty) {
      final entries = porDetalheRaw.entries.map((entry) {
        final key = entry.key.toString();
        final quantidade = _asInt(entry.value);

        final parts = key.split('|');
        final modelagem = parts.isNotEmpty ? parts[0] : 'NORMAL';
        final tipo = parts.length > 1 ? parts[1] : 'MANGA';
        final tamanho = parts.length > 2 ? parts[2] : key;

        final unitario = valorUnitarioDaChave(key, quantidade);
        final total = valorTotalDaChave(key, quantidade, unitario);

        return _CamisaGradeRow(
          modelagem: _normalizarModelagemCamisa(modelagem),
          tipo: _normalizarTipoCamisa(tipo),
          tamanho: tamanho.trim().isEmpty
              ? 'OUTRO'
              : tamanho.trim().toUpperCase().replaceAll(' ', ''),
          quantidade: quantidade,
          valorUnitario: unitario,
          valorTotal: total,
        );
      }).where((row) => row.quantidade > 0).toList();

      entries.sort(_compararCamisaGradeRow);

      for (final row in entries) {
        rows.add([
          _modelagemLabel(row.modelagem),
          _tipoCamisaLabel(row.tipo),
          row.tamanho,
          row.quantidade.toString(),
          row.valorUnitario > 0 ? _fmt(row.valorUnitario) : '---',
          row.valorTotal > 0 ? _fmt(row.valorTotal) : '---',
        ]);
      }

      return rows;
    }

    final porTamanho = Map<String, int>.from(bloco['por_tamanho'] ?? {});

    final antigas = _ordenarTamanhos(porTamanho)
        .map(
          (entry) => _CamisaGradeRow(
        modelagem: 'NORMAL',
        tipo: 'MANGA',
        tamanho: entry.key,
        quantidade: entry.value,
        valorUnitario: 0,
        valorTotal: 0,
      ),
    )
        .toList();

    antigas.sort(_compararCamisaGradeRow);

    for (final row in antigas) {
      rows.add([
        _modelagemLabel(row.modelagem),
        _tipoCamisaLabel(row.tipo),
        row.tamanho,
        row.quantidade.toString(),
        row.valorUnitario > 0 ? _fmt(row.valorUnitario) : '---',
        row.valorTotal > 0 ? _fmt(row.valorTotal) : '---',
      ]);
    }

    return rows;
  }

  static double _valorTotalPedidoCamisas(Map<String, dynamic> bloco) {
    final direto = _asDouble(
      bloco['valor_total_pedido'] ??
          bloco['valor_total_confeccao'] ??
          bloco['total_pedido'],
    );

    if (direto > 0) return direto;

    final totaisRaw = bloco['por_detalhe_total'] ??
        bloco['por_total'] ??
        bloco['totais_por_detalhe'];

    if (totaisRaw is Map) {
      double total = 0;
      totaisRaw.forEach((_, value) => total += _asDouble(value));
      if (total > 0) return total;
    }

    return _asDouble(bloco['valor_total_camisas'] ?? bloco['valor'] ?? 0);
  }

  static int _compararCamisaGradeRow(
      _CamisaGradeRow a,
      _CamisaGradeRow b,
      ) {
    final modelagem = _ordemModelagemCamisa(a.modelagem)
        .compareTo(_ordemModelagemCamisa(b.modelagem));
    if (modelagem != 0) return modelagem;

    final tipo = _ordemTipoCamisa(a.tipo).compareTo(_ordemTipoCamisa(b.tipo));
    if (tipo != 0) return tipo;

    final tamanho = _ordemTamanhoCamisa(a.tamanho)
        .compareTo(_ordemTamanhoCamisa(b.tamanho));
    if (tamanho != 0) return tamanho;

    return a.tamanho.compareTo(b.tamanho);
  }


  // ───────────────────── PDF DE CONFECÇÃO DE CAMISAS (TOTAL) ─────────────────────
  static Future<void> gerarPdfConfeccaoCamisas({
    required Map<String, dynamic> detalhesCamisas,
    String? eventoNome,
  }) async {
    final logo = await _carregarLogo();
    final pdf = pw.Document();

    final totalCamisas = _asInt(detalhesCamisas['total_camisas']);
    final totalPedido = _valorTotalPedidoCamisas(detalhesCamisas);
    final dataRows = _linhasCamisasDetalhadas(detalhesCamisas);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : _miniHeader(logo, eventoNome ?? 'Evento'),
        footer: (ctx) => _rodapePaginado(ctx),
        build: (ctx) => [
          _heroRelatorio(
            logo: logo,
            titulo: 'PEDIDO DE CONFECÇÃO',
            subtitulo: eventoNome ?? 'Evento',
            descricao:
            'Resumo total de camisas separado por modelagem, tipo, tamanho e valor.',
            cor: verdeEscuro,
            icone: '👕',
          ),
          pw.SizedBox(height: 14),
          _metricGrid([
            _MetricData(
              titulo: 'Total de camisas',
              valor: totalCamisas.toString(),
              subtitulo: 'Peças para confecção',
              cor: verdeEscuro,
            ),
            _MetricData(
              titulo: 'Variações',
              valor: dataRows.length.toString(),
              subtitulo: 'Modelagem + tipo + tamanho',
              cor: azulEscuro,
            ),
            _MetricData(
              titulo: 'Valor do pedido',
              valor: _fmt(totalPedido),
              subtitulo: 'Custo total das peças',
              cor: roxoEscuro,
            ),
          ]),
          pw.SizedBox(height: 14),
          _quebraInteligente(espacoMinimo: 190),
          _sectionTitle(
            'Grade de confecção',
            'Modelagem, tipo de camisa, tamanho e quantidade',
          ),
          pw.SizedBox(height: 8),
          if (dataRows.isEmpty)
            _emptyBox('Nenhuma camisa encontrada.')
          else
            _modernTable(
              headers: ['Modelagem', 'Tipo', 'Tamanho', 'Qtd.', 'Valor unit.', 'Total'],
              data: dataRows,
              headerColor: verdeEscuro,
              widths: {
                0: const pw.FlexColumnWidth(1.25),
                1: const pw.FlexColumnWidth(1.25),
                2: const pw.FlexColumnWidth(0.85),
                3: const pw.FlexColumnWidth(0.70),
                4: const pw.FlexColumnWidth(1.05),
                5: const pw.FlexColumnWidth(1.10),
              },
            ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'confeccao_camisas_${_arquivoSeguro(eventoNome)}.pdf',
    );
  }

  // ───────────────────── PDF CONFECÇÃO COMPLETO (ALUNOS + AVULSAS SEPARADOS) ─────────────────────
  static Future<void> gerarPdfConfeccaoCompleto({
    required Map<String, dynamic> camisasAlunos,
    required Map<String, dynamic> camisasAvulsas,
    required Map<String, dynamic> totalGeral,
    String? eventoNome,
  }) async {
    final logo = await _carregarLogo();
    final pdf = pw.Document();

    final totalAlunos = _asInt(camisasAlunos['total']);
    final totalAvulsas = _asInt(camisasAvulsas['total']);
    final totalFinal = _asInt(totalGeral['total_camisas']);

    final valorPedidoFinal = _valorTotalPedidoCamisas(totalGeral);

    final dataAlunos = _linhasCamisasDetalhadas(camisasAlunos);
    final dataAvulsas = _linhasCamisasDetalhadas(camisasAvulsas);
    final dataTotal = _linhasCamisasDetalhadas(totalGeral);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : _miniHeader(logo, eventoNome ?? 'Evento'),
        footer: (ctx) => _rodapePaginado(ctx),
        build: (ctx) => [
          _heroRelatorio(
            logo: logo,
            titulo: 'CONFECÇÃO DETALHADA',
            subtitulo: eventoNome ?? 'Evento',
            descricao:
            'Separação de camisas por modelagem, tipo, tamanho, valor unitário e total.',
            cor: verdeEscuro,
            icone: '👕',
          ),
          pw.SizedBox(height: 14),
          _metricGrid([
            _MetricData(
              titulo: 'Alunos',
              valor: totalAlunos.toString(),
              subtitulo: 'Camisas de alunos',
              cor: verdeEscuro,
            ),
            _MetricData(
              titulo: 'Avulsas',
              valor: totalAvulsas.toString(),
              subtitulo: 'Camisas extras',
              cor: laranjaEscuro,
            ),
            _MetricData(
              titulo: 'Total geral',
              valor: totalFinal.toString(),
              subtitulo: 'Peças no pedido',
              cor: azulEscuro,
            ),
            _MetricData(
              titulo: 'Valor do pedido',
              valor: _fmt(valorPedidoFinal),
              subtitulo: 'Custo total das peças',
              cor: roxoEscuro,
            ),
          ]),
          pw.SizedBox(height: 16),
          _quebraInteligente(espacoMinimo: 180),
          _sectionTitle(
            'Camisas dos alunos',
            'Modelagem, tipo, tamanho e quantidade',
          ),
          pw.SizedBox(height: 8),
          if (dataAlunos.isEmpty)
            _emptyBox('Nenhuma camisa de alunos.')
          else
            _modernTable(
              headers: ['Modelagem', 'Tipo', 'Tamanho', 'Qtd.', 'Valor unit.', 'Total'],
              data: dataAlunos,
              headerColor: verdeEscuro,
              widths: {
                0: const pw.FlexColumnWidth(1.25),
                1: const pw.FlexColumnWidth(1.25),
                2: const pw.FlexColumnWidth(0.85),
                3: const pw.FlexColumnWidth(0.70),
                4: const pw.FlexColumnWidth(1.05),
                5: const pw.FlexColumnWidth(1.10),
              },
            ),
          pw.SizedBox(height: 16),
          _quebraInteligente(espacoMinimo: 180),
          _sectionTitle(
            'Camisas avulsas',
            'Modelagem, tipo, tamanho e quantidade',
          ),
          pw.SizedBox(height: 8),
          if (dataAvulsas.isEmpty)
            _emptyBox('Nenhuma camisa avulsa.')
          else
            _modernTable(
              headers: ['Modelagem', 'Tipo', 'Tamanho', 'Qtd.', 'Valor unit.', 'Total'],
              data: dataAvulsas,
              headerColor: laranjaEscuro,
              evenColor: laranjaClaro,
              widths: {
                0: const pw.FlexColumnWidth(1.25),
                1: const pw.FlexColumnWidth(1.25),
                2: const pw.FlexColumnWidth(0.85),
                3: const pw.FlexColumnWidth(0.70),
                4: const pw.FlexColumnWidth(1.05),
                5: const pw.FlexColumnWidth(1.10),
              },
            ),
          pw.SizedBox(height: 16),
          _quebraInteligente(
            espacoMinimo: dataTotal.length <= 6 ? 180 : 250,
          ),
          _sectionTitle(
            'Resumo geral',
            'Pedido total consolidado para a estamparia',
          ),
          pw.SizedBox(height: 8),
          if (dataTotal.isEmpty)
            _emptyBox('Nenhuma camisa no resumo geral.')
          else
            _modernTable(
              headers: ['Modelagem', 'Tipo', 'Tamanho', 'Qtd.', 'Valor unit.', 'Total'],
              data: dataTotal,
              headerColor: azulEscuro,
              evenColor: azulClaro,
              widths: {
                0: const pw.FlexColumnWidth(1.25),
                1: const pw.FlexColumnWidth(1.25),
                2: const pw.FlexColumnWidth(0.85),
                3: const pw.FlexColumnWidth(0.70),
                4: const pw.FlexColumnWidth(1.05),
                5: const pw.FlexColumnWidth(1.10),
              },
            ),
          pw.SizedBox(height: 10),
          _totalPedidoBox(valorPedidoFinal),
          _legendaConfeccao(),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'confeccao_detalhado_${_arquivoSeguro(eventoNome)}.pdf',
    );
  }


  // ───────────────────── PDF LISTA DE ENTREGA DE CAMISAS ─────────────────────
  static Future<void> gerarPdfListaEntregaCamisasCompleta({
    required List<Map<String, dynamic>> itens,
    String? eventoNome,
  }) async {
    final logo = await _carregarLogo();
    final pdf = pw.Document();

    final itensOrdenados = List<Map<String, dynamic>>.from(itens)
      ..sort((a, b) {
        final nomeA = _safe(a['nome']).toUpperCase();
        final nomeB = _safe(b['nome']).toUpperCase();
        return nomeA.compareTo(nomeB);
      });

    final totalItens = itensOrdenados.length;
    final totalAlunos = itensOrdenados
        .where((item) => _safe(item['origem']).toUpperCase().contains('ALUNO'))
        .length;
    final totalAvulsas = totalItens - totalAlunos;

    final rows = itensOrdenados.map((item) {
      final nome = _safe(item['nome']);
      final origem = _safe(item['origem'], fallback: '---');
      final modelagem = _modelagemLabel(item['modelagem_camisa'] ?? item['modelagem']);
      final tipo = _tipoCamisaLabel(item['tipo_camisa'] ?? item['tipo']);
      final tamanho = _safe(
        item['tamanho_camisa'] ?? item['tamanho'],
        fallback: '---',
      );

      return [
        '',
        nome,
        origem,
        '$modelagem • $tipo',
        tamanho,
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : _miniHeader(logo, eventoNome ?? 'Evento'),
        footer: (ctx) => _rodapePaginado(ctx),
        build: (ctx) => [
          _heroRelatorio(
            logo: logo,
            titulo: 'LISTA DE ENTREGA DE CAMISAS',
            subtitulo: eventoNome ?? 'Evento',
            descricao:
            'Lista única com alunos e camisas avulsas para conferência de entrega.',
            cor: azulEscuro,
            icone: '👕',
          ),
          pw.SizedBox(height: 14),
          _metricGrid([
            _MetricData(
              titulo: 'Total',
              valor: totalItens.toString(),
              subtitulo: 'Camisas na lista',
              cor: azulEscuro,
            ),
            _MetricData(
              titulo: 'Alunos',
              valor: totalAlunos.toString(),
              subtitulo: 'Participantes do evento',
              cor: verdeEscuro,
            ),
            _MetricData(
              titulo: 'Avulsas',
              valor: totalAvulsas.toString(),
              subtitulo: 'Camisas extras',
              cor: laranjaEscuro,
            ),
          ]),
          pw.SizedBox(height: 14),
          _sectionTitle(
            'Conferência de entrega',
            'Marque o quadradinho quando a camisa for entregue',
          ),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            _emptyBox('Nenhuma camisa encontrada para entrega.')
          else
            _modernTable(
              headers: ['Entregue', 'Nome', 'Origem', 'Camisa', 'Tam.'],
              data: rows,
              headerColor: azulEscuro,
              evenColor: azulClaro,
              widths: {
                0: const pw.FlexColumnWidth(0.75),
                1: const pw.FlexColumnWidth(2.35),
                2: const pw.FlexColumnWidth(0.95),
                3: const pw.FlexColumnWidth(1.55),
                4: const pw.FlexColumnWidth(0.70),
              },
              cellBuilder: (value, rowIndex, colIndex) {
                if (colIndex == 0) {
                  return pw.Center(
                    child: pw.Container(
                      width: 11,
                      height: 11,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: cinza700, width: 0.9),
                        borderRadius: pw.BorderRadius.circular(2),
                        color: PdfColors.white,
                      ),
                    ),
                  );
                }

                return pw.Text(
                  value,
                  style: pw.TextStyle(
                    color: cinza900,
                    fontSize: 8,
                    fontWeight: colIndex == 1
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip,
                );
              },
            ),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: cinza100,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: cinza300, width: 0.6),
            ),
            child: pw.Text(
              'Observação: esta lista serve apenas para controle manual da entrega. '
                  'Após conferir no papel, atualize o status de entrega no sistema.',
              style: pw.TextStyle(
                color: cinza700,
                fontSize: 8.5,
                lineSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'lista_entrega_camisas_${_arquivoSeguro(eventoNome)}.pdf',
    );
  }

  // ───────────────────── PDF RELATÓRIO GERAL ─────────────────────
  static Future<void> gerarPdfRelatorioGeral({
    required double totalReceitas,
    required double totalGastos,
    required double saldoLiquido,
    required int totalParticipantes,
    required int quitados,
    required int inadimplentes,
    required int cobertosPorPatrocinio,
    required double totalInscricoes,
    required double totalCamisas,
    required double totalPatrocinios,
    required Map<String, double> receitasPorForma,
    required Map<String, double> gastosPorCategoria,
    required Map<String, dynamic> detalhesCamisas,
    required Map<String, dynamic> detalhesPatrocinios,
    required List<Map<String, dynamic>> usosPatrocinio,
    String? eventoNome,
  }) async {
    final logo = await _carregarLogo();
    final pdf = pw.Document();

    final saldoCor = saldoLiquido >= 0 ? verdeEscuro : vermelhoEscuro;
    final taxaQuitados = totalParticipantes <= 0
        ? 0.0
        : (quitados / totalParticipantes).clamp(0.0, 1.0);
    final taxaPatrocinados = totalParticipantes <= 0
        ? 0.0
        : (cobertosPorPatrocinio / totalParticipantes).clamp(0.0, 1.0);
    final taxaInadimplentes = totalParticipantes <= 0
        ? 0.0
        : (inadimplentes / totalParticipantes).clamp(0.0, 1.0);

    final camisaRows = _linhasCamisasDetalhadas(detalhesCamisas);

    final receitaTipoRows = [
      ['Inscrições', _fmt(totalInscricoes)],
      ['Camisas', _fmt(totalCamisas)],
      ['Patrocínios', _fmt(totalPatrocinios)],
    ];

    final receitasFormaRows = receitasPorForma.entries
        .map((e) => [e.key, _fmt(e.value)])
        .toList();

    final gastosRows = gastosPorCategoria.entries
        .map((e) => [e.key, _fmt(e.value)])
        .toList();

    final usosRows = usosPatrocinio.map((u) {
      return [
        _safe(u['aluno_nome']),
        _fmt(u['valor']),
        _safe(u['patrocinador']),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : _miniHeader(logo, eventoNome ?? 'Evento'),
        footer: (ctx) => _rodapePaginado(ctx),
        build: (ctx) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _heroRelatorio(
                logo: logo,
                titulo: 'RELATÓRIO FINANCEIRO GERAL',
                subtitulo: eventoNome ?? 'Evento',
                descricao:
                'Visão completa de receitas, gastos, participantes, camisas e patrocínios.',
                cor: verdeEscuro,
                icone: 'PDF',
              ),
              pw.SizedBox(height: 14),
            ],
          ),

          _sectionBlock(
            title: 'Resumo financeiro',
            subtitle: 'Resultado geral do evento',
            minFreeSpace: 190,
            children: [
              _metricGrid([
                _MetricData(
                  titulo: 'Receitas',
                  valor: _fmt(totalReceitas),
                  subtitulo: 'Total arrecadado',
                  cor: verdeEscuro,
                ),
                _MetricData(
                  titulo: 'Gastos',
                  valor: _fmt(totalGastos),
                  subtitulo: 'Total de despesas',
                  cor: vermelhoEscuro,
                ),
                _MetricData(
                  titulo: saldoLiquido >= 0 ? 'Saldo positivo' : 'Saldo negativo',
                  valor: _fmt(saldoLiquido),
                  subtitulo: 'Resultado líquido',
                  cor: saldoCor,
                ),
              ]),
              pw.SizedBox(height: 12),
              _resultadoDestaque(
                saldoLiquido: saldoLiquido,
                totalReceitas: totalReceitas,
                totalGastos: totalGastos,
              ),
            ],
          ),

          _sectionBlock(
            title: 'Participações',
            subtitle: 'Situação dos alunos no evento',
            minFreeSpace: 220,
            children: [
              _metricGrid([
                _MetricData(
                  titulo: 'Participantes',
                  valor: totalParticipantes.toString(),
                  subtitulo: 'Alunos válidos',
                  cor: azulEscuro,
                ),
                _MetricData(
                  titulo: 'Quitados',
                  valor: quitados.toString(),
                  subtitulo:
                  '${(taxaQuitados * 100).toStringAsFixed(1)}% do total',
                  cor: verdeEscuro,
                ),
                _MetricData(
                  titulo: 'Patrocinados',
                  valor: cobertosPorPatrocinio.toString(),
                  subtitulo:
                  '${(taxaPatrocinados * 100).toStringAsFixed(1)}% do total',
                  cor: roxoEscuro,
                ),
                _MetricData(
                  titulo: 'Inadimplentes',
                  valor: inadimplentes.toString(),
                  subtitulo:
                  '${(taxaInadimplentes * 100).toStringAsFixed(1)}% do total',
                  cor: vermelhoEscuro,
                ),
              ]),
              pw.SizedBox(height: 10),
              _progressBlock(
                title: 'Quitação geral',
                items: [
                  _ProgressData(
                    label: 'Quitados',
                    value: taxaQuitados,
                    color: verdeEscuro,
                    detail: '$quitados de $totalParticipantes',
                  ),
                  _ProgressData(
                    label: 'Patrocinados',
                    value: taxaPatrocinados,
                    color: roxoEscuro,
                    detail: '$cobertosPorPatrocinio de $totalParticipantes',
                  ),
                  _ProgressData(
                    label: 'Inadimplentes',
                    value: taxaInadimplentes,
                    color: vermelhoEscuro,
                    detail: '$inadimplentes de $totalParticipantes',
                  ),
                ],
              ),
            ],
          ),

          _sectionBlock(
            title: 'Receitas por origem',
            subtitle: 'Inscrições, camisas e patrocínios',
            minFreeSpace: 130,
            children: [
              _modernTable(
                headers: ['Origem', 'Valor'],
                data: receitaTipoRows,
                headerColor: verdeEscuro,
                widths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1.2),
                },
              ),
            ],
          ),

          if (receitasFormaRows.isNotEmpty)
            _sectionBlock(
              title: 'Receitas por forma de pagamento',
              subtitle: 'Como os pagamentos foram recebidos',
              minFreeSpace: 130,
              children: [
                _modernTable(
                  headers: ['Forma de pagamento', 'Valor'],
                  data: receitasFormaRows,
                  headerColor: azulEscuro,
                  evenColor: azulClaro,
                  widths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1.2),
                  },
                ),
              ],
            ),

          if (gastosRows.isNotEmpty)
            _sectionBlock(
              title: 'Gastos por categoria',
              subtitle: 'Resumo das despesas',
              minFreeSpace: 130,
              keepTogether: gastosRows.length <= 8,
              children: [
                _modernTable(
                  headers: ['Categoria', 'Valor'],
                  data: gastosRows,
                  headerColor: vermelhoEscuro,
                  evenColor: vermelhoClaro,
                  widths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1.2),
                  },
                ),
              ],
            ),

          _sectionBlock(
            title: 'Camisas',
            subtitle: 'Pedido, pagamentos e grade',
            minFreeSpace: camisaRows.length <= 10 ? 230 : 170,
            keepTogether: camisaRows.length <= 10,
            children: [
              _metricGrid([
                _MetricData(
                  titulo: 'Total camisas',
                  valor: '${detalhesCamisas['total_camisas'] ?? 0}',
                  subtitulo: 'Modelagem, tipo e tamanho',
                  cor: azulEscuro,
                ),
                _MetricData(
                  titulo: 'Pagas',
                  valor: '${detalhesCamisas['camisas_pagas'] ?? 0}',
                  subtitulo: 'Camisas quitadas',
                  cor: verdeEscuro,
                ),
                _MetricData(
                  titulo: 'Valor total',
                  valor: _fmt(detalhesCamisas['valor_total_camisas']),
                  subtitulo: 'Receita de camisas',
                  cor: laranjaEscuro,
                ),
              ]),
              if (camisaRows.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                _modernTable(
                  headers: ['Modelagem', 'Tipo', 'Tamanho', 'Qtd.', 'Valor unit.', 'Total'],
                  data: camisaRows,
                  headerColor: laranjaEscuro,
                  evenColor: laranjaClaro,
                  widths: {
                    0: const pw.FlexColumnWidth(1.35),
                    1: const pw.FlexColumnWidth(1.35),
                    2: const pw.FlexColumnWidth(1),
                    3: const pw.FlexColumnWidth(1),
                  },
                ),
              ],
            ],
          ),

          _sectionBlock(
            title: 'Patrocínios',
            subtitle: 'Controle de patrocinadores e beneficiados',
            minFreeSpace: 170,
            children: [
              _metricGrid([
                _MetricData(
                  titulo: 'Patrocinadores',
                  valor: '${detalhesPatrocinios['total_patrocinadores'] ?? 0}',
                  subtitulo: 'Apoiadores cadastrados',
                  cor: roxoEscuro,
                ),
                _MetricData(
                  titulo: 'Pagos',
                  valor: '${detalhesPatrocinios['patrocinios_pagos'] ?? 0}',
                  subtitulo: 'Patrocínios recebidos',
                  cor: verdeEscuro,
                ),
                _MetricData(
                  titulo: 'Pendentes',
                  valor: '${detalhesPatrocinios['patrocinios_pendentes'] ?? 0}',
                  subtitulo: 'Aguardando pagamento',
                  cor: vermelhoEscuro,
                ),
                _MetricData(
                  titulo: 'Valor recebido',
                  valor: _fmt(detalhesPatrocinios['valor_total_patrocinios']),
                  subtitulo: 'Total em patrocínios',
                  cor: azulEscuro,
                ),
              ]),
            ],
          ),

          if (usosRows.isNotEmpty)
            _sectionBlock(
              title: 'Beneficiados por patrocínio',
              subtitle: 'Alunos cobertos por patrocinadores',
              minFreeSpace: usosRows.length <= 8 ? 170 : 120,
              keepTogether: usosRows.length <= 8,
              children: [
                _noticeBox(
                  title: 'Alunos beneficiados por patrocínio',
                  text:
                  'Lista gerada com base nos dados válidos enviados pela tela de relatório.',
                  color: roxoEscuro,
                  background: roxoClaro,
                ),
                pw.SizedBox(height: 8),
                _modernTable(
                  headers: ['Aluno', 'Valor', 'Patrocinador'],
                  data: usosRows,
                  headerColor: roxoEscuro,
                  evenColor: roxoClaro,
                  cellFontSize: 7.5,
                  widths: {
                    0: const pw.FlexColumnWidth(2.4),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1.6),
                  },
                ),
              ],
            ),

          _sectionBlock(
            title: 'Observação final',
            subtitle: 'Registro automático',
            minFreeSpace: 90,
            children: [
              _assinaturaBox(),
            ],
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'relatorio_geral_${_arquivoSeguro(eventoNome)}.pdf',
    );
  }

  // ───────────────────── PDF LISTA DE PARTICIPANTES (BÁSICO) ─────────────────────
  static Future<void> gerarPdfListaParticipantes({
    required List<Map<String, dynamic>> participantes,
    String? eventoNome,
  }) async {
    final logo = await _carregarLogo();
    final pdf = pw.Document();

    final rows = participantes.map((p) {
      return [
        _safe(p['nome']),
        _safe(p['status']),
        _safe(p['tamanho_camisa']),
        _fmt(p['valor_pago'] ?? 0),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : _miniHeader(logo, eventoNome ?? 'Evento'),
        footer: (ctx) => _rodapePaginado(ctx),
        build: (ctx) => [
          _heroRelatorio(
            logo: logo,
            titulo: 'LISTA DE PARTICIPANTES',
            subtitulo: eventoNome ?? 'Evento',
            descricao: 'Relação básica de participantes do evento.',
            cor: verdeEscuro,
            icone: '👥',
          ),
          pw.SizedBox(height: 14),
          _metricGrid([
            _MetricData(
              titulo: 'Participantes',
              valor: participantes.length.toString(),
              subtitulo: 'Registros na lista',
              cor: azulEscuro,
            ),
          ]),
          pw.SizedBox(height: 14),
          _modernTable(
            headers: ['Nome', 'Status', 'Camisa', 'Valor pago'],
            data: rows,
            headerColor: verdeEscuro,
            cellFontSize: 8,
            widths: {
              0: const pw.FlexColumnWidth(2.8),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(0.8),
              3: const pw.FlexColumnWidth(1.1),
            },
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'lista_participantes_${_arquivoSeguro(eventoNome)}.pdf',
    );
  }

  // ───────────────────── PDF CONFERÊNCIA DE NOMES ─────────────────────
  static Future<void> gerarPdfConferenciaNomes({
    required List<Map<String, dynamic>> participantes,
    String? eventoNome,
  }) async {
    final logo = await _carregarLogo();
    final pdf = pw.Document();

    final rows = participantes.map((p) {
      return [
        _safe(p['nome']),
        _safe(p['tamanho_camisa']),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : _miniHeader(logo, eventoNome ?? 'Evento'),
        footer: (ctx) => _rodapePaginado(ctx),
        build: (ctx) => [
          _heroRelatorio(
            logo: logo,
            titulo: 'CONFERÊNCIA DE NOMES',
            subtitulo: eventoNome ?? 'Evento',
            descricao:
            'Lista para conferência antes da impressão de certificados e camisas.',
            cor: verdeEscuro,
            icone: '✅',
          ),
          pw.SizedBox(height: 14),
          _noticeBox(
            title: 'ATENÇÃO',
            text:
            'Verifique se o nome e o tamanho da camisa estão corretos. O nome será impresso no certificado exatamente como estiver nesta lista.',
            color: vermelhoEscuro,
            background: vermelhoClaro,
          ),
          pw.SizedBox(height: 14),
          _modernTable(
            headers: ['Nome', 'Tamanho camisa'],
            data: rows,
            headerColor: verdeEscuro,
            cellFontSize: 8,
            widths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FixedColumnWidth(78),
            },
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'conferencia_nomes_${_arquivoSeguro(eventoNome)}.pdf',
    );
  }

  // ───────────────────── PDF LISTA COMPLETA (COM CORDA E GRADUAÇÃO) ─────────────────────
  static Future<void> gerarPdfListaCompleta({
    required List<Map<String, dynamic>> participantes,
    String? eventoNome,
  }) async {
    final logo = await _carregarLogo();
    final pdf = pw.Document();

    final headers = [
      'Nome',
      'Status',
      'Camisa / Entregue',
      'Brinde Entregue',
      'Valor Pago',
      'Corda Cortada',
      'Graduação',
    ];

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: verdeEscuro),
        children: headers.map((h) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: pw.Text(
              h,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 7.5,
              ),
            ),
          );
        }).toList(),
      ),
    ];

    for (int i = 0; i < participantes.length; i++) {
      final p = participantes[i];
      final bgColor = i % 2 == 0 ? verdeClaro : PdfColors.white;

      final graduacaoNome = _safe(p['graduacao_nova']);
      final hex1 = p['hex_cor1'] as String?;
      final hex2 = p['hex_cor2'] as String?;

      final cordaCortada = _checkBoxPdf();

      pw.Widget graduacaoWidget;

      if (hex1 != null && hex2 != null && hex1.isNotEmpty && hex2.isNotEmpty) {
        final cor1 = PdfColor.fromHex(hex1);
        final cor2 = PdfColor.fromHex(hex2);

        graduacaoWidget = pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              graduacaoNome,
              maxLines: 2,
              style: const pw.TextStyle(fontSize: 6.0),
            ),
            pw.SizedBox(height: 3),
            pw.Row(
              children: [
                pw.Container(
                  width: 10,
                  height: 10,
                  decoration: pw.BoxDecoration(
                    color: cor2,
                    borderRadius: pw.BorderRadius.circular(2),
                    border: pw.Border.all(color: cinza700, width: 0.4),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Container(
                  width: 10,
                  height: 10,
                  decoration: pw.BoxDecoration(
                    color: cor1,
                    borderRadius: pw.BorderRadius.circular(2),
                    border: pw.Border.all(color: cinza700, width: 0.4),
                  ),
                ),
              ],
            ),
          ],
        );
      } else {
        graduacaoWidget = pw.Text(
          graduacaoNome,
          maxLines: 2,
          style: const pw.TextStyle(fontSize: 6.0),
        );
      }

      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: bgColor),
          children: [
            _tableCell(_safe(p['nome']), fontSize: 6.4),
            _tableCell(_safe(p['status']), fontSize: 6.4),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Center(
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      _safe(p['tamanho_camisa']),
                      maxLines: 1,
                      style: pw.TextStyle(
                        fontSize: 6.4,
                        color: cinza900,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 3),
                    _checkBoxPdf(),
                  ],
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Center(child: _checkBoxPdf()),
            ),
            _tableCell(_fmt(p['valor_pago'] ?? 0), fontSize: 6.4),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Center(child: cordaCortada),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: graduacaoWidget,
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(),
        header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : _miniHeader(logo, eventoNome ?? 'Evento'),
        footer: (ctx) => _rodapePaginado(ctx),
        build: (ctx) => [
          _heroRelatorio(
            logo: logo,
            titulo: 'LISTA COMPLETA',
            subtitulo: eventoNome ?? 'Evento',
            descricao:
            'Participantes, pagamento, camisa, brinde, corda cortada e graduação.',
            cor: verdeEscuro,
            icone: 'PDF',
            destaqueDireitaTitulo: participantes.length.toString(),
            destaqueDireitaSubtitulo: 'PARTICIPANTES',
          ),
          pw.SizedBox(height: 12),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: cinza200, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.15),
              1: const pw.FixedColumnWidth(45),
              2: const pw.FixedColumnWidth(58),
              3: const pw.FixedColumnWidth(48),
              4: const pw.FixedColumnWidth(54),
              5: const pw.FixedColumnWidth(46),
              6: const pw.FlexColumnWidth(1.45),
            },
            children: tableRows,
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'lista_completa_${_arquivoSeguro(eventoNome)}.pdf',
    );
  }

  // ───────────────────── HELPERS DE DESIGN ─────────────────────
  static pw.Widget _sectionBlock({
    required String title,
    required String subtitle,
    required List<pw.Widget> children,
    double minFreeSpace = 130,
    bool keepTogether = true,
  }) {
    final content = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(title, subtitle),
        pw.SizedBox(height: 8),
        ...children,
        pw.SizedBox(height: 16),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.NewPage(freeSpace: minFreeSpace),
        if (keepTogether) content else content,
      ],
    );
  }


  static pw.Widget _quebraInteligente({double espacoMinimo = 180}) {
    return pw.NewPage(freeSpace: espacoMinimo);
  }


  static pw.Widget _totalPedidoBox(double valorTotal) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: roxoClaro,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: roxoEscuro, width: 0.65),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'VALOR TOTAL DO PEDIDO',
            style: pw.TextStyle(
              color: roxoEscuro,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            _fmt(valorTotal),
            style: pw.TextStyle(
              color: roxoEscuro,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _legendaConfeccao() {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: azulClaro,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: azulEscuro, width: 0.65),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Legenda para a estamparia',
            style: pw.TextStyle(
              color: azulEscuro,
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.RichText(
            text: pw.TextSpan(
              style: pw.TextStyle(
                color: cinza700,
                fontSize: 8,
                lineSpacing: 1.5,
              ),
              children: [
                pw.TextSpan(
                  text: 'Modelagem: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                const pw.TextSpan(
                  text:
                  'Normal = camisa tradicional/unissex. Baby Look = modelagem feminina mais ajustada. ',
                ),
                pw.TextSpan(
                  text: 'Tipo: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                const pw.TextSpan(
                  text:
                  'Manga = manga curta normal. Manga Longa = camisa de manga longa. Regata = camisa sem mangas.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _logoBox(
      pw.MemoryImage? logo, {
        double size = 64,
        PdfColor? fallbackColor,
        bool compact = false,
      }) {
    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(compact ? 8 : 14),
      ),
      child: pw.Center(
        child: logo != null
            ? pw.Padding(
          // A logo original tem respiro interno. Esse padding assimétrico
          // centraliza melhor visualmente dentro do quadrado branco.
          padding: const pw.EdgeInsets.fromLTRB(7, 4, 7, 8),
          child: pw.Image(
            logo,
            fit: pw.BoxFit.contain,
            alignment: pw.Alignment.center,
          ),
        )
            : pw.Text(
          'UAI',
          style: pw.TextStyle(
            fontSize: compact ? 10 : 16,
            fontWeight: pw.FontWeight.bold,
            color: fallbackColor ?? verdeEscuro,
          ),
        ),
      ),
    );
  }

  static pw.PageTheme _pageTheme({
    pw.PageOrientation orientation = pw.PageOrientation.portrait,
  }) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
    );
  }

  static pw.Widget _miniHeader(pw.MemoryImage? logo, String eventoNome) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: cinza200, width: 1)),
      ),
      child: pw.Row(
        children: [
          if (logo != null)
            pw.Container(
              margin: const pw.EdgeInsets.only(right: 10),
              child: _logoBox(
                logo,
                size: 34,
                fallbackColor: verdeEscuro,
                compact: true,
              ),
            ),
          pw.Expanded(
            child: pw.Text(
              eventoNome,
              maxLines: 1,
              style: pw.TextStyle(
                color: cinza700,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(
            DateFormat('dd/MM/yyyy').format(DateTime.now()),
            style: pw.TextStyle(color: cinza600, fontSize: 8),
          ),
        ],
      ),
    );
  }

  static pw.Widget _heroRelatorio({
    required pw.MemoryImage? logo,
    required String titulo,
    required String subtitulo,
    required String descricao,
    required PdfColor cor,
    required String icone,
    String? destaqueDireitaTitulo,
    String? destaqueDireitaSubtitulo,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: cor,
        borderRadius: pw.BorderRadius.circular(16),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _logoBox(
            logo,
            size: 64,
            fallbackColor: cor,
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  titulo,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  subtitulo,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  descricao,
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9.5,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          if (destaqueDireitaTitulo != null) ...[
            pw.SizedBox(width: 12),
            pw.Container(
              width: 96,
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    destaqueDireitaTitulo,
                    maxLines: 1,
                    style: pw.TextStyle(
                      color: cor,
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    destaqueDireitaSubtitulo ?? '',
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    style: pw.TextStyle(
                      color: cinza700,
                      fontSize: 6.8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String title, String subtitle) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 6,
          height: 24,
          decoration: pw.BoxDecoration(
            color: verdeEscuro,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: cinza900,
                ),
              ),
              pw.Text(
                subtitle,
                style: pw.TextStyle(
                  fontSize: 8,
                  color: cinza600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _metricGrid(List<_MetricData> metrics) {
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints?.maxWidth ?? PdfPageFormat.a4.width;
        final columns = metrics.length >= 4
            ? 4
            : metrics.length == 3
            ? 3
            : 2;
        final spacing = 8.0;
        final itemWidth = (maxWidth - spacing * (columns - 1)) / columns;

        return pw.Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics.map((metric) {
            return pw.SizedBox(
              width: itemWidth,
              child: _metricCard(metric),
            );
          }).toList(),
        );
      },
    );
  }

  static pw.Widget _metricCard(_MetricData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: cinza200, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            height: 4,
            width: 32,
            decoration: pw.BoxDecoration(
              color: data.cor,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            data.titulo,
            maxLines: 1,
            style: pw.TextStyle(
              fontSize: 8,
              color: cinza600,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            data.valor,
            maxLines: 1,
            style: pw.TextStyle(
              fontSize: 14,
              color: data.cor,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            data.subtitulo,
            maxLines: 2,
            style: pw.TextStyle(
              fontSize: 7.2,
              color: cinza600,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _resultadoDestaque({
    required double saldoLiquido,
    required double totalReceitas,
    required double totalGastos,
  }) {
    final positivo = saldoLiquido >= 0;
    final cor = positivo ? verdeEscuro : vermelhoEscuro;
    final bg = positivo ? verdeClaro : vermelhoClaro;

    final margem = totalReceitas <= 0 ? 0.0 : saldoLiquido / totalReceitas;

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: cor, width: 0.8),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 42,
            height: 42,
            decoration: pw.BoxDecoration(
              color: cor,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Center(
              child: pw.Text(
                positivo ? 'OK' : '!',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  positivo ? 'Evento com saldo positivo' : 'Evento com saldo negativo',
                  style: pw.TextStyle(
                    color: cor,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Saldo líquido de ${_fmt(saldoLiquido)}. Margem aproximada: ${(margem * 100).toStringAsFixed(1)}%.',
                  style: pw.TextStyle(
                    color: cinza700,
                    fontSize: 8.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _progressBlock({
    required String title,
    required List<_ProgressData> items,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: cinza200, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              color: cinza900,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...items.map((item) => _progressLine(item)),
        ],
      ),
    );
  }

  static pw.Widget _progressLine(_ProgressData item) {
    final percent = (item.value * 100).clamp(0, 100).toStringAsFixed(1);

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  item.label,
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: cinza700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                '$percent% - ${item.detail}',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: item.color,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 6,
            decoration: pw.BoxDecoration(
              color: cinza200,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: (item.value * 1000).round().clamp(0, 1000),
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      color: item.color,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: (1000 - (item.value * 1000).round()).clamp(0, 1000),
                  child: pw.SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _modernTable({
    required List<String> headers,
    required List<List<String>> data,
    required PdfColor headerColor,
    PdfColor? evenColor,
    double cellFontSize = 8.5,
    Map<int, pw.TableColumnWidth>? widths,
    pw.Widget Function(String value, int rowIndex, int colIndex)? cellBuilder,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: cinza200, width: 0.45),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerColor),
          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: pw.Text(
                h,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: cellFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
        ...List.generate(data.length, (index) {
          final row = data[index];

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? (evenColor ?? cinza50) : PdfColors.white,
            ),
            children: List.generate(row.length, (colIndex) {
              final cell = row[colIndex];

              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                child: cellBuilder == null
                    ? pw.Text(
                  cell,
                  style: pw.TextStyle(
                    color: cinza900,
                    fontSize: cellFontSize,
                  ),
                )
                    : cellBuilder(cell, index, colIndex),
              );
            }),
          );
        }),
      ],
    );
  }

  static pw.Widget _checkBoxPdf() {
    return pw.Container(
      width: 10,
      height: 10,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(1),
        border: pw.Border.all(color: cinza700, width: 0.9),
      ),
    );
  }

  static pw.Widget _tableCell(String text, {double fontSize = 8}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        maxLines: 2,
        style: pw.TextStyle(fontSize: fontSize, color: cinza900),
      ),
    );
  }

  static pw.Widget _noticeBox({
    required String title,
    required String text,
    required PdfColor color,
    required PdfColor background,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: color, width: 0.7),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 22,
            height: 22,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: pw.BorderRadius.circular(7),
            ),
            child: pw.Center(
              child: pw.Text(
                '!',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  text,
                  style: pw.TextStyle(
                    color: cinza700,
                    fontSize: 8.2,
                    lineSpacing: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _emptyBox(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: cinza50,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: cinza200, width: 0.8),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: cinza600, fontSize: 9),
      ),
    );
  }

  static pw.Widget _assinaturaBox() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: cinza50,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: cinza200, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Observação',
            style: pw.TextStyle(
              color: cinza900,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Este relatório foi gerado automaticamente pelo sistema UAI Capoeira com base nos dados financeiros registrados no evento.',
            style: pw.TextStyle(color: cinza700, fontSize: 8.3),
          ),
        ],
      ),
    );
  }

  static pw.Widget _rodapePaginado(pw.Context context) {
    final agora = DateFormat("dd/MM/yyyy 'às' HH:mm").format(DateTime.now());

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: cinza200, width: 1)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Gerado em $agora - Sistema UAI Capoeira',
              style: pw.TextStyle(fontSize: 7, color: cinza600),
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7, color: cinza600),
          ),
        ],
      ),
    );
  }

  static List<MapEntry<String, int>> _ordenarTamanhos(Map<String, int> mapa) {
    final entries = mapa.entries.toList();

    entries.sort((a, b) {
      final ai = _ordemTamanhoCamisa(a.key);
      final bi = _ordemTamanhoCamisa(b.key);

      if (ai != bi) return ai.compareTo(bi);
      return a.key.compareTo(b.key);
    });

    return entries;
  }
}

class _CamisaGradeRow {
  final String modelagem;
  final String tipo;
  final String tamanho;
  final int quantidade;
  final double valorUnitario;
  final double valorTotal;

  const _CamisaGradeRow({
    required this.modelagem,
    required this.tipo,
    required this.tamanho,
    required this.quantidade,
    this.valorUnitario = 0,
    this.valorTotal = 0,
  });
}

class _MetricData {
  final String titulo;
  final String valor;
  final String subtitulo;
  final PdfColor cor;

  const _MetricData({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.cor,
  });
}

class _ProgressData {
  final String label;
  final double value;
  final PdfColor color;
  final String detail;

  const _ProgressData({
    required this.label,
    required this.value,
    required this.color,
    required this.detail,
  });
}
