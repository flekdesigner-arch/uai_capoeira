import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class RelatorioFinanceiroScreen extends StatelessWidget {
  const RelatorioFinanceiroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final NumberFormat realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final DateFormat mesFormat = DateFormat('MMM/yyyy', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('RELATÓRIO FINANCEIRO'),
        backgroundColor: Colors.green.shade900,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {},
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vendas_uniformes')
            .orderBy('data_venda', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 50, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text('Erro ao carregar dados: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var vendas = snapshot.data!.docs;

          // Processamento dos dados
          double totalVendas = 0;
          double totalRecebido = 0;
          double totalPendente = 0;
          int totalVendasCount = vendas.length;

          Map<String, double> vendasPorMes = {};
          Map<String, double> recebidoPorMes = {};
          Map<String, int> vendasPorFormaPagamento = {};
          Map<String, double> vendasPorAluno = {};

          for (var doc in vendas) {
            var data = doc.data() as Map<String, dynamic>;
            double valorTotal = (data['valor_total'] ?? 0).toDouble();
            double valorPago = (data['valor_pago'] ?? 0).toDouble();

            totalVendas += valorTotal;
            totalRecebido += valorPago;
            totalPendente += (valorTotal - valorPago);

            // Vendas por mês
            if (data['data_venda'] != null) {
              try {
                Timestamp ts = data['data_venda'];
                String mesAno = mesFormat.format(ts.toDate());
                vendasPorMes[mesAno] = (vendasPorMes[mesAno] ?? 0) + valorTotal;
                recebidoPorMes[mesAno] = (recebidoPorMes[mesAno] ?? 0) + valorPago;
              } catch (e) {}
            }

            // Formas de pagamento
            if (data['pagamentos'] != null) {
              for (var pagamento in data['pagamentos']) {
                String forma = pagamento['forma'] ?? 'outros';
                vendasPorFormaPagamento[forma] = (vendasPorFormaPagamento[forma] ?? 0) + 1;
              }
            } else {
              // Se não tem pagamentos registrados, considera o status
              String status = data['status_pagamento'] ?? 'pendente';
              if (status == 'pago') {
                vendasPorFormaPagamento['nao_informado'] = (vendasPorFormaPagamento['nao_informado'] ?? 0) + 1;
              }
            }

            // Vendas por aluno (top 5)
            String aluno = data['aluno_nome'] ?? 'Não identificado';
            vendasPorAluno[aluno] = (vendasPorAluno[aluno] ?? 0) + valorTotal;
          }

          // Ordenar e pegar top 5 alunos
          var topAlunos = vendasPorAluno.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          topAlunos = topAlunos.take(5).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // RESUMO FINANCEIRO
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'RESUMO FINANCEIRO',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Divider(),
                      _buildResumoLinha('Total de Vendas', realFormat.format(totalVendas), Colors.blue),
                      _buildResumoLinha('Total Recebido', realFormat.format(totalRecebido), Colors.green),
                      _buildResumoLinha('Total Pendente', realFormat.format(totalPendente), Colors.red),
                      const Divider(),
                      _buildResumoLinha('Número de Vendas', totalVendasCount.toString(), Colors.purple),
                      _buildResumoLinha('Ticket Médio',
                          totalVendasCount > 0 ? realFormat.format(totalVendas / totalVendasCount) : 'R\$ 0,00',
                          Colors.orange),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // GRÁFICO DE VENDAS POR MÊS
              if (vendasPorMes.isNotEmpty)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'VENDAS POR MÊS',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 200,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: vendasPorMes.values.reduce((a, b) => a > b ? a : b) * 1.1,
                              barTouchData: BarTouchData(
                                enabled: false, // Desativa o tooltip para simplificar
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      if (value.toInt() >= 0 && value.toInt() < vendasPorMes.length) {
                                        String mes = vendasPorMes.keys.elementAt(value.toInt());
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            mes.substring(0, 3),
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                        );
                                      }
                                      return const Text('');
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: vendasPorMes.values.reduce((a, b) => a > b ? a : b) / 5,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        realFormat.format(value).replaceAll('R\$', ''),
                                        style: const TextStyle(fontSize: 10),
                                      );
                                    },
                                  ),
                                ),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: vendasPorMes.entries.map((entry) {
                                int index = vendasPorMes.keys.toList().indexOf(entry.key);
                                return BarChartGroupData(
                                  x: index,
                                  barRods: [
                                    BarChartRodData(
                                      toY: entry.value,
                                      color: Colors.green.shade700,
                                      width: 20,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        // Legenda manual
                        const SizedBox(height: 8),
                        const Text(
                          'Toque nas barras para ver os valores',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              // LISTA DE VENDAS POR MÊS
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'VENDAS POR MÊS (DETALHADO)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Divider(),
                      ...vendasPorMes.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    realFormat.format(entry.value),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Recebido: ${realFormat.format(recebidoPorMes[entry.key] ?? 0)}',
                                    style: TextStyle(fontSize: 10, color: Colors.green.shade600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // FORMAS DE PAGAMENTO
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'FORMAS DE PAGAMENTO',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Divider(),
                      ...vendasPorFormaPagamento.entries.map((entry) {
                        String forma = entry.key.toUpperCase().replaceAll('_', ' ');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(forma),
                              Text(
                                '${entry.value} venda(s)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // TOP 5 ALUNOS
              if (topAlunos.isNotEmpty)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'TOP 5 ALUNOS',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Divider(),
                        ...topAlunos.asMap().entries.map((entry) {
                          int position = entry.key + 1;
                          String aluno = entry.value.key;
                          double valor = entry.value.value;

                          Color medalColor;
                          if (position == 1) {
                            medalColor = Colors.amber;
                          } else if (position == 2) {
                            medalColor = Colors.grey.shade400;
                          } else if (position == 3) {
                            medalColor = Colors.brown.shade300;
                          } else {
                            medalColor = Colors.grey;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: medalColor.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$position',
                                      style: TextStyle(
                                        color: medalColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    aluno,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  realFormat.format(valor),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // ÚLTIMAS VENDAS
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'ÚLTIMAS 5 VENDAS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Divider(),
                      ...vendas.take(5).map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                data['status_pagamento'] == 'pago'
                                    ? Icons.check_circle
                                    : Icons.pending,
                                size: 16,
                                color: data['status_pagamento'] == 'pago'
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['aluno_nome'] ?? 'N/I',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      _formatarDataResumida(data['data_venda']),
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                realFormat.format(data['valor_total'] ?? 0),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // BOTÕES DE AÇÃO
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Exportar relatório
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('EXPORTAR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade900,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Compartilhar relatório
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('COMPARTILHAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResumoLinha(String label, String valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            valor,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatarDataResumida(dynamic data) {
    if (data == null) return '';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yy', 'pt_BR').format(data.toDate());
      }
    } catch (e) {}
    return '';
  }
}