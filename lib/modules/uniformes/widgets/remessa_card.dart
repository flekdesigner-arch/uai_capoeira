import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

/// Entrada visual de uma remessa. Ações críticas continuam nos serviços
/// já existentes; este card apenas organiza a navegação pelos pedidos.
class RemessaCard extends StatelessWidget {
  final String remessaId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final bool podeEditar;
  final bool podeExcluir;

  const RemessaCard({
    super.key,
    required this.remessaId,
    required this.data,
    required this.onTap,
    required this.onEditar,
    required this.onExcluir,
    this.podeEditar = false,
    this.podeExcluir = false,
  });

  String _data(dynamic value) {
    if (value is Timestamp) return DateFormat('dd/MM/yyyy', 'pt_BR').format(value.toDate());
    if (value is DateTime) return DateFormat('dd/MM/yyyy', 'pt_BR').format(value);
    if (value is String && value.trim().isNotEmpty) return value;
    return 'A definir';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final status = (data['status'] ?? 'pendente').toString().toLowerCase();
    final (statusLabel, statusColor) = switch (status) {
      'finalizada' || 'finalizado' => ('Finalizada', t.success),
      'em_producao' || 'em_confeccao' => ('Em produção', t.info),
      'recebida' || 'recebido' => ('Recebida', t.success),
      'cancelada' || 'cancelado' => ('Cancelada', t.error),
      _ => ('Pendente', t.warning),
    };
    final nome = (data['nome'] ?? 'Remessa sem nome').toString();
    final count = (data['pedidos_ids'] as List?)?.length ?? 0;
    final fornecedor = (data['fornecedor_nome'] ?? '').toString().trim();
    final previsao = data['data_prevista'];
    final capa = (data['capa_url'] ?? '').toString().trim();
    final modo = (data['capa_modo'] ?? (capa.isNotEmpty ? 'imagem' : 'icone')).toString();
    final icone = (data['capa_icone'] ?? 'remessa').toString();

    Widget tag(IconData icon, String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(48)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontWeight: FontWeight.w800,
          fontSize: 11, color: color)),
      ]),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Container(width: 4, height: 144, color: statusColor),
              Expanded(child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 9, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: SizedBox(width: 62, height: 68,
                      child: modo == 'imagem' && capa.isNotEmpty
                          ? Image.network(capa, fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) => _capaPadrao(statusColor, icone))
                          : _capaPadrao(statusColor, icone),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(nome, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textPrimary,
                          fontWeight: FontWeight.w900, fontSize: 14.5)),
                      if (fornecedor.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(fornecedor, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.textSecondary, fontSize: 11)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        tag(Icons.shopping_bag_rounded,
                          '$count ${count == 1 ? 'pedido' : 'pedidos'}', t.primary),
                        tag(Icons.circle, statusLabel, statusColor),
                        if (previsao != null)
                          tag(Icons.event_rounded, _data(previsao), t.info),
                      ]),
                      const SizedBox(height: 9),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Abrir pedidos e pagamentos',
                          style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 11, color: t.textSecondary)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 14, color: t.primary),
                      ]),
                    ],
                  )),
                  if (podeEditar || podeExcluir)
                    PopupMenuButton<String>(
                      tooltip: 'Ações da remessa',
                      icon: Icon(Icons.more_vert_rounded, color: t.textSecondary),
                      onSelected: (value) {
                        if (value == 'editar') onEditar();
                        if (value == 'excluir') onExcluir();
                      },
                      itemBuilder: (_) => [
                        if (podeEditar) const PopupMenuItem(
                          value: 'editar', child: Text('Editar remessa')),
                        if (podeExcluir) const PopupMenuItem(
                          value: 'excluir', child: Text('Excluir remessa')),
                      ],
                    )
                  else
                    Icon(Icons.chevron_right_rounded, color: t.textMuted),
                ]),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _capaPadrao(Color color, String tipo) => Container(
    color: color.withAlpha(25),
    alignment: Alignment.center,
    child: Icon(switch (tipo) {
      'camisa' => Icons.checkroom_rounded,
      'calca' => Icons.dry_cleaning_outlined,
      'uniforme' => Icons.sports_martial_arts_rounded,
      'estoque' => Icons.inventory_2_rounded,
      _ => Icons.local_shipping_rounded,
    }, size: 32, color: color),
  );
}
