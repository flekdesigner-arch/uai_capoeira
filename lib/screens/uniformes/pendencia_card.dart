import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: percentualPago > 0 ? Colors.blue.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    percentualPago > 0 ? 'PAGO ${percentualPago.toStringAsFixed(0)}%' : 'NÃO PAGO',
                    style: TextStyle(
                      color: percentualPago > 0 ? Colors.blue.shade900 : Colors.orange.shade900,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Data: ${_formatarData(data['data_venda'])}'),
            const SizedBox(height: 8),

            // Barra de progresso do pagamento
            LinearProgressIndicator(
              value: percentualPago / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                percentualPago > 50 ? Colors.green : Colors.orange,
              ),
            ),

            const SizedBox(height: 8),

            // Valores
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total:', style: TextStyle(fontSize: 12)),
                    Text(
                      realFormat.format(total),
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Restante:', style: TextStyle(fontSize: 12)),
                    Text(
                      realFormat.format(restante),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Lista de itens (resumida)
            if (data['itens'] != null && data['itens'].length > 0) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text('Itens:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              ...(data['itens'] as List).take(2).map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['nome'] ?? 'Item',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${item['quantidade']}x ${realFormat.format(item['preco_unitario'])}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                );
              }).toList(),
              if (data['itens'].length > 2)
                Text(
                  '+ mais ${data['itens'].length - 2} itens',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
            ],

            const SizedBox(height: 12),

            // Botão de pagamento
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => onRegistrarPagamento(docId, data, restante),
                  icon: const Icon(Icons.payment, size: 18),
                  label: const Text('Registrar Pagamento'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(180, 40),
                  ),
                ),
              ],
            ),

            // Histórico de pagamentos (se houver)
            if (data['pagamentos'] != null && data['pagamentos'].length > 0) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text('Histórico de pagamentos:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              ...(data['pagamentos'] as List).map((pagamento) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 12, color: Colors.green.shade400),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${realFormat.format(pagamento['valor'])} - ${_formatarData(pagamento['data'])}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      Text(
                        pagamento['forma']?.toUpperCase().replaceAll('_', ' ') ?? '',
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
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