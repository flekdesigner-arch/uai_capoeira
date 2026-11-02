import '../dialogs/uniformes_motivo_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_pdf_service.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/pedido_card.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/pagamento_dialog.dart';
import 'package:uai_capoeira/modules/uniformes/screens/editar_pedido_screen.dart';
import 'package:uai_capoeira/modules/uniformes/screens/remessa_form_screen.dart';
import 'package:uai_capoeira/modules/uniformes/screens/remessa_financeiro_screen.dart';
import 'package:uai_capoeira/modules/uniformes/screens/novo_pedido_screen.dart';
import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/modules/uniformes/utils/remessa_status_utils.dart';

String _mensagemErroRemessa(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'A operação foi recusada pelo servidor.';
  }
  final primeiraLinha = error.toString().split('\n').first.trim();
  return primeiraLinha.replaceFirst(RegExp(r'^(Bad state:|StateError:)\s*'), '');
}

class RemessaDetalhesScreen extends StatefulWidget {
  final String remessaId;
  final Map<String, dynamic> remessaData;
  final bool podeEditar;
  final bool podeExcluir;
  final bool podeCriarPedido;
  final bool podeEditarPedido;
  final bool podeExcluirPedido;
  final bool podeRegistrarPagamentoPedido;
  final bool podeAlterarStatusPedido;

  const RemessaDetalhesScreen({
    super.key,
    required this.remessaId,
    required this.remessaData,
    this.podeEditar = false,
    this.podeExcluir = false,
    this.podeCriarPedido = false,
    this.podeEditarPedido = false,
    this.podeExcluirPedido = false,
    this.podeRegistrarPagamentoPedido = false,
    this.podeAlterarStatusPedido = false,
  });

  @override
  State<RemessaDetalhesScreen> createState() => _RemessaDetalhesScreenState();
}

class _RemessaDetalhesScreenState extends State<RemessaDetalhesScreen> {
  final NumberFormat _realFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final UniformesService _uniformesService = UniformesService();
  final RemessaService _remessaService = RemessaService();
  final FornecedorService _fornecedorService = FornecedorService();

  String? _fornecedorNome;
  bool _carregandoFornecedor = false;
  int _revisaoPedidos = 0;
  String? _statusRemessaLocal;
  late Stream<QuerySnapshot> _streamPedidos;

  bool get _remessaAberta {
    final status = _statusRemessaLocal ?? normalizarStatusRemessa(widget.remessaData['status']);
    return !{'finalizada', 'finalizado', 'cancelada', 'cancelado', 'recebida', 'recebido'}.contains(status);
  }

  Stream<QuerySnapshot> _pedidosDaRemessa() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return Stream.fromFuture(FirebaseFirestore.instance
          .collection('pedidos_uniformes')
          .where('remessa_id', isEqualTo: widget.remessaId)
          .orderBy('data_pedido', descending: true)
          .get(const GetOptions(source: Source.serverAndCache)));
    }
    return _remessaService.getPedidosDaRemessa(widget.remessaId);
  }

  void _atualizarPedidos() {
    if (!mounted) return;
    setState(() {
      _revisaoPedidos++;
      _streamPedidos = _pedidosDaRemessa();
    });
  }

  Future<void> _novoPedido() async {
    if (!widget.podeCriarPedido || !_remessaAberta) return;
    final autorizado = await PermissionAccessGuard().revalidate(
      context,
      permission: 'pode_criar_pedido',
      message: 'Sem permissão para cadastrar pedidos de Uniformes.',
    );
    if (!autorizado || !mounted) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NovoPedidoScreen(
        remessaInicialId: widget.remessaId,
        remessaInicial: widget.remessaData,
      )),
    );
    if (result == true) _atualizarPedidos();
  }

  // Helpers de contraste
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  @override
  void initState() {
    super.initState();
    _streamPedidos = _pedidosDaRemessa();
    _carregarFornecedor();
  }

  Future<void> _carregarFornecedor() async {
    final fornecedorId = widget.remessaData['fornecedor_id'] as String?;
    if (fornecedorId == null) return;

    setState(() => _carregandoFornecedor = true);
    try {
      final doc = await _fornecedorService.getFornecedor(fornecedorId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _fornecedorNome = data['nome'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar fornecedor: $e');
    } finally {
      if (mounted) setState(() => _carregandoFornecedor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.remessaData;
    final primary = context.uai.primary;
    final onPrimary = _readableOn(primary);
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final warning = context.uai.warning;
    final error = context.uai.error;
    final info = context.uai.info;
    final cardBg = context.uai.card;
    final border = context.uai.border;
    final cardAlt = context.uai.cardAlt;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          data['nome'] ?? 'Remessa',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: onPrimary),
            onSelected: (value) async {
              if (value == 'pdf_resumido') {
                await RemessaPdfService.gerarPdfResumido(
                  widget.remessaId,
                  data,
                );
              } else if (value == 'pdf_completo') {
                await RemessaPdfService.gerarPdfCompleto(
                  widget.remessaId,
                  data,
                );
              } else if (value == 'custos_remessa') {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RemessaFinanceiroScreen(remessaId: widget.remessaId)));
              } else if (value == 'editar') {
                _editarRemessa();
              } else if (value == 'alterar_status') {
                _mostrarAlterarStatus();
              } else if (value == 'finalizar') {
                _finalizarRemessa();
              } else if (value == 'excluir') {
                _excluirRemessa();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pdf_resumido',
                child: Text(
                  '📄 PDF resumido (confecção)',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'pdf_completo',
                child: Text(
                  '📊 PDF completo (associação)',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              const PopupMenuDivider(),
              if (widget.podeEditar) const PopupMenuItem(value: 'custos_remessa', child: Text('💰 Custos e pagamento ao fornecedor')),
              if (widget.podeEditar)
                PopupMenuItem(
                  value: 'editar',
                  child: Text(
                    '✏️ Editar remessa',
                    style: TextStyle(color: textPrimary),
                  ),
                ),
              PopupMenuItem(
                value: 'alterar_status',
                child: Text(
                  '🔄 Alterar status',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'finalizar',
                child: Text(
                  '✅ Finalizar remessa',
                  style: TextStyle(color: textPrimary),
                ),
              ),
              if (widget.podeExcluir)
                PopupMenuItem(
                  value: 'excluir',
                  child: Text(
                    '🗑️ Excluir remessa',
                    style: TextStyle(color: error),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.podeCriarPedido && _remessaAberta
          ? FloatingActionButton.extended(
              onPressed: _novoPedido,
              backgroundColor: primary,
              foregroundColor: onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: const Text('NOVO PEDIDO', style: TextStyle(fontWeight: FontWeight.w900)),
            )
          : null,
      body: Column(
        children: [
          _buildCabecalho(
            data,
            primary,
            textPrimary,
            textSecondary,
            textMuted,
            cardBg,
            border,
            cardAlt,
            warning,
            error,
            info,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              key: ValueKey('remessa_pedidos_${widget.remessaId}_$_revisaoPedidos'),
              stream: _streamPedidos,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Não foi possível carregar os pedidos.', style: TextStyle(color: error)),
                      const SizedBox(height: 8),
                      TextButton.icon(onPressed: _atualizarPedidos,
                        icon: const Icon(Icons.refresh_rounded), label: const Text('Tentar novamente')),
                    ]),
                  ));
                }
                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: primary),
                  );
                }
                final pedidos = snapshot.data!.docs;
                if (pedidos.isEmpty) {
                  return Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag_outlined, size: 52, color: textMuted),
                      const SizedBox(height: 10),
                      Text('Nenhum pedido nesta remessa', style: TextStyle(color: textPrimary,
                          fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text('Use Novo pedido para cadastrar diretamente aqui.',
                        style: TextStyle(color: textSecondary, fontSize: 12)),
                      if (widget.podeCriarPedido && _remessaAberta) const SizedBox(height: 78),
                    ],
                  ));
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final colunas = width >= 1700
                        ? 4
                        : width >= 1250
                        ? 3
                        : width >= 900
                        ? 2
                        : 1;

                    Widget buildPedido(QueryDocumentSnapshot pedido) {
                      final pedidoData = pedido.data() as Map<String, dynamic>;
                      final bool ehEstoque = pedidoData['tipo_estoque'] == true;

                      final card = PedidoCard(
                        docId: pedido.id,
                        data: pedidoData,
                        realFormat: _realFormat,
                        onMarcarConfeccao: _marcarPedidoComoConfeccao,
                        onFinalizar: _marcarPedidoComoFinalizado,
                        onRegistrarEntrega: _confirmarEntregaAluno,
                        onRegistrarPagamento: _registrarPagamentoPedido,
                        onEditar: widget.podeEditarPedido ? _editarPedido : null,
                        onExcluir: widget.podeExcluirPedido ? _excluirPedido : null,
                        podeEditar: widget.podeEditarPedido,
                        podeExcluir: widget.podeExcluirPedido,
                        podeRegistrarPagamento: widget.podeRegistrarPagamentoPedido,
                        podeAlterarStatus: widget.podeAlterarStatusPedido,
                        onTap: (id, d) {},
                      );

                      if (!ehEstoque) return card;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: warning.withAlpha(26),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_rounded,
                                  size: 14,
                                  color: warning,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    'Item para estoque • entra ao finalizar',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          card,
                        ],
                      );
                    }

                    if (colunas == 1) {
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 104),
                        itemCount: pedidos.length,
                        itemBuilder: (_, i) => buildPedido(pedidos[i]),
                      );
                    }

                    const spacing = 12.0;
                    final maxWidth = width >= 1700
                        ? 1500.0
                        : width >= 1250
                        ? 1220.0
                        : 920.0;
                    final contentWidth = width < maxWidth ? width : maxWidth;
                    final cardWidth =
                        (contentWidth - 24 - (spacing * (colunas - 1))) /
                        colunas;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 104),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            alignment: WrapAlignment.start,
                            children: pedidos.map((pedido) {
                              return SizedBox(
                                width: cardWidth,
                                child: buildPedido(pedido),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCabecalho(
    Map<String, dynamic> data,
    Color primary,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    Color cardBg,
    Color border,
    Color cardAlt,
    Color warning,
    Color error,
    Color info,
  ) {
    final pedidosIds = (data['pedidos_ids'] as List?) ?? const [];
    final status = _statusRemessaLocal ?? normalizarStatusRemessa(data['status']);
    final statusColor = switch (status) {
      'finalizada' => context.uai.success,
      'em_confeccao' => info,
      'em_producao' => info,
      'enviada' => info,
      'cancelada' => error,
      _ => warning,
    };
    final statusLabel = switch (status) {
      'finalizada' => 'Finalizada',
      'em_confeccao' => 'Em confecção',
      'em_producao' => 'Em produção (legado)',
      'enviada' => 'Enviada',
      'cancelada' => 'Cancelada',
      _ => 'Pendente',
    };

    Widget metric({
      required IconData icon,
      required String label,
      required String value,
      required Color color,
    }) {
      return Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: cardAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(31),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: textMuted)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 650;

        Widget compactMetric({
          required IconData icon,
          required String label,
          required String value,
          required Color color,
        }) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: cardAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withAlpha(31),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 8.8,
                            color: textMuted,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.7,
                            fontWeight: FontWeight.w900,
                            color: textPrimary,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (compacto) {
          return Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['nome'] ?? 'Remessa',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(31),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    compactMetric(
                      icon: Icons.shopping_bag_rounded,
                      label: 'Pedidos',
                      value: '${pedidosIds.length}',
                      color: primary,
                    ),
                    const SizedBox(width: 6),
                    compactMetric(
                      icon: Icons.event_available_rounded,
                      label: 'Previsão',
                      value: data['data_prevista'] != null
                          ? DateFormat('dd/MM/yyyy').format(
                              (data['data_prevista'] as Timestamp).toDate(),
                            )
                          : 'Não informada',
                      color: info,
                    ),
                    const SizedBox(width: 6),
                    compactMetric(
                      icon: Icons.business_rounded,
                      label: 'Fornecedor',
                      value: _carregandoFornecedor
                          ? '...'
                          : (_fornecedorNome ?? 'Não informado'),
                      color: warning,
                    ),
                  ],
                ),
                if (_carregandoFornecedor) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(minHeight: 2, color: primary),
                ],
                if (data['observacoes'] != null &&
                    data['observacoes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.sticky_note_2_rounded,
                        size: 14,
                        color: textMuted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          data['observacoes'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textSecondary, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['nome'] ?? 'Remessa',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(31),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flag_circle_rounded,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (data['observacoes'] != null &&
                            data['observacoes'].toString().isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              data['observacoes'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Expanded(
                      child: metric(
                        icon: Icons.shopping_bag_rounded,
                        label: 'Pedidos vinculados',
                        value: '${pedidosIds.length}',
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: metric(
                        icon: Icons.event_available_rounded,
                        label: 'Previsão',
                        value: data['data_prevista'] != null
                            ? DateFormat('dd/MM/yyyy').format(
                                (data['data_prevista'] as Timestamp).toDate(),
                              )
                            : 'Não informada',
                        color: info,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: metric(
                        icon: Icons.business_rounded,
                        label: 'Fornecedor',
                        value: _carregandoFornecedor
                            ? 'Carregando...'
                            : (_fornecedorNome ?? 'Não informado'),
                        color: warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Finalização com lógica de estoque integrada ─────────────
  Future<void> _finalizarRemessa() async {
    final todosPedidos = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: widget.remessaId)
        .get();

    final pedidosAluno = <QueryDocumentSnapshot>[];
    final pedidosEstoque = <QueryDocumentSnapshot>[];
    for (var doc in todosPedidos.docs) {
      final data = doc.data();
      if (data['tipo_estoque'] == true) {
        pedidosEstoque.add(doc);
      } else {
        pedidosAluno.add(doc);
      }
    }

    // Recebimento físico e confecção finalizada são independentes de cobrança
    // e entrega. Um aluno ainda poderá pagar/retirar sua camisa depois.
    final emAberto = pedidosAluno.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final total = (d['valor_total'] as num?)?.toDouble() ?? 0;
      final pago = (d['valor_pago'] as num?)?.toDouble() ?? 0;
      return total - pago > 0.005;
    }).length;
    final aguardandoEntrega = pedidosAluno.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return d['status_entrega'] != 'entregue';
    }).length;
    final int qtdEstoque = pedidosEstoque.length;
    final mensagem = 'Confirma que a fábrica entregou as peças desta remessa?\n\n'
        '• ${pedidosAluno.length} pedido(s) de alunos ficarão com a confecção finalizada.\n'
        '• $emAberto pedido(s) ainda têm valores a receber.\n'
        '• $aguardandoEntrega pedido(s) ainda aguardam entrega ao aluno.\n'
        '• $qtdEstoque pedido(s) para estoque terão entrada física registrada.\n\n'
        'Não serão marcados pagamentos nem entregas automaticamente.';

    if (!mounted) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Receber remessa da fábrica',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          mensagem,
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: context.uai.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.success,
              foregroundColor: _readableOn(context.uai.success),
            ),
            child: const Text('Confirmar recebimento'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _remessaService.receberRemessa(widget.remessaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Remessa recebida! Cobranças e entregas continuam separadas. ${qtdEstoque > 0 ? "$qtdEstoque pedido(s) para estoque recebidos." : ""}',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível receber a remessa: ${_mensagemErroRemessa(e)}',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  void _mostrarAlterarStatus() {
    final statusAtual = _statusRemessaLocal ??
        normalizarStatusRemessa(widget.remessaData['status']);
    // O backend grava `em_confeccao`. Remessas antigas podem ter
    // `em_producao`/`enviada`; o valor inicial DEVE constar exatamente uma
    // vez na lista do DropdownButtonFormField.
    final opcoesStatus = opcoesStatusRemessa(statusAtual);
    showDialog(
      context: context,
      builder: (ctx) {
        String novoStatus = statusAtual;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'Alterar status da remessa',
                style: TextStyle(color: context.uai.textPrimary),
              ),
              content: DropdownButtonFormField<String>(
                initialValue: novoStatus,
                style: TextStyle(color: context.uai.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.uai.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      context.uai.inputRadius,
                    ),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      context.uai.inputRadius,
                    ),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      context.uai.inputRadius,
                    ),
                    borderSide: BorderSide(
                      color: context.uai.primary,
                      width: 1.4,
                    ),
                  ),
                ),
                dropdownColor: context.uai.card,
                items: opcoesStatus.entries
                    .map((opcao) => DropdownMenuItem<String>(
                          value: opcao.key,
                          child: Text(opcao.value),
                        ))
                    .toList(growable: false),
                onChanged: (v) {
                  if (v != null) setState(() => novoStatus = v);
                },
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
                    _alterarStatusRemessa(novoStatus);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.uai.primary,
                    foregroundColor: _readableOn(context.uai.primary),
                  ),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _alterarStatusRemessa(String novoStatus) async {
    try {
      if (novoStatus == 'finalizada') {
        await _finalizarRemessa();
        return;
      } else if (novoStatus == 'em_producao' || novoStatus == 'em_confeccao') {
        await _remessaService.iniciarConfeccao(widget.remessaId);
      } else {
        String? motivo;
        if (novoStatus == 'cancelada') {
          motivo = await solicitarMotivoUniformes(
            context,
            'Justificativa do cancelamento',
          );
          if (motivo == null) return;
        }
        await _remessaService.atualizarRemessa(widget.remessaId, {
          'motivo': ?motivo,
          'status': novoStatus,
        });
      }
      if (mounted) {
        setState(() {
          // `iniciar_confeccao` converte o alias legado `em_producao`
          // no valor canônico `em_confeccao` no Firestore.
          _statusRemessaLocal =
              novoStatus == 'em_producao' ? 'em_confeccao' : novoStatus;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Status atualizado!',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro: ${_mensagemErroRemessa(e)}',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _excluirRemessa() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Excluir Remessa',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'O servidor verifica pagamentos, entregas e histórico antes de excluir esta remessa e seus pedidos pendentes.',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: context.uai.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      if (!mounted) return;
      final motivo = await solicitarMotivoUniformes(
        context,
        'Justificativa para excluir remessa',
      );
      if (motivo == null) return;
      await _remessaService.excluirRemessa(widget.remessaId, motivo: motivo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Remessa excluída!',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro: ${_mensagemErroRemessa(e)}',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ─── Callbacks para os cards de pedido ────────────────────────
  Future<void> _marcarPedidoComoConfeccao(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!widget.podeAlterarStatusPedido) return;
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'em_confeccao');
      _atualizarPedidos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido em confecção',
              style: TextStyle(color: _readableOn(context.uai.info)),
            ),
            backgroundColor: context.uai.info,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro: ${_mensagemErroRemessa(e)}',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmarEntregaAluno(
    String pedidoId,
    Map<String, dynamic> dados,
  ) async {
    if (!widget.podeAlterarStatusPedido || dados['tipo_estoque'] == true) return;
    final total = (dados['valor_total'] as num?)?.toDouble() ?? 0;
    final pago = (dados['valor_pago'] as num?)?.toDouble() ?? 0;
    final falta = (total - pago).clamp(0, double.infinity).toDouble();
    final avisoFinanceiro = falta > 0.005
        ? 'Atenção: falta receber ${_realFormat.format(falta)}. A entrega NÃO quita esta dívida.'
        : 'Pedido quitado.';
    final aluno = (dados['aluno_nome'] ?? 'este aluno').toString();
    if (!mounted) return;
    final confirmado = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Confirmar entrega ao aluno'),
      content: Text('A confecção está finalizada. Confirma a entrega física para $aluno?\n\n$avisoFinanceiro'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar entrega')),
      ],
    ));
    if (confirmado != true) return;
    try {
      await _uniformesService.registrarEntregaPedido(pedidoId);
      _atualizarPedidos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Entrega registrada. Pagamentos permaneceram inalterados.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Entrega não registrada: ${_mensagemErroRemessa(e)}')));
      }
    }
  }

  Future<void> _marcarPedidoComoFinalizado(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!widget.podeAlterarStatusPedido) return;
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'finalizado');
      _atualizarPedidos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido finalizado',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro: ${_mensagemErroRemessa(e)}',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _editarRemessa() async {
    if (!widget.podeEditar) return;

    final doc = await FirebaseFirestore.instance
        .collection('remessas')
        .doc(widget.remessaId)
        .get();

    final atual = doc.data() ?? widget.remessaData;

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RemessaFormScreen(remessaId: widget.remessaId, remessaData: atual),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _editarPedido(String docId, Map<String, dynamic> data) async {
    if (!widget.podeEditarPedido) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarPedidoScreen(pedidoId: docId, pedidoData: data),
      ),
    );

    if (result == true && mounted) {
      _atualizarPedidos();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido atualizado!',
            style: TextStyle(color: _readableOn(context.uai.success)),
          ),
          backgroundColor: context.uai.success,
        ),
      );
    }
  }

  Future<void> _excluirPedido(String docId, Map<String, dynamic> data) async {
    if (!widget.podeExcluirPedido) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Excluir pedido',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'Excluir definitivamente o pedido de '
          '${data['aluno_nome'] ?? 'aluno não identificado'}?',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      if (!mounted) return;
      final motivo = await solicitarMotivoUniformes(
        context,
        'Justificativa para excluir pedido',
      );
      if (motivo == null) return;
      await _remessaService.excluirPedidoDefinitivamente(
        docId,
        remessaId: widget.remessaId,
        motivo: motivo,
      );

      if (mounted) {
        _atualizarPedidos();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido excluído.',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível excluir o pedido agora.',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _registrarPagamentoPedido(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!widget.podeRegistrarPagamentoPedido) return;
    double total = (data['valor_total'] ?? 0).toDouble();
    double pago = (data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;
    if (restante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido já pago!',
            style: TextStyle(color: _readableOn(context.uai.warning)),
          ),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => PagamentoDialog(
        alunoNome: data['aluno_nome'] ?? 'Aluno',
        valorTotal: total,
        valorPago: pago,
        valorRestante: restante,
        onConfirm: (valor, formaPagamento) async {
          try {
            await _uniformesService.registrarPagamentoPedido(
              pedidoId: docId,
              valorPagamento: valor,
              formaPagamento: formaPagamento,
              pedidoData: data,
            );
            _atualizarPedidos();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Pagamento registrado',
                    style: TextStyle(color: _readableOn(context.uai.success)),
                  ),
                  backgroundColor: context.uai.success,
                ),
              );
            }
          } catch (_) {
            // PagamentoDialog preserva os dados e exibe a falha sem fechar.
            rethrow;
          }
        },
      ),
    );
  }
}
