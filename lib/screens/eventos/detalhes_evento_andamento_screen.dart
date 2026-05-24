// lib/screens/eventos/detalhes_evento_andamento_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/evento_model.dart';
import '../../services/participacao_service.dart';
import '../../services/permissao_service.dart';
import 'participantes_evento_screen.dart';
import 'gastos_evento_screen.dart';
import 'patrocinadores_evento_screen.dart';
import 'camisas_evento_screen.dart';
import '../relatorios/relatorio_financeiro_screen.dart';

class DetalhesEventoAndamentoScreen extends StatefulWidget {
  final EventoModel evento;
  final String eventoId;

  const DetalhesEventoAndamentoScreen({
    super.key,
    required this.evento,
    required this.eventoId,
  });

  @override
  State<DetalhesEventoAndamentoScreen> createState() => _DetalhesEventoAndamentoScreenState();
}

class _DetalhesEventoAndamentoScreenState extends State<DetalhesEventoAndamentoScreen> {
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final PermissaoService _permissaoService = PermissaoService();

  bool _isLoading = true;
  int _totalParticipantes = 0;
  double _totalGastos = 0;
  double _totalPatrocinioValor = 0;
  Map<String, int> _camisasCount = {};
  int _totalCamisas = 0;

  // 🔥 LISTA COMBINADA DE CAMISAS (participações + avulsas)
  List<Map<String, dynamic>> _todasCamisas = [];

  // Permissões
  bool _podeGerenciarParticipantes = false;
  bool _podeGerenciarFinanceiro = false;
  bool _podeGerenciarPatrocinadores = false;
  bool _podeGerenciarCamisas = false;
  bool _podeVerRelatorios = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
    _verificarPermissoes();
  }

  Future<void> _verificarPermissoes() async {
    _podeGerenciarParticipantes = await _permissaoService.temPermissao('pode_gerenciar_participantes') ?? false;
    _podeGerenciarFinanceiro = await _permissaoService.temPermissao('pode_gerenciar_financeiro') ?? false;
    _podeGerenciarPatrocinadores = await _permissaoService.temPermissao('pode_gerenciar_patrocinadores') ?? false;
    _podeGerenciarCamisas = await _permissaoService.temPermissao('pode_gerenciar_camisas') ?? false;
    _podeVerRelatorios = await _permissaoService.temPermissao('pode_ver_relatorios') ?? false;

    if (mounted) setState(() {});
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _carregarEstatisticas(),
        _carregarGastos(),
        _carregarPatrocinadores(),
        _carregarTodasCamisas(), // 🔥 Carrega TODAS as camisas
      ]);
    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _carregarEstatisticas() async {
    try {
      final estatisticas = await _participacaoService.getEstatisticasPorEvento(widget.eventoId);

      setState(() {
        _totalParticipantes = estatisticas['total'] ?? 0;
      });
    } catch (e) {
      debugPrint('Erro ao carregar participantes: $e');
    }
  }

  Future<void> _carregarGastos() async {
    try {
      final gastosSnapshot = await FirebaseFirestore.instance
          .collection('gastos_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      double total = 0;
      for (var doc in gastosSnapshot.docs) {
        total += (doc['valor'] as num?)?.toDouble() ?? 0;
      }

      setState(() {
        _totalGastos = total;
      });
    } catch (e) {
      debugPrint('Erro ao carregar gastos: $e');
    }
  }

  Future<void> _carregarPatrocinadores() async {
    try {
      final patrocinadoresSnapshot = await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      double totalValor = 0;

      for (var doc in patrocinadoresSnapshot.docs) {
        final data = doc.data();

        if (data['valor'] != null) {
          totalValor += (data['valor'] as num?)?.toDouble() ?? 0;
        }

        if (data['valor_patrocinio'] != null) {
          totalValor += (data['valor_patrocinio'] as num?)?.toDouble() ?? 0;
        }

        final valorInicial = (data['valor_inicial'] as num?)?.toDouble() ?? 0;
        final saldo = (data['saldo_disponivel'] as num?)?.toDouble() ?? 0;

        if (valorInicial > 0) {
          totalValor += valorInicial - saldo;
        }
      }

      setState(() {
        _totalPatrocinioValor = totalValor;
      });
    } catch (e) {
      debugPrint('Erro ao carregar patrocinadores: $e');
    }
  }

  // 🔥 NOVO: Carrega TODAS as camisas (participações + avulsas)
  Future<void> _carregarTodasCamisas() async {
    try {
      final Map<String, int> contagemCombinada = {};

      // 1️⃣ Busca camisas das PARTICIPAÇÕES
      final participacoesSnapshot = await FirebaseFirestore.instance
          .collection('participacoes_eventos_em_andamento')
          .where('evento_id', isEqualTo: widget.eventoId)
          .where('tamanho_camisa', isNotEqualTo: null)
          .get();

      for (var doc in participacoesSnapshot.docs) {
        final tamanho = doc['tamanho_camisa'] as String?;
        if (tamanho != null && tamanho.isNotEmpty) {
          contagemCombinada[tamanho] = (contagemCombinada[tamanho] ?? 0) + 1;
        }
      }

      debugPrint('📊 Camisas de PARTICIPAÇÕES: ${participacoesSnapshot.docs.length}');

      // 2️⃣ Busca camisas AVULSAS
      final camisasSnapshot = await FirebaseFirestore.instance
          .collection('camisas_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();

      for (var doc in camisasSnapshot.docs) {
        final tamanho = doc['tamanho'] as String?;
        if (tamanho != null && tamanho.isNotEmpty) {
          contagemCombinada[tamanho] = (contagemCombinada[tamanho] ?? 0) + 1;
        }
      }

      debugPrint('📊 Camisas AVULSAS: ${camisasSnapshot.docs.length}');

      setState(() {
        _camisasCount = Map.fromEntries(
          contagemCombinada.entries.toList()..sort((a, b) {
            // Ordenação personalizada (PP, P, M, G, GG, XG, XXG, 4A, 6A, etc)
            final ordem = ['PP', 'P', 'M', 'G', 'GG', 'XG', 'XXG', '4A', '6A', '8A', '10A', '12A', '14A'];
            final indexA = ordem.indexOf(a.key);
            final indexB = ordem.indexOf(b.key);
            if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
            if (indexA != -1) return -1;
            if (indexB != -1) return 1;
            return a.key.compareTo(b.key);
          }),
        );
        _totalCamisas = contagemCombinada.values.fold(0, (sum, val) => sum + val);
      });

      debugPrint('🎯 TOTAL DE CAMISAS: $_totalCamisas');
      debugPrint('📋 Distribuição: $_camisasCount');

    } catch (e) {
      debugPrint('❌ Erro ao carregar camisas: $e');
    }
  }

  // 🔥 DIÁLOGO SIMPLIFICADO - SÓ MOSTRA TAMANHOS E QUANTIDADES
  void _mostrarDetalhesCamisas() {
    if (_camisasCount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma camisa registrada'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.orange.shade50,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shopping_bag,
                      color: Colors.orange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Camisas do Evento',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Total de camisas
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade300, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL DE CAMISAS:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                    Text(
                      '$_totalCamisas',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Distribuição por tamanho
              const Text(
                '📊 DISTRIBUIÇÃO POR TAMANHO',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // Grid de tamanhos
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _camisasCount.length,
                itemBuilder: (context, index) {
                  final entry = _camisasCount.entries.elementAt(index);
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.shade100.withOpacity(0.5),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${entry.value}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirLink(String? url) async {
    if (url == null || url.isEmpty) return;

    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível abrir o link'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir link: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatarData() {
    return widget.evento.dataFormatada;
  }

  String _formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final evento = widget.evento;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Gerenciar Evento',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_podeVerRelatorios)
            IconButton(
              icon: const Icon(Icons.assessment_rounded),
              onPressed: _abrirRelatorioFinanceiro,
              tooltip: 'Relatório Financeiro',
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _compartilharEvento,
            tooltip: 'Compartilhar',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : RefreshIndicator(
        onRefresh: _carregarDados,
        color: Colors.red.shade900,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(evento),
                    const SizedBox(height: 14),
                    _buildEstatisticasCard(),
                    const SizedBox(height: 14),
                    _buildMenuBotoes(evento),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.red.shade900),
            const SizedBox(height: 14),
            Text(
              'Carregando dados do evento...',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirRelatorioFinanceiro() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RelatorioFinanceiroScreen(
          eventoId: widget.eventoId,
          eventoNome: widget.evento.nome,
        ),
      ),
    );
  }

  Widget _buildHeader(EventoModel evento) {
    final hasBanner = evento.linkBanner != null && evento.linkBanner!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1.65,
              child: hasBanner
                  ? Image.network(
                evento.linkBanner!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallbackBanner(),
              )
                  : _buildFallbackBanner(),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.10),
                      Colors.black.withOpacity(0.50),
                      Colors.black.withOpacity(0.86),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _headerChip(
                        icon: Icons.pending_actions_rounded,
                        text: 'EM ANDAMENTO',
                        color: Colors.green,
                      ),
                      if (evento.tipo.trim().isNotEmpty)
                        _headerChip(
                          icon: evento.iconeDoTipo,
                          text: evento.tipo,
                          color: Colors.orange,
                        ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Text(
                    evento.nome,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.03,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _headerMeta(Icons.calendar_month_rounded, _formatarData()),
                      if (evento.horario.trim().isNotEmpty)
                        _headerMeta(Icons.access_time_rounded, evento.horario),
                      if (evento.cidade.trim().isNotEmpty)
                        _headerMeta(Icons.location_city_rounded, evento.cidade),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.event_available_rounded, size: 72, color: Colors.white),
      ),
    );
  }

  Widget _headerChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.44),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerMeta(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTituloEvento(EventoModel evento) {
    return const SizedBox.shrink();
  }

  Widget _buildEstatisticasCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.dashboard_rounded,
            title: 'Resumo do evento',
            subtitle: 'Dados atualizados de participantes, camisas, gastos e patrocínios.',
            color: Colors.red.shade900,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 620 ? 2 : 4;
              const spacing = 10.0;
              final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

              final items = [
                _StatData(Icons.people_rounded, '$_totalParticipantes', 'Participantes', Colors.blue, null),
                _StatData(Icons.shopping_bag_rounded, '$_totalCamisas', 'Camisas', Colors.orange, _mostrarDetalhesCamisas),
                _StatData(Icons.money_off_rounded, _formatarMoeda(_totalGastos), 'Gastos', Colors.red, null),
                _StatData(Icons.volunteer_activism_rounded, _formatarMoeda(_totalPatrocinioValor), 'Patrocínio', Colors.green, null),
              ];

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: items.map((item) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildStatItem(
                      icon: item.icon,
                      value: item.value,
                      label: item.label,
                      color: item.color,
                      onTap: item.onTap,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuBotoes(EventoModel evento) {
    final buttons = <Widget>[
      if (_podeGerenciarParticipantes)
        _buildMenuButton(
          icon: Icons.people_rounded,
          title: 'Participantes',
          subtitle: 'Adicionar, remover e acompanhar alunos',
          color: Colors.blue,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ParticipantesEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                  evento: evento,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeGerenciarFinanceiro)
        _buildMenuButton(
          icon: Icons.attach_money_rounded,
          title: 'Gastos',
          subtitle: 'Controlar despesas do evento',
          color: Colors.red,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GastosEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeGerenciarPatrocinadores)
        _buildMenuButton(
          icon: Icons.volunteer_activism_rounded,
          title: 'Patrocinadores',
          subtitle: 'Gerenciar apoios e beneficiados',
          color: Colors.green,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PatrocinadoresEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeGerenciarCamisas)
        _buildMenuButton(
          icon: Icons.shopping_bag_rounded,
          title: 'Camisas avulsas',
          subtitle: 'Registrar e conferir camisas extras',
          color: Colors.orange,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CamisasEventoScreen(
                  eventoId: widget.eventoId,
                  eventoNome: evento.nome,
                ),
              ),
            ).then((_) => _carregarDados());
          },
        ),
      if (_podeVerRelatorios)
        _buildMenuButton(
          icon: Icons.assessment_rounded,
          title: 'Relatório financeiro',
          subtitle: 'PDFs, conferências e resumo geral',
          color: Colors.purple,
          onTap: _abrirRelatorioFinanceiro,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.apps_rounded,
            title: 'Ações do evento',
            subtitle: 'Escolha o que deseja gerenciar.',
            color: Colors.red.shade900,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              if (!wide) {
                return Column(children: buttons);
              }

              const spacing = 12.0;
              final itemWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: buttons.map((b) => SizedBox(width: itemWidth, child: b)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Toque para ver',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.12)),
              color: color.withOpacity(0.035),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(icon, color: color, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11.5,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Future<void> _compartilharEvento() async {
    final String organizadores = widget.evento.organizadores is List
        ? (widget.evento.organizadores as List).join(', ')
        : widget.evento.organizadores?.toString() ?? 'Não informado';

    String texto = '''
🎉 *${widget.evento.nome}* (EM ANDAMENTO)

📅 Data: ${_formatarData()} ${widget.evento.horario.isNotEmpty ? 'às ${widget.evento.horario}' : ''}
📍 Local: ${widget.evento.local} - ${widget.evento.cidade}

👥 Organizadores: $organizadores

📊 Estatísticas atuais:
• Participantes: $_totalParticipantes
• Gastos: ${_formatarMoeda(_totalGastos)}
• Patrocínios: ${_formatarMoeda(_totalPatrocinioValor)}
• Camisas: $_totalCamisas

🔗 Gerencie este evento no app UAI CAPOEIRA!
''';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compartilhamento será implementado'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

class _StatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _StatData(this.icon, this.value, this.label, this.color, this.onTap);
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Text(
        'EM ANDAMENTO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}