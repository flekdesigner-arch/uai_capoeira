import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/services/usuario_service.dart';

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
  State<DetalhesVendaBottomSheet> createState() => _DetalhesVendaBottomSheetState();
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

  // 🔥 MÉTODO CORRIGIDO - VERSÃO SUPER SIMPLES
  void _confirmarExclusao(BuildContext context) {
    // Guarda o contexto do bottom sheet ANTES de abrir o dialog
    final bottomSheetContext = context;

    // Abre o dialog
    showDialog(
      context: context,
      barrierDismissible: false, // Impede fechar clicando fora
      builder: (dialogContext) => AlertDialog(
        title: const Text('🗑️ Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir esta venda?\n\n'
              'Aluno: ${widget.data['aluno_nome']}\n'
              'Valor: ${widget.realFormat.format(widget.data['valor_total'] ?? 0)}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Fecha só o dialog
            },
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              // Fecha o dialog
              Navigator.pop(dialogContext);

              // Fecha o bottom sheet (usando o contexto guardado)
              Navigator.pop(bottomSheetContext);

              // Chama a exclusão
              widget.onExcluir?.call(widget.docId, widget.data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double total = (widget.data['valor_total'] ?? 0).toDouble();
    double pago = (widget.data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;
    String status = widget.data['status_pagamento'] ?? 'pendente';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Colors.grey.shade300,
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
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt, color: Colors.green),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'DETALHES DA VENDA',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),

                  // Botão EDITAR
                  if (widget.podeEditar && widget.onEditar != null)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEditar!.call(widget.docId, widget.data);
                      },
                      tooltip: 'Editar venda',
                    ),

                  // 🔥 BOTÃO EXCLUIR - CHAMA O MÉTODO SIMPLES
                  if (widget.podeExcluir && widget.onExcluir != null)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmarExclusao(context),
                      tooltip: 'Excluir venda',
                    ),

                  IconButton(
                    icon: const Icon(Icons.print),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Funcionalidade em desenvolvimento')),
                      );
                    },
                  ),
                ],
              ),

              const Divider(height: 24),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Informações do aluno
                    _buildInfoSection(
                      title: 'ALUNO',
                      icon: Icons.person,
                      children: [
                        _buildInfoRow('Nome', widget.data['aluno_nome'] ?? 'N/I'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Informações da venda
                    _buildInfoSection(
                      title: 'INFORMAÇÕES DA VENDA',
                      icon: Icons.sell,
                      children: [
                        _buildInfoRow('Data', _formatarData(widget.data['data_venda'])),
                        _buildInfoRow(
                          'Vendedor',
                          _carregandoVendedor ? 'Carregando...' : _nomeVendedor,
                        ),
                        _buildInfoRow('Observações', widget.data['observacoes'] ?? 'Sem observações'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Status do pagamento
                    _buildInfoSection(
                      title: 'STATUS DO PAGAMENTO',
                      icon: Icons.payment,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _getStatusIcon(status),
                                color: _getStatusColor(status),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: _getStatusColor(status),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow('Total', widget.realFormat.format(total), isBold: true),
                        _buildInfoRow('Pago', widget.realFormat.format(pago), color: Colors.green),
                        _buildInfoRow('Restante', widget.realFormat.format(restante), color: Colors.red),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Itens da venda
                    _buildInfoSection(
                      title: 'ITENS (${widget.data['itens']?.length ?? 0})',
                      icon: Icons.shopping_bag,
                      children: [
                        ...(widget.data['itens'] as List? ?? []).map((item) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['nome'] ?? 'Item',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        '${item['quantidade']} x ${widget.realFormat.format(item['preco_unitario'])}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  widget.realFormat.format(
                                      (item['quantidade'] ?? 1) * (item['preco_unitario'] ?? 0)
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
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
                    if (widget.data['pagamentos'] != null && widget.data['pagamentos'].length > 0)
                      _buildInfoSection(
                        title: 'HISTÓRICO DE PAGAMENTOS',
                        icon: Icons.history,
                        children: [
                          ...(widget.data['pagamentos'] as List).map((pagamento) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.green.shade400,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.realFormat.format(pagamento['valor']),
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        Text(
                                          _formatarData(pagamento['data']),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
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
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      pagamento['forma']?.toUpperCase().replaceAll('_', ' ') ?? '',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.purple.shade700,
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
                            widget.onRegistrarPagamento(widget.docId, widget.data, restante);
                          },
                          icon: const Icon(Icons.payment),
                          label: Text(
                            restante > 0
                                ? 'REGISTRAR PAGAMENTO (${widget.realFormat.format(restante)})'
                                : 'REGISTRAR PAGAMENTO',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
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

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pago':
        return Colors.green;
      case 'pendente':
        return Colors.orange;
      case 'parcial':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
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
}