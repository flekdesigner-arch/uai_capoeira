import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class VendaCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onTap;
  final bool podeEditar;
  final bool podeExcluir;

  const VendaCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onTap,
    this.podeEditar = false,
    this.podeExcluir = false,
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
  // Formatação de data (mantida igual)
  // ---------------------------------------------------------------------------
  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(data.toDate());
      } else if (data is String) {
        return data;
      }
    } catch (e) {
      return 'Data inválida';
    }
    return 'Data inválida';
  }

  // ---------------------------------------------------------------------------
  // Cores e ícones de status de pagamento (usando tokens do tema)
  // ---------------------------------------------------------------------------
  Color _pagamentoColor(BuildContext context, String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return context.uai.success;
      case 'pendente':
        return context.uai.warning;
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

  @override
  Widget build(BuildContext context) {
    final statusPag = data['status_pagamento'] as String?;
    final Color pagColor = _pagamentoColor(context, statusPag);
    final IconData pagIcon = _pagamentoIcon(statusPag);
    final String pagText = _pagamentoText(statusPag);

    final double total = (data['valor_total'] ?? 0).toDouble();
    final double pago = (data['valor_pago'] ?? 0).toDouble();

    // Contraste do ícone sobre o fundo do CircleAvatar
    final Color onPag = _readableOn(pagColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        clipBehavior: Clip.antiAlias,
        elevation: 0, // sombra aplicada no Container externo
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            border: Border.all(color: context.uai.border),
            boxShadow: context.uai.cardShadow,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              backgroundColor: pagColor.withOpacity(0.15),
              child: Icon(pagIcon, color: pagColor),
            ),
            title: Text(
              data['aluno_nome'] ?? 'Aluno não identificado',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.uai.textPrimary,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data['itens']?.length ?? 0} itens',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                Text(
                  'Data: ${_formatarData(data['data_venda'])}',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                Row(
                  children: [
                    Text('Status: ',
                        style: TextStyle(color: context.uai.textMuted)),
                    Text(pagText,
                        style: TextStyle(
                            color: pagColor, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
            // --- trailing corrigido para evitar overflow ---
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  realFormat.format(total),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14, // reduzido de 16 para caber
                    color: context.uai.textPrimary,
                  ),
                ),
                if (pago < total)
                  Text(
                    'Pago: ${realFormat.format(pago)}',
                    style: TextStyle(
                      fontSize: 10, // reduzido de 11
                      color: context.uai.textSecondary,
                    ),
                  ),
                if (podeEditar || podeExcluir)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (podeEditar)
                        Icon(Icons.edit,
                            size: 12, color: context.uai.info),
                      if (podeEditar && podeExcluir)
                        const SizedBox(width: 4),
                      if (podeExcluir)
                        Icon(Icons.delete,
                            size: 12, color: context.uai.error),
                    ],
                  ),
              ],
            ),
            onTap: () => onTap(docId, data),
          ),
        ),
      ),
    );
  }
}