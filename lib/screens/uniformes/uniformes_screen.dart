import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/services/permissao_service.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'package:uai_capoeira/services/usuario_service.dart';

// Widgets
import 'resumo_cards.dart';
import 'item_estoque_card.dart';
import 'venda_card.dart';
import 'pendencia_card.dart';
import 'pedido_card.dart';

// Telas
import 'adicionar_estoque_screen.dart';
import 'nova_venda_screen.dart';
import 'novo_pedido_screen.dart';
import 'relatorio_financeiro_screen.dart';
import 'editar_venda_screen.dart';
import 'editar_pedido_screen.dart';

// Dialogs
import 'dialogs/quantidade_dialog.dart';
import 'dialogs/pagamento_dialog.dart';
import 'package:uai_capoeira/widgets/detalhes_venda_bottom_sheet.dart';

class UniformesScreen extends StatefulWidget {
  const UniformesScreen({super.key});

  @override
  State<UniformesScreen> createState() => _UniformesScreenState();
}

class _UniformesScreenState extends State<UniformesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final PermissaoService _permissaoService = PermissaoService();
  final UniformesService _uniformesService = UniformesService();
  final UsuarioService _usuarioService = UsuarioService();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Permissões
  bool _podeEditar = false;
  bool _podeExcluir = false;
  bool _carregandoPermissoes = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _verificarPermissoes();
    _verificarPermissoesEdicao();
  }

  Future<void> _verificarPermissoes() async {
    final temPermissao = await _permissaoService.temPermissao('podeAcessarUniformes');
    if (!temPermissao && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para acessar esta área'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _verificarPermissoesEdicao() async {
    final uid = currentUser?.uid;

    if (uid != null) {
      try {
        // Buscar permissões específicas
        final permissoesDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get();

        if (permissoesDoc.exists) {
          final permissoes = permissoesDoc.data()!;
          _podeEditar = permissoes['pode_editar_venda'] ?? false;
          _podeExcluir = permissoes['pode_excluir_venda'] ?? false;
        } else {
          // Fallback para peso_permissao
          final userDoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data()!;
            final peso = userData['peso_permissao'] ?? 0;
            _podeEditar = peso >= 100;
            _podeExcluir = peso >= 100;
          }
        }
      } catch (e) {
        print('Erro ao verificar permissões: $e');
      }
    }

    if (mounted) {
      setState(() {
        _carregandoPermissoes = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'GESTÃO DE UNIFORMES',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.green.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.inventory), text: 'ESTOQUE'),
            Tab(icon: Icon(Icons.sell), text: 'VENDAS'),
            Tab(icon: Icon(Icons.payment), text: 'PENDÊNCIAS'),
            Tab(icon: Icon(Icons.shopping_cart), text: 'PEDIDOS'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            tooltip: 'Nova Venda',
            onPressed: () => _abrirNovaVenda(),
          ),
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: 'Adicionar ao Estoque',
            onPressed: () => _abrirAdicionarEstoque(),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Relatório Financeiro',
            onPressed: () => _abrirRelatorioFinanceiro(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          ResumoCards(
            realFormat: _realFormat,
            onNovaVenda: _abrirNovaVenda,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEstoqueTab(),
                _buildVendasTab(),
                _buildPendenciasTab(),
                _buildPedidosTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovaVenda,
        backgroundColor: Colors.green.shade900,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'NOVA VENDA',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Pesquisar...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  // ==================== ABA ESTOQUE ====================
  Widget _buildEstoqueTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('uniformes_estoque')
          .where('status', isEqualTo: 'ativo')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 50, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text('Erro ao carregar estoque: ${snapshot.error}'),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Nenhum item no estoque',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _abrirAdicionarEstoque,
                  icon: const Icon(Icons.add),
                  label: const Text('ADICIONAR ITEM'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade900,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }

        var itens = snapshot.data!.docs.where((doc) {
          if (_searchQuery.isEmpty) return true;
          var data = doc.data() as Map<String, dynamic>;
          String nome = data['nome'] ?? '';
          String categoria = data['categoria'] ?? '';
          String tamanho = data['tamanho'] ?? '';
          return nome.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              categoria.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              tamanho.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: itens.length,
          itemBuilder: (context, index) {
            var doc = itens[index];
            var data = doc.data() as Map<String, dynamic>;
            return ItemEstoqueCard(
              docId: doc.id,
              data: data,
              realFormat: _realFormat,
              onEditar: _editarItemEstoque,
              onRegistrarEntrada: _registrarEntrada,
              onRegistrarSaida: _registrarSaida,
            );
          },
        );
      },
    );
  }

  // ==================== ABA VENDAS ====================
  Widget _buildVendasTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vendas_uniformes')
          .orderBy('data_venda', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var vendas = snapshot.data?.docs ?? [];

        if (vendas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma venda registrada',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        if (_searchQuery.isNotEmpty) {
          vendas = vendas.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return (data['aluno_nome'] ?? '')
                .toLowerCase()
                .contains(_searchQuery.toLowerCase());
          }).toList();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: vendas.length,
          itemBuilder: (context, index) {
            var doc = vendas[index];
            var data = doc.data() as Map<String, dynamic>;
            return VendaCard(
              docId: doc.id,
              data: data,
              realFormat: _realFormat,
              onTap: _abrirDetalhesVenda,
              podeEditar: _podeEditar,
              podeExcluir: _podeExcluir,
            );
          },
        );
      },
    );
  }

  // ==================== ABA PENDÊNCIAS ====================
  Widget _buildPendenciasTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vendas_uniformes')
          .where('status_pagamento', whereIn: ['pendente', 'parcial'])
          .orderBy('data_venda', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var vendasPendentes = snapshot.data?.docs ?? [];

        if (vendasPendentes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 80, color: Colors.green.shade400),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma pendência!',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const Text('Todas as vendas estão pagas'),
              ],
            ),
          );
        }

        double totalPendente = 0;
        for (var doc in vendasPendentes) {
          var data = doc.data() as Map<String, dynamic>;
          totalPendente += (data['valor_total'] ?? 0).toDouble() - (data['valor_pago'] ?? 0).toDouble();
        }

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL PENDENTE',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        _realFormat.format(totalPendente),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${vendasPendentes.length} venda(s)',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: vendasPendentes.length,
                itemBuilder: (context, index) {
                  var doc = vendasPendentes[index];
                  var data = doc.data() as Map<String, dynamic>;
                  return PendenciaCard(
                    docId: doc.id,
                    data: data,
                    realFormat: _realFormat,
                    onRegistrarPagamento: _registrarPagamento,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ==================== ABA PEDIDOS ====================
  Widget _buildPedidosTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pedidos_uniformes')
          .orderBy('data_pedido', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var pedidos = snapshot.data?.docs ?? [];

        if (pedidos.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Nenhum pedido de encomenda',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _abrirNovoPedido,
                  icon: const Icon(Icons.add),
                  label: const Text('NOVO PEDIDO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }

        if (_searchQuery.isNotEmpty) {
          pedidos = pedidos.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return (data['aluno_nome'] ?? '')
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
                (data['id_pedido'] ?? '')
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase());
          }).toList();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: pedidos.length,
          itemBuilder: (context, index) {
            var doc = pedidos[index];
            var data = doc.data() as Map<String, dynamic>;
            return PedidoCard(
              docId: doc.id,
              data: data,
              realFormat: _realFormat,
              onMarcarConfeccao: _marcarPedidoComoConfeccao,
              onFinalizar: _marcarPedidoComoFinalizado,
              onRegistrarPagamento: _registrarPagamentoPedido,
              onEditar: _podeEditar ? _editarPedido : null,
              onExcluir: _podeExcluir ? _excluirPedido : null,
              podeEditar: _podeEditar,
              podeExcluir: _podeExcluir,
              onTap: _abrirDetalhesPedido,
            );
          },
        );
      },
    );
  }

  // ==================== MÉTODOS DE NAVEGAÇÃO ====================

  void _abrirNovaVenda() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NovaVendaScreen(),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _abrirAdicionarEstoque() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdicionarEstoqueScreen(),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _abrirRelatorioFinanceiro() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RelatorioFinanceiroScreen(),
      ),
    );
  }

  void _abrirNovoPedido() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NovoPedidoScreen(),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _editarItemEstoque(String docId, Map<String, dynamic> data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdicionarEstoqueScreen(
          itemId: docId,
          itemData: data,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  // ==================== MÉTODOS DE ESTOQUE ====================

  void _registrarEntrada(String docId, Map<String, dynamic> data) {
    _showQuantidadeDialog(
      titulo: 'Registrar Entrada',
      itemNome: data['nome'],
      precoUnitario: data['preco_venda']?.toDouble(),
      onConfirm: (quantidade) async {
        int novaQuantidade = (data['quantidade'] ?? 0) + quantidade;
        await FirebaseFirestore.instance
            .collection('uniformes_estoque')
            .doc(docId)
            .update({
          'quantidade': novaQuantidade,
          'ultima_atualizacao': FieldValue.serverTimestamp(),
        });

        await _uniformesService.registrarMovimentacao(
          itemId: docId,
          itemNome: data['nome'],
          tipo: 'entrada',
          quantidade: quantidade,
          quantidadeAnterior: data['quantidade'] ?? 0,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Entrada de $quantidade unidade(s) registrada!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
    );
  }

  void _registrarSaida(String docId, Map<String, dynamic> data) {
    _showQuantidadeDialog(
      titulo: 'Registrar Saída',
      itemNome: data['nome'],
      precoUnitario: data['preco_venda']?.toDouble(),
      maxQuantidade: data['quantidade'],
      onConfirm: (quantidade) async {
        int novaQuantidade = (data['quantidade'] ?? 0) - quantidade;
        if (novaQuantidade < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Quantidade insuficiente em estoque!'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        await FirebaseFirestore.instance
            .collection('uniformes_estoque')
            .doc(docId)
            .update({
          'quantidade': novaQuantidade,
          'ultima_atualizacao': FieldValue.serverTimestamp(),
        });

        await _uniformesService.registrarMovimentacao(
          itemId: docId,
          itemNome: data['nome'],
          tipo: 'saida',
          quantidade: quantidade,
          quantidadeAnterior: data['quantidade'] ?? 0,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Saída de $quantidade unidade(s) registrada!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      },
    );
  }

  void _showQuantidadeDialog({
    required String titulo,
    required String itemNome,
    required Function(int) onConfirm,
    double? precoUnitario,
    int? maxQuantidade,
  }) {
    showDialog(
      context: context,
      builder: (context) => QuantidadeDialog(
        titulo: titulo,
        itemNome: itemNome,
        onConfirm: onConfirm,
        precoUnitario: precoUnitario,
        maxQuantidade: maxQuantidade,
      ),
    );
  }

  // ==================== MÉTODOS DE PAGAMENTO ====================

  void _registrarPagamento(String docId, Map<String, dynamic> data, double valorRestante) {
    if (valorRestante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta venda já está totalmente paga!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => PagamentoDialog(
        alunoNome: data['aluno_nome'] ?? 'Aluno',
        valorTotal: data['valor_total']?.toDouble() ?? 0,
        valorPago: data['valor_pago']?.toDouble() ?? 0,
        valorRestante: valorRestante,
        onConfirm: (valor, formaPagamento) async {
          try {
            await _uniformesService.registrarPagamentoVenda(
              vendaId: docId,
              valorPagamento: valor,
              formaPagamento: formaPagamento,
              vendaData: data,
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Pagamento de ${_realFormat.format(valor)} registrado!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Erro ao registrar pagamento: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _registrarPagamentoPedido(String docId, Map<String, dynamic> data) async {
    double total = (data['valor_total'] ?? 0).toDouble();
    double pago = (data['valor_pago'] ?? 0).toDouble();
    double restante = total - pago;

    if (restante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este pedido já está totalmente pago!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => PagamentoDialog(
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

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Pagamento de ${_realFormat.format(valor)} registrado!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Erro ao registrar pagamento: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  // ==================== MÉTODOS DE DETALHES ====================

  void _abrirDetalhesVenda(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DetalhesVendaBottomSheet(
        docId: docId,
        data: data,
        realFormat: _realFormat,
        onRegistrarPagamento: _registrarPagamento,
        onEditar: _podeEditar ? _editarVenda : null,
        onExcluir: _podeExcluir ? _excluirVenda : null,
        podeEditar: _podeEditar,
        podeExcluir: _podeExcluir,
      ),
    );
  }

  void _abrirDetalhesPedido(String docId, Map<String, dynamic> data) {
    // TODO: Implementar bottom sheet de detalhes do pedido
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Detalhes do pedido em desenvolvimento'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ==================== MÉTODOS DE EDIÇÃO/EXCLUSÃO CORRIGIDOS ====================

  void _editarVenda(String docId, Map<String, dynamic> data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarVendaScreen(
          vendaId: docId,
          vendaData: data,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Venda atualizada!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ✅ MÉTODO CORRIGIDO - EXCLUIR VENDA
  void _excluirVenda(String docId, Map<String, dynamic> data) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir esta venda?\n\n'
              'Aluno: ${data['aluno_nome']}\n'
              'Valor: ${_realFormat.format(data['valor_total'] ?? 0)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('vendas_uniformes')
          .doc(docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Venda excluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editarPedido(String docId, Map<String, dynamic> data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarPedidoScreen(
          pedidoId: docId,
          pedidoData: data,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pedido atualizado!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ✅ MÉTODO CORRIGIDO - EXCLUIR PEDIDO
  void _excluirPedido(String docId, Map<String, dynamic> data) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir este pedido?\n\n'
              'Pedido: ${data['id_pedido'] ?? 'N/I'}\n'
              'Aluno: ${data['aluno_nome']}\n'
              'Valor: ${_realFormat.format(data['valor_total'] ?? 0)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('pedidos_uniformes')
          .doc(docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Pedido excluído com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==================== MÉTODOS DE PEDIDOS ====================

  Future<void> _marcarPedidoComoConfeccao(String docId, Map<String, dynamic> data) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'em_confeccao');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pedido marcado como EM CONFECÇÃO'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao atualizar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _marcarPedidoComoFinalizado(String docId, Map<String, dynamic> data) async {
    try {
      await _uniformesService.atualizarStatusPedido(docId, 'finalizado');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pedido finalizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao finalizar pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}