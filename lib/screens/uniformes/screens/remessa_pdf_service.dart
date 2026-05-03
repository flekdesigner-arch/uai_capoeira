import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class RemessaPdfService {
  static final PdfColor verdeEscuro = PdfColor.fromHex('#2E7D32');
  static final PdfColor verdeClaro = PdfColor.fromHex('#E8F5E9');
  static final PdfColor verdePagamento = PdfColor.fromHex('#43A047');
  static final PdfColor vermelhoPendente = PdfColor.fromHex('#E53935');
  static final PdfColor cinzaClaro = PdfColor.fromHex('#F5F5F5');
  static final PdfColor textoEscuro = PdfColor.fromHex('#212121');

  static Future<pw.MemoryImage?> _carregarLogo() async {
    try {
      final Uint8List bytes = await rootBundle
          .load('assets/images/logo_uai.png')
          .then((data) => data.buffer.asUint8List());
      return pw.MemoryImage(bytes);
    } catch (e) {
      return null;
    }
  }

  static Future<void> gerarPdfResumido(
      String remessaId, Map<String, dynamic> remessaData) async {
    final logo = await _carregarLogo();

    final pedidosSnapshot = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .get();

    final pdf = pw.Document();
    final itemsAgrupados = <String, Map<String, dynamic>>{};
    int totalPecas = 0;

    for (var doc in pedidosSnapshot.docs) {
      final pedido = doc.data();
      for (var item in pedido['itens'] ?? []) {
        final chave =
            '${item['nome'] ?? 'Item'}_${item['tamanho'] ?? 'Único'}_${item['cor'] ?? 'N/A'}';
        itemsAgrupados.putIfAbsent(chave, () => {
          'nome': item['nome'] ?? 'Item',
          'tamanho': item['tamanho'] ?? 'Único',
          'cor': item['cor'] ?? '—',
          'quantidade': 0,
        });
        final qtd = (item['quantidade'] ?? 0) as int;
        itemsAgrupados[chave]!['quantidade'] += qtd;
        totalPecas += qtd;
      }
    }

    final dataPrevisao = remessaData['data_prevista'] != null
        ? DateFormat('dd/MM/yyyy')
        .format((remessaData['data_prevista'] as Timestamp).toDate())
        : 'Não definida';

    final lista = itemsAgrupados.values.toList()
      ..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return [
            _cabecalho(logo, 'PEDIDO PARA CONFECÇÃO', remessaData),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Previsão de entrega: $dataPrevisao',
                    style: pw.TextStyle(fontSize: 10, color: textoEscuro)),
                pw.Text('Total de peças: $totalPecas',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold, color: textoEscuro)),
              ],
            ),
            pw.SizedBox(height: 12),
            _tabelaEstilizada(
              headers: ['Item', 'Tamanho', 'Cor', 'Qtd.'],
              dados: lista
                  .map((e) => [
                e['nome'].toString(),
                e['tamanho'].toString(),
                e['cor'].toString(),
                e['quantidade'].toString(),
              ])
                  .toList(),
            ),
            pw.SizedBox(height: 20),
            _rodape(),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static Future<void> gerarPdfCompleto(
      String remessaId, Map<String, dynamic> remessaData) async {
    final logo = await _carregarLogo();
    final numberFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final pedidosSnapshot = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .get();

    final pdf = pw.Document();
    final rows = <List<String>>[];
    double totalGeral = 0;
    double totalPago = 0;
    int totalPedidos = pedidosSnapshot.docs.length;

    for (var doc in pedidosSnapshot.docs) {
      final pedido = doc.data();
      final valorTotal = (pedido['valor_total'] ?? 0).toDouble();
      final valorPago = (pedido['valor_pago'] ?? 0).toDouble();
      totalGeral += valorTotal;
      totalPago += valorPago;

      final itensDesc = (pedido['itens'] as List?)
          ?.map((i) => '${i['quantidade']}x ${i['nome']}')
          .join(', ') ??
          '';
      rows.add([
        pedido['id_pedido'] ?? '',
        pedido['aluno_nome'] ?? '',
        itensDesc,
        numberFormat.format(valorTotal),
        _statusFormatado(pedido['status']),
        _statusPgtoFormatado(pedido['status_pagamento']),
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return [
            _cabecalho(logo, 'RELATÓRIO COMPLETO', remessaData),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: verdeClaro,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Total de pedidos: $totalPedidos',
                          style: pw.TextStyle(fontSize: 10, color: textoEscuro)),
                      pw.Text(
                          'Valor total: ${numberFormat.format(totalGeral)}',
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold, color: textoEscuro)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                          'Total pago: ${numberFormat.format(totalPago)}',
                          style: pw.TextStyle(fontSize: 10, color: verdePagamento)),
                      pw.Text(
                          'Pendente: ${numberFormat.format(totalGeral - totalPago)}',
                          style: pw.TextStyle(fontSize: 10, color: vermelhoPendente)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            _tabelaEstilizada(
              headers: ['Pedido', 'Aluno', 'Itens', 'Valor', 'Status', 'Pagamento'],
              dados: rows,
            ),
            pw.SizedBox(height: 20),
            _rodape(),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static pw.Widget _cabecalho(
      pw.MemoryImage? logo, String titulo, Map<String, dynamic> remessaData) {
    return pw.Container(
      padding: pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: verdeEscuro, width: 2),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null)
            pw.Container(
              margin: pw.EdgeInsets.only(right: 12),
              child: pw.Image(logo, width: 50, height: 25),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(titulo,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: verdeEscuro,
                    )),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Remessa: ${remessaData['nome'] ?? '—'}',
                  style: pw.TextStyle(fontSize: 11, color: textoEscuro),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tabelaEstilizada({
    required List<String> headers,
    required List<List<String>> dados,
  }) {
    return pw.Table.fromTextArray(
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 10,
      ),
      cellStyle: pw.TextStyle(fontSize: 9, color: textoEscuro),
      headerDecoration: pw.BoxDecoration(color: verdeEscuro),
      cellDecoration: (row, col, idx) {
        final color = (idx % 2 == 0) ? cinzaClaro : PdfColors.white;
        return pw.BoxDecoration(color: color);
      },
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      headers: headers,
      data: dados,
      cellPadding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }

  static pw.Widget _rodape() {
    final agora = DateFormat("dd/MM/yyyy 'às' HH:mm").format(DateTime.now());
    return pw.Container(
      padding: pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            'Gerado em $agora — Sistema UAI Capoeira',
            style: pw.TextStyle(fontSize: 7, color: PdfColors.grey),
          ),
        ],
      ),
    );
  }

  static String _statusFormatado(dynamic status) {
    switch (status) {
      case 'pendente': return 'Pendente';
      case 'em_confeccao': return 'Em confecção';
      case 'finalizado': return 'Finalizado';
      default: return status?.toString() ?? '—';
    }
  }

  static String _statusPgtoFormatado(dynamic status) {
    switch (status) {
      case 'pago': return 'Pago';
      case 'pendente': return 'Pendente';
      case 'parcial': return 'Parcial';
      default: return status?.toString() ?? '—';
    }
  }
}