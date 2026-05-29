import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_service.dart';

class DetalhesVendaBottomSheet extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>, double) onRegistrarPagamento;
  final Function(String, Map<String, dynamic>)? onEditar;
  final Function(String, Map<String, dynamic>)? onExcluir;
  final bool podeEditar;
  final bool podeExcluir;

  const DetalhesVendaBottomSheet({
    super.key,
    required this.docId,
    required this.data,
    required this.realFormat,
    required this.onRegistrarPagamento,
    this.onEditar,
    this.onExcluir,
    this.podeEditar = false,
    this.podeExcluir = false,
  });

  @override
  State<DetalhesVendaBottomSheet> createState() =>
      _DetalhesVendaBottomSheetState();
}

class _DetalhesVendaBottomSheetState extends State<DetalhesVendaBottomSheet> {
  final UsuarioService _usuarioService = UsuarioService();
  String _nomeVendedor = 'Carregando...';
  bool _carregandoVendedor = true;

  @override
  void initState() {
    super.initState();
    _carregarNomeVendedor();
  }

  // ---------------------------------------------------------------------------
  // Helpers de contraste
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
  // Carregamento do vendedor (mantido igual)
  // ---------------------------------------------------------------------------
  Future<void> _carregarNomeVendedor() async {
    final vendedorId = widget.data['vendedor_id'];
    if (vendedorId != null && vendedorId.toString().isNotEmpty) {
      final nome = await _usuarioService.getNomeUsuario(vendedorId);
      if (mounted) {
        setState(() {
          _nomeVendedor = nome;
          _carregandoVendedor = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _nomeVendedor = 'Não informado';
          _carregandoVendedor = false;
        });
      }
    }
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';
    try {
      if (data is Timestamp) {
        return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(data.toDate());
      } else if (data is String) {
        return data;
      }
    } catch (e) {
      return 'Data inválida';
    }
    return 'Data inválida';
  }

  // 🔥 MÉTODO DE EXCLUSÃO (mantido igual)
  void _confirmarExclusao(BuildContext context) {
    final bottomSheetContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.uai.surface,
        title: Text(
          '🗑️ Confirmar Exclusão',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Tem certeza que deseja excluir esta venda?\n\n'
              'Aluno: ${widget.data['aluno_nome']}\n'
              'Valor: ${widget.realFormat.format(widget.data['valor_total'] ?? 0)}',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: Text(
              'CANCELAR',
              style: TextStyle(color: context.uai.textPrimary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(bottomSheetContext);
              widget.onExcluir?.call(widget.docId, widget.data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cores de status (usam tokens)
  // ---------------------------------------------------------------------------
  Color _statusColor(BuildContext context, String status) {
    switch (status) {
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

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pago':
        return Icons.check_circle;
      case 'pendente':
        return Icons.pending;
      case 'parcial':
        return Icons.money_off;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    double total = (widget.data['valor_total'] ?? 0).toDouble();
    double pago = (widget.data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;
    String status = widget.data['status_pagamento'] ?? 'pendente';

    final Color statusColor = _statusColor(context, status);
    final Color onStatus = _readableOn(statusColor);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.uai.surface,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle para arrastar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.uai.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cabeçalho com botões de ação
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.uai.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.receipt,
                      color: context.uai.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'DETALHES DA VENDA',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.uai.textPrimary,
                    ),
                  ),
                  const Spacer(),

                  // Botão EDITAR
                  if (widget.podeEditar && widget.onEditar != null)
                    IconButton(
                      icon: Icon(Icons.edit, color: context.uai.info),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEditar!.call(widget.docId, widget.data);
                      },
                      tooltip: 'Editar venda',
                    ),

                  // 🔥 BOTÃO EXCLUIR
                  if (widget.podeExcluir && widget.onExcluir != null)
                    IconButton(
                      icon: Icon(Icons.delete, color: context.uai.error),
                      onPressed: () => _confirmarExclusao(context),
                      tooltip: 'Excluir venda',
                    ),

                  IconButton(
                    icon: Icon(Icons.print, color: context.uai.textSecondary),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                          const Text('Funcionalidade em desenvolvimento'),
                          backgroundColor: context.uai.warning,
                        ),
                      );
                    },
                  ),
                ],
              ),

              Divider(height: 24, color: context.uai.border),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Informações do aluno
                    _buildInfoSection(
                      context,
                      title: 'ALUNO',
                      icon: Icons.person,
                      children: [
                        _buildInfoRow(context,
                            'Nome', widget.data['aluno_nome'] ?? 'N/I'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Informações da venda
                    _buildInfoSection(
                      context,
                      title: 'INFORMAÇÕES DA VENDA',
                      icon: Icons.sell,
                      children: [
                        _buildInfoRow(context, 'Data',
                            _formatarData(widget.data['data_venda'])),
                        _buildInfoRow(
                          context,
                          'Vendedor',
                          _carregandoVendedor
                              ? 'Carregando...'
                              : _nomeVendedor,
                        ),
                        _buildInfoRow(
                          context,
                          'Observações',
                          widget.data['observacoes'] ?? 'Sem observações',
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Status do pagamento
                    _buildInfoSection(
                      context,
                      title: 'STATUS DO PAGAMENTO',
                      icon: Icons.payment,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: statusColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _statusIcon(status),
                                color: statusColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(context, 'Total',
                            widget.realFormat.format(total),
                            isBold: true),
                        _buildInfoRow(context, 'Pago',
                            widget.realFormat.format(pago),
                            color: context.uai.success),
                        _buildInfoRow(context, 'Restante',
                            widget.realFormat.format(restante),
                            color: context.uai.error),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Itens da venda
                    _buildInfoSection(
                      context,
                      title:
                      'ITENS (${widget.data['itens']?.length ?? 0})',
                      icon: Icons.shopping_bag,
                      children: [
                        ...(widget.data['itens'] as List? ?? []).map((item) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.uai.cardAlt,
                              borderRadius:
                              BorderRadius.circular(context.uai.inputRadius),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['nome'] ?? 'Item',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: context.uai.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        '${item['quantidade']} x ${widget.realFormat.format(item['preco_unitario'])}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.uai.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  widget.realFormat.format(
                                      (item['quantidade'] ?? 1) *
                                          (item['preco_unitario'] ?? 0)),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: context.uai.success,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Histórico de pagamentos
                    if (widget.data['pagamentos'] != null &&
                        widget.data['pagamentos'].length > 0)
                      _buildInfoSection(
                        context,
                        title: 'HISTÓRICO DE PAGAMENTOS',
                        icon: Icons.history,
                        children: [
                          ...(widget.data['pagamentos'] as List)
                              .map((pagamento) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.uai.cardAlt,
                                borderRadius: BorderRadius.circular(
                                    context.uai.inputRadius),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: context.uai.success,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.realFormat.format(
                                              pagamento['valor']),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: context.uai.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          _formatarData(pagamento['data']),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: context.uai.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.uai.info.withOpacity(0.15),
                                      borderRadius:
                                      BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      pagamento['forma']
                                          ?.toUpperCase()
                                          .replaceAll('_', ' ') ??
                                          '',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: context.uai.info,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),

                    const SizedBox(height: 24),

                    // Botão de pagamento (se necessário)
                    if (status != 'pago')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onRegistrarPagamento(
                                widget.docId, widget.data, restante);
                          },
                          icon: const Icon(Icons.payment),
                          label: Text(
                            restante > 0
                                ? 'REGISTRAR PAGAMENTO (${widget.realFormat.format(restante)})'
                                : 'REGISTRAR PAGAMENTO',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.uai.success,
                            foregroundColor:
                            _readableOn(context.uai.success),
                            minimumSize: const Size(double.infinity, 50),
                          ),
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

  // ---------------------------------------------------------------------------
  // Widgets auxiliares já tematizados
  // ---------------------------------------------------------------------------
  Widget _buildInfoSection(
      BuildContext context, {
        required String title,
        required IconData icon,
        required List<Widget> children,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: context.uai.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: context.uai.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(
      BuildContext context,
      String label,
      String value, {
        bool isBold = false,
        Color? color,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: context.uai.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color ?? context.uai.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}