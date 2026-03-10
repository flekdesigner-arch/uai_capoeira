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
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (_podeVerRelatorios)
            IconButton(
              icon: const Icon(Icons.assessment),
              onPressed: _abrirRelatorioFinanceiro,
              tooltip: 'Relatório Financeiro',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _compartilharEvento,
            tooltip: 'Compartilhar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _carregarDados,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(evento),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTituloEvento(evento),
                    const SizedBox(height: 20),
                    _buildEstatisticasCard(),
                    const SizedBox(height: 20),
                    _buildMenuBotoes(evento),
                    const SizedBox(height: 20),
                    // Links removidos
                  ],
                ),
              ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      width: double.infinity,
      color: Colors.red.shade900.withOpacity(0.05),
      child: Center(
        child: Stack(
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.red.shade900,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: evento.linkBanner != null && evento.linkBanner!.isNotEmpty
                    ? Image.network(
                  evento.linkBanner!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildFallbackBanner(evento);
                  },
                )
                    : _buildFallbackBanner(evento),
              ),
            ),
            const Positioned(
              bottom: 0,
              right: 0,
              child: _StatusBadge(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackBanner(EventoModel evento) {
    return Container(
      color: Colors.red.shade900.withOpacity(0.1),
      child: Center(
        child: Icon(
          evento.iconeDoTipo,
          size: 50,
          color: Colors.red.shade900,
        ),
      ),
    );
  }

  Widget _buildTituloEvento(EventoModel evento) {
    return Column(
      children: [
        Text(
          evento.nome,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              '${_formatarData()} ${evento.horario.isNotEmpty ? 'às ${evento.horario}' : ''}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (evento.local.isNotEmpty || evento.cidade.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${evento.local}${evento.local.isNotEmpty && evento.cidade.isNotEmpty ? ' - ' : ''}${evento.cidade}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildEstatisticasCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.people,
                  value: '$_totalParticipantes',
                  label: 'Participantes',
                  color: Colors.blue,
                  onTap: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.attach_money,
                  value: _formatarMoeda(_totalGastos),
                  label: 'Gastos',
                  color: Colors.green,
                  onTap: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.volunteer_activism,
                  value: _formatarMoeda(_totalPatrocinioValor),
                  label: 'Patrocínios',
                  color: Colors.purple,
                  onTap: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.shopping_bag,
                  value: '$_totalCamisas',
                  label: 'Camisas',
                  color: Colors.orange,
                  onTap: _totalCamisas > 0 ? _mostrarDetalhesCamisas : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuBotoes(EventoModel evento) {
    return Column(
      children: [
        if (_podeGerenciarParticipantes)
          _buildMenuButton(
            icon: Icons.people,
            title: 'Gerenciar Participantes',
            subtitle: 'Adicione alunos participantes do evento',
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
            icon: Icons.attach_money,
            title: 'Gerenciar Gastos',
            subtitle: 'Controle de despesas do evento',
            color: Colors.green,
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
            icon: Icons.star,
            title: 'Gerenciar Patrocinadores',
            subtitle: 'Adicione patrocinadores e apoios',
            color: Colors.amber,
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
        if (_podeGerenciarCamisas && evento.temCamisa)
          _buildMenuButton(
            icon: Icons.shopping_bag,
            title: 'Gerenciar Camisas',
            subtitle: 'Lista de camisas por tamanho',
            color: Colors.purple,
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
        if (!_podeGerenciarParticipantes &&
            !_podeGerenciarFinanceiro &&
            !_podeGerenciarPatrocinadores &&
            !_podeGerenciarCamisas)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.lock, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'Você não tem permissão para gerenciar este evento',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onTap != null ? color : color.withOpacity(0.3),
            width: onTap != null ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            if (onTap != null) ...[
              const SizedBox(height: 4),
              Icon(
                Icons.touch_app,
                size: 12,
                color: color.withOpacity(0.7),
              ),
            ],
          ],
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade600),
        onTap: onTap,
      ),
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