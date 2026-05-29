import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

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

  // ---------------------------------------------------------------------------
  // Helpers de contraste (estáticos para uso no build)
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
    if (data == null) return 'N/I';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yyyy').format(data.toDate());
      }
      if (data is String) return data;
    } catch (_) {}
    return 'N/I';
  }

  // ---------------------------------------------------------------------------
  // Status mapeado para tokens do tema
  // ---------------------------------------------------------------------------
  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'pendente':
        return context.uai.warning;
      case 'em_producao':
        return context.uai.info;
      case 'finalizada':
        return context.uai.success;
      case 'cancelada':
        return context.uai.error;
      default:
        return context.uai.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'pendente';
    final pedidosIds = (data['pedidos_ids'] as List?) ?? [];

    final Color statusColor = _statusColor(context, status);
    final Color onStatus = _readableOn(statusColor); // contraste para ícone

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shadowColor: Colors.transparent, // sombra do tema aplicada abaixo
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            border: Border.all(color: context.uai.border),
            boxShadow: context.uai.cardShadow,
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.2),
              child: Icon(Icons.local_shipping, color: statusColor),
            ),
            title: Text(
              data['nome'] ?? 'Remessa sem nome',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: $status',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                Text(
                  'Pedidos: ${pedidosIds.length}',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                if (data['data_prevista'] != null)
                  Text(
                    'Previsão: ${_formatarData(data['data_prevista'])}',
                    style: TextStyle(color: context.uai.textSecondary),
                  ),
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
        ),
      ),
    );
  }
}