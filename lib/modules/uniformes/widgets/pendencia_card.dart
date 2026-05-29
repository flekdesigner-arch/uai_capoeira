import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class PendenciaCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>, double) onRegistrarPagamento;

  const PendenciaCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onRegistrarPagamento,
  });

  // Helpers de contraste estáticos
  static Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  static Color _ensureVisible(Color color, Color background) {
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

  @override
  Widget build(BuildContext context) {
    double total = (data['valor_total'] ?? 0).toDouble();
    double pago = (data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;
    double percentualPago = total > 0 ? (pago / total) * 100 : 0;

    final tema = context.uai;
    final Color cardBg = tema.card;
    final Color textPrimary = tema.textPrimary;
    final Color textSecondary = tema.textSecondary;
    final Color textMuted = tema.textMuted;
    final Color infoColor = tema.info;
    final Color warningColor = tema.warning;
    final Color errorColor = tema.error;
    final Color successColor = tema.success;
    final Color borderColor = tema.border;
    final Color cardAlt = tema.cardAlt;

    // Cor do chip de status
    final Color statusBg = percentualPago > 0
        ? infoColor.withOpacity(0.1)
        : warningColor.withOpacity(0.1);
    final Color statusFg = percentualPago > 0 ? infoColor : warningColor;

    // Cor da barra de progresso
    final Color progressColor =
    percentualPago > 50 ? successColor : warningColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['aluno_nome'] ?? 'Aluno não identificado',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    percentualPago > 0
                        ? 'PAGO ${percentualPago.toStringAsFixed(0)}%'
                        : 'NÃO PAGO',
                    style: TextStyle(
                      color: statusFg,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Data: ${_formatarData(data['data_venda'])}',
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 8),

            // Barra de progresso do pagamento
            LinearProgressIndicator(
              value: percentualPago / 100,
              backgroundColor: cardAlt,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),

            const SizedBox(height: 8),

            // Valores
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total:',
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    Text(
                      realFormat.format(total),
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Restante:',
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    Text(
                      realFormat.format(restante),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: errorColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Lista de itens (resumida)
            if (data['itens'] != null && data['itens'].length > 0) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 8),
              Text('Itens:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textPrimary)),
              const SizedBox(height: 4),
              ...(data['itens'] as List).take(2).map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['nome'] ?? 'Item',
                          style: TextStyle(fontSize: 11, color: textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${item['quantidade']}x ${realFormat.format(item['preco_unitario'])}',
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ],
                  ),
                );
              }).toList(),
              if (data['itens'].length > 2)
                Text(
                  '+ mais ${data['itens'].length - 2} itens',
                  style: TextStyle(fontSize: 10, color: textMuted),
                ),
            ],

            const SizedBox(height: 12),

            // Botão de pagamento
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () =>
                      onRegistrarPagamento(docId, data, restante),
                  icon: const Icon(Icons.payment, size: 18),
                  label: const Text('Registrar Pagamento'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successColor,
                    foregroundColor: _readableOn(successColor),
                    minimumSize: const Size(180, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          context.uai.buttonRadius),
                    ),
                  ),
                ),
              ],
            ),

            // Histórico de pagamentos (se houver)
            if (data['pagamentos'] != null &&
                data['pagamentos'].length > 0) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 8),
              Text('Histórico de pagamentos:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: textPrimary)),
              const SizedBox(height: 4),
              ...(data['pagamentos'] as List).map((pagamento) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cardAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 12, color: successColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${realFormat.format(pagamento['valor'])} - ${_formatarData(pagamento['data'])}',
                          style: TextStyle(fontSize: 10, color: textSecondary),
                        ),
                      ),
                      Text(
                        pagamento['forma']
                            ?.toUpperCase()
                            .replaceAll('_', ' ') ??
                            '',
                        style: TextStyle(fontSize: 9, color: textMuted),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }
}