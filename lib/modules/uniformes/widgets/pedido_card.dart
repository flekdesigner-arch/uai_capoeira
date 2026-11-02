import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/pedido_status_visual.dart';

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
    return out
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onMarcarConfeccao;
  final Function(String, Map<String, dynamic>) onFinalizar;
  final Function(String, Map<String, dynamic>)? onRegistrarEntrega;
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
    this.onRegistrarEntrega,
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

  String _statusText(String? status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'em_confeccao':
        return 'Em confecção';
      case 'finalizado':
        return 'Confecção pronta';
      default:
        return 'Indefinido';
    }
  }

  Color _pagamentoColor(BuildContext context, String? statusPag) {
    switch (statusPag) {
      case 'pago':
        return const Color(0xFF16A34A);
      case 'pendente':
        return const Color(0xFFEA580C);
      case 'parcial':
        return const Color(0xFFCA8A04);
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
              child: Icon(icon, size: compacto ? 10 : 14, color: color),
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
    if (data['tipo_estoque'] == true) {
      return Future<String?>.value(null);
    }
    final direta =
        (data['foto_aluno_url'] ??
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

        if (foto.isEmpty) {
          return null;
        }

        return foto;
      } catch (_) {
        return null;
      }
    });
  }

  Widget _fotoAluno(BuildContext context, bool compacto) {
    final width = compacto ? 55.0 : 62.0;
    final height = compacto ? 65.0 : 70.0;

    Widget fallback = Container(
      width: width,
      height: height,
      color: context.uai.cardAlt,
      alignment: Alignment.center,
      child: Icon(
        data['tipo_estoque'] == true
            ? Icons.inventory_2_outlined
            : Icons.person_rounded,
        size: compacto ? 28 : 30,
        color: context.uai.textMuted,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(compacto ? 14 : 16),
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
    final entrega = (data['status_entrega'] ?? 'aguardando').toString();
    final entregue = entrega == 'entregue';
    final ehEstoque = data['tipo_estoque'] == true;
    final dataEntrega = data['entregue_em'];
    final previsao = (data['data_previsao'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(entregue ? Icons.verified_rounded : Icons.local_shipping_outlined,
            color: entregue ? context.uai.success : context.uai.info),
          const SizedBox(width: 10),
          Expanded(child: Text(ehEstoque
              ? 'Confecção para estoque'
              : 'Confecção e entrega')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Fabricação: ${_statusText(status)}'),
            const SizedBox(height: 8),
            if (ehEstoque) ...[
              const Text('Este pedido não pertence a um aluno.'),
              const SizedBox(height: 8),
              const Text('Consulte o estoque para verificar a entrada física das peças.'),
            ] else ...[
            Text('Entrega: ${entregue ? 'Entregue ao aluno' : 'Aguardando retirada/entrega'}'),
            const SizedBox(height: 8),
            if (entregue)
              Text('Entregue em: ${_formatarData(dataEntrega)}')
            else if (previsao.isNotEmpty)
              Text('Previsão: $previsao')
            else
              const Text('A entrega ainda não foi confirmada.'),
            ],
          ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'))],
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
    required PedidoStatusVisual operacao,
    required Color pagColor,
    required IconData pagIcon,
    required String pagText,
    required bool ehEstoque,
  }) {
    final nome = ehEstoque
        ? 'ITEM PARA ESTOQUE'
        : (data['aluno_nome'] ?? 'Aluno não identificado').toString();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _fotoAluno(context, compacto),
            SizedBox(width: compacto ? 9 : 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: compacto ? 12.5 : 15,
                      height: 1.12,
                      color: context.uai.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _resumirItens(itens),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.uai.textSecondary,
                      fontSize: compacto ? 10.5 : 12,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 11, color: context.uai.textMuted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _formatarData(data['data_pedido']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: context.uai.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: compacto ? 83 : 102,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    realFormat.format(total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontSize: compacto ? 13.5 : 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ehEstoque
                        ? 'Sem cobrança'
                        : data['status_pagamento'] == 'pago'
                            ? 'Quitado'
                            : restante > 0
                                ? 'Falta ${realFormat.format(restante)}'
                                : 'Sem saldo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: compacto ? 9.5 : 11,
                      fontWeight: FontWeight.w700,
                      color: ehEstoque
                          ? context.uai.textMuted
                          : restante > 0
                              ? pagColor
                              : context.uai.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Divider(height: 1, thickness: 1, color: context.uai.border),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _mostrarEntregaResumo(context),
                child: Row(
                  children: [
                    Icon(operacao.icone,
                        color: operacao.cor, size: compacto ? 19 : 21),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            operacao.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: operacao.cor,
                              fontSize: compacto ? 11 : 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            operacao.apoio,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compacto ? 9.5 : 11,
                              color: context.uai.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            _buildChip(
              context,
              icon: ehEstoque ? Icons.inventory_2_outlined : pagIcon,
              label: pagText,
              color: pagColor,
              compacto: true,
              onTap: ehEstoque ? null : () => _mostrarPagamentoResumo(context),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ver detalhes',
                style: TextStyle(color: context.uai.textMuted, fontSize: 10)),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded,
                size: 17, color: context.uai.textMuted),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final operacao = PedidoStatusVisual.doPedido(data);
    final pagColor = _pagamentoColor(context, data['status_pagamento']);
    final pagIcon = _pagamentoIcon(data['status_pagamento']);
    final ehEstoque = data['tipo_estoque'] == true;
    final estoqueSemCobranca = ehEstoque;
    final pagText = ehEstoque ? 'Estoque' : _pagamentoText(data['status_pagamento']);
    final corFinanceira = ehEstoque ? const Color(0xFF7C3AED) : pagColor;

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
          elevation: 0,
          color: context.uai.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            side: BorderSide(color: context.uai.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5),
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
                  visualDensity: compacto
                      ? const VisualDensity(vertical: -1)
                      : null,
                  trailing: const SizedBox.shrink(),
                  title: _cabecalho(
                    context,
                    compacto: compacto,
                    total: total,
                    restante: restante,
                    itens: itens,
                    operacao: operacao,
                    pagColor: corFinanceira,
                    pagIcon: pagIcon,
                    pagText: pagText,
                    ehEstoque: ehEstoque,
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
                            label: ehEstoque ? 'Valor registrado' : 'Total do pedido',
                            value: realFormat.format(total),
                          ),
                          if (!ehEstoque) _detailItem(
                            context,
                            label: 'Pago',
                            value: realFormat.format(pago),
                          ),
                          if (!ehEstoque) _detailItem(
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
                      final precoUnitario = ((item['preco_unitario'] ?? 0) as num)
                          .toDouble();
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
                    if (!ehEstoque && data['status_pagamento'] != 'pago') ...[
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
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
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
                            label: const Text('Concluir confecção'),
                          ),
                        if (podeAlterarStatus && onRegistrarEntrega != null &&
                            data['tipo_estoque'] != true && data['status'] == 'finalizado' &&
                            data['status_entrega'] != 'entregue')
                          ElevatedButton.icon(
                            onPressed: () => onRegistrarEntrega!(docId, data),
                            icon: const Icon(Icons.local_shipping_rounded, size: 18),
                            label: const Text('Entregar ao aluno'),
                          ),
                        if (!estoqueSemCobranca && podeRegistrarPagamento &&
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
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Semantics(
                  label: 'Etapa do pedido: ${operacao.titulo}',
                  child: Container(width: 5, color: operacao.cor),
                ),
              ),
            ],
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
