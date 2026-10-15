import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class PedidoCard extends StatelessWidget {
  static final Map<String, Future<String?>> _fotoAlunoCache =
      <String, Future<String?>>{};
  static Future<QuerySnapshot<Map<String, dynamic>>>? _alunosLookupFuture;

  static String _normalizarNome(String value) {
    const com = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const sem = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var out = value.trim().toLowerCase();
    for (var i = 0; i < com.length; i++) {
      out = out.replaceAll(com[i], sem[i].toLowerCase());
    }
    return out.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onMarcarConfeccao;
  final Function(String, Map<String, dynamic>) onFinalizar;
  final Function(String, Map<String, dynamic>) onRegistrarPagamento;
  final Function(String, Map<String, dynamic>)? onEditar;
  final Function(String, Map<String, dynamic>)? onExcluir;
  final bool podeEditar;
  final bool podeExcluir;
  final bool podeRegistrarPagamento;
  final bool podeAlterarStatus;
  final Function(String, Map<String, dynamic>)? onTap;

  const PedidoCard({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onMarcarConfeccao,
    required this.onFinalizar,
    required this.onRegistrarPagamento,
    this.onEditar,
    this.onExcluir,
    this.podeEditar = false,
    this.podeExcluir = false,
    this.podeRegistrarPagamento = false,
    this.podeAlterarStatus = false,
    this.onTap,
  });

  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yyyy', 'pt_BR').format(data.toDate());
      }
      if (data is DateTime) {
        return DateFormat('dd/MM/yyyy', 'pt_BR').format(data);
      }
      if (data is String) {
        final parsed = DateTime.tryParse(data);
        if (parsed != null) {
          return DateFormat('dd/MM/yyyy', 'pt_BR').format(parsed);
        }
        return data;
      }
    } catch (_) {
      return 'Data inválida';
    }
    return 'Data inválida';
  }

  Color _statusColor(BuildContext context, String? status) {
    switch (status) {
      case 'pendente':
        return context.uai.warning;
      case 'em_confeccao':
        return context.uai.info;
      case 'finalizado':
        return context.uai.success;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'pendente':
        return Icons.inventory_2_outlined;
      case 'em_confeccao':
        return Icons.build_circle_rounded;
      case 'finalizado':
        return Icons.inventory_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _statusText(String? status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'em_confeccao':
        return 'Em confecção';
      case 'finalizado':
        return 'Entregue';
      default:
        return 'Indefinido';
    }
  }

  Color _pagamentoColor(BuildContext context, String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return context.uai.success;
      case 'pendente':
        return context.uai.error;
      case 'parcial':
        return context.uai.info;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _pagamentoIcon(String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return Icons.check_circle_rounded;
      case 'pendente':
        return Icons.more_horiz_rounded;
      case 'parcial':
        return Icons.payments_rounded;
      default:
        return Icons.help_outline_rounded;
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

  String _resumirItens(List<dynamic>? itens) {
    if (itens == null || itens.isEmpty) return 'Nenhum item no pedido';
    final linhas = itens.take(2).map((item) {
      final nome = (item['nome'] ?? item['produtoNome'] ?? 'Item').toString();
      final quantidade = (item['quantidade'] ?? 1).toString();
      return '$quantidade x $nome';
    }).toList();
    if (itens.length > 2) linhas.add('+${itens.length - 2} item(ns)');
    return linhas.join(' • ');
  }

  Widget _buildChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
    bool compacto = false,
  }) {
    final content = Container(
      constraints: BoxConstraints(
        minHeight: compacto ? 22 : 28,
        maxWidth: compacto ? 118 : 180,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 6 : 10,
        vertical: compacto ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                icon,
                size: compacto ? 10 : 14,
                color: color,
              ),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(width: compacto ? 3 : 6),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: compacto ? 9 : 11,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textAlign: TextAlign.left,
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: content,
      ),
    );
  }

  Future<String?> _resolverFotoAluno() {
    final direta = (data['foto_aluno_url'] ??
            data['aluno_foto_url'] ??
            data['foto_perfil_aluno'] ??
            data['foto_url'] ??
            data['fotoUrl'] ??
            '')
        .toString()
        .trim();

    if (direta.isNotEmpty) {
      return Future<String?>.value(direta);
    }

    final alunoId = (data['aluno_id'] ?? '').toString().trim();
    final alunoNome = (data['aluno_nome'] ?? '').toString().trim();
    final cacheKey = alunoId.isNotEmpty
        ? 'id:$alunoId'
        : 'nome:${alunoNome.toLowerCase()}';

    if (cacheKey.endsWith(':')) {
      return Future<String?>.value(null);
    }

    return _fotoAlunoCache.putIfAbsent(cacheKey, () async {
      try {
        Map<String, dynamic>? aluno;

        if (alunoId.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('alunos')
              .doc(alunoId)
              .get(const GetOptions(source: Source.serverAndCache));
          aluno = doc.data();
        }

        // Compatibilidade com pedidos antigos que eventualmente ficaram sem
        // aluno_id ou com vínculo incompleto: tenta localizar pelo nome exato.
        if ((aluno == null || aluno.isEmpty) && alunoNome.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('alunos')
              .where('nome', isEqualTo: alunoNome)
              .limit(1)
              .get(const GetOptions(source: Source.serverAndCache));

          if (snap.docs.isNotEmpty) {
            aluno = snap.docs.first.data();
          }
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

        if (aluno == null || aluno.isEmpty) {
          return null;
        }

        final foto = (aluno['foto_perfil_aluno'] ??
                aluno['foto_url'] ??
                aluno['fotoUrl'] ??
                aluno['foto'] ??
                aluno['url_foto'] ??
                aluno['fotoPerfil'] ??
                aluno['foto_perfil_url'] ??
                '')
            .toString()
            .trim();

        if (foto.isEmpty) {
          return null;
        }

        // Backfill silencioso: pedidos antigos sem snapshot de foto passam a
        // guardar a imagem encontrada e deixam de consultar o aluno nas
        // próximas renderizações.
        try {
          await FirebaseFirestore.instance
              .collection('pedidos_uniformes')
              .doc(docId)
              .set({
            'foto_aluno_url': foto,
            'foto_perfil_aluno': foto,
            'foto_aluno_atualizada_em': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {
          // Falha de backfill não impede a exibição da foto encontrada.
        }

        return foto;
      } catch (_) {
        return null;
      }
    });
  }

  Widget _fotoAluno(BuildContext context, bool compacto) {
    final width = compacto ? 68.0 : 42.0;
    final height = compacto ? 84.0 : 42.0;

    Widget fallback = Container(
      width: width,
      height: height,
      color: context.uai.cardAlt,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        size: compacto ? 34 : 22,
        color: context.uai.textMuted,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(compacto ? 16 : 999),
      child: FutureBuilder<String?>(
        future: _resolverFotoAluno(),
        builder: (context, snapshot) {
          final url = snapshot.data?.trim() ?? '';
          if (url.isEmpty) return fallback;
          return CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          );
        },
      ),
    );
  }

  void _mostrarPagamentoResumo(BuildContext context) {
    final total = ((data['valor_total'] ?? 0) as num).toDouble();
    final pago = ((data['valor_pago'] ?? 0) as num).toDouble();
    final restante = (total - pago).clamp(0, double.infinity).toDouble();
    final pagamentos = (data['pagamentos'] as List?) ?? const [];

    String ultimaData = 'Nenhum pagamento registrado';
    String forma = '';
    if (pagamentos.isNotEmpty && pagamentos.last is Map) {
      final pg = Map<String, dynamic>.from(pagamentos.last as Map);
      ultimaData = _formatarData(pg['data']);
      forma = (pg['forma'] ?? '').toString();
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _pagamentoIcon(data['status_pagamento']),
              color: _pagamentoColor(context, data['status_pagamento']),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Pagamento do pedido')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${_pagamentoText(data['status_pagamento'])}'),
            const SizedBox(height: 8),
            Text('Total: ${realFormat.format(total)}'),
            Text('Pago: ${realFormat.format(pago)}'),
            Text('Restante: ${realFormat.format(restante)}'),
            const SizedBox(height: 10),
            Text('Último pagamento: $ultimaData'),
            if (forma.isNotEmpty) Text('Forma: $forma'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _mostrarEntregaResumo(BuildContext context) {
    final status = (data['status'] ?? 'pendente').toString();
    final entregue = status == 'finalizado';
    final dataEntrega = data['data_finalizacao'] ?? data['entregue_em'];
    final previsao = (data['data_previsao'] ?? '').toString();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_statusIcon(status), color: _statusColor(context, status)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Situação da entrega')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${_statusText(status)}'),
            const SizedBox(height: 8),
            if (entregue)
              Text('Entregue/finalizado em: ${_formatarData(dataEntrega)}')
            else if (previsao.isNotEmpty)
              Text('Previsão: $previsao')
            else
              const Text('Ainda sem data de entrega confirmada.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _confirmarExclusao(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.uai.surface,
        title: Text(
          '🗑️ Confirmar exclusão',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Tem certeza que deseja excluir este pedido?\n\n'
          'Aluno: ${data['aluno_nome'] ?? 'N/I'}\n'
          'Valor: ${realFormat.format(data['valor_total'] ?? 0)}',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancelar',
              style: TextStyle(color: context.uai.textPrimary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onExcluir?.call(docId, data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho(
    BuildContext context, {
    required bool compacto,
    required double total,
    required double restante,
    required List<dynamic> itens,
    required Color pagColor,
    required IconData pagIcon,
    required String pagText,
    required Color statusColor,
    required IconData statusIcon,
    required String statusText,
  }) {
    final nome = (data['aluno_nome'] ?? 'Aluno não identificado').toString();

    if (!compacto) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _fotoAluno(context, false),
        title: Text(
          nome,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: context.uai.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _resumirItens(itens),
                style: TextStyle(color: context.uai.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChip(
                    context,
                    icon: pagIcon,
                    label: pagText,
                    color: pagColor,
                    onTap: () => _mostrarPagamentoResumo(context),
                  ),
                  _buildChip(
                    context,
                    icon: statusIcon,
                    label: statusText,
                    color: statusColor,
                    onTap: () => _mostrarEntregaResumo(context),
                  ),
                  _buildChip(
                    context,
                    icon: Icons.calendar_today_rounded,
                    label: _formatarData(data['data_pedido']),
                    color: context.uai.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              realFormat.format(total),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: context.uai.textPrimary,
              ),
            ),
            if (restante > 0)
              Text(
                'Falta ${realFormat.format(restante)}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.uai.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _fotoAluno(context, true),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nome,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: context.uai.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _resumirItens(itens),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.2,
                  height: 1.1,
                  color: context.uai.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              _buildChip(
                context,
                icon: Icons.calendar_today_rounded,
                label: _formatarData(data['data_pedido']),
                color: context.uai.textMuted,
                compacto: true,
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  _buildChip(
                    context,
                    icon: pagIcon,
                    label: pagText,
                    color: pagColor,
                    onTap: () => _mostrarPagamentoResumo(context),
                    compacto: true,
                  ),
                  _buildChip(
                    context,
                    icon: statusIcon,
                    label: statusText,
                    color: statusColor,
                    onTap: () => _mostrarEntregaResumo(context),
                    compacto: true,
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
                overflow: TextOverflow.fade,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: context.uai.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 19,
                color: context.uai.textMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context, data['status']);
    final statusIcon = _statusIcon(data['status']);
    final statusText = _statusText(data['status']);
    final pagColor = _pagamentoColor(context, data['status_pagamento']);
    final pagIcon = _pagamentoIcon(data['status_pagamento']);
    final pagText = _pagamentoText(data['status_pagamento']);

    final total = ((data['valor_total'] ?? 0) as num).toDouble();
    final pago = ((data['valor_pago'] ?? 0) as num).toDouble();
    final restante = (total - pago).clamp(0, double.infinity).toDouble();
    final progresso = total > 0 ? (pago / total).clamp(0.0, 1.0) : 0.0;
    final itens = (data['itens'] as List?)?.cast<dynamic>() ?? const [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 620;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
          ),
          color: context.uai.card,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
              border: Border.all(color: context.uai.border),
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.symmetric(
                horizontal: compacto ? 10 : 16,
                vertical: compacto ? 7 : 8,
              ),
              childrenPadding: EdgeInsets.fromLTRB(
                compacto ? 10 : 16,
                0,
                compacto ? 10 : 16,
                14,
              ),
              dense: compacto,
              visualDensity:
                  compacto ? const VisualDensity(vertical: -1) : null,
              trailing: const SizedBox.shrink(),
              title: _cabecalho(
                context,
                compacto: compacto,
                total: total,
                restante: restante,
                itens: itens,
                pagColor: pagColor,
                pagIcon: pagIcon,
                pagText: pagText,
                statusColor: statusColor,
                statusIcon: statusIcon,
                statusText: statusText,
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.uai.cardAlt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _detailItem(
                        context,
                        label: 'Código interno',
                        value: data['id_pedido'] ?? 'N/I',
                      ),
                      _detailItem(
                        context,
                        label: 'Total do pedido',
                        value: realFormat.format(total),
                      ),
                      _detailItem(
                        context,
                        label: 'Pago',
                        value: realFormat.format(pago),
                      ),
                      _detailItem(
                        context,
                        label: 'Restante',
                        value: realFormat.format(restante),
                        valueColor: restante > 0
                            ? context.uai.error
                            : context.uai.success,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...itens.map((item) {
                  final nome = item['nome'] ?? 'Item';
                  final quantidade = (item['quantidade'] ?? 1) as num;
                  final precoUnitario =
                      ((item['preco_unitario'] ?? 0) as num).toDouble();
                  final subtotal = quantidade.toDouble() * precoUnitario;
                  final tamanho = (item['tamanho'] ?? '').toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.uai.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.uai.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$nome${tamanho.isNotEmpty ? ' • Tam. $tamanho' : ''}\n'
                            '${quantidade.toStringAsFixed(quantidade % 1 == 0 ? 0 : 1)} x ${realFormat.format(precoUnitario)}',
                            style: TextStyle(
                              color: context.uai.textSecondary,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          realFormat.format(subtotal),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: context.uai.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (data['status_pagamento'] != 'pago') ...[
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progresso,
                    backgroundColor: context.uai.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      pago >= total ? context.uai.success : context.uai.warning,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (podeEditar && onEditar != null)
                      OutlinedButton.icon(
                        onPressed: () => onEditar!(docId, data),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Editar'),
                      ),
                    if (podeExcluir && onExcluir != null)
                      OutlinedButton.icon(
                        onPressed: () => _confirmarExclusao(context),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Excluir'),
                      ),
                    if (podeAlterarStatus && data['status'] == 'pendente')
                      OutlinedButton.icon(
                        onPressed: () => onMarcarConfeccao(docId, data),
                        icon: const Icon(Icons.build_rounded, size: 18),
                        label: const Text('Em confecção'),
                      ),
                    if (podeAlterarStatus && data['status'] == 'em_confeccao')
                      ElevatedButton.icon(
                        onPressed: () => onFinalizar(docId, data),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Marcar entregue'),
                      ),
                    if (podeRegistrarPagamento &&
                        data['status_pagamento'] != 'pago')
                      ElevatedButton.icon(
                        onPressed: () => onRegistrarPagamento(docId, data),
                        icon: const Icon(Icons.payment_rounded, size: 18),
                        label: const Text('Pagamento'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailItem(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.uai.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: valueColor ?? context.uai.textPrimary,
          ),
        ),
      ],
    );
  }
}
