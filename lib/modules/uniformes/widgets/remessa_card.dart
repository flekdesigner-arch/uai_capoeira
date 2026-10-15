import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

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

  String _formatarData(dynamic data) {
    if (data == null) return 'Não informada';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yyyy', 'pt_BR').format(data.toDate());
      }
      if (data is DateTime) {
        return DateFormat('dd/MM/yyyy', 'pt_BR').format(data);
      }
      if (data is String) return data;
    } catch (_) {
      return 'Não informada';
    }
    return 'Não informada';
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'pendente':
        return context.uai.warning;
      case 'em_producao':
        return context.uai.info;
      case 'finalizada':
        return context.uai.success;
      case 'cancelada':
        return context.uai.error;
      default:
        return context.uai.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'em_producao':
        return 'Em produção';
      case 'finalizada':
        return 'Finalizada';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Indefinida';
    }
  }

  Widget _chip(
    BuildContext context,
    IconData icon,
    String label,
    Color color, {
    bool compacto = false,
  }) {
    return Container(
      constraints: BoxConstraints(maxWidth: compacto ? 135 : 190),
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 8 : 10,
        vertical: compacto ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                icon,
                size: compacto ? 12 : 14,
                color: color,
              ),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(width: compacto ? 4 : 6),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: compacto ? 10 : 11,
              ),
            ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _acoes(BuildContext context) {
    if (!podeEditar && !podeExcluir) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      iconSize: 20,
      tooltip: 'Ações da remessa',
      onSelected: (value) {
        if (value == 'editar') onEditar();
        if (value == 'excluir') onExcluir();
      },
      itemBuilder: (_) => [
        if (podeEditar)
          const PopupMenuItem(
            value: 'editar',
            child: Text('Editar remessa'),
          ),
        if (podeExcluir)
          const PopupMenuItem(
            value: 'excluir',
            child: Text('Excluir remessa'),
          ),
      ],
    );
  }

  Widget _visualRemessa(
    BuildContext context, {
    required bool compacto,
    required Color statusColor,
  }) {
    final capaUrl = (data['capa_url'] ?? '').toString().trim();

    if (capaUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(compacto ? 16 : 14),
        child: Image.network(
          capaUrl,
          width: compacto ? 76 : 44,
          height: compacto ? 88 : 44,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _visualPadrao(
            context,
            compacto: compacto,
            statusColor: statusColor,
          ),
        ),
      );
    }

    return _visualPadrao(
      context,
      compacto: compacto,
      statusColor: statusColor,
    );
  }

  Widget _visualPadrao(
    BuildContext context, {
    required bool compacto,
    required Color statusColor,
  }) {
    return Container(
      width: compacto ? 76 : 44,
      height: compacto ? 88 : 44,
      decoration: BoxDecoration(
        color: statusColor.withAlpha(31),
        borderRadius: BorderRadius.circular(compacto ? 16 : 14),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.local_shipping_rounded,
        size: compacto ? 34 : 24,
        color: statusColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pendente').toString();
    final pedidosIds = (data['pedidos_ids'] as List?) ?? const [];
    final statusColor = _statusColor(context, status);
    final fornecedorNome = (data['fornecedor_nome'] ?? '').toString().trim();
    final observacoes = (data['observacoes'] ?? '').toString().trim();
    final dataPrevista = data['data_prevista'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 620;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: InkWell(
              onTap: onTap,
              onLongPress: podeEditar ? onEditar : null,
              child: Container(
                padding: EdgeInsets.all(compacto ? 10 : 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(context.uai.cardRadius),
                  border: Border.all(color: context.uai.border),
                ),
                child: compacto
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _visualRemessa(
                            context,
                            compacto: true,
                            statusColor: statusColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['nome'] ?? 'Remessa sem nome',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.uai.textPrimary,
                                          fontWeight: FontWeight.w900,
                                          height: 1.08,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    _acoes(context),
                                  ],
                                ),
                                if (fornecedorNome.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    fornecedorNome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.uai.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 5,
                                  children: [
                                    _chip(
                                      context,
                                      Icons.flag_circle_rounded,
                                      _statusLabel(status),
                                      statusColor,
                                      compacto: true,
                                    ),
                                    _chip(
                                      context,
                                      Icons.shopping_bag_rounded,
                                      '${pedidosIds.length} pedido(s)',
                                      context.uai.primary,
                                      compacto: true,
                                    ),
                                    if (dataPrevista != null)
                                      _chip(
                                        context,
                                        Icons.event_available_rounded,
                                        _formatarData(dataPrevista),
                                        context.uai.info,
                                        compacto: true,
                                      ),
                                  ],
                                ),
                                if (observacoes.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    observacoes,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.uai.textMuted,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: context.uai.textMuted,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _visualRemessa(
                            context,
                            compacto: false,
                            statusColor: statusColor,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['nome'] ?? 'Remessa sem nome',
                                        style: TextStyle(
                                          color: context.uai.textPrimary,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 17,
                                        ),
                                      ),
                                    ),
                                    _acoes(context),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _chip(
                                      context,
                                      Icons.flag_circle_rounded,
                                      _statusLabel(status),
                                      statusColor,
                                    ),
                                    _chip(
                                      context,
                                      Icons.shopping_bag_rounded,
                                      '${pedidosIds.length} pedido(s)',
                                      context.uai.primary,
                                    ),
                                    if (dataPrevista != null)
                                      _chip(
                                        context,
                                        Icons.event_available_rounded,
                                        'Prev. ${_formatarData(dataPrevista)}',
                                        context.uai.info,
                                      ),
                                  ],
                                ),
                                if (fornecedorNome.isNotEmpty ||
                                    observacoes.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  if (fornecedorNome.isNotEmpty)
                                    Text(
                                      fornecedorNome,
                                      style: TextStyle(
                                        color: context.uai.textSecondary,
                                      ),
                                    ),
                                  if (observacoes.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        observacoes,
                                        style: TextStyle(
                                          color: context.uai.textSecondary,
                                          height: 1.25,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
