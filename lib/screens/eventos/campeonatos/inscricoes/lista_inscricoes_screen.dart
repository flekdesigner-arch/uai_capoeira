import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/campeonato_model.dart';
import 'detalhe_inscricao_screen.dart';

class ListaInscricoesScreen extends StatefulWidget {
  final String campeonatoId;
  final bool podeGerenciar;

  const ListaInscricoesScreen({
    super.key,
    required this.campeonatoId,
    required this.podeGerenciar,
  });

  @override
  State<ListaInscricoesScreen> createState() => _ListaInscricoesScreenState();
}

class _ListaInscricoesScreenState extends State<ListaInscricoesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CampeonatoService _campeonatoService = CampeonatoService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  String _filtroCategoria = 'Todas';
  String _filtroGrupo = 'Todos';
  String _searchQuery = '';
  String _filtroPagamento = 'todos'; // 'todos', 'pagos', 'nao_pagos'
  List<String> _categorias = ['Todas'];
  List<String> _grupos = ['Todos'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _carregarFiltros();
  }

  Future<void> _carregarFiltros() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('campeonato_inscricoes')
          .get();

      Set<String> categoriasSet = {};
      Set<String> gruposSet = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['categoria_nome'] != null) {
          categoriasSet.add(data['categoria_nome']);
        }
        if (data['grupo'] != null) {
          gruposSet.add(data['grupo']);
        }
      }

      if (mounted) {
        setState(() {
          _categorias = ['Todas', ...categoriasSet.toList()..sort()];
          _grupos = ['Todos', ...gruposSet.toList()..sort()];
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar filtros: $e');
    }
  }

  Stream<QuerySnapshot> _getInscricoesStream(String status) {
    Query query = FirebaseFirestore.instance
        .collection('campeonato_inscricoes')
        .orderBy('data_inscricao', descending: true);

    if (status != 'todos') {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots();
  }

  // Método para filtrar docs com todos os critérios
  List<QueryDocumentSnapshot> _filtrarDocs(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      // Filtro de categoria
      bool categoriaOk = _filtroCategoria == 'Todas' || data['categoria_nome'] == _filtroCategoria;

      // Filtro de grupo
      bool grupoOk = _filtroGrupo == 'Todos' || data['grupo'] == _filtroGrupo;

      // Filtro de pagamento
      bool pagamentoOk = true;
      if (_filtroPagamento != 'todos') {
        final isPago = data['taxa_paga'] ?? false;
        pagamentoOk = _filtroPagamento == 'pagos' ? isPago : !isPago;
      }

      // Filtro de busca
      bool searchOk = true;
      if (_searchQuery.isNotEmpty) {
        final nome = (data['nome'] ?? '').toLowerCase();
        final apelido = (data['apelido'] ?? '').toLowerCase();
        final grupo = (data['grupo'] ?? '').toLowerCase();
        final query = _searchQuery.toLowerCase();

        searchOk = nome.contains(query) ||
            apelido.contains(query) ||
            grupo.contains(query);
      }

      return categoriaOk && grupoOk && pagamentoOk && searchOk;
    }).toList();
  }

  void _mostrarFiltrosDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 20),
                const Text(
                  'Filtrar Inscrições',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _filtroCategoria,
                  decoration: InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.category, color: Colors.amber),
                  ),
                  items: _categorias.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      _filtroCategoria = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _filtroGrupo,
                  decoration: InputDecoration(
                    labelText: 'Grupo',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.group, color: Colors.amber),
                  ),
                  items: _grupos.map((grupo) {
                    return DropdownMenuItem(
                      value: grupo,
                      child: Text(grupo),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      _filtroGrupo = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _filtroPagamento,
                  decoration: InputDecoration(
                    labelText: 'Pagamento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.attach_money, color: Colors.amber),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'pagos', child: Text('Pagos')),
                    DropdownMenuItem(value: 'nao_pagos', child: Text('Não pagos')),
                  ],
                  onChanged: (value) {
                    setStateDialog(() {
                      _filtroPagamento = value!;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setStateDialog(() {
                            _filtroCategoria = 'Todas';
                            _filtroGrupo = 'Todos';
                            _filtroPagamento = 'todos';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('LIMPAR'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {});
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('APLICAR'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barra de busca
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.amber.shade50,
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, apelido ou grupo...',
              prefixIcon: const Icon(Icons.search, color: Colors.amber),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () => setState(() => _searchQuery = ''),
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
          ),
        ),

        // Tabs
        Container(
          color: Colors.amber.shade50,
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.amber.shade900,
            labelColor: Colors.amber.shade900,
            unselectedLabelColor: Colors.grey.shade600,
            tabs: const [
              Tab(text: 'TODAS'),
              Tab(text: 'PENDENTES'),
              Tab(text: 'CONFIRMADAS'),
            ],
          ),
        ),

        // Botão de filtros e indicador
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.amber.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _filtroCategoria != 'Todas' ||
                          _filtroGrupo != 'Todos' ||
                          _filtroPagamento != 'todos'
                          ? Colors.amber.shade200
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _filtroCategoria != 'Todas' ||
                          _filtroGrupo != 'Todos' ||
                          _filtroPagamento != 'todos'
                          ? 'Filtros ativos'
                          : 'Todos os filtros',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _mostrarFiltrosDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.filter_list, size: 14, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text(
                        'Filtrar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Lista
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildListaInscricoes('todos'),
              _buildListaInscricoes('pendente'),
              _buildListaInscricoes('confirmado'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListaInscricoes(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getInscricoesStream(status),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar inscrições',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
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
                Icon(Icons.event_busy, size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma inscrição encontrada',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        // Aplicar todos os filtros
        var docs = _filtrarDocs(snapshot.data!.docs);

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.filter_alt_off, size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'Nenhum resultado para "$_searchQuery"'
                      : 'Nenhuma inscrição com os filtros selecionados',
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildInscricaoCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildInscricaoCard(String docId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'pendente';
    final isPago = data['taxa_paga'] ?? false;
    final isMaior = data['is_maior_idade'] ?? true;
    final temFoto = data['foto_url'] != null && data['foto_url'].toString().isNotEmpty;

    Color statusColor;
    String statusText;

    switch (status) {
      case 'confirmado':
        statusColor = Colors.green;
        statusText = 'CONFIRMADO';
        break;
      case 'cancelado':
        statusColor = Colors.red;
        statusText = 'CANCELADO';
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'PENDENTE';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetalheInscricaoScreen(
                inscricaoId: docId,
                podeGerenciar: widget.podeGerenciar,
              ),
            ),
          ).then((_) {
            setState(() {});
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar com foto ou inicial
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: statusColor,
                        width: 2,
                      ),
                    ),
                    child: temFoto
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: CachedNetworkImage(
                        imageUrl: data['foto_url'],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Text(
                            data['nome']?[0] ?? '?',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ),
                    )
                        : Center(
                      child: Text(
                        data['nome']?[0] ?? '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['nome'] ?? 'Sem nome',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!isMaior)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'MENOR',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPago ? Colors.green.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isPago ? 'PAGO' : 'NÃO PAGO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isPago ? Colors.green : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data['categoria_nome'] ?? 'Sem categoria',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.group,
                      text: data['grupo'] ?? 'Sem grupo',
                    ),
                  ),
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.grade,
                      text: data['graduacao_nome'] ?? 'Sem graduação',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.phone,
                      text: data['contato_aluno'] ?? 'Sem contato',
                    ),
                  ),
                  if (!isMaior && data['nome_responsavel'] != null)
                    Expanded(
                      child: _buildInfoRow(
                        icon: Icons.person_outline,
                        text: 'Resp: ${data['nome_responsavel']}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.access_time, size: 10, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    'Inscrição: ${_dateFormat.format((data['data_inscricao'] as Timestamp).toDate())}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}