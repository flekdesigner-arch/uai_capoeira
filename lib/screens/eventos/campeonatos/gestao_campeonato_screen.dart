import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/models/campeonato_model.dart';
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/services/permissao_service.dart';
import 'inscricoes/lista_inscricoes_screen.dart';
import 'chaveamento/chaves_por_categoria_screen.dart';

class GestaoCampeonatoScreen extends StatefulWidget {
  final String campeonatoId;
  final String nomeCampeonato;

  const GestaoCampeonatoScreen({
    super.key,
    required this.campeonatoId,
    required this.nomeCampeonato,
  });

  @override
  State<GestaoCampeonatoScreen> createState() => _GestaoCampeonatoScreenState();
}

class _GestaoCampeonatoScreenState extends State<GestaoCampeonatoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late CampeonatoService _campeonatoService;
  late PermissaoService _permissaoService;

  bool _isLoading = true;
  CampeonatoModel? _campeonato;
  Map<String, dynamic> _estatisticas = {};

  // 🔥 TAXA CORRETA DAS CONFIGURAÇÕES
  double _taxaAtual = 30.0;

  // Permissões
  bool _podeGerenciarInscricoes = false;
  bool _podeGerenciarFinanceiro = false;
  bool _podeGerenciarChaves = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _campeonatoService = CampeonatoService();
    _permissaoService = PermissaoService();
    _carregarDados();
    _verificarPermissoes();
  }

  Future<void> _verificarPermissoes() async {
    _podeGerenciarInscricoes = await _permissaoService.temPermissao('pode_gerenciar_inscricoes') ?? false;
    _podeGerenciarFinanceiro = await _permissaoService.temPermissao('pode_gerenciar_financeiro') ?? false;
    _podeGerenciarChaves = await _permissaoService.temPermissao('pode_gerenciar_chaves') ?? false;

    if (mounted) setState(() {});
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 🔥 BUSCAR CAMPEONATO
      final campeonato = await _campeonatoService.getCampeonato(widget.campeonatoId);

      // 🔥 BUSCAR CONFIGURAÇÕES PARA PEGAR A TAXA CORRETA
      final configDoc = await FirebaseFirestore.instance
          .collection('configuracoes')
          .doc('campeonato')
          .get();

      if (configDoc.exists) {
        final configData = configDoc.data();
        if (configData != null && configData.containsKey('taxa_inscricao')) {
          _taxaAtual = (configData['taxa_inscricao'] as num).toDouble();
        }
      }

      // 🔥 SE O CAMPEONATO EXISTIR, ATUALIZAR A TAXA DELE
      if (campeonato != null) {
        // Como o modelo é imutável, vamos criar uma cópia modificada
        // Isso requer que o CampeonatoModel tenha um copyWith ou construtor
        // Se não tiver, vamos usar as estatísticas para exibir a taxa
      }

      // 🔥 BUSCAR ESTATÍSTICAS (JÁ VEM COM A TAXA CORRETA DO SERVIÇO MODIFICADO)
      final estatisticas = await _campeonatoService.getEstatisticas(widget.campeonatoId);

      if (mounted) {
        setState(() {
          _campeonato = campeonato;
          _estatisticas = estatisticas;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2)}';
  }

  void _abrirChavesCategoria(CategoriaCampeonato categoria) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChavesPorCategoriaScreen(
          campeonatoId: widget.campeonatoId,
          categoriaId: categoria.id,
          categoriaNome: categoria.nome,
        ),
      ),
    ).then((_) {
      _carregarDados();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          widget.nomeCampeonato,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          tabs: const [
            Tab(text: 'VISÃO GERAL', icon: Icon(Icons.dashboard)),
            Tab(text: 'INSCRIÇÕES', icon: Icon(Icons.app_registration)),
            Tab(text: 'COMPETIÇÃO', icon: Icon(Icons.emoji_events)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildVisaoGeral(),
          _buildInscricoesTab(),
          _buildCompeticaoTab(),
        ],
      ),
    );
  }

  // ==================== TAB 1: VISÃO GERAL ====================
  Widget _buildVisaoGeral() {
    if (_campeonato == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Campeonato não encontrado',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildInfoCard(),
          const SizedBox(height: 20),
          _buildEstatisticasCard(),
          const SizedBox(height: 20),
          _buildCategoriasCard(),
          const SizedBox(height: 20),
          if (_podeGerenciarFinanceiro) _buildFinanceiroCard(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.emoji_events, size: 40, color: Colors.amber),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _campeonato!.dataFormatada,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _campeonato!.local,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  _campeonato!.cidade,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'ATIVO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.people,
                    value: '${_estatisticas['total'] ?? 0}',
                    label: 'Inscrições',
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.pending,
                    value: '${_estatisticas['pendentes'] ?? 0}',
                    label: 'Pendentes',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.check_circle,
                    value: '${_estatisticas['confirmados'] ?? 0}',
                    label: 'Confirmados',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.attach_money,
                    value: '${_estatisticas['pagos'] ?? 0}',
                    label: 'Pagamentos',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstatisticasCard() {
    final porGrupo = _estatisticas['por_grupo'] as Map<String, int>? ?? {};

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 DISTRIBUIÇÃO POR GRUPO',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (porGrupo.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nenhum grupo inscrito'),
                ),
              )
            else
              Column(
                children: porGrupo.entries.map((entry) {
                  final total = _estatisticas['total'] ?? 1;
                  final percentual = (entry.value / total * 100).toStringAsFixed(1);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              Container(
                                height: 8,
                                width: MediaQuery.of(context).size.width * 0.4 * (entry.value / total),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade700,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.value} ($percentual%)',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriasCard() {
    final porCategoria = _estatisticas['por_categoria'] as Map<String, int>? ?? {};
    final pagosPorCategoria = _estatisticas['pagos_por_categoria'] as Map<String, int>? ?? {};

    if (porCategoria.isEmpty) {
      return const SizedBox();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🏆 CATEGORIAS COM INSCRIÇÕES',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...porCategoria.entries.map((entry) {
              final inscritos = entry.value;
              final pagos = pagosPorCategoria[entry.key] ?? 0;

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
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$inscritos inscritos',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$pagos pagos',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade700,
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
      ),
    );
  }

  Widget _buildFinanceiroCard() {
    if (_campeonato == null) return const SizedBox();

    // 🔥 SOLUÇÃO DEFINITIVA: USAR A TAXA DAS ESTATÍSTICAS (QUE JÁ VEM CORRETA DO SERVIÇO)
    double taxaParaExibir = _estatisticas['taxa_base'] ?? _taxaAtual;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '💰 RESUMO FINANCEIRO',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildFinanceiroItem(
                    label: 'Taxa',
                    value: _formatarMoeda(taxaParaExibir), // 👈 USA A TAXA CORRETA
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildFinanceiroItem(
                    label: 'Inscrições pagas',
                    value: '${_estatisticas['pagos'] ?? 0}',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL ARRECADADO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _formatarMoeda(_estatisticas['total_arrecadado'] ?? 0),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
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

  Widget _buildFinanceiroItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 2: INSCRIÇÕES ====================
  Widget _buildInscricoesTab() {
    return ListaInscricoesScreen(
      campeonatoId: widget.campeonatoId,
      podeGerenciar: _podeGerenciarInscricoes,
    );
  }

  // ==================== TAB 3: COMPETIÇÃO ====================
  Widget _buildCompeticaoTab() {
    final porCategoria = _estatisticas['por_categoria'] as Map<String, int>? ?? {};

    if (porCategoria.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma inscrição',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Aguardando inscrições para gerar chaves',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'SELECIONE UMA CATEGORIA',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...porCategoria.entries.map((entry) {
          final categoriaNome = entry.key;
          final inscritos = entry.value;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () {
                final tempCategoria = CategoriaCampeonato(
                  id: categoriaNome,
                  nome: categoriaNome,
                  idadeMin: 0,
                  idadeMax: 99,
                  sexo: 'MISTO',
                  taxa: _campeonato?.taxaInscricao ?? 0,
                );
                _abrirChavesCategoria(tempCategoria);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.emoji_events,
                        color: Colors.amber,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoriaNome,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$inscritos inscritos',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.amber,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}