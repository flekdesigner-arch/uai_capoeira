import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/services/permissao_service.dart';
import 'package:uai_capoeira/services/uniformes_service.dart';
import 'package:uai_capoeira/services/remessa_service.dart';
import 'package:uai_capoeira/services/usuario_service.dart';

// Widgets
import 'resumo_cards.dart';
import 'item_estoque_card.dart';
import 'venda_card.dart';
import 'pendencia_card.dart';
import 'pedido_card.dart';
import 'remessa_card.dart';

// Telas
import 'adicionar_estoque_screen.dart';
import 'nova_venda_screen.dart';
import 'novo_pedido_screen.dart';
import 'relatorio_financeiro_screen.dart';
import 'editar_venda_screen.dart';
import 'editar_pedido_screen.dart';
import 'remessa_form_screen.dart';
import 'remessa_detalhes_screen.dart';
import 'fornecedores_list_screen.dart';

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
  final RemessaService _remessaService = RemessaService();
  final UsuarioService _usuarioService = UsuarioService();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _podeEditar = false;
  bool _podeExcluir = false;
  bool _carregandoPermissoes = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
    if (mounted) setState(() => _carregandoPermissoes = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onAddPressed() {
    switch (_tabController.index) {
      case 0:
        _abrirAdicionarEstoque();
        break;
      case 1:
        _abrirNovaVenda();
        break;
      case 2:
        break;
      case 3:
        _abrirNovoPedido();
        break;
      case 4:
        _abrirNovaRemessa();
        break;
    }
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
            Tab(icon: Icon(Icons.local_shipping), text: 'REMESSAS'),
          ],
        ),
        actions: [
          if (_tabController.index != 2)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 28),
              tooltip: _getAddTooltip(),
              onPressed: _onAddPressed,
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Relatório Financeiro',
            onPressed: () => _abrirRelatorioFinanceiro(),
          ),
          if (_tabController.index == 4)
            IconButton(
              icon: const Icon(Icons.business),
              tooltip: 'Fornecedores',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FornecedoresListScreen()),
                );
                if (mounted) setState(() {});
              },
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
                _buildRemessasTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getAddTooltip() {
    switch (_tabController.index) {
      case 0: return 'Adicionar ao Estoque';
      case 1: return 'Nova Venda';
      case 3: return 'Novo Pedido';
      case 4: return 'Nova Remessa';
      default: return 'Adicionar';
    }
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

  // ==================== ABA ESTOQUE (CATEGORIAS EXPANSÍVEIS) ====================
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

        var categorias = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          final tipo = data['tipo'] as String?;
          if (tipo != null && tipo != 'base') return false;
          if (_searchQuery.isEmpty) return true;
          String nome = data['nome'] ?? '';
          return nome.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: categorias.length,
          itemBuilder: (context, index) {
            var doc = categorias[index];
            var data = doc.data() as Map<String, dynamic>;
            final bool isBase = data['tipo'] == 'base';
            if (isBase) {
              return _CategoriaEstoqueExpansivel(
                categoriaId: doc.id,
                categoriaData: data,
                realFormat: _realFormat,
                onEditarItem: _editarItemEstoque,
                onRegistrarEntrada: _registrarEntrada,
                onRegistrarSaida: _registrarSaida,
                onExcluirItem: _excluirItemEstoque,
                // 🔥 NOVO CALLBACK
                onExcluirCategoria: () => _excluirCategoriaEstoque(doc.id, data),
              );
            } else {
              final int quantidade = data['quantidade'] ?? 0;
              return ItemEstoqueCard(
                docId: doc.id,
                data: data,
                realFormat: _realFormat,
                onEditar: _editarItemEstoque,
                onRegistrarEntrada: _registrarEntrada,
                onRegistrarSaida: _registrarSaida,
                onExcluir: quantidade == 0
                    ? (docId, data) => _excluirItemEstoque(docId, data)
                    : null,
              );
            }
          },
        );
      },
    );
  }

  // 🔥 EXCLUIR CATEGORIA INTEIRA (BASE + VARIAÇÕES)
  Future<void> _excluirCategoriaEstoque(String categoriaId, Map<String, dynamic> data) async {
    try {
      // Exclui todas as variações vinculadas
      final variacoes = await FirebaseFirestore.instance
          .collection('uniformes_estoque')
          .where('item_base_id', isEqualTo: categoriaId)
          .get();
      for (var doc in variacoes.docs) {
        await doc.reference.delete();
      }
      // Exclui a categoria base
      await FirebaseFirestore.instance.collection('uniformes_estoque').doc(categoriaId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Categoria "${data['nome']}" e suas variações foram excluídas!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao excluir categoria: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  // ==================== ABA REMESSAS ====================
  Widget _buildRemessasTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _remessaService.getTodasRemessas(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var remessas = snapshot.data?.docs ?? [];
        if (remessas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_shipping_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma remessa cadastrada',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _abrirNovaRemessa,
                  icon: const Icon(Icons.add),
                  label: const Text('NOVA REMESSA'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }

        if (_searchQuery.isNotEmpty) {
          remessas = remessas.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return (data['nome'] ?? '')
                .toLowerCase()
                .contains(_searchQuery.toLowerCase());
          }).toList();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: remessas.length,
          itemBuilder: (context, index) {
            var doc = remessas[index];
            var data = doc.data() as Map<String, dynamic>;
            return RemessaCard(
              remessaId: doc.id,
              data: data,
              onTap: () => _abrirDetalhesRemessa(doc.id, data),
              onEditar: () => _editarRemessa(doc.id, data),
              onExcluir: () => _excluirRemessa(doc.id, data),
            );
          },
        );
      },
    );
  }

  // ==================== NAVEGAÇÃO ====================
  void _abrirNovaVenda() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NovaVendaScreen()),
    );
    if (result == true && mounted) setState(() {});
  }

  void _abrirAdicionarEstoque() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdicionarEstoqueScreen()),
    );
    if (result == true && mounted) setState(() {});
  }

  void _abrirRelatorioFinanceiro() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RelatorioFinanceiroScreen()),
    );
  }

  void _abrirNovoPedido() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NovoPedidoScreen()),
    );
    if (result == true && mounted) setState(() {});
  }

  void _editarItemEstoque(String docId, Map<String, dynamic> data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdicionarEstoqueScreen(itemId: docId, itemData: data),
      ),
    );
    if (result == true && mounted) setState(() {});
  }

  void _abrirNovaRemessa() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RemessaFormScreen()),
    );
    if (result == true) setState(() {});
  }

  void _editarRemessa(String remessaId, Map<String, dynamic> data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RemessaFormScreen(remessaId: remessaId, remessaData: data),
      ),
    );
    if (result == true) setState(() {});
  }

  void _abrirDetalhesRemessa(String remessaId, Map<String, dynamic> data) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RemessaDetalhesScreen(remessaId: remessaId, remessaData: data),
      ),
    );
    setState(() {});
  }

  void _excluirRemessa(String remessaId, Map<String, dynamic> data) async {
    final pedidosSnapshot = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .get();
    final qtdPedidos = pedidosSnapshot.docs.length;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Excluir Remessa'),
        content: Text(
          qtdPedidos > 0
              ? 'Esta remessa possui $qtdPedidos pedido(s) vinculado(s). '
              'Ao excluir a remessa, todos esses pedidos também serão excluídos permanentemente. Deseja continuar?'
              : 'Tem certeza que deseja excluir esta remessa?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir tudo'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      for (var doc in pedidosSnapshot.docs) {
        await doc.reference.delete();
      }
      await _remessaService.excluirRemessa(remessaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(qtdPedidos > 0
                ? '✅ Remessa e $qtdPedidos pedido(s) excluídos!'
                : '✅ Remessa excluída!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao excluir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== REGRAS DE REMESSA ↔ PEDIDOS ====================
  Future<void> _alterarStatusRemessa(String remessaId, String novoStatus) async {
    if (novoStatus == 'em_confeccao') {
      final pedidos = await FirebaseFirestore.instance
          .collection('pedidos_uniformes')
          .where('remessa_id', isEqualTo: remessaId)
          .get();
      for (var doc in pedidos.docs) {
        await doc.reference.update({'status': 'em_confeccao'});
      }
    }
    await _remessaService.atualizarRemessa(remessaId, {'status': novoStatus});
    setState(() {});
  }

  Future<bool> _verificarSePodeFinalizarRemessa(String remessaId) async {
    final pedidos = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .get();
    if (pedidos.docs.isEmpty) return true;
    for (var doc in pedidos.docs) {
      final data = doc.data();
      final status = data['status'] as String?;
      final statusPgto = data['status_pagamento'] as String?;
      if (status != 'finalizado' || statusPgto != 'pago') {
        return false;
      }
    }
    return true;
  }

  void _mostrarDialogoPedidosPendentes(String acao) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ação não permitida'),
        content: const Text(
            'Todos os pedidos vinculados devem estar finalizados e pagos antes de finalizar/excluir a remessa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi')),
        ],
      ),
    );
  }

  // ==================== ESTOQUE ====================
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
      builder: (_) => QuantidadeDialog(
        titulo: titulo,
        itemNome: itemNome,
        onConfirm: onConfirm,
        precoUnitario: precoUnitario,
        maxQuantidade: maxQuantidade,
      ),
    );
  }

  Future<void> _excluirItemEstoque(String docId, Map<String, dynamic> data) async {
    try {
      await FirebaseFirestore.instance.collection('uniformes_estoque').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Item "${data['nome']}" excluído do estoque!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao excluir item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==================== PAGAMENTOS ====================
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
      builder: (_) => PagamentoDialog(
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

  // ==================== DETALHES ====================
  void _abrirDetalhesVenda(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DetalhesVendaBottomSheet(
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Detalhes do pedido em desenvolvimento'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ==================== EDIÇÃO/EXCLUSÃO ====================
  void _editarVenda(String docId, Map<String, dynamic> data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarVendaScreen(vendaId: docId, vendaData: data),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Venda atualizada!'), backgroundColor: Colors.green),
      );
    }
  }

  void _excluirVenda(String docId, Map<String, dynamic> data) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir esta venda?\n\n'
              'Aluno: ${data['aluno_nome']}\n'
              'Valor: ${_realFormat.format(data['valor_total'] ?? 0)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
          const SnackBar(content: Text('✅ Venda excluída com sucesso!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao excluir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _editarPedido(String docId, Map<String, dynamic> data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarPedidoScreen(pedidoId: docId, pedidoData: data),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Pedido atualizado!'), backgroundColor: Colors.green),
      );
    }
  }

  void _excluirPedido(String docId, Map<String, dynamic> data) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir este pedido?\n\n'
              'Pedido: ${data['id_pedido'] ?? 'N/I'}\n'
              'Aluno: ${data['aluno_nome']}\n'
              'Valor: ${_realFormat.format(data['valor_total'] ?? 0)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final remessaId = data['remessa_id'] as String?;
      if (remessaId != null && remessaId.isNotEmpty) {
        await _remessaService.desvincularPedido(docId, remessaId);
      }

      await FirebaseFirestore.instance
          .collection('pedidos_uniformes')
          .doc(docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Pedido excluído com sucesso!'), backgroundColor: Colors.green),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao excluir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== STATUS DE PEDIDOS ====================
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

// ==================== WIDGET AUXILIAR: CATEGORIA EXPANSÍVEL (COM EXCLUSÃO) ====================
class _CategoriaEstoqueExpansivel extends StatefulWidget {
  final String categoriaId;
  final Map<String, dynamic> categoriaData;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onEditarItem;
  final Function(String, Map<String, dynamic>) onRegistrarEntrada;
  final Function(String, Map<String, dynamic>) onRegistrarSaida;
  final Function(String, Map<String, dynamic>) onExcluirItem;
  final VoidCallback? onExcluirCategoria; // 🔥 NOVO

  const _CategoriaEstoqueExpansivel({
    required this.categoriaId,
    required this.categoriaData,
    required this.realFormat,
    required this.onEditarItem,
    required this.onRegistrarEntrada,
    required this.onRegistrarSaida,
    required this.onExcluirItem,
    this.onExcluirCategoria,
  });

  @override
  State<_CategoriaEstoqueExpansivel> createState() => _CategoriaEstoqueExpansivelState();
}

class _CategoriaEstoqueExpansivelState extends State<_CategoriaEstoqueExpansivel> {
  bool _expanded = false;

  Color _getCategoriaColor(String? categoria) {
    switch (categoria?.toLowerCase()) {
      case 'camisa': case 'camiseta': return Colors.blue;
      case 'calça': case 'calca': case 'bermuda': return Colors.green;
      case 'abada': case 'corda': return Colors.orange;
      case 'acessório': case 'acessorio': return Colors.purple;
      default: return Colors.grey;
    }
  }

  IconData _getCategoriaIcon(String? categoria) {
    switch (categoria?.toLowerCase()) {
      case 'camisa': case 'camiseta': return Icons.shopping_bag;
      case 'calça': case 'calca': case 'bermuda': return Icons.shopping_bag;
      case 'abada': return Icons.sports_kabaddi;
      case 'corda': return Icons.sensors;
      case 'acessório': case 'acessorio': return Icons.watch;
      default: return Icons.inventory;
    }
  }

  void _confirmarExclusaoCategoria() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir categoria'),
        content: Text(
          'Tem certeza que deseja excluir a categoria "${widget.categoriaData['nome']}"?\n\n'
              'Todos os itens vinculados (variações) também serão excluídos permanentemente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onExcluirCategoria?.call();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir tudo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.categoriaData;
    final String nome = data['nome'] ?? 'Sem nome';
    final String? fotoUrl = data['foto_url'];
    final String categoria = data['categoria'] ?? 'Outro';
    final Color corCat = _getCategoriaColor(categoria);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: corCat.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: fotoUrl != null && fotoUrl.isNotEmpty
              ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(imageUrl: fotoUrl, fit: BoxFit.cover),
          )
              : Icon(_getCategoriaIcon(categoria), color: corCat),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (widget.onExcluirCategoria != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                onPressed: _confirmarExclusaoCategoria,
                tooltip: 'Excluir categoria',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
        subtitle: Text(categoria),
        onExpansionChanged: (expanded) {
          setState(() => _expanded = expanded);
        },
        children: [
          if (_expanded)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('uniformes_estoque')
                  .where('item_base_id', isEqualTo: widget.categoriaId)
                  .where('status', isEqualTo: 'ativo')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final variacoes = snapshot.data!.docs;
                if (variacoes.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nenhuma variação disponível'),
                  );
                }
                return Column(
                  children: variacoes.map((doc) {
                    var varData = doc.data() as Map<String, dynamic>;
                    final int quantidade = varData['quantidade'] ?? 0;
                    return ItemEstoqueCard(
                      docId: doc.id,
                      data: varData,
                      realFormat: widget.realFormat,
                      onEditar: widget.onEditarItem,
                      onRegistrarEntrada: widget.onRegistrarEntrada,
                      onRegistrarSaida: widget.onRegistrarSaida,
                      onExcluir: quantidade == 0
                          ? widget.onExcluirItem
                          : null,
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}