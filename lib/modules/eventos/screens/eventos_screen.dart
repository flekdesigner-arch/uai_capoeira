import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'detalhes_evento_screen.dart';
import 'detalhes_evento_andamento_screen.dart';
import 'package:uai_capoeira/modules/campeonatos/screens/gestao_campeonato_screen.dart';

class EventosScreen extends StatefulWidget {
  const EventosScreen({super.key});

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen>
    with SingleTickerProviderStateMixin {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);
  Color _appBarBg() => Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() => Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());


  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final PermissaoService _permissaoService = PermissaoService();

  late Future<_EventosPermissoes> _permissoesFuture;

  // Filtros
  String _filtroCidade = 'Todas';
  String _filtroTipo = 'Todos';

  // Listas para os filtros
  List<String> _cidades = ['Todas'];
  List<String> _tipos = ['Todos'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _permissoesFuture = _carregarPermissoesTela();
    _carregarFiltros();
  }

  Future<_EventosPermissoes> _carregarPermissoesTela() async {
    final results = await Future.wait<bool>([
      _permissaoService.temQualquerPermissao([
        'pode_acessar_eventos',
        'podeAcessarEventos',
        'pode_ver_eventos',
      ]),
      _permissaoService.temQualquerPermissao([
        'pode_ver_eventos',
        'pode_acessar_eventos',
        'podeAcessarEventos',
      ]),
      _permissaoService.temQualquerPermissao([
        'pode_ver_eventos_andamento',
        'pode_acessar_eventos_andamento',
        'pode_gerenciar_eventos_andamento',
      ]),
      _permissaoService.temQualquerPermissao([
        'pode_editar_evento',
      ]),
      _permissaoService.temQualquerPermissao([
        'pode_excluir_evento',
      ]),
      _permissaoService.temQualquerPermissao([
        'pode_finalizar_evento',
      ]),
    ]);

    final permissoes = _EventosPermissoes(
      podeAcessarEventos: results[0],
      podeVerEventos: results[1],
      podeVerEventosAndamento: results[2],
      podeEditarEvento: results[3],
      podeExcluirEvento: results[4],
      podeFinalizarEvento: results[5],
    );

    await _selecionarAbaInicial(permissoes);

    return permissoes;
  }

  Future<void> _recarregarPermissoes() async {
    await _permissaoService.recarregarPermissoes();
    if (!mounted) return;

    setState(() {
      _permissoesFuture = _carregarPermissoesTela();
    });
  }

  Future<void> _selecionarAbaInicial(_EventosPermissoes permissoes) async {
    // Regra:
    // - Se existir evento em andamento E o usuário puder ver andamento, abre na aba EM ANDAMENTO.
    // - Se não existir, ou se o usuário não puder ver andamento, fica em TODOS.
    try {
      if (!permissoes.podeVerEventosAndamento) {
        _agendarTrocaAba(0);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .where('status', isEqualTo: 'andamento')
          .limit(1)
          .get();

      _agendarTrocaAba(snapshot.docs.isNotEmpty ? 1 : 0);
    } catch (e) {
      debugPrint('Erro ao selecionar aba inicial de eventos: $e');
      _agendarTrocaAba(0);
    }
  }

  void _agendarTrocaAba(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tabController.index == index) return;
      _tabController.animateTo(index);
    });
  }

  Future<void> _carregarFiltros() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('eventos').get();

      final eventos =
      snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();

      final cidadesSet = <String>{};
      final tiposSet = <String>{};

      for (var evento in eventos) {
        if (evento.cidade.isNotEmpty) {
          cidadesSet.add(evento.cidade);
        }
        if (evento.tipo.isNotEmpty) {
          tiposSet.add(evento.tipo);
        }
      }

      if (mounted) {
        setState(() {
          _cidades = ['Todas', ...cidadesSet.toList()..sort()];
          _tipos = ['Todos', ...tiposSet.toList()..sort()];
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar filtros: $e');
    }
  }

  Stream<QuerySnapshot> _getEventosStream() {
    Query query = FirebaseFirestore.instance
        .collection('eventos')
        .orderBy('data', descending: true);

    if (_filtroCidade != 'Todas') {
      query = query.where('cidade', isEqualTo: _filtroCidade);
    }
    if (_filtroTipo != 'Todos') {
      query = query.where('tipo', isEqualTo: _filtroTipo);
    }

    return query.snapshots();
  }

  void _mostrarSemPermissao(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarFiltrosDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return SafeArea(
            child: Container(
              decoration: BoxDecoration(color: context.uai.card, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
              padding: EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.uai.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: context.uai.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(Icons.filter_list_rounded,
                            color: context.uai.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Filtrar Eventos',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: _onCard(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: _filtroCidade,
                    decoration: InputDecoration(
                      labelText: 'Cidade',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      prefixIcon:
                      Icon(Icons.location_city, color: context.uai.error),
                      filled: true,
                      fillColor: context.uai.cardAlt,
                    ),
                    items: _cidades.map((cidade) {
                      return DropdownMenuItem(
                        value: cidade,
                        child: Text(cidade),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        _filtroCidade = value!;
                      });
                    },
                  ),
                  SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _filtroTipo,
                    decoration: InputDecoration(
                      labelText: 'Tipo de Evento',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      prefixIcon: Icon(Icons.category, color: context.uai.error),
                      filled: true,
                      fillColor: context.uai.cardAlt,
                    ),
                    items: _tipos.map((tipo) {
                      return DropdownMenuItem(
                        value: tipo,
                        child: Text(tipo),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        _filtroTipo = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setStateDialog(() {
                              _filtroCidade = 'Todas';
                              _filtroTipo = 'Todos';
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.uai.primary,
                            side: BorderSide(color: context.uai.error.withOpacity(0.22)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'LIMPAR',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
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
                            backgroundColor: _appBarBg(),
                            foregroundColor: _appBarFg(),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'APLICAR',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _abrirEvento({
    required EventoModel evento,
    required String docId,
    required _EventosPermissoes permissoes,
  }) {
    final status = evento.status;
    final tipo = evento.tipo.toLowerCase().trim();
    final isCampeonato = tipo == 'campeonato';

    if (status == 'andamento' && !permissoes.podeVerEventosAndamento) {
      _mostrarSemPermissao(
        'Você não tem permissão para abrir eventos em andamento.',
      );
      return;
    }

    if (isCampeonato && status != 'finalizado') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GestaoCampeonatoScreen(
            campeonatoId: docId,
            nomeCampeonato: evento.nome,
          ),
        ),
      );
      return;
    }

    if (isCampeonato && status == 'finalizado') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DetalhesEventoScreen(
            evento: evento,
            eventoId: docId,
          ),
        ),
      );
      return;
    }

    if (status == 'andamento') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DetalhesEventoAndamentoScreen(
            evento: evento,
            eventoId: docId,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalhesEventoScreen(
          evento: evento,
          eventoId: docId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EventosPermissoes>(
      future: _permissoesFuture,
      builder: (context, snapshot) {
        final loadingPermissoes =
            snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

        if (loadingPermissoes) {
          return Scaffold(
            backgroundColor: context.uai.background,
            appBar: _buildAppBar(const _EventosPermissoes()),
            body: _buildLoadingPermissoes(),
          );
        }

        final permissoes = snapshot.data ?? const _EventosPermissoes();

        if (!permissoes.podeAcessarEventos && !permissoes.podeVerEventos) {
          return Scaffold(
            backgroundColor: context.uai.background,
            appBar: _buildAppBar(permissoes),
            body: _buildSemAcessoEventos(),
          );
        }

        return Scaffold(
          backgroundColor: context.uai.background,
          appBar: _buildAppBar(permissoes),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildEventosGrid('todos', permissoes),
              _buildEventosGrid('andamento', permissoes),
              _buildEventosGrid('finalizado', permissoes),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(_EventosPermissoes permissoes) {
    return AppBar(
      title: Text(
        'EVENTOS',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
          fontSize: 20,
        ),
      ),
      backgroundColor: _appBarBg(),
      foregroundColor: _appBarFg(),
      elevation: 0,
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: _appBarFg(),
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: _appBarFg(),
        unselectedLabelColor: _appBarFg().withOpacity(0.62),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 12,
        ),
        tabs: const [
          Tab(text: 'TODOS', icon: Icon(Icons.event, size: 18)),
          Tab(text: 'EM ANDAMENTO', icon: Icon(Icons.pending, size: 18)),
          Tab(text: 'FINALIZADOS', icon: Icon(Icons.history, size: 18)),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.refresh_rounded),
          onPressed: _recarregarPermissoes,
          tooltip: 'Recarregar permissões',
        ),
        Container(
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: _appBarFg().withOpacity(0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _mostrarFiltrosDialog,
            tooltip: 'Filtrar eventos',
          ),
        ),
      ],
    );
  }

  Widget _buildEventosGrid(String status, _EventosPermissoes permissoes) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getEventosStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErroState('Erro ao carregar eventos');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: context.uai.primary));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('Nenhum evento encontrado');
        }

        List<EventoModel> eventos =
        snapshot.data!.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();

        if (status != 'todos') {
          eventos = eventos.where((e) => e.status == status).toList();
        }

        if (!permissoes.podeVerEventosAndamento) {
          eventos = eventos.where((e) => e.status != 'andamento').toList();
        }

        if (eventos.isEmpty) {
          final mensagem = status == 'andamento'
              ? 'Nenhum evento em andamento liberado para você'
              : status == 'finalizado'
              ? 'Nenhum evento finalizado'
              : 'Nenhum evento encontrado';
          return _buildEmptyState(mensagem);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1100
                ? 5
                : width >= 850
                ? 4
                : width >= 620
                ? 3
                : 2;

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: width < 380 ? 0.68 : 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: eventos.length,
              itemBuilder: (context, index) {
                final evento = eventos[index];
                return _buildEventoCard(evento, evento.id!, permissoes);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildErroState(String mensagem) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.uai.error.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              size: 60,
              color: context.uai.error.withOpacity(0.22),
            ),
          ),
          SizedBox(height: 16),
          Text(
            mensagem,
            style: TextStyle(fontSize: 16, color: context.uai.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPermissoes() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.uai.cardAlt),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            const SizedBox(height: 14),
            Text(
              'Carregando permissões...',
              style: TextStyle(
                color: _onCardMuted(),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemAcessoEventos() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(20),
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: context.uai.error.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 62, color: context.uai.error.withOpacity(0.22)),
            const SizedBox(height: 12),
            Text(
              'Acesso não liberado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _onCard(),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Peça para o administrador liberar a permissão de acesso aos eventos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _onCardMuted(),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _recarregarPermissoes,
              icon: Icon(Icons.refresh_rounded),
              label: Text('Recarregar permissões'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.uai.primary,
                side: BorderSide(color: context.uai.error.withOpacity(0.22)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String mensagem) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.uai.cardAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_busy,
              size: 60,
              color: context.uai.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _onCardMuted(),
            ),
          ),
        ],
      ),
    );
  }

  String? _normalizarBannerUrl(EventoModel evento) {
    final raw = evento.linkBanner?.trim();

    if (raw == null || raw.isEmpty) {
      return null;
    }

    // CachedNetworkImage só consegue abrir http/https diretamente.
    // Se algum evento estiver salvo com gs://, path local ou texto inválido,
    // a imagem não aparece nessa tela.
    final uri = Uri.tryParse(raw);

    if (uri == null || !uri.hasScheme) {
      debugPrint('🖼️ [Eventos] Banner inválido para "${evento.nome}": $raw');
      return null;
    }

    final scheme = uri.scheme.toLowerCase();

    if (scheme != 'http' && scheme != 'https') {
      debugPrint(
        '🖼️ [Eventos] Banner ignorado para "${evento.nome}". '
            'Use URL http/https. Valor atual: $raw',
      );
      return null;
    }

    return uri.toString();
  }

  Widget _buildEventoBannerImage(EventoModel evento) {
    final url = _normalizarBannerUrl(evento);

    if (url == null) {
      return _buildEventoBannerFallback(
        icon: Icons.image_not_supported_outlined,
        label: 'Sem banner',
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 100),
      useOldImageOnUrlChange: true,
      memCacheWidth: 900,
      placeholder: (context, _) {
        return Container(
          color: context.uai.cardAlt,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.uai.primary,
              ),
            ),
          ),
        );
      },
      errorWidget: (context, url, error) {
        debugPrint(
          '🖼️ [Eventos] Erro ao carregar banner de "${evento.nome}": $error | $url',
        );

        return _buildEventoBannerFallback(
          icon: Icons.broken_image_outlined,
          label: 'Imagem indisponível',
        );
      },
    );
  }

  Widget _buildEventoBannerFallback({
    required IconData icon,
    required String label,
  }) {
    final accent = _ensureVisible(context.uai.primary, context.uai.cardAlt);

    return Container(
      color: context.uai.cardAlt,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.uai.textMuted, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent.withOpacity(0.72),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventoCard(
      EventoModel evento,
      String docId,
      _EventosPermissoes permissoes,
      ) {
    final status = evento.status;
    final corStatus = status == 'finalizado'
        ? Colors.grey
        : status == 'andamento'
        ? context.uai.success
        : context.uai.textMuted;

    final textoStatus = status == 'finalizado'
        ? 'Finalizado'
        : status == 'andamento'
        ? 'Andamento'
        : 'Ativo';

    final bloqueadoAndamento =
        status == 'andamento' && !permissoes.podeVerEventosAndamento;

    return Material(
      color: context.uai.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (bloqueadoAndamento) {
            _mostrarSemPermissao(
              'Você não tem permissão para abrir eventos em andamento.',
            );
            return;
          }

          _abrirEvento(
            evento: evento,
            docId: docId,
            permissoes: permissoes,
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: bloqueadoAndamento
                  ? context.uai.warning.withOpacity(0.12)
                  : context.uai.cardAlt,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Em telas/emuladores pequenos o Grid fica estreito.
              // Esse layout trava alturas internas e usa Flexible/FittedBox,
              // evitando a faixa zebrada no nome do card.
              final cardWidth = constraints.maxWidth;
              final isTiny = cardWidth < 175;

              return Column(
                children: [
                  // Imagem ocupa a parte superior de forma controlada.
                  AspectRatio(
                    aspectRatio: 1.08,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildEventoBannerImage(evento),

                        Positioned(
                          top: 7,
                          left: 7,
                          child: _buildCardBadge(
                            text: bloqueadoAndamento ? 'Bloqueado' : textoStatus,
                            color: bloqueadoAndamento ? context.uai.warning : corStatus,
                            maxWidth: isTiny ? 72 : 88,
                          ),
                        ),

                        Positioned(
                          top: 7,
                          right: 7,
                          child: _buildCardBadge(
                            text: evento.dataFormatada,
                            color: context.uai.warning,
                            maxWidth: isTiny ? 70 : 88,
                          ),
                        ),

                        if (bloqueadoAndamento)
                          Container(
                            color: Colors.white.withOpacity(0.58),
                            child: Center(
                              child: Icon(
                                Icons.lock_outline_rounded,
                                color: context.uai.warning,
                                size: isTiny ? 30 : 36,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Informações do card.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              evento.nome,
                              textAlign: TextAlign.center,
                              maxLines: isTiny ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isTiny ? 11.5 : 12.5,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                                color: _onCard(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              evento.cidade.isEmpty
                                  ? evento.tipo
                                  : '${evento.tipo} • ${evento.cidade}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _onCardMuted(),
                                fontSize: isTiny ? 9.5 : 10.4,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCardBadge({
    required String text,
    required Color color,
    required double maxWidth,
  }) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.uai.card,
          fontSize: 9.2,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _EventosPermissoes {
  final bool podeAcessarEventos;
  final bool podeVerEventos;
  final bool podeVerEventosAndamento;
  final bool podeEditarEvento;
  final bool podeExcluirEvento;
  final bool podeFinalizarEvento;

  const _EventosPermissoes({
    this.podeAcessarEventos = false,
    this.podeVerEventos = false,
    this.podeVerEventosAndamento = false,
    this.podeEditarEvento = false,
    this.podeExcluirEvento = false,
    this.podeFinalizarEvento = false,
  });
}

