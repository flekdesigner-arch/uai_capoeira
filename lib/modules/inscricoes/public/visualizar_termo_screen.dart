import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class VisualizarTermoScreen extends StatelessWidget {
  final Map<String, dynamic> dados;
  final String inscricaoId;

  const VisualizarTermoScreen({
    super.key,
    required this.dados,
    required this.inscricaoId,
  });

  // Helpers de contraste
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

  @override
  Widget build(BuildContext context) {
    final isMaior = dados['is_maior_idade'] ?? false;
    final temAssinatura = dados['assinatura_url'] != null &&
        dados['assinatura_url'].toString().isNotEmpty;
    final temTermo = dados['termo_autorizacao'] != null &&
        dados['termo_autorizacao'].toString().isNotEmpty;
    final dataInscricao = dados['data_inscricao'] as Timestamp?;
    final dataAprovacao = dados['aprovado_em'] as Timestamp?;

    // Cores temáticas para seções
    final corTituloTermo =
    _ensureVisible(context.uai.error, context.uai.cardAlt);
    final containerWarnBg = context.uai.warning.withOpacity(0.1);
    final corTextoWarn = _ensureVisible(context.uai.warning, containerWarnBg);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '📄 Termo de Responsabilidade',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabeçalho com info da inscrição
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.uai.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(context.uai.cardRadius),
                    border: Border.all(
                      color: context.uai.info.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: context.uai.info.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.description,
                              color: context.uai.info,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dados['aluno_nome'] ??
                                      dados['nome'] ??
                                      'Nome não informado',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: context.uai.textPrimary,
                                  ),
                                ),
                                if (dados['aluno_apelido'] != null)
                                  Text(
                                    dados['aluno_apelido']!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.uai.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: context.uai.border,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildInfoChip(
                            icon: Icons.calendar_today,
                            label: dataInscricao != null
                                ? DateFormat('dd/MM/yyyy')
                                .format(dataInscricao.toDate())
                                : 'Data não informada',
                            color: context.uai.info,
                          ),
                          if (dataAprovacao != null)
                            _buildInfoChip(
                              icon: Icons.check_circle,
                              label:
                              'Aprovado: ${DateFormat('dd/MM/yyyy').format(dataAprovacao.toDate())}',
                              color: context.uai.success,
                            ),
                          _buildInfoChip(
                            icon: Icons.person,
                            label: isMaior ? 'Maior de idade' : 'Menor de idade',
                            color: isMaior
                                ? context.uai.success
                                : context.uai.warning,
                          ),
                          if (temAssinatura)
                            _buildInfoChip(
                              icon: Icons.draw,
                              label: 'Assinado',
                              color: context.uai.success,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // TERMO COMPLETO
                if (temTermo) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.uai.cardAlt,
                      borderRadius:
                      BorderRadius.circular(context.uai.cardRadius),
                      border: Border.all(color: context.uai.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Text(
                            'TERMO DE RESPONSABILIDADE',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: corTituloTermo,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Texto do termo
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.uai.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.uai.border),
                          ),
                          child: Text(
                            dados['termo_autorizacao']!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              fontFamily: 'monospace',
                              color: context.uai.textPrimary,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ASSINATURA (se houver)
                        if (temAssinatura) ...[
                          Divider(color: context.uai.border),
                          const SizedBox(height: 16),

                          Text(
                            'ASSINATURA DIGITAL:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: context.uai.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.uai.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: context.uai.success.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                // Imagem da assinatura
                                Container(
                                  height: 150,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: context.uai.cardAlt,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: context.uai.border,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      dados['assinatura_url']!,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Center(
                                          child: Column(
                                            mainAxisAlignment:
                                            MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.broken_image,
                                                size: 48,
                                                color: context.uai.textMuted,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Erro ao carregar assinatura',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: context.uai.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.uai.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.verified,
                                        size: 16,
                                        color: context.uai.success,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Assinatura verificada',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.uai.success,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // SEM ASSINATURA
                        if (!temAssinatura) ...[
                          Divider(color: context.uai.border),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: containerWarnBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: context.uai.warning.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: corTextoWarn,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Termo sem assinatura digital',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: corTextoWarn,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'O termo foi aceito, mas não foi recolhida assinatura digital.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: corTextoWarn.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // SE NÃO TIVER TERMO
                if (!temTermo) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: context.uai.cardAlt,
                      borderRadius:
                      BorderRadius.circular(context.uai.cardRadius),
                      border: Border.all(color: context.uai.border),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 64,
                          color: context.uai.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Termo não encontrado',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.uai.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Esta inscrição não possui um termo de responsabilidade salvo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.uai.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}