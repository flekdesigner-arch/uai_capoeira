import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class VendaCard extends StatelessWidget {
  static final Map<String, Future<String?>> _fotoAlunoCache =
      <String, Future<String?>>{};
  static Future<QuerySnapshot<Map<String, dynamic>>>? _alunosLookupFuture;

  static String _normalizarNome(String value) {
    const com = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÏÓÒÔÕÖÚÙÛÜÇ';
    const sem = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';

    var out = value.trim().toLowerCase();
    for (var i = 0; i < com.length; i++) {
      out = out.replaceAll(com[i], sem[i].toLowerCase());
    }

    return out
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onTap;
  final bool podeEditar;
  final bool podeExcluir;

  const VendaCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onTap,
    this.podeEditar = false,
    this.podeExcluir = false,
  });

  Future<String?> _resolverFotoAluno() {
    final alunoId = (data['aluno_id'] ?? '').toString().trim();
    final alunoNome = (data['aluno_nome'] ?? '').toString().trim();
    final direta =
        (data['foto_aluno_url'] ??
                data['aluno_foto_url'] ??
                data['foto_perfil_aluno'] ??
                data['foto_url'] ??
                data['fotoUrl'] ??
                '')
            .toString()
            .trim();

    if (direta.isNotEmpty) return Future<String?>.value(direta);

    final cacheKey = alunoId.isNotEmpty
        ? 'id:$alunoId'
        : 'nome:${_normalizarNome(alunoNome)}';

    return _fotoAlunoCache.putIfAbsent(
      cacheKey,
      () => _buscarFotoAluno(alunoId: alunoId, alunoNome: alunoNome),
    );
  }

  Future<String?> _buscarFotoAluno({
    required String alunoId,
    required String alunoNome,
  }) async {
    try {
      Map<String, dynamic>? aluno;

      if (alunoId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('alunos')
            .doc(alunoId)
            .get(const GetOptions(source: Source.serverAndCache));

        if (doc.exists) aluno = doc.data();
      }

      if ((aluno == null || aluno.isEmpty) && alunoNome.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('alunos')
            .where('nome', isEqualTo: alunoNome)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache));

        if (snap.docs.isNotEmpty) aluno = snap.docs.first.data();
      }

      if ((aluno == null || aluno.isEmpty) && alunoNome.isNotEmpty) {
        _alunosLookupFuture ??= FirebaseFirestore.instance
            .collection('alunos')
            .limit(500)
            .get(const GetOptions(source: Source.serverAndCache));

        final todos = await _alunosLookupFuture!;
        final alvo = _normalizarNome(alunoNome);

        for (final doc in todos.docs) {
          final nomeDoc = (doc.data()['nome'] ?? '').toString();
          if (_normalizarNome(nomeDoc) == alvo) {
            aluno = doc.data();
            break;
          }
        }
      }

      if (aluno == null || aluno.isEmpty) return null;

      final foto =
          (aluno['foto_perfil_aluno'] ??
                  aluno['foto_url'] ??
                  aluno['fotoUrl'] ??
                  aluno['foto'] ??
                  aluno['url_foto'] ??
                  aluno['fotoPerfil'] ??
                  aluno['foto_perfil_url'] ??
                  '')
              .toString()
              .trim();

      if (foto.isEmpty) return null;

      return foto;
    } catch (_) {
      return null;
    }
  }

  Widget _buildFotoAluno(BuildContext context, {required bool compact}) {
    final width = compact ? 66.0 : 44.0;
    final height = compact ? 78.0 : 44.0;
    final radius = compact ? 14.0 : 999.0;

    return FutureBuilder<String?>(
      future: _resolverFotoAluno(),
      builder: (context, snapshot) {
        final foto = snapshot.data?.trim() ?? '';

        Widget placeholder() => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: context.uai.cardAlt,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Icon(
            Icons.person_rounded,
            color: context.uai.textMuted,
            size: compact ? 30 : 24,
          ),
        );

        if (foto.isEmpty) return placeholder();

        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CachedNetworkImage(
            imageUrl: foto,
            width: width,
            height: height,
            fit: BoxFit.cover,
            placeholder: (_, _) => placeholder(),
            errorWidget: (_, _, _) => placeholder(),
          ),
        );
      },
    );
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(data.toDate());
      }
      if (data is String) return data;
    } catch (_) {
      return 'Data inválida';
    }
    return 'Data inválida';
  }

  Color _pagamentoColor(BuildContext context, String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return context.uai.success;
      case 'pendente':
        return context.uai.warning;
      case 'parcial':
        return context.uai.info;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _pagamentoIcon(String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return Icons.check_circle;
      case 'pendente':
        return Icons.pending;
      case 'parcial':
        return Icons.paid;
      default:
        return Icons.help_outline;
    }
  }

  String _pagamentoText(String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return 'Pago';
      case 'pendente':
        return 'Pendente';
      case 'parcial':
        return 'Parcial';
      default:
        return 'Indefinido';
    }
  }

  Color _entregaColor(BuildContext context, String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'entregue':
        return context.uai.success;
      case 'parcial':
        return context.uai.info;
      case 'cancelado':
        return context.uai.error;
      default:
        return context.uai.warning;
    }
  }

  String _entregaText(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'entregue':
        return 'Entregue';
      case 'parcial':
        return 'Entrega parcial';
      case 'cancelado':
        return 'Entrega cancelada';
      default:
        return 'Aguardando entrega';
    }
  }

  String _resumirItens(List<dynamic>? itens) {
    if (itens == null || itens.isEmpty) return 'Nenhum item informado';

    final resumos = itens.take(2).map((item) {
      final nome = (item['produtoNome'] ?? item['nome'] ?? 'Item').toString();
      final qtd = (item['quantidade'] ?? 1).toString();
      return '$qtd x $nome';
    }).toList();

    if (itens.length > 2) {
      resumos.add('+${itens.length - 2} item(ns)');
    }

    return resumos.join(' • ');
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(icon, size: 12, color: color),
            ),
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(width: 4),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusPag = data['status_pagamento'] as String?;
    final statusEntrega = data['status_entrega'] as String?;
    final pagColor = _pagamentoColor(context, statusPag);
    final pagIcon = _pagamentoIcon(statusPag);
    final pagText = _pagamentoText(statusPag);
    final entregaColor = _entregaColor(context, statusEntrega);
    final entregaText = _entregaText(statusEntrega);

    final total = ((data['valor_total'] ?? 0) as num).toDouble();
    final pago = ((data['valor_pago'] ?? 0) as num).toDouble();
    final restante = (total - pago).clamp(0, double.infinity).toDouble();
    final itens = (data['itens'] as List?)?.cast<dynamic>() ?? const [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: () => onTap(docId, data),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
              border: Border.all(color: context.uai.border),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;

                if (compact) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildFotoAluno(context, compact: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (data['aluno_nome'] ?? 'Aluno não identificado')
                                    .toString()
                                    .toUpperCase(),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.4,
                                  height: 1.05,
                                  color: context.uai.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _resumirItens(itens),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.uai.textSecondary,
                                  fontSize: 11.2,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 5,
                                runSpacing: 5,
                                children: [
                                  _buildInfoChip(
                                    context,
                                    icon: pagIcon,
                                    label: pagText,
                                    color: pagColor,
                                  ),
                                  _buildInfoChip(
                                    context,
                                    icon: Icons.local_shipping_rounded,
                                    label: entregaText,
                                    color: entregaColor,
                                  ),
                                  _buildInfoChip(
                                    context,
                                    icon: Icons.calendar_today_rounded,
                                    label: _formatarData(data['data_venda']),
                                    color: context.uai.textMuted,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 76,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                realFormat.format(total),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15.5,
                                  color: context.uai.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                pago > 0
                                    ? 'Pago ${realFormat.format(pago)}'
                                    : 'Sem pagamento',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: context.uai.textSecondary,
                                ),
                              ),
                              if (restante > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Falta ${realFormat.format(restante)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: context.uai.warning,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildFotoAluno(context, compact: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (data['aluno_nome'] ?? 'Aluno não identificado')
                                  .toString()
                                  .toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                                color: context.uai.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _resumirItens(itens),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.uai.textSecondary,
                                fontSize: 11.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 5,
                              children: [
                                _buildInfoChip(
                                  context,
                                  icon: pagIcon,
                                  label: pagText,
                                  color: pagColor,
                                ),
                                _buildInfoChip(
                                  context,
                                  icon: Icons.local_shipping_rounded,
                                  label: entregaText,
                                  color: entregaColor,
                                ),
                                _buildInfoChip(
                                  context,
                                  icon: Icons.calendar_today_rounded,
                                  label: _formatarData(data['data_venda']),
                                  color: context.uai.textMuted,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      _buildTotalColumn(context, total, pago, restante),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTotalColumn(
    BuildContext context,
    double total,
    double pago,
    double restante,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          realFormat.format(total),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: context.uai.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pago: ${realFormat.format(pago)}',
          style: TextStyle(fontSize: 12, color: context.uai.textSecondary),
        ),
        if (restante > 0)
          Text(
            'Falta: ${realFormat.format(restante)}',
            style: TextStyle(
              fontSize: 12,
              color: context.uai.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (podeEditar || podeExcluir) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (podeEditar)
                Icon(Icons.edit_rounded, size: 16, color: context.uai.info),
              if (podeEditar && podeExcluir) const SizedBox(width: 8),
              if (podeExcluir)
                Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: context.uai.error,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
