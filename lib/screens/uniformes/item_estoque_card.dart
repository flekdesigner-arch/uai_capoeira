import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ItemEstoqueCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onEditar;
  final Function(String, Map<String, dynamic>) onRegistrarEntrada;
  final Function(String, Map<String, dynamic>) onRegistrarSaida;
  final Function(String, Map<String, dynamic>)? onExcluir;

  const ItemEstoqueCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onEditar,
    required this.onRegistrarEntrada,
    required this.onRegistrarSaida,
    this.onExcluir,
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

  void _mostrarFotoAmpliada(BuildContext context, String? fotoUrl) {
    if (fotoUrl == null || fotoUrl.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          color: Colors.black87,
          child: Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              child: CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white, size: 80),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmarExclusao(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Excluir item'),
        content: Text('Tem certeza que deseja excluir "${data['nome']}" do estoque?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onExcluir?.call(docId, data);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int quantidade = data['quantidade'] ?? 0;
    int estoqueMinimo = data['estoque_minimo'] ?? 5;
    bool baixoEstoque = quantidade <= estoqueMinimo;
    double precoVenda = (data['preco_venda'] ?? 0).toDouble();
    bool controlaEstoque = data['controla_estoque'] ?? true;
    final String? fotoUrl = data['foto_url'];
    final String categoria = data['categoria'] ?? 'Outro';
    final String tamanho = data['tamanho']?.toString() ?? 'Tam. Único';
    final String cor = data['cor']?.toString() ?? '';
    final Color corCat = _getCategoriaColor(categoria);

    // Monta texto do subtítulo com tamanho e cor
    String subtitulo = '$categoria - $tamanho';
    if (cor.isNotEmpty) {
      subtitulo += ' - $cor';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: GestureDetector(
          onLongPress: () => _mostrarFotoAmpliada(context, fotoUrl),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: corCat.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: fotoUrl != null && fotoUrl.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Icon(
                  _getCategoriaIcon(categoria),
                  color: corCat,
                ),
                errorWidget: (_, __, ___) => Icon(
                  _getCategoriaIcon(categoria),
                  color: corCat,
                ),
              ),
            )
                : Icon(
              _getCategoriaIcon(categoria),
              color: corCat,
            ),
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
            Text(subtitulo),
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
                // Exibe a cor como um chip extra, se houver
                if (cor.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildInfoChip(
                      icon: Icons.color_lens,
                      label: 'Cor: $cor',
                      color: Colors.teal,
                    ),
                  ),
                ],
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
                    if (onExcluir != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _confirmarExclusao(context),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Excluir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
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