import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VendaCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onTap;
  final bool podeEditar;  // ← NOVO
  final bool podeExcluir; // ← NOVO

  const VendaCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onTap,
    this.podeEditar = false,  // ← NOVO
    this.podeExcluir = false, // ← NOVO
  });

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

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (data['status_pagamento']) {
      case 'pago':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'PAGO';
        break;
      case 'pendente':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        statusText = 'PENDENTE';
        break;
      case 'parcial':
        statusColor = Colors.blue;
        statusIcon = Icons.money_off;
        statusText = 'PARCIAL';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusText = 'INDEFINIDO';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Text(
          data['aluno_nome'] ?? 'Aluno não identificado',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${data['itens']?.length ?? 0} itens'),
            Text('Data: ${_formatarData(data['data_venda'])}'),
            Row(
              children: [
                Text('Status: ', style: TextStyle(color: Colors.grey.shade600)),
                Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              realFormat.format(data['valor_total'] ?? 0),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (data['valor_pago'] != null && data['valor_pago'] < (data['valor_total'] ?? 0))
              Text(
                'Pago: ${realFormat.format(data['valor_pago'])}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            // Indicador de permissões (opcional)
            if (podeEditar || podeExcluir)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (podeEditar)
                    const Icon(Icons.edit, size: 12, color: Colors.blue),
                  if (podeEditar && podeExcluir)
                    const SizedBox(width: 4),
                  if (podeExcluir)
                    const Icon(Icons.delete, size: 12, color: Colors.red),
                ],
              ),
          ],
        ),
        onTap: () => onTap(docId, data),
      ),
    );
  }
}