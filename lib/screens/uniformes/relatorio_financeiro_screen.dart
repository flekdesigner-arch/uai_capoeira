import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

class RelatorioFinanceiroScreen extends StatefulWidget {
  const RelatorioFinanceiroScreen({super.key});

  @override
  State<RelatorioFinanceiroScreen> createState() => _RelatorioFinanceiroScreenState();
}

class _RelatorioFinanceiroScreenState extends State<RelatorioFinanceiroScreen> {
  final NumberFormat realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat mesFormat = DateFormat('MMM/yyyy', 'pt_BR');
  final DateFormat dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

  String _filtroSelecionado = 'Mês';
  DateTime? _dataInicio;
  DateTime? _dataFim;
  bool _isLoading = false;

  double _totalVendas = 0;
  double _totalRecebido = 0;
  double _totalPendente = 0;
  int _totalVendasCount = 0;
  Map<String, double> _vendasPorMes = {};
  Map<String, double> _recebidoPorMes = {};
  Map<String, int> _vendasPorFormaPagamento = {};
  List<Map<String, dynamic>> _ultimasVendas = [];
  List<MapEntry<String, double>> _topAlunos = [];

  static final PdfColor verdeEscuro = PdfColor.fromHex('#2E7D32');
  static final PdfColor verdeClaro = PdfColor.fromHex('#E8F5E9');

  @override
  void initState() {
    super.initState();
    _aplicarFiltro('Mês');
  }

  void _aplicarFiltro(String filtro) {
    final now = DateTime.now();
    setState(() {
      _filtroSelecionado = filtro;
      switch (filtro) {
        case 'Hoje':
          _dataInicio = DateTime(now.year, now.month, now.day);
          _dataFim = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'Semana':
          _dataInicio = now.subtract(Duration(days: now.weekday - 1));
          _dataFim = now.add(const Duration(days: 6));
          break;
        case 'Mês':
          _dataInicio = DateTime(now.year, now.month, 1);
          _dataFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case 'Ano':
          _dataInicio = DateTime(now.year, 1, 1);
          _dataFim = DateTime(now.year, 12, 31, 23, 59, 59);
          break;
        case 'Personalizado':
          _abrirSeletorPeriodo();
          break;
      }
    });
  }

  Future<void> _abrirSeletorPeriodo() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _dataInicio = picked.start;
        _dataFim = picked.end;
        _filtroSelecionado = 'Personalizado';
      });
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isLoading = false);
  }

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

  // ─────────────────────────── PDF MENSAL ───────────────────────────
  Future<void> _gerarPdfMensal() async {
    try {
      final pdf = pw.Document();
      final logo = await _carregarLogo();
      final now = DateTime.now();

      final dataRows = _vendasPorMes.entries.map((e) => [
        e.key,
        realFormat.format(e.value),
        realFormat.format(_recebidoPorMes[e.key] ?? 0),
        realFormat.format(e.value - (_recebidoPorMes[e.key] ?? 0)),
      ]).toList();

      final topAlunosMap = _topAlunos.map((e) => {'nome': e.key, 'valor': e.value}).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 8),
              decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: verdeEscuro, width: 2))),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null)
                    pw.Container(margin: const pw.EdgeInsets.only(right: 12), child: pw.Image(logo, width: 50, height: 25)),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('RELATÓRIO FINANCEIRO MENSAL',
                            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: verdeEscuro)),
                        pw.Text('Período: ${dateFormat.format(DateTime(now.year, now.month, 1))} - ${dateFormat.format(now)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: verdeClaro, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(
                children: [
                  _pdfLinha('Total de Vendas', realFormat.format(_totalVendas)),
                  _pdfLinha('Total Recebido', realFormat.format(_totalRecebido)),
                  _pdfLinha('Total Pendente', realFormat.format(_totalPendente)),
                  _pdfLinha('Número de Vendas', _totalVendasCount.toString()),
                  _pdfLinha('Ticket Médio', _totalVendasCount > 0 ? realFormat.format(_totalVendas / _totalVendasCount) : 'R\$ 0,00'),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Table.fromTextArray(
              headers: ['Mês', 'Vendas', 'Recebido', 'Pendente'],
              data: dataRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.green),
            ),
            if (topAlunosMap.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text('TOP 5 ALUNOS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: verdeEscuro)),
              pw.SizedBox(height: 8),
              ...topAlunosMap.map((a) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(a['nome']?.toString() ?? '', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(realFormat.format(a['valor'] ?? 0), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              )),
            ],
            pw.SizedBox(height: 20),
            pw.Text('Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(now)} - Sistema UAI Capoeira',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
          ],
        ),
      );

      // 🔥 COMPARTILHAR / SALVAR (não depende de impressora)
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'relatorio_mensal_${DateFormat('yyyyMM').format(now)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────── PDF GERAL (ANUAL) ───────────────────────────
  Future<void> _gerarPdfGeral() async {
    try {
      final pdf = pw.Document();
      final logo = await _carregarLogo();
      final now = DateTime.now();

      final dataRows = _vendasPorMes.entries.map((e) => [
        e.key,
        realFormat.format(e.value),
        realFormat.format(_recebidoPorMes[e.key] ?? 0),
        realFormat.format(e.value - (_recebidoPorMes[e.key] ?? 0)),
      ]).toList();

      final topAlunosMap = _topAlunos.map((e) => {'nome': e.key, 'valor': e.value}).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 8),
              decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: verdeEscuro, width: 2))),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null)
                    pw.Container(margin: const pw.EdgeInsets.only(right: 12), child: pw.Image(logo, width: 50, height: 25)),
                  pw.Expanded(
                    child: pw.Text('RELATÓRIO FINANCEIRO ANUAL ${now.year}',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: verdeEscuro)),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Table.fromTextArray(
              headers: ['Mês', 'Vendas', 'Recebido', 'Pendente'],
              data: dataRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.green),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Total geral: ${realFormat.format(_totalVendas)} | Recebido: ${realFormat.format(_totalRecebido)} | Pendente: ${realFormat.format(_totalPendente)}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            if (topAlunosMap.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text('TOP 5 ALUNOS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: verdeEscuro)),
              pw.SizedBox(height: 8),
              ...topAlunosMap.map((a) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(a['nome']?.toString() ?? '', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(realFormat.format(a['valor'] ?? 0), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              )),
            ],
            pw.SizedBox(height: 20),
            pw.Text('Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(now)} - Sistema UAI Capoeira',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
          ],
        ),
      );

      // 🔥 COMPARTILHAR / SALVAR
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'relatorio_anual_${now.year}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  pw.Widget _pdfLinha(String label, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(valor, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ═══════════════════════════ INTERFACE ═══════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('RELATÓRIO FINANCEIRO'),
        backgroundColor: Colors.green.shade900,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.download), tooltip: 'Exportar PDF', onPressed: _mostrarOpcoesExportacao),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: Colors.green.shade900,
        child: _buildConteudo(),
      ),
    );
  }

  Widget _buildConteudo() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('vendas_uniformes').orderBy('data_venda', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 50, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text('Erro: ${snapshot.error}'),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }

        final vendas = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          if (data['data_venda'] == null) return false;
          try {
            final ts = data['data_venda'] as Timestamp;
            final date = ts.toDate();
            if (_dataInicio != null && date.isBefore(_dataInicio!)) return false;
            if (_dataFim != null && date.isAfter(_dataFim!)) return false;
            return true;
          } catch (_) {
            return false;
          }
        }).toList();

        if (vendas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.attach_money, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma venda encontrada',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tente alterar o período selecionado',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        double totalVendas = 0;
        double totalRecebido = 0;
        double totalPendente = 0;
        int totalVendasCount = vendas.length;
        Map<String, double> vendasPorMes = {};
        Map<String, double> recebidoPorMes = {};
        Map<String, int> vendasPorFormaPagamento = {};
        Map<String, double> vendasPorAluno = {};
        List<Map<String, dynamic>> ultimasVendas = [];

        for (var doc in vendas) {
          var data = doc.data() as Map<String, dynamic>;
          double valorTotal = (data['valor_total'] ?? 0).toDouble();
          double valorPago = (data['valor_pago'] ?? 0).toDouble();

          totalVendas += valorTotal;
          totalRecebido += valorPago;
          totalPendente += (valorTotal - valorPago);

          if (data['data_venda'] != null) {
            try {
              final ts = data['data_venda'] as Timestamp;
              final mesAno = mesFormat.format(ts.toDate());
              vendasPorMes[mesAno] = (vendasPorMes[mesAno] ?? 0) + valorTotal;
              recebidoPorMes[mesAno] = (recebidoPorMes[mesAno] ?? 0) + valorPago;
            } catch (_) {}
          }

          if (data['pagamentos'] != null) {
            for (var pagamento in data['pagamentos']) {
              String forma = pagamento['forma'] ?? 'outros';
              vendasPorFormaPagamento[forma] = (vendasPorFormaPagamento[forma] ?? 0) + 1;
            }
          }

          String aluno = data['aluno_nome'] ?? 'Não identificado';
          vendasPorAluno[aluno] = (vendasPorAluno[aluno] ?? 0) + valorTotal;
          ultimasVendas.add(data);
        }

        var topAlunos = vendasPorAluno.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        topAlunos = topAlunos.take(5).toList();

        _totalVendas = totalVendas;
        _totalRecebido = totalRecebido;
        _totalPendente = totalPendente;
        _totalVendasCount = totalVendasCount;
        _vendasPorMes = vendasPorMes;
        _recebidoPorMes = recebidoPorMes;
        _vendasPorFormaPagamento = vendasPorFormaPagamento;
        _ultimasVendas = ultimasVendas;
        _topAlunos = topAlunos;

        if (_isLoading) return _buildSkeleton();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildFiltros(),
            const SizedBox(height: 16),
            _buildKPIs(totalVendas, totalRecebido, totalPendente, totalVendasCount),
            const SizedBox(height: 16),
            if (vendasPorMes.isNotEmpty) _buildGraficoPrincipal(vendasPorMes, recebidoPorMes),
            const SizedBox(height: 16),
            if (vendasPorFormaPagamento.isNotEmpty) _buildGraficoPizza(vendasPorFormaPagamento),
            const SizedBox(height: 16),
            if (topAlunos.isNotEmpty) _buildTopAlunos(topAlunos),
            const SizedBox(height: 16),
            _buildUltimasVendas(ultimasVendas),
            const SizedBox(height: 16),
            _buildBotoesExportacao(),
          ],
        );
      },
    );
  }

  Widget _buildFiltros() {
    final filtros = ['Hoje', 'Semana', 'Mês', 'Ano', 'Personalizado'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filtros.map((filtro) {
          final isSelected = _filtroSelecionado == filtro;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filtro),
              selected: isSelected,
              selectedColor: Colors.green.shade900,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (_) => _aplicarFiltro(filtro),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKPIs(double totalVendas, double totalRecebido, double totalPendente, int totalVendasCount) {
    double ticketMedio = totalVendasCount > 0 ? totalVendas / totalVendasCount : 0;
    double inadimplencia = totalVendas > 0 ? (totalPendente / totalVendas) * 100 : 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _kpiCard('Faturamento', realFormat.format(totalVendas), Icons.trending_up, Colors.blue)),
            const SizedBox(width: 8),
            Expanded(child: _kpiCard('Recebido', realFormat.format(totalRecebido), Icons.check_circle, Colors.green)),
            const SizedBox(width: 8),
            Expanded(child: _kpiCard('Pendente', realFormat.format(totalPendente), Icons.pending, Colors.red)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _kpiCard('Vendas', totalVendasCount.toString(), Icons.shopping_cart, Colors.purple)),
            const SizedBox(width: 8),
            Expanded(child: _kpiCard('Ticket Médio', realFormat.format(ticketMedio), Icons.attach_money, Colors.orange)),
            const SizedBox(width: 8),
            Expanded(child: _kpiCard('Inadimplência', '${inadimplencia.toStringAsFixed(1)}%', Icons.warning,
                inadimplencia > 30 ? Colors.red : Colors.amber)),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard(String titulo, String valor, IconData icon, Color cor) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: cor, size: 24),
            const SizedBox(height: 4),
            Text(valor, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cor), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(titulo, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildGraficoPrincipal(Map<String, double> vendasPorMes, Map<String, double> recebidoPorMes) {
    final entries = vendasPorMes.entries.toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) * 1.2;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('VENDAS VS RECEBIDO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        String label = rodIndex == 0 ? 'Vendas' : 'Recebido';
                        return BarTooltipItem('$label\n${realFormat.format(rod.toY)}', const TextStyle(color: Colors.white, fontSize: 11));
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < entries.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(entries[value.toInt()].key.substring(0, 3).toUpperCase(), style: const TextStyle(fontSize: 10)),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        getTitlesWidget: (value, meta) => Text(realFormat.format(value).replaceAll('R\$ ', ''), style: const TextStyle(fontSize: 9)),
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  barGroups: entries.asMap().entries.map((entry) {
                    int idx = entry.key;
                    double venda = entry.value.value;
                    double recebido = recebidoPorMes[entry.value.key] ?? 0;
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(toY: venda, color: Colors.blue, width: 12, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4))),
                        BarChartRodData(toY: recebido, color: Colors.green, width: 12, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 12, height: 12, color: Colors.blue),
                const SizedBox(width: 4),
                const Text('Vendas', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 16),
                Container(width: 12, height: 12, color: Colors.green),
                const SizedBox(width: 4),
                const Text('Recebido', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraficoPizza(Map<String, int> vendasPorFormaPagamento) {
    final total = vendasPorFormaPagamento.values.fold(0, (a, b) => a + b);
    final cores = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('FORMAS DE PAGAMENTO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sections: vendasPorFormaPagamento.entries.toList().asMap().entries.map((entry) {
                          int idx = entry.key;
                          var e = entry.value;
                          double percent = (e.value / total) * 100;
                          return PieChartSectionData(
                            value: e.value.toDouble(),
                            title: '${percent.toStringAsFixed(0)}%',
                            color: cores[idx % cores.length],
                            radius: 60,
                            titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          );
                        }).toList(),
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: vendasPorFormaPagamento.entries.toList().asMap().entries.map((entry) {
                        int idx = entry.key;
                        var e = entry.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Container(width: 8, height: 8, color: cores[idx % cores.length]),
                              const SizedBox(width: 4),
                              Expanded(child: Text(e.key.replaceAll('_', ' '), style: const TextStyle(fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopAlunos(List<MapEntry<String, double>> topAlunos) {
    final medalhas = [Colors.amber, Colors.grey.shade400, Colors.brown.shade300];
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('TOP 5 ALUNOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const Divider(),
            ...topAlunos.asMap().entries.map((entry) {
              int pos = entry.key;
              Color cor = pos < 3 ? medalhas[pos] : Colors.grey;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: cor.withOpacity(0.2), shape: BoxShape.circle),
                      child: Center(child: Text('${pos + 1}', style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(entry.value.key, style: const TextStyle(fontSize: 13))),
                    Text(realFormat.format(entry.value.value), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildUltimasVendas(List<Map<String, dynamic>> vendas) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('ÚLTIMAS VENDAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const Divider(),
            ...vendas.take(10).map((data) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    data['status_pagamento'] == 'pago' ? Icons.check_circle : Icons.pending,
                    size: 16,
                    color: data['status_pagamento'] == 'pago' ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['aluno_nome'] ?? 'N/I', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        Text(_formatarDataResumida(data['data_venda']), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Text(realFormat.format(data['valor_total'] ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildBotoesExportacao() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _gerarPdfMensal,
            icon: const Icon(Icons.calendar_month),
            label: const Text('PDF MENSAL'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _gerarPdfGeral,
            icon: const Icon(Icons.description),
            label: const Text('PDF GERAL'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade900, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      ],
    );
  }

  void _mostrarOpcoesExportacao() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Exportar Relatório', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calendar_month, color: Colors.blue),
                title: const Text('PDF Mensal'),
                subtitle: const Text('Relatório do mês atual'),
                onTap: () { Navigator.pop(ctx); _gerarPdfMensal(); },
              ),
              ListTile(
                leading: const Icon(Icons.description, color: Colors.green),
                title: const Text('PDF Anual'),
                subtitle: const Text('Relatório completo do ano'),
                onTap: () { Navigator.pop(ctx); _gerarPdfGeral(); },
              ),
              ListTile(
                leading: const Icon(Icons.date_range, color: Colors.purple),
                title: const Text('Personalizado'),
                subtitle: const Text('Escolher período'),
                onTap: () { Navigator.pop(ctx); _abrirSeletorPeriodo(); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(6, (i) => Card(
        child: Container(
          height: 120,
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
        ),
      )),
    );
  }

  String _formatarDataResumida(dynamic data) {
    if (data == null) return '';
    try {
      if (data is Timestamp) return DateFormat('dd/MM/yy', 'pt_BR').format(data.toDate());
    } catch (_) {}
    return '';
  }
}