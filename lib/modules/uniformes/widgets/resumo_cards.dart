import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class ResumoCards extends StatelessWidget {
  final NumberFormat realFormat;
  final VoidCallback onNovaVenda;
  final String? cicloId;

  const ResumoCards({
    super.key,
    required this.realFormat,
    required this.onNovaVenda,
    this.cicloId,
  });

  static bool get _windowsSafeMode =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Stream<QuerySnapshot<Map<String, dynamic>>> _queryStream(
    Query<Map<String, dynamic>> query,
  ) {
    if (_windowsSafeMode) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.fromFuture(
        query.get(const GetOptions(source: Source.serverAndCache)),
      );
    }
    return query.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _queryStream(
        FirebaseFirestore.instance
            .collection('uniformes_estoque')
            .where('status', isEqualTo: 'ativo'),
      ),
      builder: (context, estoqueSnapshot) {
        int totalItens = 0;
        int itensBaixoEstoque = 0;
        double valorTotalEstoque = 0;

        if (estoqueSnapshot.hasData) {
          for (final doc in estoqueSnapshot.data!.docs) {
            final data = doc.data();
            final quantidade = ((data['quantidade'] ?? 0) as num).toInt();
            final preco = ((data['preco_venda'] ?? 0) as num).toDouble();
            totalItens += quantidade;
            valorTotalEstoque += quantidade * preco;

            if (quantidade <= (data['estoque_minimo'] ?? 5)) {
              itensBaixoEstoque++;
            }
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _queryStream(
            FirebaseFirestore.instance
                .collection('vendas_uniformes')
                .where('status_pagamento', isEqualTo: 'pendente'),
          ),
          builder: (context, vendasSnapshot) {
            double totalPendente = 0;
            int vendasPendentes = 0;

            if (vendasSnapshot.hasData) {
              for (final doc in vendasSnapshot.data!.docs) {
                final data = doc.data();
                if (cicloId != null && data['ciclo_id'] != cicloId) continue;
                totalPendente += ((data['valor_total'] ?? 0) as num).toDouble();
                if (data['status_pagamento'] == 'pendente') {
                  vendasPendentes++;
                }
              }
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _queryStream(
                FirebaseFirestore.instance
                    .collection('pedidos_uniformes')
                    .where('status', whereIn: ['pendente', 'em_confeccao']),
              ),
              builder: (context, pedidosSnapshot) {
                final pedidosPendentes = pedidosSnapshot.hasData
                    ? pedidosSnapshot.data!.docs.where((doc) =>
                        cicloId == null || doc.data()['ciclo_id'] == cicloId).length
                    : 0;

                final cards = <Widget>[
                  _buildResumoCard(
                    context: context,
                    titulo: 'ESTOQUE',
                    valor: totalItens.toString(),
                    subtitulo: 'Itens em estoque',
                    icone: Icons.inventory_2_rounded,
                    cor: context.uai.info,
                  ),
                  _buildResumoCard(
                    context: context,
                    titulo: 'VALOR DO ESTOQUE',
                    valor: realFormat.format(valorTotalEstoque),
                    subtitulo: 'Valor total disponível',
                    icone: Icons.attach_money_rounded,
                    cor: context.uai.success,
                  ),
                  if (itensBaixoEstoque > 0)
                    _buildResumoCard(
                      context: context,
                      titulo: 'BAIXO ESTOQUE',
                      valor: itensBaixoEstoque.toString(),
                      subtitulo: 'Itens para repor',
                      icone: Icons.warning_amber_rounded,
                      cor: context.uai.warning,
                    ),
                  _buildResumoCard(
                    context: context,
                    titulo: 'PENDÊNCIAS',
                    valor: realFormat.format(totalPendente),
                    subtitulo: '$vendasPendentes venda(s) pendente(s)',
                    icone: Icons.pending_actions_rounded,
                    cor: context.uai.error,
                  ),
                  _buildResumoCard(
                    context: context,
                    titulo: 'PEDIDOS',
                    valor: pedidosPendentes.toString(),
                    subtitulo: 'Encomendas em aberto',
                    icone: Icons.shopping_cart_rounded,
                    cor: context.uai.primary,
                  ),
                ];

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      if (maxWidth < 720) {
                        return SizedBox(
                          height: maxWidth < 390 ? 94 : 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: cards.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, index) => SizedBox(
                              width: maxWidth < 390 ? 142 : 154,
                              child: cards[index],
                            ),
                          ),
                        );
                      }

                      final columns = maxWidth >= 1280
                          ? 5
                          : maxWidth >= 980
                              ? 4
                              : 3;
                      final spacing = 10.0;
                      final cardWidth =
                          (maxWidth - ((columns - 1) * spacing)) / columns;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: cards
                            .map((card) => SizedBox(width: cardWidth, child: card))
                            .toList(),
                      );
                    },
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
    required BuildContext context,
    required String titulo,
    required String valor,
    required String subtitulo,
    required IconData icone,
    required Color cor,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Container(
      padding: EdgeInsets.all(compact ? 7 : 12),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: context.uai.border),
        boxShadow: const [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 5 : 6),
                decoration: BoxDecoration(
                  color: cor.withAlpha(31),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: cor, size: compact ? 15 : 18),
              ),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: compact ? 9 : 11,
                    fontWeight: FontWeight.w800,
                    color: context.uai.textPrimary,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: compact ? 12.5 : 14,
              fontWeight: FontWeight.w900,
              color: context.uai.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: compact ? 1 : 2),
          Text(
            subtitulo,
            style: TextStyle(
              fontSize: compact ? 8.5 : 11,
              color: context.uai.textSecondary,
              height: 1.08,
            ),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
