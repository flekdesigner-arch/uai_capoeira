import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ResumoCards extends StatelessWidget {
  final NumberFormat realFormat;
  final VoidCallback onNovaVenda;

  const ResumoCards({
    super.key,
    required this.realFormat,
    required this.onNovaVenda,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('uniformes_estoque')
          .where('status', isEqualTo: 'ativo')
          .snapshots(),
      builder: (context, estoqueSnapshot) {
        int totalItens = 0;
        int itensBaixoEstoque = 0;
        double valorTotalEstoque = 0;

        if (estoqueSnapshot.hasData) {
          for (var doc in estoqueSnapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            int quantidade = data['quantidade'] ?? 0;
            double preco = (data['preco_venda'] ?? 0).toDouble();
            totalItens += quantidade;
            valorTotalEstoque += quantidade * preco;

            if (quantidade <= (data['estoque_minimo'] ?? 5)) {
              itensBaixoEstoque++;
            }
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('vendas_uniformes')
              .where('status_pagamento', isEqualTo: 'pendente')
              .snapshots(),
          builder: (context, vendasSnapshot) {
            double totalPendente = 0;
            int vendasPendentes = 0;

            if (vendasSnapshot.hasData) {
              for (var doc in vendasSnapshot.data!.docs) {
                var data = doc.data() as Map<String, dynamic>;
                totalPendente += (data['valor_total'] ?? 0).toDouble();
                if (data['status_pagamento'] == 'pendente') {
                  vendasPendentes++;
                }
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('pedidos_uniformes')
                  .where('status', whereIn: ['pendente', 'em_confeccao'])
                  .snapshots(),
              builder: (context, pedidosSnapshot) {
                int pedidosPendentes = pedidosSnapshot.hasData ? pedidosSnapshot.data!.docs.length : 0;

                return SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildResumoCard(
                        titulo: 'ESTOQUE',
                        valor: totalItens.toString(),
                        subtitulo: 'Itens em estoque',
                        icone: Icons.inventory,
                        cor: Colors.blue,
                      ),
                      _buildResumoCard(
                        titulo: 'VALOR ESTOQUE',
                        valor: realFormat.format(valorTotalEstoque),
                        subtitulo: 'Valor total',
                        icone: Icons.attach_money,
                        cor: Colors.green,
                      ),
                      if (itensBaixoEstoque > 0)
                        _buildResumoCard(
                          titulo: 'BAIXO ESTOQUE',
                          valor: itensBaixoEstoque.toString(),
                          subtitulo: 'Itens para repor',
                          icone: Icons.warning,
                          cor: Colors.orange,
                        ),
                      _buildResumoCard(
                        titulo: 'PENDENTES',
                        valor: realFormat.format(totalPendente),
                        subtitulo: '$vendasPendentes vendas',
                        icone: Icons.pending_actions,
                        cor: Colors.red,
                      ),
                      _buildResumoCard(
                        titulo: 'PEDIDOS',
                        valor: pedidosPendentes.toString(),
                        subtitulo: 'Encomendas',
                        icone: Icons.shopping_cart,
                        cor: Colors.purple,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildResumoCard({
    required String titulo,
    required String valor,
    required String subtitulo,
    required IconData icone,
    required Color cor,
  }) {
    return GestureDetector(
      onTap: titulo == 'NOVA VENDA' ? onNovaVenda : null,
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icone, color: cor, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              valor,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitulo,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}