import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PedidoCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onMarcarConfeccao;
  final Function(String, Map<String, dynamic>) onFinalizar;
  final Function(String, Map<String, dynamic>) onRegistrarPagamento;
  final Function(String, Map<String, dynamic>)? onEditar;      // 🔥 NOVO
  final Function(String, Map<String, dynamic>)? onExcluir;     // 🔥 NOVO
  final bool podeEditar;                                       // 🔥 NOVO
  final bool podeExcluir;                                      // 🔥 NOVO
  final Function(String, Map<String, dynamic>)? onTap;         // 🔥 NOVO

  const PedidoCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onMarcarConfeccao,
    required this.onFinalizar,
    required this.onRegistrarPagamento,
    this.onEditar,                                              // 🔥 NOVO
    this.onExcluir,                                             // 🔥 NOVO
    this.podeEditar = false,                                    // 🔥 NOVO
    this.podeExcluir = false,                                   // 🔥 NOVO
    this.onTap,                                                 // 🔥 NOVO
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

  void _confirmarExclusao(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir este pedido?\n\n'
              'Pedido: ${data['id_pedido'] ?? 'N/I'}\n'
              'Aluno: ${data['aluno_nome']}\n'
              'Valor: ${realFormat.format(data['valor_total'] ?? 0)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onExcluir?.call(docId, data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (data['status']) {
      case 'pendente':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        statusText = 'PENDENTE';
        break;
      case 'em_confeccao':
        statusColor = Colors.blue;
        statusIcon = Icons.build;
        statusText = 'EM CONFECÇÃO';
        break;
      case 'finalizado':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'FINALIZADO';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusText = 'INDEFINIDO';
    }

    Color pagamentoColor;
    IconData pagamentoIcon;
    String pagamentoText;

    switch (data['status_pagamento']) {
      case 'pago':
        pagamentoColor = Colors.green;
        pagamentoIcon = Icons.check_circle;
        pagamentoText = 'PAGO';
        break;
      case 'pendente':
        pagamentoColor = Colors.red;
        pagamentoIcon = Icons.pending;
        pagamentoText = 'PENDENTE';
        break;
      case 'parcial':
        pagamentoColor = Colors.blue;
        pagamentoIcon = Icons.money_off;
        pagamentoText = 'PARCIAL';
        break;
      default:
        pagamentoColor = Colors.grey;
        pagamentoIcon = Icons.help;
        pagamentoText = 'INDEFINIDO';
    }

    double total = (data['valor_total'] ?? 0).toDouble();
    double pago = (data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap != null ? () => onTap!(docId, data) : null,
        borderRadius: BorderRadius.circular(12),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.1),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  data['aluno_nome'] ?? 'Aluno não identificado',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              // 🔥 INDICADORES DE PERMISSÃO (OPCIONAL)
              if (podeEditar || podeExcluir)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (podeEditar)
                        const Icon(Icons.edit, size: 14, color: Colors.blue),
                      if (podeEditar && podeExcluir)
                        const SizedBox(width: 4),
                      if (podeExcluir)
                        const Icon(Icons.delete, size: 14, color: Colors.red),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: pagamentoColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(pagamentoIcon, color: pagamentoColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      pagamentoText,
                      style: TextStyle(
                        color: pagamentoColor,
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
              Text('Pedido: ${data['id_pedido'] ?? 'N/I'}'),
              Text('Data: ${_formatarData(data['data_pedido'])}'),
              if (data['data_previsao'] != null && data['data_previsao'].toString().isNotEmpty)
                Text(
                  'Previsão: ${data['data_previsao']}',
                  style: const TextStyle(color: Colors.blue),
                ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Lista de itens do pedido
                  ...(data['itens'] as List? ?? []).map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['nome'] ?? 'Item',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            '${item['quantidade']} x ${realFormat.format(item['preco_unitario'] ?? 0)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            realFormat.format((item['quantidade'] ?? 1) * (item['preco_unitario'] ?? 0)),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }).toList(),

                  const Divider(),

                  // Totais
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL DO PEDIDO',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        realFormat.format(total),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
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
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                        Text(
                          'Restante: ${realFormat.format(restante)}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),

                    // Barra de progresso do pagamento
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: total > 0 ? pago / total : 0,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pago >= total ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],

                  // Observações
                  if (data['observacoes'] != null && data['observacoes'].toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.note, size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              data['observacoes'],
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // 🔥 BOTÕES DE AÇÃO (AGORA COM EDIÇÃO/EXCLUSÃO)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      // BOTÃO EDITAR (se tiver permissão)
                      if (podeEditar && onEditar != null)
                        OutlinedButton.icon(
                          onPressed: () => onEditar!(docId, data),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Editar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                          ),
                        ),

                      // BOTÃO EXCLUIR (se tiver permissão)
                      if (podeExcluir && onExcluir != null)
                        OutlinedButton.icon(
                          onPressed: () => _confirmarExclusao(context),
                          icon: const Icon(Icons.delete, size: 18),
                          label: const Text('Excluir'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),

                      // Botões existentes
                      if (data['status'] == 'pendente')
                        OutlinedButton.icon(
                          onPressed: () => onMarcarConfeccao(docId, data),
                          icon: const Icon(Icons.build, size: 18),
                          label: const Text('Em Confecção'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                          ),
                        ),
                      if (data['status'] == 'em_confeccao')
                        ElevatedButton.icon(
                          onPressed: () => onFinalizar(docId, data),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Finalizar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      if (data['status_pagamento'] != 'pago')
                        ElevatedButton.icon(
                          onPressed: () => onRegistrarPagamento(docId, data),
                          icon: const Icon(Icons.payment, size: 18),
                          label: const Text('Pagamento'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      if (data['status'] == 'finalizado')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'FINALIZADO',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  // Histórico de pagamentos (se houver)
                  if (data['pagamentos'] != null && data['pagamentos'].length > 0) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    const Text('Histórico de pagamentos:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
                            Icon(Icons.payment, size: 12, color: Colors.purple.shade400),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${realFormat.format(pagamento['valor'])} - ${_formatarData(pagamento['data'])}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            Text(
                              pagamento['forma']?.toUpperCase().replaceAll('_', ' ') ?? '',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
    );
  }
}