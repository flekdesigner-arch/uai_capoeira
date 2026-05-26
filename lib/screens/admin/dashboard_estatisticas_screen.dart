import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardEstatisticasScreen extends StatefulWidget {
  const DashboardEstatisticasScreen({super.key});

  @override
  State<DashboardEstatisticasScreen> createState() =>
      _DashboardEstatisticasScreenState();
}

class _DashboardEstatisticasScreenState
    extends State<DashboardEstatisticasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic> _dadosAgregados = {};
  List<Map<String, dynamic>> _acessosCarregados = [];

  int _totalAcessos = 0;
  int _visitasHoje = 0;
  int _visitasSemana = 0;
  int _visitasMes = 0;

  Map<String, int> _acessosPorHora = {};
  Map<String, int> _acessosPorDia = {};

  bool _carregandoInicial = true;
  bool _carregandoMais = false;
  bool _temMaisDados = true;

  String _filtroPeriodo = 'todos';

  DocumentSnapshot? _ultimoDocumento;
  final int _limitePorPagina = 30;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final posicao = _scrollController.position;
    if (posicao.pixels >= posicao.maxScrollExtent - 240) {
      _carregarMaisAcessos();
    }
  }

  Future<void> _carregarTudo() async {
    await Future.wait([
      _carregarDadosAgregados(),
      _carregarPrimeiraPagina(),
    ]);
  }

  Future<void> _atualizarTudo() async {
    await _carregarTudo();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Dashboard atualizado com sucesso'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _carregarDadosAgregados() async {
    try {
      final docAgregado = await _firestore
          .collection('estatisticas')
          .doc('contadores_agregados')
          .get();

      if (!mounted) return;

      if (docAgregado.exists && docAgregado.data() != null) {
        final data = docAgregado.data()!;

        setState(() {
          _dadosAgregados = _converterNotacaoPontoParaArvore(data);
          _totalAcessos = (data['total_visitas'] ?? 0) as int;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados agregados: $e');
    }
  }

  Future<void> _carregarPrimeiraPagina() async {
    if (mounted) {
      setState(() {
        _carregandoInicial = true;
        _acessosCarregados = [];
        _ultimoDocumento = null;
        _temMaisDados = true;
      });
    }

    try {
      final query = _firestore
          .collection('estatisticas_acessos')
          .orderBy('data_acesso', descending: true)
          .limit(_limitePorPagina);

      final snapshot = await query.get();

      final acessos = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (!mounted) return;

      setState(() {
        _acessosCarregados = acessos;
        _ultimoDocumento = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _temMaisDados = snapshot.docs.length == _limitePorPagina;
        _carregandoInicial = false;
      });

      _recalcularEstatisticasCompletas();
    } catch (e) {
      debugPrint('❌ Erro ao carregar primeira página: $e');
      if (mounted) setState(() => _carregandoInicial = false);
    }
  }

  Future<void> _carregarMaisAcessos() async {
    if (_carregandoMais ||
        !_temMaisDados ||
        _carregandoInicial ||
        _ultimoDocumento == null) {
      return;
    }

    setState(() => _carregandoMais = true);

    try {
      final query = _firestore
          .collection('estatisticas_acessos')
          .orderBy('data_acesso', descending: true)
          .startAfterDocument(_ultimoDocumento!)
          .limit(_limitePorPagina);

      final snapshot = await query.get();

      final novosAcessos = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (!mounted) return;

      setState(() {
        _acessosCarregados.addAll(novosAcessos);
        _ultimoDocumento = snapshot.docs.isNotEmpty ? snapshot.docs.last : _ultimoDocumento;
        _temMaisDados = snapshot.docs.length == _limitePorPagina;
        _carregandoMais = false;
      });

      _recalcularEstatisticasCompletas();
    } catch (e) {
      debugPrint('❌ Erro ao carregar mais acessos: $e');
      if (mounted) setState(() => _carregandoMais = false);
    }
  }

  void _recalcularEstatisticasCompletas() {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
    final inicioMes = DateTime(agora.year, agora.month, 1);

    int visitasHoje = 0;
    int visitasSemana = 0;
    int visitasMes = 0;

    final porHora = <String, int>{};
    final porDia = <String, int>{};

    for (final acesso in _acessosCarregados) {
      final timestamp = acesso['data_acesso'];
      final dataAcesso = timestamp is Timestamp ? timestamp.toDate() : null;

      if (dataAcesso == null) continue;

      if (dataAcesso.isAfter(hoje)) visitasHoje++;
      if (dataAcesso.isAfter(inicioSemana)) visitasSemana++;
      if (dataAcesso.isAfter(inicioMes)) visitasMes++;

      final horaKey = '${dataAcesso.hour.toString().padLeft(2, '0')}:00';
      porHora[horaKey] = (porHora[horaKey] ?? 0) + 1;

      final diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
      final diaKey = diasSemana[dataAcesso.weekday - 1];
      porDia[diaKey] = (porDia[diaKey] ?? 0) + 1;
    }

    if (!mounted) return;

    setState(() {
      _visitasHoje = visitasHoje;
      _visitasSemana = visitasSemana;
      _visitasMes = visitasMes;
      _acessosPorHora = porHora;
      _acessosPorDia = porDia;
    });
  }

  Map<String, dynamic> _converterNotacaoPontoParaArvore(
      Map<String, dynamic> dados,
      ) {
    final resultado = <String, dynamic>{};

    dados.forEach((chave, valor) {
      if (chave == 'total_visitas' || chave == 'ultima_atualizacao') {
        resultado[chave] = valor;
      } else if (chave.contains('.')) {
        final partes = chave.split('.');
        Map<String, dynamic> atual = resultado;

        for (int i = 0; i < partes.length - 1; i++) {
          final parte = partes[i];
          atual.putIfAbsent(parte, () => <String, dynamic>{});
          atual = atual[parte] as Map<String, dynamic>;
        }

        atual[partes.last] = valor;
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

    final dataLimite = switch (_filtroPeriodo) {
      'hoje' => hoje,
      'semana' => hoje.subtract(Duration(days: hoje.weekday - 1)),
      'mes' => DateTime(agora.year, agora.month, 1),
      _ => DateTime(2000),
    };

    return _acessosCarregados.where((acesso) {
      final timestamp = acesso['data_acesso'];
      final dataAcesso = timestamp is Timestamp ? timestamp.toDate() : null;
      return dataAcesso != null && dataAcesso.isAfter(dataLimite);
    }).toList();
  }

  String _formatarDataHora(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';

    final date = timestamp.toDate();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatarHoraEvento(dynamic valor) {
    if (valor == null) return '--:--:--';

    try {
      DateTime? dateTime;

      if (valor is Timestamp) {
        dateTime = valor.toDate();
      } else {
        final texto = valor.toString();
        if (texto.trim().isNotEmpty) {
          dateTime = DateTime.parse(texto);
        }
      }

      if (dateTime == null) return '--:--:--';

      return '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}:'
          '${dateTime.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--:--';
    }
  }

  Future<void> _abrirGoogleMaps(double? latitude, double? longitude) async {
    if (latitude == null || longitude == null) {
      _mostrarSnack('Coordenadas não disponíveis para este acesso', erro: true);
      return;
    }

    final lat = latitude.toStringAsFixed(6);
    final lng = longitude.toStringAsFixed(6);

    final urls = <Uri>[
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
      Uri.parse('https://maps.google.com/?q=$lat,$lng'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];

    for (final uri in urls) {
      try {
        final abriu = await launchUrl(
          uri,
          mode: uri.scheme == 'geo'
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );

        if (abriu) return;
      } catch (e) {
        debugPrint('⚠️ Falha ao abrir mapa com $uri: $e');
      }
    }

    _mostrarSnack('Não foi possível abrir o Google Maps neste dispositivo.', erro: true);
  }

  void _mostrarSnack(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _contarEventos(List<Map<String, dynamic>> eventos, String tipo) {
    return eventos.where((e) => e['tipo']?.toString() == tipo).length;
  }

  Map<String, int> _resumoTiposEvento(List<Map<String, dynamic>> eventos) {
    return {
      'menus': _contarEventos(eventos, 'menu'),
      'botoes': _contarEventos(eventos, 'botao_social') + _contarEventos(eventos, 'clique'),
      'cards': _contarEventos(eventos, 'card'),
      'paginas': _contarEventos(eventos, 'pagina'),
      'telas': _contarEventos(eventos, 'tela'),
      'formularios': _contarEventos(eventos, 'formulario'),
      'etapas': _contarEventos(eventos, 'etapa_formulario'),
      'erros': _contarEventos(eventos, 'erro_formulario'),
      'conversoes': _contarEventos(eventos, 'conversao'),
      'campos': _contarEventos(eventos, 'campo_formulario'),
      'snapshots': _contarEventos(eventos, 'snapshot_formulario'),
      'rolagens': _contarEventos(eventos, 'rolagem'),
      'filtros': _contarEventos(eventos, 'filtro'),
      'itens': _contarEventos(eventos, 'item_visualizado'),
    };
  }

  int _contarCamposSuspeitos(List<Map<String, dynamic>> eventos) {
    var total = 0;

    for (final evento in eventos) {
      final metadata = evento['metadata'];
      if (metadata is! Map) continue;

      if (metadata['suspeito'] == true) total++;

      final camposSuspeitos = metadata['campos_suspeitos'];
      if (camposSuspeitos is List) total += camposSuspeitos.length;
    }

    return total;
  }

  int _somarDuracaoEventos(List<Map<String, dynamic>> eventos, String tipo) {
    var total = 0;

    for (final evento in eventos) {
      if (evento['tipo']?.toString() != tipo) continue;
      final metadata = evento['metadata'];
      if (metadata is! Map) continue;
      final valor = metadata['duracao_segundos'] ?? metadata['duracao_etapa_segundos'];
      if (valor is int) total += valor;
      if (valor is double) total += valor.round();
    }

    return total;
  }

  String _formatarDuracao(int segundos) {
    if (segundos <= 0) return '0s';
    if (segundos < 60) return '${segundos}s';

    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    if (minutos < 60) return resto == 0 ? '${minutos}min' : '${minutos}min ${resto}s';

    final horas = minutos ~/ 60;
    final minutosRestantes = minutos % 60;
    return '${horas}h ${minutosRestantes}min';
  }

  String _descricaoEvento(Map<String, dynamic> evento) {
    final tipo = evento['tipo']?.toString() ?? 'evento';
    final metadataRaw = evento['metadata'];
    final metadata = metadataRaw is Map ? Map<String, dynamic>.from(metadataRaw) : <String, dynamic>{};

    switch (tipo) {
      case 'etapa_formulario':
        return '${metadata['acao'] ?? 'etapa'} • ${metadata['formulario'] ?? ''}';
      case 'erro_formulario':
        final erros = metadata['erros'];
        if (erros is List && erros.isNotEmpty) return erros.take(2).join(' | ');
        return 'Erro de formulário';
      case 'campo_formulario':
        final valor = metadata['valor']?.toString() ?? '';
        return valor.isEmpty ? 'Campo vazio' : 'Digitou: $valor';
      case 'snapshot_formulario':
        final suspeitos = metadata['campos_suspeitos'];
        if (suspeitos is List && suspeitos.isNotEmpty) {
          return 'Snapshot com campos suspeitos: ${suspeitos.join(', ')}';
        }
        return 'Snapshot de ${metadata['total_campos'] ?? 0} campos';
      case 'conversao':
        return 'Conversão registrada';
      case 'rolagem':
        return 'Rolagem até ${metadata['percentual'] ?? evento['nome']}';
      case 'filtro':
        return 'Filtro ${metadata['filtro'] ?? evento['nome']}: ${metadata['valor'] ?? ''}';
      case 'item_visualizado':
        return '${metadata['item_tipo'] ?? 'item'} visualizado';
      case 'tela':
        return '${metadata['acao'] ?? ''}${metadata['duracao_segundos'] != null ? ' • ${_formatarDuracao((metadata['duracao_segundos'] as num).round())}' : ''}';
      default:
        return '${evento['tipo'] ?? ''} • Origem: ${evento['origem'] ?? 'N/A'}';
    }
  }

  void _mostrarRastroDocumento(Map<String, dynamic> documento) {
    final eventosMap = <Map<String, dynamic>>[];
    final eventosRaw = documento['eventos'];

    if (eventosRaw is List) {
      for (final e in eventosRaw) {
        if (e is Map<String, dynamic>) {
          eventosMap.add(e);
        } else if (e is Map) {
          eventosMap.add(Map<String, dynamic>.from(e));
        }
      }
    }

    final totalEventos = eventosMap.length;
    final resumoTipos = _resumoTiposEvento(eventosMap);
    final camposSuspeitos = _contarCamposSuspeitos(eventosMap);

    final latitude = _toDouble(documento['latitude']);
    final longitude = _toDouble(documento['longitude']);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        backgroundColor: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = MediaQuery.of(context).size.width;
            final compact = width < 520;

            return Container(
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildRastroHeader(documento, compact),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(compact ? 12 : 16),
                      children: [
                        _buildResumoEventos(
                          totalEventos: totalEventos,
                          resumoTipos: resumoTipos,
                          camposSuspeitos: camposSuspeitos,
                          compact: compact,
                        ),
                        const SizedBox(height: 10),
                        _buildInteligenciaFluxo(eventosMap, compact),
                        if (latitude != null && longitude != null) ...[
                          const SizedBox(height: 10),
                          _buildMapaCard(latitude, longitude),
                        ],
                        const SizedBox(height: 14),
                        _buildTimeline(eventosMap, compact),
                        const SizedBox(height: 14),
                        _buildInfoAcesso(documento, latitude, longitude),
                      ],
                    ),
                  ),
                  _buildRastroBottomBar(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 520;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Dashboard de Visitas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: compact,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
            onPressed: _atualizarTudo,
          ),
        ],
      ),
      body: _carregandoInicial
          ? _buildLoadingInicial()
          : RefreshIndicator(
        color: Colors.red.shade900,
        onRefresh: _atualizarTudo,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 20,
                  compact ? 12 : 18,
                  compact ? 12 : 20,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroDashboard(compact),
                        const SizedBox(height: 12),
                        _buildCardsRapidos(),
                        const SizedBox(height: 14),
                        _buildGraficosSection(compact),
                        const SizedBox(height: 14),
                        _buildTopCidadesEstados(),
                        const SizedBox(height: 14),
                        _buildFiltroPeriodo(),
                        const SizedBox(height: 10),
                        _buildListaAcessos(),
                        if (_carregandoMais) _buildLoadingIndicator(),
                        if (!_temMaisDados && _acessosCarregados.isNotEmpty)
                          _buildFimLista(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingInicial() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(radius: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.red.shade900),
            const SizedBox(height: 14),
            Text(
              'Carregando estatísticas...',
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

  Widget _buildHeroDashboard(bool compact) {
    final filtrados = _getAcessosFiltrados();

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 650;

          final icon = Container(
            width: compact ? 58 : 68,
            height: compact ? 58 : 68,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              color: Colors.white,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Estatísticas do Site',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 25 : 34,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Acompanhe acessos, localização, cliques e comportamento dos visitantes.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: compact ? 12.8 : 15,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildWhiteChip(Icons.people_alt_rounded, '$_totalAcessos visitas'),
                  _buildWhiteChip(Icons.history_rounded, '${filtrados.length} carregados'),
                  _buildWhiteChip(Icons.location_on_rounded, 'Mapa integrado'),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 12),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteChip(IconData icon, String label) {
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
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardsRapidos() {
    final cards = [
      _MetricCard('Total', _totalAcessos.toString(), Icons.people, Colors.red),
      _MetricCard('Hoje', _visitasHoje.toString(), Icons.today, Colors.orange),
      _MetricCard('Semana', _visitasSemana.toString(), Icons.calendar_view_week, Colors.green),
      _MetricCard('Mês', _visitasMes.toString(), Icons.calendar_month, Colors.blue),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 420 ? 2 : width < 760 ? 4 : 4;
        const spacing = 10.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: itemWidth,
              child: _buildCardRapidoItem(card),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCardRapidoItem(_MetricCard card) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(13),
      decoration: _cardDecoration(
        radius: 22,
        borderColor: card.color.withOpacity(0.10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: card.color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(card.icon, color: card.color, size: 21),
          ),
          const Spacer(),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraficosSection(bool compact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        final hora = _buildGraficoHoras();
        final dia = _buildGraficoDiasSemana();

        if (hora is SizedBox && dia is SizedBox) return const SizedBox.shrink();

        if (!wide) {
          return Column(
            children: [
              hora,
              if (hora is! SizedBox && dia is! SizedBox) const SizedBox(height: 14),
              dia,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: hora),
            const SizedBox(width: 14),
            Expanded(child: dia),
          ],
        );
      },
    );
  }

  Widget _buildGraficoHoras() {
    if (_acessosPorHora.isEmpty) return const SizedBox.shrink();

    final horasOrdenadas = _acessosPorHora.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxY =
        horasOrdenadas.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 1;

    return _chartCard(
      title: 'Acessos por hora',
      icon: Icons.schedule_rounded,
      color: Colors.purple,
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
                return BarTooltipItem(
                  '$hora\n$valor acesso${valor != 1 ? 's' : ''}',
                  const TextStyle(color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < horasOrdenadas.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        horasOrdenadas[index].key,
                        style: const TextStyle(fontSize: 9),
                      ),
                    );
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
                  if (value % 1 == 0) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    );
                  }

                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
          ),
          borderData: FlBorderData(show: false),
          barGroups: horasOrdenadas.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.value.toDouble(),
                  color: Colors.purple.shade300,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGraficoDiasSemana() {
    if (_acessosPorDia.isEmpty) return const SizedBox.shrink();

    final diasOrdem = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
    final dadosOrdenados =
    diasOrdem.map((dia) => MapEntry(dia, _acessosPorDia[dia] ?? 0)).toList();
    final maxY =
        dadosOrdenados.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 1;

    return _chartCard(
      title: 'Acessos por dia',
      icon: Icons.calendar_today_rounded,
      color: Colors.teal,
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
                return BarTooltipItem(
                  '$dia\n$valor acesso${valor != 1 ? 's' : ''}',
                  const TextStyle(color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < dadosOrdenados.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dadosOrdenados[index].key,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
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
                  if (value % 1 == 0) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    );
                  }

                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
          ),
          borderData: FlBorderData(show: false),
          barGroups: dadosOrdenados.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.value.toDouble(),
                  color: Colors.teal.shade300,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required IconData icon,
    required MaterialColor color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: icon, title: title, color: color),
          const SizedBox(height: 16),
          SizedBox(height: 176, child: child),
        ],
      ),
    );
  }

  Widget _buildTopCidadesEstados() {
    Map<String, dynamic> paises = {};

    if (_dadosAgregados['paises'] != null) {
      paises = Map<String, dynamic>.from(_dadosAgregados['paises'] as Map);
    }

    final cidades = <String, int>{};
    final estados = <String, int>{};

    for (final pais in paises.values) {
      final paisMap = pais is Map ? Map<String, dynamic>.from(pais) : <String, dynamic>{};
      final estadosDoPaisRaw = paisMap['estados'];

      if (estadosDoPaisRaw is! Map) continue;

      final estadosDoPais = Map<String, dynamic>.from(estadosDoPaisRaw);

      for (final estadoEntry in estadosDoPais.entries) {
        final estadoNome = estadoEntry.key;
        final estadoData = estadoEntry.value is Map
            ? Map<String, dynamic>.from(estadoEntry.value as Map)
            : <String, dynamic>{};

        estados[estadoNome] = (estadoData['total'] ?? 0) as int;

        final cidadesDoEstadoRaw = estadoData['cidades'];
        if (cidadesDoEstadoRaw is! Map) continue;

        final cidadesDoEstado = Map<String, dynamic>.from(cidadesDoEstadoRaw);

        for (final cidadeEntry in cidadesDoEstado.entries) {
          final cidadeData = cidadeEntry.value is Map
              ? Map<String, dynamic>.from(cidadeEntry.value as Map)
              : <String, dynamic>{};

          cidades[cidadeEntry.key] = (cidadeData['total'] ?? 0) as int;
        }
      }
    }

    final topCidades = cidades.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEstados = estados.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.emoji_events_rounded,
            title: 'Top locais',
            color: Colors.orange,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;

              if (!wide) {
                return Column(
                  children: [
                    _buildSecaoTop(
                      'Cidades',
                      Icons.location_city,
                      Colors.orange,
                      topCidades.take(5).toList(),
                    ),
                    const SizedBox(height: 14),
                    _buildSecaoTop(
                      'Estados',
                      Icons.map_rounded,
                      Colors.blue,
                      topEstados.take(5).toList(),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildSecaoTop(
                      'Cidades',
                      Icons.location_city,
                      Colors.orange,
                      topCidades.take(5).toList(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildSecaoTop(
                      'Estados',
                      Icons.map_rounded,
                      Colors.blue,
                      topEstados.take(5).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoTop(
      String titulo,
      IconData icone,
      MaterialColor cor,
      List<MapEntry<String, int>> items,
      ) {
    if (items.isEmpty) {
      return _emptyMiniCard('Nenhum dado de $titulo ainda');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 18, color: cor.shade700),
              const SizedBox(width: 6),
              Text(
                titulo,
                style: TextStyle(
                  color: cor.shade900,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
                (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: cor.shade100),
                    ),
                    child: Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: cor.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroPeriodo() {
    final filtros = [
      ('Todos', 'todos'),
      ('Hoje', 'hoje'),
      ('Semana', 'semana'),
      ('Mês', 'mes'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(radius: 20),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, color: Colors.red.shade900),
          const SizedBox(width: 8),
          Text(
            'Filtrar',
            style: TextStyle(
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filtros.map((filtro) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _buildChipFiltro(filtro.$1, filtro.$2),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipFiltro(String label, String valor) {
    final selecionado = _filtroPeriodo == valor;

    return ChoiceChip(
      label: Text(label),
      selected: selecionado,
      onSelected: (_) => setState(() => _filtroPeriodo = valor),
      backgroundColor: Colors.grey.shade100,
      selectedColor: Colors.red.shade900,
      labelStyle: TextStyle(
        color: selecionado ? Colors.white : Colors.grey.shade800,
        fontWeight: selecionado ? FontWeight.w900 : FontWeight.w700,
        fontSize: 12,
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: selecionado ? Colors.red.shade900 : Colors.grey.shade200,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    );
  }

  Widget _buildListaAcessos() {
    final acessosFiltrados = _getAcessosFiltrados();

    if (acessosFiltrados.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: _cardDecoration(radius: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.travel_explore_rounded, size: 54, color: Colors.grey.shade300),
              const SizedBox(height: 10),
              Text(
                'Nenhum acesso neste período',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.history_rounded,
            title: 'Acessos recentes',
            color: Colors.green,
            trailing: '${acessosFiltrados.length} de $_totalAcessos',
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: acessosFiltrados.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (context, index) => _buildAcessoItem(acessosFiltrados[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildAcessoItem(Map<String, dynamic> acesso) {
    final timestamp = acesso['data_acesso'];
    final dataAcesso = timestamp is Timestamp ? timestamp.toDate() : DateTime.now();

    final dataFormatada =
        '${dataAcesso.day.toString().padLeft(2, '0')}/${dataAcesso.month.toString().padLeft(2, '0')}';
    final horaFormatada =
        '${dataAcesso.hour.toString().padLeft(2, '0')}:${dataAcesso.minute.toString().padLeft(2, '0')}';

    final ip = acesso['ip']?.toString() ?? 'N/A';
    final ipCurto = ip.contains('.') ? ip.substring(0, ip.lastIndexOf('.')) : ip;

    final eventos = acesso['eventos'];
    final temEventos = eventos is List && eventos.isNotEmpty;
    final eventosLista = temEventos
        ? eventos.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final temConversao = eventosLista.any((e) => e['tipo'] == 'conversao');
    final temErro = eventosLista.any((e) => e['tipo'] == 'erro_formulario');
    final suspeitos = _contarCamposSuspeitos(eventosLista);

    final cidade = acesso['cidade']?.toString().trim();
    final estado = acesso['estado']?.toString().trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _mostrarRastroDocumento(acesso),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cidade?.isNotEmpty == true ? cidade : 'Desconhecida'}'
                          '${estado?.isNotEmpty == true ? ', $estado' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: Colors.grey.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$dataFormatada às $horaFormatada',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: temEventos ? Colors.blue.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: temEventos ? Colors.blue.shade100 : Colors.green.shade100,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: temEventos
                      ? [
                    Icon(Icons.timeline_rounded, size: 13, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Text(
                      suspeitos > 0 ? 'Suspeito' : temConversao ? 'Conversão' : temErro ? 'Erro' : '${eventosLista.length} eventos',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ]
                      : [
                    Text(
                      ipCurto,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w900,
                      ),
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

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: Colors.red.shade900),
            const SizedBox(height: 8),
            Text(
              'Carregando mais acessos...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFimLista() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade400),
            const SizedBox(height: 8),
            Text(
              'Todos os $_totalAcessos acessos carregados',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRastroHeader(Map<String, dynamic> documento, bool compact) {
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade900, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(Icons.timeline_rounded, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rastro do acesso',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'IP: ${documento['ip'] ?? 'N/A'} • ${documento['cidade'] ?? 'N/A'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoEventos({
    required int totalEventos,
    required Map<String, int> resumoTipos,
    required int camposSuspeitos,
    required bool compact,
  }) {
    final items = [
      _ResumoDialog('Total', totalEventos.toString(), Icons.touch_app_rounded, Colors.blue),
      _ResumoDialog('Telas', (resumoTipos['telas'] ?? 0).toString(), Icons.web_rounded, Colors.indigo),
      _ResumoDialog('Cliques', (resumoTipos['botoes'] ?? 0).toString(), Icons.ads_click_rounded, Colors.orange),
      _ResumoDialog('Etapas', (resumoTipos['etapas'] ?? 0).toString(), Icons.stairs_rounded, Colors.purple),
      _ResumoDialog('Campos', (resumoTipos['campos'] ?? 0).toString(), Icons.edit_note_rounded, Colors.teal),
      _ResumoDialog('Erros', (resumoTipos['erros'] ?? 0).toString(), Icons.warning_rounded, Colors.red),
      _ResumoDialog('Conversões', (resumoTipos['conversoes'] ?? 0).toString(), Icons.verified_rounded, Colors.green),
      if (camposSuspeitos > 0)
        _ResumoDialog('Suspeitos', camposSuspeitos.toString(), Icons.report_rounded, Colors.deepOrange),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return SizedBox(
          width: compact ? 98 : 128,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: _cardDecoration(
              radius: 18,
              borderColor: item.color.withOpacity(0.12),
            ),
            child: Column(
              children: [
                Icon(item.icon, color: item.color, size: 21),
                const SizedBox(height: 5),
                Text(
                  item.value,
                  style: TextStyle(
                    color: item.color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInteligenciaFluxo(List<Map<String, dynamic>> eventosMap, bool compact) {
    final resumo = _resumoTiposEvento(eventosMap);
    final duracaoTelas = _somarDuracaoEventos(eventosMap, 'tela');
    final duracaoEtapas = _somarDuracaoEventos(eventosMap, 'etapa_formulario');
    final suspeitos = _contarCamposSuspeitos(eventosMap);
    final conversoes = resumo['conversoes'] ?? 0;
    final erros = resumo['erros'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(
        radius: 22,
        borderColor: suspeitos > 0 ? Colors.deepOrange.shade100 : Colors.green.shade100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: suspeitos > 0 ? Icons.report_rounded : Icons.auto_graph_rounded,
            title: 'Leitura inteligente do fluxo',
            color: suspeitos > 0 ? Colors.deepOrange : Colors.green,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip('Tempo em telas', _formatarDuracao(duracaoTelas)),
              _buildInfoChip('Tempo em etapas', _formatarDuracao(duracaoEtapas)),
              _buildInfoChip('Erros', erros),
              _buildInfoChip('Conversões', conversoes),
              _buildInfoChip('Campos suspeitos', suspeitos),
            ],
          ),
          if (suspeitos > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepOrange.shade100),
              ),
              child: Text(
                'Atenção: esta sessão possui texto suspeito/zoeira em campos digitados ou snapshots.',
                style: TextStyle(
                  color: Colors.deepOrange.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapaCard(double latitude, double longitude) {
    return Material(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _abrirGoogleMaps(latitude, longitude),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(Icons.map_rounded, color: Colors.blue.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Abrir localização no Google Maps',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: Colors.blue.shade800, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline(List<Map<String, dynamic>> eventosMap, bool compact) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.route_rounded,
            title: 'Linha do tempo',
            color: Colors.blue,
            trailing: '${eventosMap.length} eventos',
          ),
          const SizedBox(height: 10),
          if (eventosMap.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: Text(
                  'Nenhum evento registrado nesta sessão',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            ...List.generate(eventosMap.length, (index) {
              final evento = eventosMap[index];
              return _buildEventoLinha(evento, index, compact);
            }),
        ],
      ),
    );
  }

  Widget _buildEventoLinha(
      Map<String, dynamic> evento,
      int index,
      bool compact,
      ) {
    final tipo = evento['tipo']?.toString() ?? 'evento';
    final nome = evento['nome']?.toString() ?? 'Evento';
    final origem = evento['origem']?.toString() ?? 'N/A';
    final hora = _formatarHoraEvento(evento['data_hora'] ?? evento['timestamp']);

    final (icone, cor) = switch (tipo) {
      'menu' => (Icons.menu_rounded, Colors.green),
      'botao_social' => (Icons.share_rounded, Colors.blue),
      'clique' => (Icons.ads_click_rounded, Colors.orange),
      'card' => (Icons.grid_view_rounded, Colors.orange),
      'pagina' => (Icons.web_rounded, Colors.purple),
      'tela' => (Icons.desktop_windows_rounded, Colors.indigo),
      'formulario' => (Icons.dynamic_form_rounded, Colors.teal),
      'etapa_formulario' => (Icons.stairs_rounded, Colors.purple),
      'erro_formulario' => (Icons.warning_rounded, Colors.red),
      'conversao' => (Icons.verified_rounded, Colors.green),
      'campo_formulario' => (Icons.edit_note_rounded, Colors.blue),
      'snapshot_formulario' => (Icons.fact_check_rounded, Colors.cyan),
      'rolagem' => (Icons.swap_vert_rounded, Colors.brown),
      'filtro' => (Icons.filter_alt_rounded, Colors.deepPurple),
      'item_visualizado' => (Icons.visibility_rounded, Colors.pink),
      _ => (Icons.touch_app_rounded, Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cor.shade50,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: cor.shade100),
                ),
                child: Icon(icone, color: cor.shade700, size: 18),
              ),
              if (index != 9999)
                Container(
                  width: 2,
                  height: 24,
                  color: Colors.grey.shade200,
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade900,
                            fontSize: compact ? 12.2 : 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _descricaoEvento(evento),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hora,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoAcesso(
      Map<String, dynamic> documento,
      double? latitude,
      double? longitude,
      ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.info_rounded,
            title: 'Informações do acesso',
            color: Colors.grey,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip('ISP', documento['isp'] ?? 'N/A'),
              _buildInfoChip(
                'Data/Hora',
                _formatarDataHora(documento['data_acesso'] as Timestamp?),
              ),
              _buildInfoChip(
                'Total Eventos',
                (documento['total_eventos'] ?? 0).toString(),
              ),
              if (latitude != null && longitude != null)
                _buildInfoChip(
                  'Coordenadas',
                  '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRastroBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_rounded),
            label: const Text('FECHAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, dynamic valor) {
    final texto = valor?.toString() ?? 'N/A';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        '$label: $texto',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade800,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required MaterialColor color,
    String? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: color.shade100),
          ),
          child: Icon(icon, color: color.shade700, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyMiniCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(color: Colors.grey.shade600),
      ),
    );
  }

  BoxDecoration _cardDecoration({
    double radius = 18,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}

class _MetricCard {
  final String title;
  final String value;
  final IconData icon;
  final MaterialColor color;

  const _MetricCard(this.title, this.value, this.icon, this.color);
}

class _ResumoDialog {
  final String label;
  final String value;
  final IconData icon;
  final MaterialColor color;

  const _ResumoDialog(this.label, this.value, this.icon, this.color);
}
