import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class PedidoCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onMarcarConfeccao;
  final Function(String, Map<String, dynamic>) onFinalizar;
  final Function(String, Map<String, dynamic>) onRegistrarPagamento;
  final Function(String, Map<String, dynamic>)? onEditar;
  final Function(String, Map<String, dynamic>)? onExcluir;
  final bool podeEditar;
  final bool podeExcluir;
  final Function(String, Map<String, dynamic>)? onTap;

  const PedidoCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onMarcarConfeccao,
    required this.onFinalizar,
    required this.onRegistrarPagamento,
    this.onEditar,
    this.onExcluir,
    this.podeEditar = false,
    this.podeExcluir = false,
    this.onTap,
  });

  // ---------------------------------------------------------------------------
  // Helpers de contraste
  // ---------------------------------------------------------------------------
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  // ---------------------------------------------------------------------------
  // Formatação de data (mantida)
  // ---------------------------------------------------------------------------
  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yyyy', 'pt_BR').format(data.toDate());
      } else if (data is String) {
        return data;
      }
    } catch (e) {
      return 'Data inválida';
    }
    return 'Data inválida';
  }

  // ---------------------------------------------------------------------------
  // Cores de status
  // ---------------------------------------------------------------------------
  Color _statusColor(BuildContext context, String? status) {
    switch (status) {
      case 'pendente':
        return context.uai.warning;
      case 'em_confeccao':
        return context.uai.info;
      case 'finalizado':
        return context.uai.success;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'pendente':
        return Icons.pending;
      case 'em_confeccao':
        return Icons.build;
      case 'finalizado':
        return Icons.check_circle;
      default:
        return Icons.help;
    }
  }

  String _statusText(String? status) {
    switch (status) {
      case 'pendente':
        return 'PENDENTE';
      case 'em_confeccao':
        return 'EM CONFECÇÃO';
      case 'finalizado':
        return 'FINALIZADO';
      default:
        return 'INDEFINIDO';
    }
  }

  // ---------------------------------------------------------------------------
  // Cores de pagamento
  // ---------------------------------------------------------------------------
  Color _pagamentoColor(BuildContext context, String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return context.uai.success;
      case 'pendente':
        return context.uai.error;
      case 'parcial':
        return context.uai.info;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _pagamentoIcon(String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return Icons.check_circle;
      case 'pendente':
        return Icons.pending;
      case 'parcial':
        return Icons.money_off;
      default:
        return Icons.help;
    }
  }

  String _pagamentoText(String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return 'PAGO';
      case 'pendente':
        return 'PENDENTE';
      case 'parcial':
        return 'PARCIAL';
      default:
        return 'INDEFINIDO';
    }
  }

  // ---------------------------------------------------------------------------
  // Confirmação de exclusão (adaptada ao tema)
  // ---------------------------------------------------------------------------
  void _confirmarExclusao(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.uai.surface,
        title: Text(
          '🗑️ Confirmar Exclusão',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Tem certeza que deseja excluir este pedido?\n\n'
              'Pedido: ${data['id_pedido'] ?? 'N/I'}\n'
              'Aluno: ${data['aluno_nome']}\n'
              'Valor: ${realFormat.format(data['valor_total'] ?? 0)}',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'CANCELAR',
              style: TextStyle(color: context.uai.textPrimary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onExcluir?.call(docId, data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build principal
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context, data['status']);
    final statusIcon = _statusIcon(data['status']);
    final statusText = _statusText(data['status']);

    final pagColor = _pagamentoColor(context, data['status_pagamento']);
    final pagIcon = _pagamentoIcon(data['status_pagamento']);
    final pagText = _pagamentoText(data['status_pagamento']);

    final double total = (data['valor_total'] ?? 0).toDouble();
    final double pago = (data['valor_pago'] ?? 0).toDouble();
    final double restante = total - pago;
    final double progresso = total > 0 ? (pago / total).clamp(0.0, 1.0) : 0.0;

    final Color onPag = _readableOn(pagColor);
    final Color onStatus = _readableOn(statusColor);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      color: context.uai.card,
      elevation: 2,
      shadowColor: Colors.transparent, // sombra controlada pelo tema via boxShadow?
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap != null ? () => onTap!(docId, data) : null,
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
          child: ExpansionTile(
            // tilePadding ajustado para alinhamento
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            leading: CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.15),
              child: Icon(statusIcon, color: statusColor, size: 20),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    data['aluno_nome'] ?? 'Aluno não identificado',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.uai.textPrimary,
                    ),
                  ),
                ),
                // Indicadores de permissão
                if (podeEditar || podeExcluir)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (podeEditar)
                          Icon(Icons.edit, size: 14, color: context.uai.info),
                        if (podeEditar && podeExcluir)
                          const SizedBox(width: 4),
                        if (podeExcluir)
                          Icon(Icons.delete, size: 14, color: context.uai.error),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: pagColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(pagIcon, color: pagColor, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        pagText,
                        style: TextStyle(
                          color: pagColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedido: ${data['id_pedido'] ?? 'N/I'}',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                Text(
                  'Data: ${_formatarData(data['data_pedido'])}',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                if (data['data_previsao'] != null &&
                    data['data_previsao'].toString().isNotEmpty)
                  Text(
                    'Previsão: ${data['data_previsao']}',
                    style: TextStyle(color: context.uai.info),
                  ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Itens do pedido
                    ...(data['itens'] as List? ?? []).map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['nome'] ?? 'Item',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.uai.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '${item['quantidade']} x ${realFormat.format(item['preco_unitario'] ?? 0)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.uai.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              realFormat.format(
                                  (item['quantidade'] ?? 1) *
                                      (item['preco_unitario'] ?? 0)),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: context.uai.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    Divider(color: context.uai.border),

                    // Totais
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL DO PEDIDO',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.uai.textPrimary,
                          ),
                        ),
                        Text(
                          realFormat.format(total),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.uai.primary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),

                    if (data['status_pagamento'] != 'pago') ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pago: ${realFormat.format(pago)}',
                            style: TextStyle(color: context.uai.success),
                          ),
                          Text(
                            'Restante: ${realFormat.format(restante)}',
                            style: TextStyle(
                              color: context.uai.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progresso,
                        backgroundColor: context.uai.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          pago >= total ? context.uai.success : context.uai.warning,
                        ),
                      ),
                    ],

                    // Observações
                    if (data['observacoes'] != null &&
                        data['observacoes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.uai.cardAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.note, size: 16, color: context.uai.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                data['observacoes'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.uai.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Botões de ação
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        // Editar
                        if (podeEditar && onEditar != null)
                          OutlinedButton.icon(
                            onPressed: () => onEditar!(docId, data),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Editar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.uai.info,
                              side: BorderSide(color: context.uai.info),
                            ),
                          ),

                        // Excluir
                        if (podeExcluir && onExcluir != null)
                          OutlinedButton.icon(
                            onPressed: () => _confirmarExclusao(context),
                            icon: const Icon(Icons.delete, size: 18),
                            label: const Text('Excluir'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.uai.error,
                              side: BorderSide(color: context.uai.error),
                            ),
                          ),

                        // Botões existentes
                        if (data['status'] == 'pendente')
                          OutlinedButton.icon(
                            onPressed: () => onMarcarConfeccao(docId, data),
                            icon: const Icon(Icons.build, size: 18),
                            label: const Text('Em Confecção'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.uai.info,
                              side: BorderSide(color: context.uai.info),
                            ),
                          ),

                        if (data['status'] == 'em_confeccao')
                          ElevatedButton.icon(
                            onPressed: () => onFinalizar(docId, data),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Finalizar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.uai.success,
                              foregroundColor: _readableOn(context.uai.success),
                            ),
                          ),

                        if (data['status_pagamento'] != 'pago')
                          ElevatedButton.icon(
                            onPressed: () => onRegistrarPagamento(docId, data),
                            icon: const Icon(Icons.payment, size: 18),
                            label: const Text('Pagamento'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.uai.primary,
                              foregroundColor: _readableOn(context.uai.primary),
                            ),
                          ),

                        if (data['status'] == 'finalizado')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: context.uai.success.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: context.uai.success.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 16, color: context.uai.success),
                                const SizedBox(width: 4),
                                Text(
                                  'FINALIZADO',
                                  style: TextStyle(
                                    color: context.uai.success,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    // Histórico de pagamentos
                    if (data['pagamentos'] != null &&
                        data['pagamentos'].length > 0) ...[
                      const SizedBox(height: 16),
                      Divider(color: context.uai.border),
                      const SizedBox(height: 8),
                      Text(
                        'Histórico de pagamentos:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.uai.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...(data['pagamentos'] as List).map((pagamento) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.uai.cardAlt,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.payment,
                                  size: 12, color: context.uai.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${realFormat.format(pagamento['valor'])} - ${_formatarData(pagamento['data'])}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.uai.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                pagamento['forma']
                                    ?.toUpperCase()
                                    .replaceAll('_', ' ') ??
                                    '',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.uai.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}