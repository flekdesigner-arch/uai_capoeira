import '../admin/uniformes_auditoria_screen.dart';
import '../services/uniformes_admin_service.dart';
import '../../../core/permissions/permission_access_guard.dart';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/uniformes_service.dart';
import 'package:uai_capoeira/modules/uniformes/services/remessa_service.dart';

// Widgets
import 'package:uai_capoeira/modules/uniformes/widgets/resumo_cards.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/item_estoque_card.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/venda_card.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/pendencia_card.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/pedido_card.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/remessa_card.dart';

// Telas
import 'adicionar_estoque_screen.dart';
import 'nova_venda_screen.dart';
import 'package:uai_capoeira/modules/uniformes/reports/relatorio_financeiro_screen.dart';
import 'editar_venda_screen.dart';
import 'editar_pedido_screen.dart';
import 'remessa_form_screen.dart';
import 'remessa_detalhes_screen.dart';
import 'fornecedores_list_screen.dart';

// Dialogs
import 'package:uai_capoeira/modules/uniformes/dialogs/quantidade_dialog.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/pagamento_dialog.dart';
import 'package:uai_capoeira/modules/uniformes/dialogs/pedidos_relatorio_dialog.dart';
import 'package:uai_capoeira/modules/uniformes/widgets/detalhes_venda_bottom_sheet.dart';

bool get _uaiUniformesWindowsSafeMode =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// No Windows evitamos listeners realtime do cloud_firestore neste modulo.
/// O plugin nativo estava emitindo query/document fora da platform thread e
/// derrubando o processo. Android/Web continuam realtime.
Stream<QuerySnapshot> _uaiUniformesQueryStream(Query query) {
  if (_uaiUniformesWindowsSafeMode) {
    return Stream<QuerySnapshot>.fromFuture(
      query.get(const GetOptions(source: Source.serverAndCache)),
    );
  }
  return query.snapshots();
}

class UniformesScreen extends StatefulWidget {
  const UniformesScreen({super.key});

  @override
  State<UniformesScreen> createState() => _UniformesScreenState();
}

class _UniformesScreenState extends State<UniformesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final PermissaoService _permissaoService = PermissaoService();
  final UniformesService _uniformesService = UniformesService();
  final RemessaService _remessaService = RemessaService();
  final NumberFormat _realFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _podeEditar = false;
  bool _podeExcluir = false;
  bool _admin100 = false;
  Map<String, bool> _permissions = {};
  bool _can(String key) => _permissions[key] == true;
  Future<bool> _allow(String key) => PermissionAccessGuard().revalidate(
    context,
    permission: key,
    message: 'Sem permissão para esta operação de Uniformes.',
  );
  bool _acaoVendaEmAndamento = false;
  int _dadosRevision = 0;
  bool _cicloCarregado = false;
  String? _cicloAtualId;
  String? _cicloErro;

  bool _documentoDoCiclo(QueryDocumentSnapshot doc) {
    if (_cicloAtualId == null) return true; // Modo legado pré-ativação.
    final dados = doc.data();
    return dados is Map<String, dynamic> && dados['ciclo_id'] == _cicloAtualId;
  }

  Future<void> _carregarCicloAtual() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('uniformes_config').doc('ciclo_atual')
          .get(const GetOptions(source: Source.server));
      final dados = snap.data();
      if (!mounted) return;
      setState(() {
        _cicloAtualId = null;
        if (dados?['estado'] == 'ativo') {
          final id = dados?['ciclo_id'];
          if (id is String) {
            _cicloAtualId = id;
          }
        }
        _cicloErro = dados?['estado'] == 'ativando'
            ? 'Virada de ciclo em andamento. Reabra após a conclusão.' : null;
        _cicloCarregado = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cicloCarregado = true;
          _cicloErro = 'Não foi possível confirmar o ciclo ativo no servidor: $e';
        });
      }
    }
  }

  void _atualizarDadosUniformes() {
    _carregarCicloAtual();
    if (mounted) setState(() => _dadosRevision++);
  }

  void _feedbackPagamentoConfirmado(double valor) {
    if (!mounted) return;
    _atualizarDadosUniformes();
    final t = context.uai;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: t.success,
      duration: const Duration(seconds: 3),
      content: Row(children: [
        Icon(Icons.verified_rounded, color: _readableOn(t.success)),
        const SizedBox(width: 10),
        Expanded(child: Text('Pagamento de ${_realFormat.format(valor)} confirmado. Dados atualizados.',
          style: TextStyle(fontWeight: FontWeight.w700, color: _readableOn(t.success)))),
      ]),
    ));
  }

  // IDs confirmados como excluídos nesta sessão. Protege a UI contra um
  // snapshot local/stale do Firestore (especialmente no Windows).
  final Set<String> _vendasExcluidasLocal = <String>{};
  final Set<String> _pedidosExcluidosLocal = <String>{};
  final Set<String> _remessasExcluidasLocal = <String>{};

  // ---------------------------------------------------------------------------
  // Helpers de contraste
  // ---------------------------------------------------------------------------
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  Color _tabSelectedBg() => _appBarFg();

  Color _tabSelectedFg() => _readableOn(_tabSelectedBg());

  Color _tabUnselectedFg() => _appBarFg().withAlpha(209);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _verificarPermissoes();
    _verificarPermissoesEdicao();
    _carregarCicloAtual();
  }

  Future<void> _verificarPermissoes() async {
    final temPermissao = await _permissaoService.temPermissao(
      'podeAcessarUniformes',
    );
    if (!temPermissao && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Você não tem permissão para acessar esta área'),
          backgroundColor: context.uai.error,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _verificarPermissoesEdicao() async {
    try {
      final keys = [
        'pode_editar_venda',
        'pode_excluir_venda',
        'pode_criar_venda',
        'pode_criar_pedido',
        'pode_editar_pedido',
        'pode_excluir_pedido',
        'pode_registrar_pagamento_uniforme',
        'pode_registrar_pagamento_pedido',
        'pode_alterar_status_pedido',
        'pode_gerenciar_estoque',
        'pode_gerenciar_remessas_uniformes',
        'pode_gerenciar_fornecedores_uniformes',
        'pode_ver_relatorio_uniformes',
        'pode_ver_auditoria_uniformes',
        'pode_registrar_entrega_uniforme',
      ];
      final permissions = await _permissaoService.verificarMultiplasPermissoes(
        keys,
      );
      final admin = await UniformesAdminService().admin100();
      if (mounted) {
        setState(() {
          _permissions = permissions;
          _admin100 = admin;
          _podeEditar = permissions['pode_editar_venda'] == true;
          _podeExcluir = permissions['pode_excluir_venda'] == true;
        });
      }
    } catch (e) {
      developer.log('Erro ao carregar permissões de Uniformes: $e');
    }
  }

  Future<String?> _pedirMotivo(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Motivo (mínimo 3 caracteres)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 3) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _entregarVenda(String id, Map<String, dynamic> data) async {
    if (!await _allow('pode_registrar_entrega_uniforme')) return;
    if (!mounted) return;
    try {
      await _executarAcaoVenda(
        mensagem: 'Registrando entrega...',
        acao: () => _uniformesService.atualizarStatusEntregaVenda(
          vendaId: id,
          statusEntrega: 'entregue',
        ),
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entrega registrada com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível registrar a entrega: $e')),
        );
      }
    }
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
        _abrirNovaRemessa();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        // Mesmo respiro visual da Home / mockup aprovado:
        // barra principal mais alta + navegação de Uniformes em faixa separada.
        toolbarHeight: 64,
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        iconTheme: IconThemeData(color: _appBarFg()),
        actionsIconTheme: IconThemeData(color: _appBarFg()),
        title: Text(
          'GESTÃO DE UNIFORMES',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _appBarFg(),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _appBarFg().withAlpha(20),
              border: Border(top: BorderSide(color: _appBarFg().withAlpha(26))),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
              indicator: BoxDecoration(
                color: _tabSelectedBg(),
                borderRadius: BorderRadius.circular(14),
              ),
              labelColor: _tabSelectedFg(),
              unselectedLabelColor: _tabUnselectedFg(),
              labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              overlayColor: WidgetStatePropertyAll(_appBarFg().withAlpha(20)),
              tabs: const [
                Tab(icon: Icon(Icons.inventory_rounded), text: 'ESTOQUE'),
                Tab(icon: Icon(Icons.sell_rounded), text: 'VENDAS'),
                Tab(icon: Icon(Icons.payment_rounded), text: 'PENDÊNCIAS'),
                Tab(icon: Icon(Icons.local_shipping_rounded), text: 'PEDIDOS / REMESSAS'),
              ],
            ),
          ),
        ),
        actions: [
          if (_tabController.index != 2 && _tabController.index != 3 &&
              (_tabController.index == 0
                  ? _admin100
                  : _tabController.index == 1
                  ? _can('pode_criar_venda')
                  : _can('pode_gerenciar_remessas_uniformes')))
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: _getAddTooltip(),
              onPressed: _onAddPressed,
            ),
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .doc('uniformes_config/politicas')
                .get(),
            builder: (context, policySnapshot) {
              // Fail closed: a opção só aparece após a política ser lida.
              final auditVisible = policySnapshot.hasData &&
                  policySnapshot.data!.data()?['auditoria_visivel'] == true;
              return PopupMenuButton<String>(
            tooltip: 'Mais ações',
            onSelected: (value) async {
              if (value == 'auditoria') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UniformesAuditoriaScreen(),
                  ),
                );
              }
              if (!context.mounted) return;
              if (value == 'relatorio') _abrirRelatorioFinanceiro();
              if (value == 'pedidos') PedidosRelatorioDialog.show(context);
              if (value == 'fornecedores') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FornecedoresListScreen(),
                  ),
                );
                if (mounted) setState(() {});
              }
            },
            itemBuilder: (_) => [
              if (auditVisible && (_admin100 || _can('pode_ver_auditoria_uniformes')))
                const PopupMenuItem(
                  value: 'auditoria',
                  child: Text('Auditoria'),
                ),
              if (_can('pode_ver_relatorio_uniformes'))
                const PopupMenuItem(
                  value: 'relatorio',
                  child: Text('Relatório financeiro'),
                ),
              if (_tabController.index == 3 &&
                  _can('pode_ver_relatorio_uniformes'))
                const PopupMenuItem(
                  value: 'pedidos',
                  child: Text('Relatório de pedidos'),
                ),
              if (_can('pode_gerenciar_fornecedores_uniformes'))
                const PopupMenuItem(
                  value: 'fornecedores',
                  child: Text('Fornecedores'),
                ),
            ],
          );
            },
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 3 &&
              _can('pode_gerenciar_remessas_uniformes')
          ? FloatingActionButton.extended(
              onPressed: _abrirNovaRemessa,
              icon: const Icon(Icons.add_rounded),
              label: const Text('NOVA REMESSA',
                style: TextStyle(fontWeight: FontWeight.w900)),
              backgroundColor: context.uai.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: !_cicloCarregado
          ? const Center(child: CircularProgressIndicator())
          : _cicloErro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: SelectableText(_cicloErro!)))
              : LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth >= 1500
              ? 1420.0
              : constraints.maxWidth >= 1100
              ? 1280.0
              : constraints.maxWidth;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  if (_cicloAtualId != null)
                    Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                      child: Row(children: [
                        Icon(Icons.event_available, size: 17,
                          color: context.uai.success),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Ciclo ativo: $_cicloAtualId · Histórico anterior preservado',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                      ])),
                  _buildSearchBar(),
                  ResumoCards(
                    key: ValueKey('uniformes_resumo_$_dadosRevision'),
                    realFormat: _realFormat,
                    cicloId: _cicloAtualId,
                    onNovaVenda: _abrirNovaVenda,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _uaiUniformesWindowsSafeMode
                        ? _buildCurrentTabWindows()
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildEstoqueTab(),
                              _buildVendasTab(),
                              _buildPendenciasTab(),
                              _buildPedidosRemessasTab(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentTabWindows() {
    switch (_tabController.index) {
      case 0:
        return _buildEstoqueTab();
      case 1:
        return _buildVendasTab();
      case 2:
        return _buildPendenciasTab();
      case 3:
        return _buildPedidosRemessasTab();
      default:
        return _buildEstoqueTab();
    }
  }

  String _getAddTooltip() {
    switch (_tabController.index) {
      case 0:
        return 'Adicionar ao Estoque';
      case 1:
        return 'Nova Venda';
      case 3:
        return 'Nova Remessa';
      default:
        return 'Adicionar';
    }
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: context.uai.textPrimary),
        decoration: InputDecoration(
          hintText: 'Pesquisar...',
          hintStyle: TextStyle(color: context.uai.textMuted),
          prefixIcon: Icon(Icons.search, color: context.uai.textMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: context.uai.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(context.uai.inputRadius),
            borderSide: BorderSide(color: context.uai.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(context.uai.inputRadius),
            borderSide: BorderSide(color: context.uai.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(context.uai.inputRadius),
            borderSide: BorderSide(color: context.uai.primary, width: 1.4),
          ),
          filled: true,
          fillColor: context.uai.cardAlt,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  // ==================== ABA ESTOQUE (CATEGORIAS EXPANSÍVEIS) ====================
  Widget _buildEstoqueTab() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('uniformes_query_1_$_dadosRevision'),
      stream: _uaiUniformesQueryStream(
        FirebaseFirestore.instance
            .collection('uniformes_estoque')
            .where('status', isEqualTo: 'ativo'),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 50, color: context.uai.error),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar estoque: ${snapshot.error}',
                  style: TextStyle(color: context.uai.textPrimary),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 80,
                  color: context.uai.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Nenhum item no estoque',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.uai.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _admin100 ? _abrirAdicionarEstoque : null,
                  icon: Icon(
                    Icons.add,
                    color: _readableOn(context.uai.primary),
                  ),
                  label: Text(
                    'ADICIONAR ITEM',
                    style: TextStyle(color: _readableOn(context.uai.primary)),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.uai.primary,
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
                dadosRevision: _dadosRevision,
                podeConfigurar: _admin100,
                categoriaId: doc.id,
                categoriaData: data,
                realFormat: _realFormat,
                onEditarItem: _editarItemEstoque,
                onRegistrarEntrada: _registrarEntrada,
                onRegistrarSaida: _registrarSaida,
                onExcluirItem: _excluirItemEstoque,
                onExcluirCategoria: _admin100
                    ? () => _excluirCategoriaEstoque(doc.id, data)
                    : null,
              );
            } else {
              final int quantidade = data['quantidade'] ?? 0;
              return ItemEstoqueCard(
                podeConfigurar: _admin100,
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

  Future<void> _excluirCategoriaEstoque(
    String categoriaId,
    Map<String, dynamic> data,
  ) async {
    try {
      if (!await UniformesAdminService().admin100() || !mounted) return;
      final motivo = await _pedirMotivo('Justificativa para excluir categoria');
      if (motivo == null) return;
      await UniformesAdminService().operar('excluir_produto', {
        'itemId': categoriaId,
        'motivo': motivo,
        'confirmacao': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Categoria "${data['nome']}" e suas variações foram excluídas!',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Erro ao excluir categoria: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ==================== ABA VENDAS ====================
  Widget _buildVendasTab() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('uniformes_query_2_$_dadosRevision'),
      stream: _uaiUniformesQueryStream(
        FirebaseFirestore.instance
            .collection('vendas_uniformes')
            .orderBy('data_venda', descending: true),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro: ${snapshot.error}',
              style: TextStyle(color: context.uai.textPrimary),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
        }

        var vendas = (snapshot.data?.docs ?? [])
            .where((doc) => !_vendasExcluidasLocal.contains(doc.id) && _documentoDoCiclo(doc))
            .toList();

        if (vendas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 80,
                  color: context.uai.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma venda registrada',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.uai.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        if (_searchQuery.isNotEmpty) {
          vendas = vendas.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return (data['aluno_nome'] ?? '').toLowerCase().contains(
              _searchQuery.toLowerCase(),
            );
          }).toList();
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

            Widget buildVenda(dynamic doc) {
              final data = doc.data() as Map<String, dynamic>;
              return VendaCard(
                docId: doc.id,
                data: data,
                realFormat: _realFormat,
                onTap: _abrirDetalhesVenda,
                podeEditar: _podeEditar,
                podeExcluir: _podeExcluir,
              );
            }

            if (colunas == 1) {
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: vendas.length,
                itemBuilder: (context, index) => buildVenda(vendas[index]),
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
                (contentWidth - 24 - (spacing * (colunas - 1))) / colunas;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    alignment: WrapAlignment.start,
                    children: vendas.map((doc) {
                      return SizedBox(width: cardWidth, child: buildVenda(doc));
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================== ABA PENDÊNCIAS ====================
  Widget _buildPendenciasTab() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('uniformes_query_3_$_dadosRevision'),
      stream: _uaiUniformesQueryStream(
        FirebaseFirestore.instance
            .collection('vendas_uniformes')
            .where('status_pagamento', whereIn: ['pendente', 'parcial'])
            .orderBy('data_venda', descending: true),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro: ${snapshot.error}',
              style: TextStyle(color: context.uai.textPrimary),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
        }

        var vendasPendentes = (snapshot.data?.docs ?? []).where((doc) {
          if (_vendasExcluidasLocal.contains(doc.id) || !_documentoDoCiclo(doc)) return false;
          final data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'ativa').toString().toLowerCase() !=
              'cancelada';
        }).toList();

        if (vendasPendentes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: context.uai.success,
                ),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma pendência!',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.uai.textSecondary,
                  ),
                ),
                Text(
                  'Todas as vendas estão pagas',
                  style: TextStyle(color: context.uai.textMuted),
                ),
              ],
            ),
          );
        }

        double totalPendente = 0;
        for (var doc in vendasPendentes) {
          var data = doc.data() as Map<String, dynamic>;
          totalPendente +=
              (data['valor_total'] ?? 0).toDouble() -
              (data['valor_pago'] ?? 0).toDouble();
        }

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.uai.card,
                borderRadius: BorderRadius.circular(context.uai.cardRadius),
                border: Border.all(color: context.uai.error.withAlpha(51)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL PENDENTE',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.uai.textSecondary,
                        ),
                      ),
                      Text(
                        _realFormat.format(totalPendente),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: context.uai.error,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${vendasPendentes.length} venda(s)',
                    style: TextStyle(color: context.uai.textMuted),
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
                    podeReceberPagamento: _can(
                      'pode_registrar_pagamento_uniforme',
                    ),
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

  // Pedidos legados sem remessa continuam acessíveis e editáveis.
  Widget _buildPedidosSemRemessa(Set<String> remessasConhecidas) {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('uniformes_query_4_$_dadosRevision'),
      stream: _uaiUniformesQueryStream(
        FirebaseFirestore.instance
            .collection('pedidos_uniformes')
            .orderBy('data_pedido', descending: true),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro: ${snapshot.error}',
              style: TextStyle(color: context.uai.textPrimary),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
        }

        var pedidos = (snapshot.data?.docs ?? [])
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final remessaId = (data['remessa_id'] ?? '').toString();
              return !_pedidosExcluidosLocal.contains(doc.id) && _documentoDoCiclo(doc) &&
                  (remessaId.isEmpty || !remessasConhecidas.contains(remessaId));
            })
            .toList();

        if (pedidos.isEmpty) return const SizedBox.shrink();

        if (_searchQuery.isNotEmpty) {
          pedidos = pedidos.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return (data['aluno_nome'] ?? '').toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                (data['id_pedido'] ?? '').toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();
        }

        if (pedidos.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 18),
          child: Card(
            child: ExpansionTile(
              leading: Icon(Icons.inventory_2_outlined, color: context.uai.warning),
              title: Text('Pedidos sem remessa (${pedidos.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Registros sem vínculo ativo; consulte e regularize na edição.'),
              children: [
                ListView.builder(
                  padding: const EdgeInsets.all(12),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pedidos.length,
                  itemBuilder: (context, index) {
                    final doc = pedidos[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return PedidoCard(
                      docId: doc.id,
                      data: data,
                      realFormat: _realFormat,
                      onMarcarConfeccao: _marcarPedidoComoConfeccao,
                      onFinalizar: _marcarPedidoComoFinalizado,
                      onRegistrarPagamento: _registrarPagamentoPedido,
                      onEditar: _can('pode_editar_pedido') ? _editarPedido : null,
                      onExcluir: _can('pode_excluir_pedido') ? _excluirPedido : null,
                      podeEditar: _can('pode_editar_pedido'),
                      podeExcluir: _can('pode_excluir_pedido'),
                      podeRegistrarPagamento: _can('pode_registrar_pagamento_pedido'),
                      podeAlterarStatus: _can('pode_alterar_status_pedido'),
                      onTap: _abrirDetalhesPedido,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== PEDIDOS + REMESSAS ====================
  Widget _buildPedidosRemessasTab() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('uniformes_query_5_$_dadosRevision'),
      stream: _uaiUniformesWindowsSafeMode
          ? _uaiUniformesQueryStream(FirebaseFirestore.instance
              .collection('remessas')
              .orderBy('criado_em', descending: true))
          : _remessaService.getTodasRemessas(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro: ${snapshot.error}',
              style: TextStyle(color: context.uai.textPrimary),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
        }

        var remessas = (snapshot.data?.docs ?? [])
            .where((doc) => !_remessasExcluidasLocal.contains(doc.id) && _documentoDoCiclo(doc))
            .toList();
        // Guarde os IDs antes do filtro de pesquisa para não tratar remessa
        // escondida pela busca como remessa inexistente.
        final remessasConhecidas = remessas.map((doc) => doc.id).toSet();
        if (remessas.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 28),
              Icon(Icons.local_shipping_outlined, size: 64, color: context.uai.textMuted),
              const SizedBox(height: 12),
              Center(child: Text('Nenhuma remessa cadastrada',
                  style: TextStyle(fontWeight: FontWeight.w800, color: context.uai.textPrimary))),
              const SizedBox(height: 14),
              if (_can('pode_gerenciar_remessas_uniformes'))
                Center(child: FilledButton.icon(
                  onPressed: _abrirNovaRemessa,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar primeira remessa'),
                )),
              _buildPedidosSemRemessa(remessasConhecidas),
            ],
          );
        }

        if (_searchQuery.isNotEmpty) {
          remessas = remessas.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return (data['nome'] ?? '').toLowerCase().contains(
              _searchQuery.toLowerCase(),
            );
          }).toList();
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 14),
              child: Row(children: [
                Icon(Icons.local_shipping_rounded, color: context.uai.primary),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pedidos por remessa', style: TextStyle(fontSize: 17,
                    fontWeight: FontWeight.w900, color: context.uai.textPrimary)),
                  Text('Abra a remessa para consultar pedidos, receber pagamentos e adicionar novos.',
                    style: TextStyle(fontSize: 12, color: context.uai.textSecondary)),
                ])),
              ]),
            ),
            for (final doc in remessas)
              RemessaCard(
                key: ValueKey(doc.id),
                remessaId: doc.id,
                data: doc.data() as Map<String, dynamic>,
                onTap: () => _abrirDetalhesRemessa(doc.id, doc.data() as Map<String, dynamic>),
                onEditar: () => _editarRemessa(doc.id, doc.data() as Map<String, dynamic>),
                onExcluir: () => _excluirRemessa(doc.id, doc.data() as Map<String, dynamic>),
                podeEditar: _can('pode_gerenciar_remessas_uniformes'),
                podeExcluir: _can('pode_gerenciar_remessas_uniformes'),
              ),
            _buildPedidosSemRemessa(remessasConhecidas),
            const SizedBox(height: 104),
          ],
        );
      },
    );
  }

  // ==================== NAVEGAÇÃO ====================
  void _abrirNovaVenda() async {
    if (!await _allow('pode_criar_venda')) return;
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NovaVendaScreen()),
    );
    if (result == true && mounted) _atualizarDadosUniformes();
  }

  void _abrirAdicionarEstoque() async {
    if (!await UniformesAdminService().admin100() || !mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdicionarEstoqueScreen()),
    );
    if (result == true && mounted) _atualizarDadosUniformes();
  }

  void _abrirRelatorioFinanceiro() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RelatorioFinanceiroScreen()),
    );
  }

  void _editarItemEstoque(String docId, Map<String, dynamic> data) async {
    if (!await UniformesAdminService().admin100() || !mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdicionarEstoqueScreen(itemId: docId, itemData: data),
      ),
    );
    if (result == true && mounted) _atualizarDadosUniformes();
  }

  void _abrirNovaRemessa() async {
    if (!await _allow('pode_gerenciar_remessas_uniformes')) return;
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RemessaFormScreen()),
    );
    if (result == true && mounted) _atualizarDadosUniformes();
  }

  void _editarRemessa(String remessaId, Map<String, dynamic> data) async {
    if (!await _allow('pode_gerenciar_remessas_uniformes')) return;
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RemessaFormScreen(remessaId: remessaId, remessaData: data),
      ),
    );
    if (result == true && mounted) _atualizarDadosUniformes();
  }

  void _abrirDetalhesRemessa(
    String remessaId,
    Map<String, dynamic> data,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemessaDetalhesScreen(
          remessaId: remessaId,
          remessaData: data,
          podeEditar: _can('pode_gerenciar_remessas_uniformes'),
          podeExcluir: _can('pode_gerenciar_remessas_uniformes'),
          podeCriarPedido: _can('pode_criar_pedido'),
          podeEditarPedido: _can('pode_editar_pedido'),
          podeExcluirPedido: _can('pode_excluir_pedido'),
          podeRegistrarPagamentoPedido: _can('pode_registrar_pagamento_pedido'),
          podeAlterarStatusPedido: _can('pode_alterar_status_pedido'),
        ),
      ),
    );
    if (mounted) _atualizarDadosUniformes();
  }

  void _excluirRemessa(String remessaId, Map<String, dynamic> data) async {
    if (!await _allow('pode_gerenciar_remessas_uniformes')) return;
    if (!mounted) return;
    final pedidosSnapshot = await FirebaseFirestore.instance
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .get();
    if (!mounted) return;
    final qtdPedidos = pedidosSnapshot.docs.length;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '🗑️ Excluir Remessa',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          qtdPedidos > 0
              ? 'Esta remessa possui $qtdPedidos pedido(s) vinculado(s). '
                    'Ao excluir a remessa, todos esses pedidos também serão excluídos permanentemente. Deseja continuar?'
              : 'Tem certeza que deseja excluir esta remessa?',
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
            child: const Text('Excluir tudo'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final motivo = await _pedirMotivo('Justificativa para excluir remessa');
      if (motivo == null) return;
      final removidos = await _remessaService.excluirRemessaComPedidos(
        remessaId,
        motivo: motivo,
      );

      if (mounted) {
        setState(() {
          _remessasExcluidasLocal.add(remessaId);
          for (final doc in pedidosSnapshot.docs) {
            _pedidosExcluidosLocal.add(doc.id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removidos > 0
                  ? '✅ Remessa e $removidos pedido(s) excluídos!'
                  : '✅ Remessa excluída!',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível cancelar a venda agora. Tente novamente.',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ==================== REGRAS DE REMESSA ↔ PEDIDOS ====================

  // ==================== ESTOQUE ====================
  void _registrarEntrada(String docId, Map<String, dynamic> data) async {
    if (!await UniformesAdminService().admin100() || !mounted) return;
    _showQuantidadeDialog(
      titulo: 'Registrar Entrada',
      itemNome: data['nome'],
      precoUnitario: data['preco_venda']?.toDouble(),
      onConfirm: (quantidade) async {
        final motivo = await _pedirMotivo('Justificativa do ajuste de estoque');
        if (motivo == null) return;
        await UniformesAdminService().operar('ajustar_estoque', {
          'itemId': docId,
          'tipo': 'entrada',
          'quantidade': quantidade,
          'motivo': motivo,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Entrada de $quantidade unidade(s) registrada!',
                style: TextStyle(color: _readableOn(context.uai.success)),
              ),
              backgroundColor: context.uai.success,
            ),
          );
        }
      },
    );
  }

  void _registrarSaida(String docId, Map<String, dynamic> data) async {
    if (!await UniformesAdminService().admin100() || !mounted) return;
    _showQuantidadeDialog(
      titulo: 'Registrar Saída',
      itemNome: data['nome'],
      precoUnitario: data['preco_venda']?.toDouble(),
      maxQuantidade: data['quantidade'],
      onConfirm: (quantidade) async {
        int novaQuantidade = (data['quantidade'] ?? 0) - quantidade;
        if (novaQuantidade < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Quantidade insuficiente em estoque!',
                style: TextStyle(color: _readableOn(context.uai.error)),
              ),
              backgroundColor: context.uai.error,
            ),
          );
          return;
        }
        final motivo = await _pedirMotivo('Justificativa do ajuste de estoque');
        if (motivo == null) return;
        await UniformesAdminService().operar('ajustar_estoque', {
          'itemId': docId,
          'tipo': 'saida',
          'quantidade': quantidade,
          'motivo': motivo,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Saída de $quantidade unidade(s) registrada!',
                style: TextStyle(color: _readableOn(context.uai.warning)),
              ),
              backgroundColor: context.uai.warning,
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
        onConfirm: (quantidade) async {
          if (_acaoVendaEmAndamento) return;
          setState(() => _acaoVendaEmAndamento = true);
          try {
            await onConfirm(quantidade);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Não foi possível ajustar o estoque: $e'),
                ),
              );
            }
          } finally {
            if (mounted) setState(() => _acaoVendaEmAndamento = false);
          }
        },
        precoUnitario: precoUnitario,
        maxQuantidade: maxQuantidade,
      ),
    );
  }

  Future<void> _excluirItemEstoque(
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      if (!await UniformesAdminService().admin100() || !mounted) return;
      final motivo = await _pedirMotivo('Justificativa para excluir produto');
      if (motivo == null) return;
      await UniformesAdminService().operar('excluir_produto', {
        'itemId': docId,
        'motivo': motivo,
        'confirmacao': true,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Item "${data['nome']}" excluído do estoque!',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Erro ao excluir item: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ==================== PAGAMENTOS ====================
  Future<void> _registrarPagamento(
    String docId, Map<String, dynamic> data, double valorRestante,
  ) async {
    if (!await _allow('pode_registrar_pagamento_uniforme') || !mounted) return;
    if (valorRestante <= 0) return;
    double? valorConfirmado;
    final sucesso = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PagamentoDialog(
        alunoNome: (data['aluno_nome'] ?? 'Aluno').toString(),
        valorTotal: (data['valor_total'] as num?)?.toDouble() ?? 0,
        valorPago: (data['valor_pago'] as num?)?.toDouble() ?? 0,
        valorRestante: valorRestante,
        onConfirm: (valor, formaPagamento) async {
          await _uniformesService.registrarPagamentoVenda(
            vendaId: docId, valorPagamento: valor, formaPagamento: formaPagamento,
            vendaData: data,
          );
          valorConfirmado = valor;
        },
      ),
    );
    if (sucesso == true && valorConfirmado != null) {
      _feedbackPagamentoConfirmado(valorConfirmado!);
    }
  }

  Future<void> _registrarPagamentoPedido(
    String docId, Map<String, dynamic> data,
  ) async {
    if (!await _allow('pode_registrar_pagamento_pedido') || !mounted) return;
    final total = (data['valor_total'] as num?)?.toDouble() ?? 0;
    final pago = (data['valor_pago'] as num?)?.toDouble() ?? 0;
    final restante = total - pago;
    if (restante <= 0) return;
    double? valorConfirmado;
    final sucesso = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PagamentoDialog(
        alunoNome: (data['aluno_nome'] ?? 'Aluno').toString(),
        valorTotal: total, valorPago: pago, valorRestante: restante,
        onConfirm: (valor, formaPagamento) async {
          await _uniformesService.registrarPagamentoPedido(
            pedidoId: docId, valorPagamento: valor, formaPagamento: formaPagamento,
            pedidoData: data,
          );
          valorConfirmado = valor;
        },
      ),
    );
    if (sucesso == true && valorConfirmado != null) {
      _feedbackPagamentoConfirmado(valorConfirmado!);
    }
  }

  // ==================== DETALHES ====================
  void _abrirDetalhesVenda(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.uai.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.uai.cardRadius),
        ),
      ),
      builder: (_) => DetalhesVendaBottomSheet(
        docId: docId,
        data: data,
        realFormat: _realFormat,
        onEntregar: _can('pode_registrar_entrega_uniforme')
            ? _entregarVenda
            : null,
        podeReceberPagamento: _can('pode_registrar_pagamento_uniforme'),
        onRegistrarPagamento: _registrarPagamento,
        onEditar: _podeEditar ? _editarVenda : null,
        onCancelar: _podeExcluir ? _cancelarVenda : null,
        onExcluirDefinitivamente: _podeExcluir
            ? _excluirVendaDefinitivamente
            : null,
        podeEditar: _podeEditar,
        podeExcluir: _podeExcluir,
      ),
    );
  }

  void _abrirDetalhesPedido(String docId, Map<String, dynamic> data) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Detalhes do pedido em desenvolvimento'),
        duration: const Duration(seconds: 1),
        backgroundColor: context.uai.info,
      ),
    );
  }

  // ==================== EDIÇÃO/EXCLUSÃO ====================
  void _editarVenda(String docId, Map<String, dynamic> data) async {
    if (!await _allow('pode_editar_venda')) return;
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarVendaScreen(vendaId: docId, vendaData: data),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Venda atualizada!',
            style: TextStyle(color: _readableOn(context.uai.success)),
          ),
          backgroundColor: context.uai.success,
        ),
      );
    }
  }

  Future<void> _executarAcaoVenda({
    required String mensagem,
    required Future<void> Function() acao,
  }) async {
    if (_acaoVendaEmAndamento) return;
    _acaoVendaEmAndamento = true;
    if (mounted) setState(() {});

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(mensagem)),
            ],
          ),
        ),
      ),
    );

    try {
      await acao();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _acaoVendaEmAndamento = false;
        _atualizarDadosUniformes();
      } else {
        _acaoVendaEmAndamento = false;
      }
    }
  }

  Future<void> _cancelarVenda(String docId, Map<String, dynamic> data) async {
    if (!await _allow('pode_excluir_venda')) return;
    if (!mounted) return;
    if (_acaoVendaEmAndamento) return;
    final motivoController = TextEditingController(
      text: 'Cancelamento administrativo',
    );
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar venda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A venda ficará cancelada e continuará disponível para auditoria.\n\nAluno: ${data['aluno_nome']}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo do cancelamento',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('VOLTAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CANCELAR VENDA'),
          ),
        ],
      ),
    );
    if (confirmar != true) {
      motivoController.dispose();
      return;
    }

    final motivo = motivoController.text.trim();
    motivoController.dispose();
    if (motivo.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe um motivo para cancelar a venda.'),
          ),
        );
      }
      return;
    }

    try {
      await _executarAcaoVenda(
        mensagem: 'Cancelando venda...',
        acao: () =>
            _uniformesService.cancelarVenda(vendaId: docId, motivo: motivo),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Venda cancelada com sucesso',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[UNIFORMES] erro ao cancelar venda $docId: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível cancelar a venda agora. Tente novamente.',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _excluirVendaDefinitivamente(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (_acaoVendaEmAndamento || !await _allow('pode_excluir_venda')) return;
    try {
      final bloqueio = await _uniformesService.verificarExclusaoDefinitiva(
        docId,
      );
      if (!mounted) return;
      if (bloqueio != null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exclusão definitiva indisponível'),
            content: Text(bloqueio),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
        return;
      }
      final motivo = await _pedirMotivo(
        'Excluir venda de ${data['aluno_nome']}',
      );
      if (motivo == null || !mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir definitivamente'),
          content: const Text(
            'O histórico do aluno, a auditoria e os registros contábeis da Associação serão preservados. Confirmar exclusão desta venda cancelada?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar exclusão'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
      await _executarAcaoVenda(
        mensagem: 'Excluindo venda...',
        acao: () => _uniformesService.excluirVendaDefinitivamente(
          vendaId: docId,
          motivo: motivo,
        ),
      );
      if (mounted) {
        setState(() => _vendasExcluidasLocal.add(docId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venda excluída com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível excluir a venda: $e')),
        );
      }
    }
  }

  void _editarPedido(String docId, Map<String, dynamic> data) async {
    if (!await _allow('pode_editar_pedido')) return;
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarPedidoScreen(pedidoId: docId, pedidoData: data),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Pedido atualizado!',
            style: TextStyle(color: _readableOn(context.uai.success)),
          ),
          backgroundColor: context.uai.success,
        ),
      );
    }
  }

  void _excluirPedido(String docId, Map<String, dynamic> data) async {
    if (!await _allow('pode_excluir_pedido')) return;
    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '🗑️ Confirmar Exclusão',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'Tem certeza que deseja excluir este pedido?\n\n'
          'Pedido: ${data['id_pedido'] ?? 'N/I'}\n'
          'Aluno: ${data['aluno_nome']}\n'
          'Valor: ${_realFormat.format(data['valor_total'] ?? 0)}',
          style: TextStyle(color: context.uai.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final motivo = await _pedirMotivo('Justificativa para excluir pedido');
      if (motivo == null) return;
      final remessaId = data['remessa_id']?.toString();
      await _remessaService.excluirPedidoDefinitivamente(
        docId,
        remessaId: remessaId,
        motivo: motivo,
      );

      if (mounted) {
        setState(() => _pedidosExcluidosLocal.add(docId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Pedido excluído com sucesso!',
              style: TextStyle(color: _readableOn(context.uai.success)),
            ),
            backgroundColor: context.uai.success,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível cancelar a venda agora. Tente novamente.',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ==================== STATUS DE PEDIDOS ====================
  Future<void> _marcarPedidoComoConfeccao(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!await _allow('pode_alterar_status_pedido')) return;
    if (!mounted) return;
    try {
      await _executarAcaoVenda(
        mensagem: 'Atualizando pedido...',
        acao: () => _uniformesService.atualizarStatusPedido(docId, 'em_confeccao'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Pedido marcado como EM CONFECÇÃO',
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
              '❌ Erro ao atualizar status: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _marcarPedidoComoFinalizado(
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (!await _allow('pode_alterar_status_pedido')) return;
    if (!mounted) return;
    try {
      await _executarAcaoVenda(
        mensagem: 'Finalizando pedido...',
        acao: () => _uniformesService.atualizarStatusPedido(docId, 'finalizado'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Pedido finalizado com sucesso!',
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
              '❌ Erro ao finalizar pedido: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }
}

// ==================== WIDGET AUXILIAR: CATEGORIA EXPANSÍVEL ====================
class _CategoriaEstoqueExpansivel extends StatefulWidget {
  final int dadosRevision;
  final bool podeConfigurar;
  final String categoriaId;
  final Map<String, dynamic> categoriaData;
  final NumberFormat realFormat;
  final Function(String, Map<String, dynamic>) onEditarItem;
  final Function(String, Map<String, dynamic>) onRegistrarEntrada;
  final Function(String, Map<String, dynamic>) onRegistrarSaida;
  final Function(String, Map<String, dynamic>) onExcluirItem;
  final VoidCallback? onExcluirCategoria;

  const _CategoriaEstoqueExpansivel({
    required this.dadosRevision,
    this.podeConfigurar = false,
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
  State<_CategoriaEstoqueExpansivel> createState() =>
      _CategoriaEstoqueExpansivelState();
}

class _CategoriaEstoqueExpansivelState
    extends State<_CategoriaEstoqueExpansivel> {
  bool _expanded = false;

  // Helpers para dentro do widget
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _getCategoriaColor(String? categoria) {
    switch (categoria?.toLowerCase()) {
      case 'camisa':
      case 'camiseta':
        return context.uai.info;
      case 'calça':
      case 'calca':
      case 'bermuda':
        return context.uai.success;
      case 'abada':
      case 'corda':
        return context.uai.warning;
      case 'acessório':
      case 'acessorio':
        return context.uai.primary;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _getCategoriaIcon(String? categoria) {
    switch (categoria?.toLowerCase()) {
      case 'camisa':
      case 'camiseta':
        return Icons.shopping_bag;
      case 'calça':
      case 'calca':
      case 'bermuda':
        return Icons.shopping_bag;
      case 'abada':
        return Icons.sports_kabaddi;
      case 'corda':
        return Icons.sensors;
      case 'acessório':
      case 'acessorio':
        return Icons.watch;
      default:
        return Icons.inventory;
    }
  }

  void _confirmarExclusaoCategoria() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Excluir categoria',
          style: TextStyle(color: context.uai.textPrimary),
        ),
        content: Text(
          'Tem certeza que deseja excluir a categoria "${widget.categoriaData['nome']}"?\n\n'
          'Todos os itens vinculados (variações) também serão excluídos permanentemente.',
          style: TextStyle(color: context.uai.textSecondary),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
            ),
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
    final Color cardBg = context.uai.card; // Fundo do card para contraste

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            border: Border.all(color: context.uai.border),
            boxShadow: const [],
          ),
          child: ExpansionTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: corCat.withAlpha(38),
                borderRadius: BorderRadius.circular(8),
              ),
              child: fotoUrl != null && fotoUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Icon(
                      _getCategoriaIcon(categoria),
                      color: _ensureVisible(corCat, cardBg),
                    ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    nome,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.uai.textPrimary,
                    ),
                  ),
                ),
                if (widget.onExcluirCategoria != null)
                  IconButton(
                    icon: Icon(
                      Icons.delete,
                      color: _ensureVisible(context.uai.error, cardBg),
                      size: 20,
                    ),
                    onPressed: _confirmarExclusaoCategoria,
                    tooltip: 'Excluir categoria',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            subtitle: Text(
              categoria,
              style: TextStyle(color: context.uai.textSecondary),
            ),
            onExpansionChanged: (expanded) {
              setState(() => _expanded = expanded);
            },
            children: [
              if (_expanded)
                StreamBuilder<QuerySnapshot>(
                  key: ValueKey('uniformes_query_6_${widget.dadosRevision}'),
                  stream: _uaiUniformesQueryStream(
                    FirebaseFirestore.instance
                        .collection('uniformes_estoque')
                        .where('item_base_id', isEqualTo: widget.categoriaId)
                        .where('status', isEqualTo: 'ativo'),
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: context.uai.primary,
                        ),
                      );
                    }
                    final variacoes = snapshot.data!.docs;
                    if (variacoes.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhuma variação disponível',
                          style: TextStyle(color: context.uai.textMuted),
                        ),
                      );
                    }
                    return Column(
                      children: variacoes.map((doc) {
                        var varData = doc.data() as Map<String, dynamic>;
                        final int quantidade = varData['quantidade'] ?? 0;
                        return ItemEstoqueCard(
                          podeConfigurar: widget.podeConfigurar,
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
        ),
      ),
    );
  }
}
