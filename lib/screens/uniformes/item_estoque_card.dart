import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ItemEstoqueCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onEditar;
  final Function(String, Map<String, dynamic>) onRegistrarEntrada;
  final Function(String, Map<String, dynamic>) onRegistrarSaida;

  const ItemEstoqueCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onEditar,
    required this.onRegistrarEntrada,
    required this.onRegistrarSaida,
  });

  Color _getCategoriaColor(String? categoria) {
    switch (categoria?.toLowerCase()) {
      case 'camisa':
      case 'camiseta':
        return Colors.blue;
      case 'calça':
      case 'calca':
      case 'bermuda':
        return Colors.green;
      case 'abada':
      case 'corda':
        return Colors.orange;
      case 'acessório':
      case 'acessorio':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoriaIcon(String? categoria) {
    switch (categoria?.toLowerCase()) {
      case 'camisa':
      case 'camiseta':
        return Icons.shopping_bag;
      case 'calça':
      case 'calca':
      case 'bermuda':
        return Icons.shopping_bag;
      case 'abada':
        return Icons.sports_kabaddi;
      case 'corda':
        return Icons.sensors;
      case 'acessório':
      case 'acessorio':
        return Icons.watch;
      default:
        return Icons.inventory;
    }
  }

  @override
  Widget build(BuildContext context) {
    int quantidade = data['quantidade'] ?? 0;
    int estoqueMinimo = data['estoque_minimo'] ?? 5;
    bool baixoEstoque = quantidade <= estoqueMinimo;
    double precoVenda = (data['preco_venda'] ?? 0).toDouble();
    bool controlaEstoque = data['controla_estoque'] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: _getCategoriaColor(data['categoria']).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getCategoriaIcon(data['categoria']),
            color: _getCategoriaColor(data['categoria']),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                data['nome'] ?? 'Sem nome',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: baixoEstoque && controlaEstoque
                    ? Colors.orange.shade100
                    : Colors.green.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                controlaEstoque ? '$quantidade un' : 'Sem estoque',
                style: TextStyle(
                  color: baixoEstoque && controlaEstoque
                      ? Colors.orange.shade900
                      : Colors.green.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${data['categoria'] ?? 'Sem categoria'} - ${data['tamanho'] ?? 'Tam. Único'}'),
            Text(
              'Preço: ${realFormat.format(precoVenda)}',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        icon: Icons.inventory,
                        label: 'Estoque mínimo: $estoqueMinimo',
                        color: Colors.blue,
                      ),
                    ),
                    if (data['fornecedor'] != null && data['fornecedor'].toString().isNotEmpty)
                      Expanded(
                        child: _buildInfoChip(
                          icon: Icons.business,
                          label: data['fornecedor'],
                          color: Colors.purple,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (data['descricao'] != null && data['descricao'].toString().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Descrição: ${data['descricao']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (data['codigo_barras'] != null && data['codigo_barras'].toString().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Código: ${data['codigo_barras']}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => onEditar(docId, data),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Editar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (controlaEstoque) ...[
                      ElevatedButton.icon(
                        onPressed: () => onRegistrarEntrada(docId, data),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Entrada'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: quantidade > 0 ? () => onRegistrarSaida(docId, data) : null,
                        icon: const Icon(Icons.remove, size: 18),
                        label: const Text('Saída'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: quantidade > 0 ? Colors.orange : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}