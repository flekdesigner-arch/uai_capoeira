import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

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

  // Helpers de contraste – estáticos para uso em qualquer lugar
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

  Color _getCategoriaColor(String? categoria, BuildContext context) {
    switch (categoria?.toLowerCase()) {
      case 'camisa':
      case 'camiseta':
        return context.uai.info;
      case 'calça':
      case 'calca':
      case 'bermuda':
        return context.uai.success;
      case 'abada':
      case 'corda':
        return context.uai.warning;
      case 'acessório':
      case 'acessorio':
        return context.uai.primary;
      default:
        return context.uai.textMuted;
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
          color: Colors.black87, // overlay escuro, comum em ambos os temas
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
        title: Text(
          '🗑️ Excluir item',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'Tem certeza que deseja excluir "${data['nome']}" do estoque?',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancelar',
              style: TextStyle(color: context.uai.primary),
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
    final Color corCat = _getCategoriaColor(categoria, context);
    final Color cardBg = context.uai.card;
    final Color visibleCatColor = _ensureVisible(corCat, cardBg);

    String subtitulo = '$categoria - $tamanho';
    if (cor.isNotEmpty) subtitulo += ' - $cor';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      child: ExpansionTile(
        leading: GestureDetector(
          onLongPress: () => _mostrarFotoAmpliada(context, fotoUrl),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: visibleCatColor.withOpacity(0.1),
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
                  color: visibleCatColor,
                ),
                errorWidget: (_, __, ___) => Icon(
                  _getCategoriaIcon(categoria),
                  color: visibleCatColor,
                ),
              ),
            )
                : Icon(
              _getCategoriaIcon(categoria),
              color: visibleCatColor,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                data['nome'] ?? 'Sem nome',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: context.uai.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: controlaEstoque
                    ? (baixoEstoque
                    ? context.uai.warning.withOpacity(0.1)
                    : context.uai.success.withOpacity(0.1))
                    : context.uai.textMuted.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                controlaEstoque ? '$quantidade un' : 'Sem estoque',
                style: TextStyle(
                  color: controlaEstoque
                      ? (baixoEstoque ? context.uai.warning : context.uai.success)
                      : context.uai.textMuted,
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
            Text(
              subtitulo,
              style: TextStyle(color: context.uai.textSecondary),
            ),
            Text(
              'Preço: ${realFormat.format(precoVenda)}',
              style: TextStyle(
                color: context.uai.success,
                fontWeight: FontWeight.w500,
              ),
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
                        color: context.uai.info,
                        context: context,
                      ),
                    ),
                    if (data['fornecedor'] != null &&
                        data['fornecedor'].toString().isNotEmpty)
                      Expanded(
                        child: _buildInfoChip(
                          icon: Icons.business,
                          label: data['fornecedor'],
                          color: context.uai.primary,
                          context: context,
                        ),
                      ),
                  ],
                ),
                if (cor.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildInfoChip(
                      icon: Icons.color_lens,
                      label: 'Cor: $cor',
                      color: context.uai.primary,
                      context: context,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (data['descricao'] != null &&
                    data['descricao'].toString().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Descrição: ${data['descricao']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.uai.textSecondary,
                      ),
                    ),
                  ),
                if (data['codigo_barras'] != null &&
                    data['codigo_barras'].toString().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Código: ${data['codigo_barras']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.uai.textMuted,
                      ),
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
                        foregroundColor: context.uai.primary,
                        side: BorderSide(
                          color: context.uai.primary.withOpacity(0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(context.uai.buttonRadius),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (controlaEstoque) ...[
                      ElevatedButton.icon(
                        onPressed: () => onRegistrarEntrada(docId, data),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Entrada'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.uai.success,
                          foregroundColor: _readableOn(context.uai.success),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                context.uai.buttonRadius),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: quantidade > 0
                            ? () => onRegistrarSaida(docId, data)
                            : null,
                        icon: const Icon(Icons.remove, size: 18),
                        label: const Text('Saída'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: quantidade > 0
                              ? context.uai.warning
                              : context.uai.border,
                          foregroundColor: quantidade > 0
                              ? _readableOn(context.uai.warning)
                              : context.uai.textMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                context.uai.buttonRadius),
                          ),
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
                          backgroundColor: context.uai.error,
                          foregroundColor: _readableOn(context.uai.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                context.uai.buttonRadius),
                          ),
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
    required BuildContext context,
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