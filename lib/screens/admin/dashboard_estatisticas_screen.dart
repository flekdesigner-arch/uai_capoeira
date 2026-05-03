import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardEstatisticasScreen extends StatefulWidget {
  const DashboardEstatisticasScreen({super.key});

  @override
  State<DashboardEstatisticasScreen> createState() => _DashboardEstatisticasScreenState();
}

class _DashboardEstatisticasScreenState extends State<DashboardEstatisticasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic> _dadosAgregados = {};
  List<Map<String, dynamic>> _acessosCarregados = [];
  int _totalAcessos = 0;
  bool _carregandoInicial = true;
  bool _carregandoMais = false;
  bool _temMaisDados = true;
  String _filtroPeriodo = 'todos';
  int _visitasHoje = 0;
  int _visitasSemana = 0;
  int _visitasMes = 0;
  Map<String, int> _acessosPorHora = {};
  Map<String, int> _acessosPorDia = {};

  DocumentSnapshot? _ultimoDocumento;
  final int _limitePorPagina = 30;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _carregarDadosAgregados();
    _carregarPrimeiraPagina();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _carregarMaisAcessos();
    }
  }

  Future<void> _carregarDadosAgregados() async {
    try {
      final docAgregado = await _firestore
          .collection('estatisticas')
          .doc('contadores_agregados')
          .get();

      if (docAgregado.exists && docAgregado.data() != null) {
        final data = docAgregado.data()!;
        setState(() {
          _dadosAgregados = _converterNotacaoPontoParaArvore(data);
          _totalAcessos = (data['total_visitas'] ?? 0) as int;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar dados agregados: $e');
    }
  }

  Future<void> _carregarPrimeiraPagina() async {
    setState(() {
      _carregandoInicial = true;
      _acessosCarregados = [];
      _ultimoDocumento = null;
      _temMaisDados = true;
    });

    try {
      Query query = _firestore
          .collection('estatisticas_acessos')
          .orderBy('data_acesso', descending: true)
          .limit(_limitePorPagina);

      final snapshot = await query.get();

      final List<Map<String, dynamic>> acessos = [];
      for (var doc in snapshot.docs) {
        final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        acessos.add(data);
      }

      setState(() {
        _acessosCarregados = acessos;
        if (snapshot.docs.isNotEmpty) {
          _ultimoDocumento = snapshot.docs.last;
        }
        _temMaisDados = snapshot.docs.length == _limitePorPagina;
        _carregandoInicial = false;
      });

      _calcularEstatisticasLocais();
    } catch (e) {
      print('❌ Erro ao carregar primeira página: $e');
      setState(() => _carregandoInicial = false);
    }
  }

  Future<void> _carregarMaisAcessos() async {
    if (_carregandoMais || !_temMaisDados || _carregandoInicial || _ultimoDocumento == null) return;

    setState(() => _carregandoMais = true);

    try {
      Query query = _firestore
          .collection('estatisticas_acessos')
          .orderBy('data_acesso', descending: true)
          .startAfterDocument(_ultimoDocumento!)
          .limit(_limitePorPagina);

      final snapshot = await query.get();

      final List<Map<String, dynamic>> novosAcessos = [];
      for (var doc in snapshot.docs) {
        final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        novosAcessos.add(data);
      }

      setState(() {
        _acessosCarregados.addAll(novosAcessos);
        if (snapshot.docs.isNotEmpty) {
          _ultimoDocumento = snapshot.docs.last;
        }
        _temMaisDados = snapshot.docs.length == _limitePorPagina;
        _carregandoMais = false;
      });

      _recalcularEstatisticasCompletas();
    } catch (e) {
      print('❌ Erro ao carregar mais acessos: $e');
      setState(() => _carregandoMais = false);
    }
  }

  void _calcularEstatisticasLocais() {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
    final inicioMes = DateTime(agora.year, agora.month, 1);

    int visitasHoje = 0;
    int visitasSemana = 0;
    int visitasMes = 0;
    final Map<String, int> porHora = {};
    final Map<String, int> porDia = {};

    for (var acesso in _acessosCarregados) {
      final Timestamp? timestamp = acesso['data_acesso'] as Timestamp?;
      final DateTime? dataAcesso = timestamp?.toDate();

      if (dataAcesso != null) {
        if (dataAcesso.isAfter(hoje)) visitasHoje++;
        if (dataAcesso.isAfter(inicioSemana)) visitasSemana++;
        if (dataAcesso.isAfter(inicioMes)) visitasMes++;

        final horaKey = '${dataAcesso.hour.toString().padLeft(2, '0')}:00';
        porHora[horaKey] = (porHora[horaKey] ?? 0) + 1;

        final diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
        final diaKey = diasSemana[dataAcesso.weekday - 1];
        porDia[diaKey] = (porDia[diaKey] ?? 0) + 1;
      }
    }

    setState(() {
      _visitasHoje = visitasHoje;
      _visitasSemana = visitasSemana;
      _visitasMes = visitasMes;
      _acessosPorHora = porHora;
      _acessosPorDia = porDia;
    });
  }

  void _recalcularEstatisticasCompletas() {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
    final inicioMes = DateTime(agora.year, agora.month, 1);

    int visitasHoje = 0;
    int visitasSemana = 0;
    int visitasMes = 0;
    final Map<String, int> porHora = {};
    final Map<String, int> porDia = {};

    for (var acesso in _acessosCarregados) {
      final Timestamp? timestamp = acesso['data_acesso'] as Timestamp?;
      final DateTime? dataAcesso = timestamp?.toDate();

      if (dataAcesso != null) {
        if (dataAcesso.isAfter(hoje)) visitasHoje++;
        if (dataAcesso.isAfter(inicioSemana)) visitasSemana++;
        if (dataAcesso.isAfter(inicioMes)) visitasMes++;

        final horaKey = '${dataAcesso.hour.toString().padLeft(2, '0')}:00';
        porHora[horaKey] = (porHora[horaKey] ?? 0) + 1;

        final diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
        final diaKey = diasSemana[dataAcesso.weekday - 1];
        porDia[diaKey] = (porDia[diaKey] ?? 0) + 1;
      }
    }

    setState(() {
      _visitasHoje = visitasHoje;
      _visitasSemana = visitasSemana;
      _visitasMes = visitasMes;
      _acessosPorHora = porHora;
      _acessosPorDia = porDia;
    });
  }

  Map<String, dynamic> _converterNotacaoPontoParaArvore(Map<String, dynamic> dados) {
    final Map<String, dynamic> resultado = {};

    dados.forEach((chave, valor) {
      if (chave == 'total_visitas' || chave == 'ultima_atualizacao') {
        resultado[chave] = valor;
      } else if (chave.contains('.')) {
        final partes = chave.split('.');
        Map<String, dynamic> atual = resultado;

        for (int i = 0; i < partes.length - 1; i++) {
          final parte = partes[i];
          if (!atual.containsKey(parte)) {
            atual[parte] = <String, dynamic>{};
          }
          atual = atual[parte] as Map<String, dynamic>;
        }

        final ultimaParte = partes.last;
        atual[ultimaParte] = valor;
      } else {
        resultado[chave] = valor;
      }
    });

    return resultado;
  }

  List<Map<String, dynamic>> _getAcessosFiltrados() {
    if (_filtroPeriodo == 'todos') return _acessosCarregados;

    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    DateTime dataLimite;

    switch (_filtroPeriodo) {
      case 'hoje':
        dataLimite = hoje;
        break;
      case 'semana':
        dataLimite = hoje.subtract(Duration(days: hoje.weekday - 1));
        break;
      case 'mes':
        dataLimite = DateTime(agora.year, agora.month, 1);
        break;
      default:
        dataLimite = DateTime(2000);
    }

    return _acessosCarregados.where((acesso) {
      final Timestamp? timestamp = acesso['data_acesso'] as Timestamp?;
      final DateTime? dataAcesso = timestamp?.toDate();
      return dataAcesso != null && dataAcesso.isAfter(dataLimite);
    }).toList();
  }

  // ==================== ABRIR COORDENADAS NO GOOGLE MAPS ====================
  Future<void> _abrirGoogleMaps(double? latitude, double? longitude) async {
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordenadas não disponíveis para este acesso')),
      );
      return;
    }

    final url = 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o mapa')),
      );
    }
  }

  // ==================== EXIBIR RASTRO DO DOCUMENTO ====================
  void _mostrarRastroDocumento(Map<String, dynamic> documento) {
    print('🖱️ Clicou no acesso: ${documento['id']} - ${documento['cidade']}');

    // Garante que eventos seja uma lista
    List<Map<String, dynamic>> eventosMap = [];
    final eventosRaw = documento['eventos'];
    if (eventosRaw is List) {
      eventosMap = eventosRaw.map((e) {
        if (e is Map<String, dynamic>) return e;
        return <String, dynamic>{};
      }).toList();
    }

    final totalEventos = eventosMap.length;
    final menus = eventosMap.where((e) => e['tipo'] == 'menu').length;
    final botoes = eventosMap.where((e) => e['tipo'] == 'botao_social').length;
    final cards = eventosMap.where((e) => e['tipo'] == 'card').length;
    final paginas = eventosMap.where((e) => e['tipo'] == 'pagina').length;

    final latitude = documento['latitude'] as double?;
    final longitude = documento['longitude'] as double?;

    print('📊 Eventos encontrados: $totalEventos');

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.timeline, color: Colors.blue.shade900, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📊 RASTRO COMPLETO DO ACESSO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(
                          'IP: ${documento['ip']} • ${documento['cidade']}/${documento['estado']}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Resumo dos eventos
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem('🎯 Total', totalEventos.toString(), Colors.blue),
                    _buildResumoItem('📋 Menus', menus.toString(), Colors.green),
                    _buildResumoItem('🔘 Botões', botoes.toString(), Colors.orange),
                    _buildResumoItem('🃏 Cards', cards.toString(), Colors.purple),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Botão do Google Maps
              if (latitude != null && longitude != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ElevatedButton.icon(
                    onPressed: () => _abrirGoogleMaps(latitude, longitude),
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('Ver localização no Google Maps'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

              const Text('🕐 LINHA DO TEMPO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: eventosMap.isEmpty
                    ? const Center(child: Text('Nenhum evento registrado nesta sessão'))
                    : ListView.separated(
                  itemCount: eventosMap.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final evento = eventosMap[index];
                    // Usa o campo data_hora (string ISO) para exibir o horário
                    final String dataHoraStr = evento['data_hora'] ?? '';
                    String hora = '--:--:--';
                    if (dataHoraStr.isNotEmpty) {
                      try {
                        final dateTime = DateTime.parse(dataHoraStr);
                        hora = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
                      } catch (e) {}
                    }

                    IconData icone;
                    Color cor;
                    switch (evento['tipo'] as String) {
                      case 'menu':
                        icone = Icons.menu;
                        cor = Colors.green;
                        break;
                      case 'botao_social':
                        icone = Icons.share;
                        cor = Colors.blue;
                        break;
                      case 'card':
                        icone = Icons.grid_view;
                        cor = Colors.orange;
                        break;
                      case 'pagina':
                        icone = Icons.web;
                        cor = Colors.purple;
                        break;
                      default:
                        icone = Icons.touch_app;
                        cor = Colors.grey;
                    }

                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: cor.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(icone, color: cor, size: 20),
                      ),
                      title: Text(evento['nome'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('${evento['tipo']} • Origem: ${evento['origem'] ?? 'N/A'}', style: const TextStyle(fontSize: 11)),
                      trailing: Text(hora, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
              // Informações adicionais do acesso
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ℹ️ INFORMAÇÕES DO ACESSO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildInfoChip('ISP', documento['isp'] ?? 'N/A'),
                        _buildInfoChip('Data/Hora', _formatarDataHora(documento['data_acesso'] as Timestamp?)),
                        _buildInfoChip('Total Eventos', (documento['total_eventos'] ?? 0).toString()),
                        if (latitude != null && longitude != null)
                          _buildInfoChip('Coordenadas', '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumoItem(String label, String valor, Color cor) {
    return Column(
      children: [
        Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cor)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildInfoChip(String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text('$label: $valor', style: const TextStyle(fontSize: 10)),
    );
  }

  String _formatarDataHora(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final date = timestamp.toDate();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('📊 DASHBOARD DE VISITAS'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _carregarPrimeiraPagina();
              _carregarDadosAgregados();
            },
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _carregandoInicial
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardsRapidos(),
            const SizedBox(height: 20),
            _buildGraficoHoras(),
            const SizedBox(height: 20),
            _buildGraficoDiasSemana(),
            const SizedBox(height: 20),
            _buildTopCidadesEstados(),
            const SizedBox(height: 20),
            _buildFiltroPeriodo(),
            const SizedBox(height: 16),
            _buildListaAcessos(),
            if (_carregandoMais) _buildLoadingIndicator(),
            if (!_temMaisDados && _acessosCarregados.isNotEmpty) _buildFimLista(),
          ],
        ),
      ),
    );
  }

  Widget _buildListaAcessos() {
    final acessosFiltrados = _getAcessosFiltrados();

    if (acessosFiltrados.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: Text('Nenhum acesso registrado neste período')),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                '🕐 ACESSOS (${acessosFiltrados.length} de $_totalAcessos)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: acessosFiltrados.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _buildAcessoItem(acessosFiltrados[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: const Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Carregando mais acessos...'),
          ],
        ),
      ),
    );
  }

  Widget _buildFimLista() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade400),
            const SizedBox(height: 8),
            Text(
              '✅ Todos os $_totalAcessos acessos carregados',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== CARDS RÁPIDOS ====================
  Widget _buildCardsRapidos() {
    final isSmallScreen = MediaQuery.of(context).size.width < 400;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isSmallScreen ? 2 : 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: isSmallScreen ? 1.2 : 1.3,
      children: [
        _buildCardRapidoItem('Total', _totalAcessos.toString(), Icons.people, Colors.red),
        _buildCardRapidoItem('Hoje', _visitasHoje.toString(), Icons.today, Colors.orange),
        _buildCardRapidoItem('Semana', _visitasSemana.toString(), Icons.calendar_view_week, Colors.green),
        _buildCardRapidoItem('Mês', _visitasMes.toString(), Icons.calendar_month, Colors.blue),
      ],
    );
  }

  Widget _buildCardRapidoItem(String titulo, String valor, IconData icone, Color cor) {
    final isSmallScreen = MediaQuery.of(context).size.width < 400;
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 10 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
            decoration: BoxDecoration(color: cor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Icon(icone, color: cor, size: isSmallScreen ? 16 : 20),
          ),
          const Spacer(),
          Text(valor, style: TextStyle(fontSize: isSmallScreen ? 22 : 28, fontWeight: FontWeight.bold)),
          Text(titulo, style: TextStyle(fontSize: isSmallScreen ? 11 : 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // ==================== GRÁFICOS ====================
  Widget _buildGraficoHoras() {
    if (_acessosPorHora.isEmpty) return const SizedBox.shrink();

    final horasOrdenadas = _acessosPorHora.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxY = horasOrdenadas.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(Icons.schedule, color: Colors.purple.shade700), const SizedBox(width: 8), const Text('⏰ ACESSOS POR HORA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final hora = horasOrdenadas[group.x].key;
                      final valor = horasOrdenadas[group.x].value;
                      return BarTooltipItem('$hora\n$valor acesso${valor != 1 ? 's' : ''}', const TextStyle(color: Colors.white));
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < horasOrdenadas.length) {
                          return Padding(padding: const EdgeInsets.only(top: 8), child: Text(horasOrdenadas[value.toInt()].key, style: const TextStyle(fontSize: 9)));
                        }
                        return const Text('');
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        if (value % 1 == 0) return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10));
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1),
                barGroups: horasOrdenadas.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [BarChartRodData(toY: entry.value.value.toDouble(), color: Colors.purple.shade300, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraficoDiasSemana() {
    if (_acessosPorDia.isEmpty) return const SizedBox.shrink();

    final diasOrdem = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
    final dadosOrdenados = diasOrdem.map((dia) => MapEntry(dia, _acessosPorDia[dia] ?? 0)).toList();
    final maxY = dadosOrdenados.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(Icons.calendar_today, color: Colors.teal.shade700), const SizedBox(width: 8), const Text('📅 ACESSOS POR DIA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final dia = dadosOrdenados[group.x].key;
                      final valor = dadosOrdenados[group.x].value;
                      return BarTooltipItem('$dia\n$valor acesso${valor != 1 ? 's' : ''}', const TextStyle(color: Colors.white));
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() < dadosOrdenados.length) {
                          return Padding(padding: const EdgeInsets.only(top: 8), child: Text(dadosOrdenados[value.toInt()].key, style: const TextStyle(fontSize: 10)));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        if (value % 1 == 0) return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10));
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1),
                barGroups: dadosOrdenados.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [BarChartRodData(toY: entry.value.value.toDouble(), color: Colors.teal.shade300, width: 20, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TOP CIDADES/ESTADOS ====================
  Widget _buildTopCidadesEstados() {
    Map<String, dynamic> paises = {};
    if (_dadosAgregados['paises'] != null) {
      paises = Map<String, dynamic>.from(_dadosAgregados['paises'] as Map);
    }

    final Map<String, int> cidades = {};
    final Map<String, int> estados = {};

    for (var pais in paises.values) {
      final estadosDoPais = (pais as Map<String, dynamic>)['estados'] as Map<String, dynamic>?;
      if (estadosDoPais != null) {
        for (var estadoEntry in estadosDoPais.entries) {
          final estadoNome = estadoEntry.key;
          final estadoData = estadoEntry.value as Map<String, dynamic>;
          estados[estadoNome] = (estadoData['total'] ?? 0) as int;

          final cidadesDoEstado = estadoData['cidades'] as Map<String, dynamic>?;
          if (cidadesDoEstado != null) {
            for (var cidadeEntry in cidadesDoEstado.entries) {
              cidades[cidadeEntry.key] = (cidadeEntry.value as Map<String, dynamic>)['total'] as int;
            }
          }
        }
      }
    }

    final topCidades = cidades.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topEstados = estados.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final isSmallScreen = MediaQuery.of(context).size.width < 400;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🏆 TOP LOCAIS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (isSmallScreen)
            Column(
              children: [
                _buildSecaoTop('Cidades', Icons.location_city, Colors.orange, topCidades.take(5).toList()),
                const SizedBox(height: 12),
                _buildSecaoTop('Estados', Icons.map, Colors.blue, topEstados.take(5).toList()),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildSecaoTop('Cidades', Icons.location_city, Colors.orange, topCidades.take(5).toList())),
                const SizedBox(width: 16),
                Expanded(child: _buildSecaoTop('Estados', Icons.map, Colors.blue, topEstados.take(5).toList())),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSecaoTop(String titulo, IconData icone, MaterialColor cor, List<MapEntry<String, int>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icone, size: 14, color: cor.shade700), const SizedBox(width: 4), Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))]),
        const SizedBox(height: 6),
        ...items.map((entry) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: cor.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text('${entry.value}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cor.shade900)),
              ),
            ],
          ),
        )),
      ],
    );
  }

  // ==================== FILTROS ====================
  Widget _buildFiltroPeriodo() {
    final isSmallScreen = MediaQuery.of(context).size.width < 400;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Padding(padding: const EdgeInsets.only(right: 8), child: Text('Filtrar:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: isSmallScreen ? 12 : 14))),
        _buildChipFiltro('Todos', 'todos'),
        _buildChipFiltro('Hoje', 'hoje'),
        _buildChipFiltro('Semana', 'semana'),
        _buildChipFiltro('Mês', 'mes'),
      ],
    );
  }

  Widget _buildChipFiltro(String label, String valor) {
    final selecionado = _filtroPeriodo == valor;
    final isSmallScreen = MediaQuery.of(context).size.width < 400;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: isSmallScreen ? 11 : 13)),
      selected: selecionado,
      onSelected: (_) => setState(() => _filtroPeriodo = valor),
      backgroundColor: Colors.grey.shade200,
      selectedColor: Colors.red.shade100,
      checkmarkColor: Colors.red.shade900,
      labelStyle: TextStyle(color: selecionado ? Colors.red.shade900 : Colors.grey.shade700, fontWeight: selecionado ? FontWeight.bold : FontWeight.normal),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  // ==================== ITEM DE ACESSO ====================
  Widget _buildAcessoItem(Map<String, dynamic> acesso) {
    final Timestamp? timestamp = acesso['data_acesso'] as Timestamp?;
    final DateTime dataAcesso = timestamp?.toDate() ?? DateTime.now();
    final dataFormatada = '${dataAcesso.day.toString().padLeft(2, '0')}/${dataAcesso.month.toString().padLeft(2, '0')}';
    final horaFormatada = '${dataAcesso.hour.toString().padLeft(2, '0')}:${dataAcesso.minute.toString().padLeft(2, '0')}';
    final ip = acesso['ip']?.toString() ?? 'N/A';
    final ipCurto = ip.contains('.') ? ip.substring(0, ip.lastIndexOf('.')) : ip;
    final eventos = acesso['eventos'];
    final temEventos = eventos is List && eventos.isNotEmpty;

    return InkWell(
      onTap: () {
        print('🔍 Toque no acesso: ${acesso['id']}');
        _mostrarRastroDocumento(acesso);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.green.shade300, Colors.green.shade500]), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${acesso['cidade'] ?? 'Desconhecida'}, ${acesso['estado'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('$dataFormatada $horaFormatada', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: temEventos ? Colors.blue.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: temEventos
                    ? [
                  Icon(Icons.timeline, size: 10, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text('Rastro', style: TextStyle(fontSize: 8, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
                ]
                    : [
                  Text(ipCurto, style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}