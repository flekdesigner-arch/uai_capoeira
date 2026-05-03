import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RemessaCard extends StatelessWidget {
  final String remessaId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;

  const RemessaCard({
    super.key,
    required this.remessaId,
    required this.data,
    required this.onTap,
    required this.onEditar,
    required this.onExcluir,
  });

  String _formatarData(dynamic data) {
    if (data == null) return 'N/I';
    try {
      if (data is Timestamp) return DateFormat('dd/MM/yyyy').format(data.toDate());
      if (data is String) return data;
    } catch (_) {}
    return 'N/I';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pendente': return Colors.orange;
      case 'em_producao': return Colors.blue;
      case 'finalizada': return Colors.green;
      case 'cancelada': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'pendente';
    final pedidosIds = (data['pedidos_ids'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(status).withOpacity(0.2),
          child: Icon(Icons.local_shipping, color: _statusColor(status)),
        ),
        title: Text(data['nome'] ?? 'Remessa sem nome'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $status'),
            Text('Pedidos: ${pedidosIds.length}'),
            if (data['data_prevista'] != null) Text('Previsão: ${_formatarData(data['data_prevista'])}'),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'editar') onEditar();
            if (value == 'excluir') onExcluir();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(value: 'excluir', child: Text('Excluir')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}