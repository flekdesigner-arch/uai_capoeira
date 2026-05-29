import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class InscricoesAprovadasDialog extends StatefulWidget {
  const InscricoesAprovadasDialog({super.key});

  @override
  State<InscricoesAprovadasDialog> createState() =>
      _InscricoesAprovadasDialogState();
}

class _InscricoesAprovadasDialogState extends State<InscricoesAprovadasDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Helpers de contraste (estáticos para uso em build e métodos internos)
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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      child: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CABEÇALHO
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.uai.success,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(context.uai.cardRadius),
                  topRight: Radius.circular(context.uai.cardRadius),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _readableOn(context.uai.success).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.checklist,
                      color: _readableOn(context.uai.success),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Inscrições Aprovadas',
                      style: TextStyle(
                        color: _readableOn(context.uai.success),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: _readableOn(context.uai.success),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // CONTEÚDO
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('inscricoes_aprovadas')
                    .orderBy('aprovado_em', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: context.uai.primary,
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox,
                            size: 64,
                            color: context.uai.textMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma inscrição aprovada',
                            style: TextStyle(
                              fontSize: 16,
                              color: context.uai.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'As inscrições aprovadas aparecerão aqui',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.uai.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final inscricoes = snapshot.data!.docs;

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: inscricoes.length,
                    itemBuilder: (context, index) {
                      final doc = inscricoes[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final dataAprovacao = data['aprovado_em'] as Timestamp?;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: context.uai.card,
                          borderRadius:
                          BorderRadius.circular(context.uai.cardRadius),
                          border: Border.all(color: context.uai.border),
                          boxShadow: context.uai.softShadow,
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _mostrarTermo(context, data, doc.id);
                          },
                          borderRadius:
                          BorderRadius.circular(context.uai.cardRadius),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: context.uai.info.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    color: context.uai.info,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['aluno_nome'] ??
                                            data['nome'] ??
                                            'Nome não informado',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: context.uai.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        data['aluno_apelido'] ??
                                            data['apelido'] ??
                                            '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.uai.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 12,
                                            color: context.uai.textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            dataAprovacao != null
                                                ? DateFormat('dd/MM/yyyy')
                                                .format(
                                                dataAprovacao.toDate())
                                                : 'Data não informada',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.uai.textMuted,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            Icons.school,
                                            size: 12,
                                            color: context.uai.textMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              data['turma_nome'] ??
                                                  'Turma não informada',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: context.uai.textMuted,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (data['assinatura_url'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.draw,
                                                size: 12,
                                                color: context.uai.success,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Termo assinado',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: context.uai.success,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: context.uai.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // RODAPÉ
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.uai.cardAlt,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(context.uai.cardRadius),
                  bottomRight: Radius.circular(context.uai.cardRadius),
                ),
                border: Border(
                  top: BorderSide(color: context.uai.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: context.uai.primary,
                    ),
                    child: const Text('FECHAR'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarTermo(
      BuildContext context, Map<String, dynamic> dados, String inscricaoId) {
    final isMaior = dados['is_maior_idade'] ?? false;
    final temAssinatura = dados['assinatura_url'] != null &&
        dados['assinatura_url'].toString().isNotEmpty;
    final temTermo = dados['termo_autorizacao'] != null &&
        dados['termo_autorizacao'].toString().isNotEmpty;
    final dataInscricao = dados['data_inscricao'] as Timestamp?;
    final dataAprovacao = dados['aprovado_em'] as Timestamp?;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // CABEÇALHO
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.uai.info,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(context.uai.cardRadius),
                    topRight: Radius.circular(context.uai.cardRadius),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _readableOn(context.uai.info).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.description,
                        color: _readableOn(context.uai.info),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Termo de Responsabilidade',
                        style: TextStyle(
                          color: _readableOn(context.uai.info),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: _readableOn(context.uai.info),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // CONTEÚDO
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // INFORMAÇÕES DA INSCRIÇÃO
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.uai.cardAlt,
                          borderRadius:
                          BorderRadius.circular(context.uai.cardRadius),
                          border: Border.all(color: context.uai.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 16,
                                  color: context.uai.info,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    dados['aluno_nome'] ??
                                        dados['nome'] ??
                                        'Nome não informado',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Divider(
                              height: 16,
                              color: context.uai.border,
                            ),
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
                                _buildInfoChip(
                                  icon: Icons.check_circle,
                                  label: dataAprovacao != null
                                      ? DateFormat('dd/MM/yyyy')
                                      .format(dataAprovacao.toDate())
                                      : 'Aprovada',
                                  color: context.uai.success,
                                ),
                                if (temAssinatura)
                                  _buildInfoChip(
                                    icon: Icons.draw,
                                    label: 'Assinado',
                                    color: context.uai.success,
                                  ),
                                if (!temAssinatura)
                                  _buildInfoChip(
                                    icon: Icons.edit_note,
                                    label: 'Sem assinatura',
                                    color: context.uai.warning,
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
                            color: context.uai.card,
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
                                    color: _ensureVisible(
                                      context.uai.error,
                                      context.uai.card,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Texto do termo
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: context.uai.cardAlt,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: context.uai.border),
                                ),
                                child: Text(
                                  dados['termo_autorizacao']!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: context.uai.textPrimary,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ASSINATURA
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
                                      color:
                                      context.uai.success.withOpacity(0.3),
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
                                          borderRadius:
                                          BorderRadius.circular(8),
                                          border: Border.all(
                                              color: context.uai.border),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                          BorderRadius.circular(8),
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
                                                      color: context
                                                          .uai.textMuted,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Erro ao carregar assinatura',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: context
                                                            .uai.textMuted,
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
                                          color: context.uai.success
                                              .withOpacity(0.1),
                                          borderRadius:
                                          BorderRadius.circular(20),
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
                                    color: context.uai.warning
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: context.uai.warning
                                          .withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: _ensureVisible(
                                          context.uai.warning,
                                          context.uai.warning
                                              .withOpacity(0.1),
                                        ),
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
                                                color: _ensureVisible(
                                                  context.uai.warning,
                                                  context.uai.warning
                                                      .withOpacity(0.1),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'O termo foi aceito, mas não foi recolhida assinatura digital.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _ensureVisible(
                                                  context.uai.warning,
                                                  context.uai.warning
                                                      .withOpacity(0.1),
                                                ).withOpacity(0.8),
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

              // RODAPÉ
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.uai.cardAlt,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(context.uai.cardRadius),
                    bottomRight: Radius.circular(context.uai.cardRadius),
                  ),
                  border: Border(
                    top: BorderSide(color: context.uai.border),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: context.uai.primary,
                      ),
                      child: const Text('FECHAR'),
                    ),
                  ],
                ),
              ),
            ],
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