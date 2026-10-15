import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/admin/criar_evento_screen.dart';
import 'package:uai_capoeira/modules/eventos/admin/gerenciar_participacoes_screen.dart';
import 'package:uai_capoeira/modules/eventos/screens/participantes_evento_screen.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/screens/detalhes_evento_screen.dart';
import 'package:uai_capoeira/modules/eventos/screens/detalhes_evento_andamento_screen.dart';
import 'package:uai_capoeira/modules/eventos/services/evento_participantes_cache_service.dart';
import 'package:uai_capoeira/modules/site/portfolio_v3/data/portfolio_repository.dart';
import 'package:uai_capoeira/modules/site/portfolio_v3/screens/portfolio_detail_screen.dart';
import 'package:uai_capoeira/modules/site/portfolio_v3/widgets/portfolio_cover_image.dart';

class GerenciarEventosScreen extends StatefulWidget {
  const GerenciarEventosScreen({super.key});

  @override
  State<GerenciarEventosScreen> createState() => _GerenciarEventosScreenState();
}

class _GerenciarEventosScreenState extends State<GerenciarEventosScreen> {
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final TextEditingController _searchController = TextEditingController();
  final PermissaoService _permissaoService = PermissaoService();
  final EventoParticipantesCacheService _cacheService =
      EventoParticipantesCacheService();
  final PortfolioRepository _portfolioRepository = PortfolioRepository();
  late final PermissionAccessGuard _accessGuard = PermissionAccessGuard(
    service: _permissaoService,
  );

  String _searchQuery = '';
  String _statusFiltro = 'todos';
  int _viewMode = 1;

  bool _podeCriarEvento = false;
  bool _podeEditarEvento = false;
  bool _podeExcluirEvento = false;
  bool _carregandoPermissoes = true;
  bool _acessoNegado = false;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      if (!mounted) return;
      setState(
        () => _searchQuery = _searchController.text.toLowerCase().trim(),
      );
    });

    _carregarPermissoes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  Future<void> _carregarPermissoes() async {
    if (mounted) {
      setState(() {
        _carregandoPermissoes = true;
        _acessoNegado = false;
      });
    }

    try {
      final podeAcessar = await _accessGuard.canAny([
        'pode_acessar_eventos',
        'pode_ver_eventos',
        'pode_criar_evento',
        'pode_editar_evento',
        'pode_gerenciar_participantes_evento',
        'pode_ver_participantes_evento',
      ]);

      if (!mounted) return;

      if (!podeAcessar) {
        setState(() {
          _podeCriarEvento = false;
          _podeEditarEvento = false;
          _podeExcluirEvento = false;
          _acessoNegado = true;
          _carregandoPermissoes = false;
        });
        return;
      }

      final results = await Future.wait<bool>([
        _permissaoService.temPermissao('pode_criar_evento'),
        _permissaoService.temPermissao('pode_editar_evento'),
        _permissaoService.temPermissao('pode_excluir_evento'),
      ]);

      if (!mounted) return;

      setState(() {
        _podeCriarEvento = results[0];
        _podeEditarEvento = results[1];
        _podeExcluirEvento = results[2];
        _acessoNegado = false;
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar permissões de eventos: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  void _showSnack(String message, {required _SnackType type}) {
    final t = context.uai;

    final color = switch (type) {
      _SnackType.success => t.success,
      _SnackType.error => t.error,
      _SnackType.warning => t.warning,
      _SnackType.info => t.info,
      _SnackType.neutral => t.textSecondary,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _alternarPortfolioWeb(String eventoId, bool valorAtual) async {
    final permitido = await _accessGuard.revalidate(
      context,
      permission: 'pode_editar_evento',
      message: 'Você não tem permissão para alterar o portfólio web.',
    );
    if (!permitido) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('eventos')
          .doc(eventoId)
          .update({
            'mostrarNoPortfolioWeb': !valorAtual,
            'atualizado_em': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      _showSnack(
        !valorAtual
            ? 'Evento será mostrado no site 🌐'
            : 'Evento removido do site',
        type: !valorAtual ? _SnackType.info : _SnackType.neutral,
      );
    } catch (e) {
      debugPrint('Erro ao alterar portfólio web: $e');
      if (!mounted) return;
      _showSnack('Erro ao alterar portfólio: $e', type: _SnackType.error);
    }
  }

  Future<void> _excluirEvento(String eventoId, String nomeEvento) async {
    final permitido = await _accessGuard.revalidate(
      context,
      permission: 'pode_excluir_evento',
      message: 'Você não tem permissão para excluir eventos.',
    );
    if (!mounted || !permitido) {
      return;
    }

    final confirmController = TextEditingController();
    bool isConfirmEnabled = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = context.uai;
        final error = _ensureVisible(t.error, t.surface);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.cardRadius + 2),
                      border: Border.all(color: t.border),
                      boxShadow: t.cardShadow,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: error.withAlpha(31),
                                  borderRadius: BorderRadius.circular(
                                    t.buttonRadius,
                                  ),
                                ),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  color: error,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Excluir evento',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Esta ação é irreversível.',
                            style: TextStyle(
                              color: error,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Digite o nome do evento exatamente como está abaixo para confirmar:',
                            style: TextStyle(
                              fontSize: 13,
                              color: t.textSecondary,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                error.withAlpha(26),
                                t.cardAlt,
                              ),
                              borderRadius: BorderRadius.circular(
                                t.inputRadius,
                              ),
                              border: Border.all(
                                color: error.withAlpha(46),
                              ),
                            ),
                            child: Text(
                              nomeEvento,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: error,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: confirmController,
                            style: TextStyle(color: t.textPrimary),
                            decoration:
                                _inputDecoration(
                                  label: 'Nome do evento',
                                  hint: 'Digite o nome exato',
                                  icon: Icons.edit_note_rounded,
                                ).copyWith(
                                  suffixIcon: confirmController.text.isNotEmpty
                                      ? Icon(
                                          isConfirmEnabled
                                              ? Icons.check_circle_rounded
                                              : Icons.error_rounded,
                                          color: isConfirmEnabled
                                              ? t.success
                                              : t.error,
                                        )
                                      : null,
                                ),
                            onChanged: (value) {
                              setDialogState(() {
                                isConfirmEnabled = value.trim() == nomeEvento;
                              });
                            },
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 380;

                              final cancel = OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: t.textPrimary,
                                  side: BorderSide(color: t.border),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      t.buttonRadius,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'CANCELAR',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              );

                              final remove = ElevatedButton.icon(
                                onPressed: isConfirmEnabled
                                    ? () => Navigator.pop(dialogContext, true)
                                    : null,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('EXCLUIR'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: t.error,
                                  foregroundColor: _readableOn(t.error),
                                  disabledBackgroundColor: t.cardAlt,
                                  disabledForegroundColor: t.textMuted,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      t.buttonRadius,
                                    ),
                                  ),
                                ),
                              );

                              if (narrow) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    cancel,
                                    const SizedBox(height: 10),
                                    remove,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: cancel),
                                  const SizedBox(width: 10),
                                  Expanded(child: remove),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    confirmController.dispose();

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('eventos')
          .doc(eventoId)
          .delete();

      if (!mounted) return;
      _showSnack('Evento excluído com sucesso!', type: _SnackType.success);
    } catch (e) {
      debugPrint('Erro ao excluir evento: $e');
      if (!mounted) return;
      _showSnack('Erro ao excluir: $e', type: _SnackType.error);
    }
  }

  Future<void> _alterarStatus(String eventoId, String statusAtual) async {
    final novoStatus = statusAtual == 'andamento' ? 'finalizado' : 'andamento';
    final permissao = novoStatus == 'finalizado'
        ? 'pode_finalizar_evento'
        : 'pode_reabrir_evento';
    final permitido = await _accessGuard.revalidate(
      context,
      permission: permissao,
      message: novoStatus == 'finalizado'
          ? 'Você não tem permissão para finalizar eventos.'
          : 'Você não tem permissão para reabrir eventos.',
    );
    if (!mounted || !permitido) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = context.uai;
        final color = novoStatus == 'andamento' ? t.success : t.textSecondary;
        final accent = _ensureVisible(color, t.surface);

        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withAlpha(31),
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                          child: Icon(
                            novoStatus == 'andamento'
                                ? Icons.play_circle_fill_rounded
                                : Icons.stop_circle_rounded,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            novoStatus == 'andamento'
                                ? 'Iniciar evento?'
                                : 'Finalizar evento?',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      novoStatus == 'andamento'
                          ? 'O evento entrará na área de eventos em andamento.'
                          : 'O evento será marcado como finalizado.',
                      style: TextStyle(color: t.textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.textPrimary,
                              side: BorderSide(color: t.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  t.buttonRadius,
                                ),
                              ),
                            ),
                            child: const Text('CANCELAR'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: _readableOn(accent),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  t.buttonRadius,
                                ),
                              ),
                            ),
                            child: Text(
                              novoStatus == 'andamento'
                                  ? 'INICIAR'
                                  : 'FINALIZAR',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmar != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('eventos')
          .doc(eventoId)
          .update({
            'status': novoStatus,
            'atualizado_em': FieldValue.serverTimestamp(),
          });

      var cacheAtualizado = false;
      if (novoStatus == 'finalizado') {
        try {
          await _cacheService.reconstruirCacheParticipantes(
            eventoId,
            forceServer: true,
          );
          cacheAtualizado = true;
        } catch (e) {
          debugPrint('Erro ao reconstruir cache de participantes: $e');
        }
      }

      if (!mounted) return;

      _showSnack(
        novoStatus == 'finalizado' && cacheAtualizado
            ? 'Evento finalizado e participantes atualizados.'
            : 'Status alterado para ${novoStatus == 'andamento' ? 'Em andamento' : 'Finalizado'}',
        type: cacheAtualizado || novoStatus == 'andamento'
            ? _SnackType.success
            : _SnackType.warning,
      );
    } catch (e) {
      debugPrint('Erro ao alterar status: $e');
      if (!mounted) return;
      _showSnack('Erro ao alterar status: $e', type: _SnackType.error);
    }
  }

  Future<void> _abrirCadastroEvento({EventoModel? evento}) async {
    final permissao = evento == null
        ? 'pode_criar_evento'
        : 'pode_editar_evento';
    final permitido = await _accessGuard.revalidate(
      context,
      permission: permissao,
      message: evento == null
          ? 'Você não tem permissão para criar eventos.'
          : 'Você não tem permissão para editar eventos.',
    );
    if (!mounted || !permitido) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CriarEventoScreen(evento: evento),
      ),
    ).then((salvo) {
      if (salvo == true && mounted) {
        _showSnack(
          evento == null
              ? 'Evento criado com sucesso!'
              : 'Evento atualizado com sucesso!',
          type: _SnackType.success,
        );
      }
    });
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Não informada';

    if (data is Timestamp) {
      return _dateFormat.format(data.toDate());
    }

    if (data is DateTime) {
      return _dateFormat.format(data);
    }

    return data.toString();
  }

  Color _statusColor(String status) {
    final t = context.uai;

    switch (status.toLowerCase()) {
      case 'andamento':
        return t.success;
      case 'finalizado':
        return t.textMuted;
      default:
        return t.info;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'andamento':
        return 'EM ANDAMENTO';
      case 'finalizado':
        return 'FINALIZADO';
      default:
        return 'ATIVO';
    }
  }

  List<EventoModel> _filtrarEventos(List<EventoModel> eventos) {
    List<EventoModel> lista = List<EventoModel>.from(eventos);

    if (_statusFiltro != 'todos') {
      lista = lista.where((e) => e.status == _statusFiltro).toList();
    }

    if (_searchQuery.isNotEmpty) {
      lista = lista.where((evento) {
        return evento.nome.toLowerCase().contains(_searchQuery) ||
            evento.cidade.toLowerCase().contains(_searchQuery) ||
            evento.tipo.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    lista.sort((a, b) {
      if (a.status == 'andamento' && b.status != 'andamento') return -1;
      if (a.status != 'andamento' && b.status == 'andamento') return 1;
      return b.data.compareTo(a.data);
    });

    return lista;
  }

  Map<String, int> _resumoEventos(List<EventoModel> eventos) {
    return {
      'todos': eventos.length,
      'andamento': eventos.where((e) => e.status == 'andamento').length,
      'finalizado': eventos.where((e) => e.status == 'finalizado').length,
      'site': eventos.where((e) => e.mostrarNoPortfolioWeb).length,
    };
  }

  Stream<QuerySnapshot> _eventosStream() {
    return FirebaseFirestore.instance
        .collection('eventos')
        .orderBy('data', descending: true)
        .snapshots();
  }

  InputDecoration _inputDecoration({
    required String label,
    IconData? icon,
    String? hint,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: primary),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregandoPermissoes) {
      return Scaffold(
        backgroundColor: t.background,
        body: _buildLoadingState(),
      );
    }

    if (_acessoNegado) {
      return PermissionAccessGuard.deniedScaffold(
        context,
        title: 'Gerenciar eventos',
        message: 'Você não tem permissão para acessar eventos.',
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      floatingActionButton: _podeCriarEvento
          ? FloatingActionButton.extended(
              heroTag: 'fab_gerenciar_eventos_criar',
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Novo evento',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              onPressed: _abrirCadastroEvento,
            )
          : null,
      body: _carregandoPermissoes
          ? _buildLoadingState()
          : _acessoNegado
          ? PermissionAccessGuard.deniedScaffold(
              context,
              title: 'Gerenciar eventos',
              message: 'Você não tem permissão para acessar eventos.',
            )
          : CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _eventosStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _buildErroState(
                          'Erro ao carregar eventos: ${snapshot.error}',
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingState();
                      }

                      final docs = snapshot.data?.docs ?? [];
                      final eventos = docs
                          .map((doc) => EventoModel.fromFirestore(doc))
                          .toList();

                      final eventosFiltrados = _filtrarEventos(eventos);
                      final resumo = _resumoEventos(eventos);

                      return Column(
                        children: [
                          _buildHero(resumo),
                          _buildSearchAndFilters(),
                          if (eventos.isEmpty)
                            _buildEmptyState(
                              titulo: 'Nenhum evento cadastrado',
                              mensagem: _podeCriarEvento
                                  ? 'Crie o primeiro evento para começar a organizar inscrições, participantes e certificados.'
                                  : 'Nenhum evento foi cadastrado ainda.',
                              mostrarBotao: _podeCriarEvento,
                            )
                          else if (eventosFiltrados.isEmpty)
                            _buildEmptyState(
                              titulo: 'Nenhum resultado',
                              mensagem:
                                  'Nenhum evento encontrado para os filtros aplicados.',
                              mostrarBotao: false,
                            )
                          else
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _viewMode == 0
                                  ? _buildListView(eventosFiltrados)
                                  : _buildGridView(eventosFiltrados),
                            ),
                          const SizedBox(height: 110),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSliverAppBar() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      elevation: 0,
      toolbarHeight: 64,
      backgroundColor: t.primary,
      foregroundColor: onPrimary,
      titleSpacing: 4,
      title: Text(
        'Gerenciar Eventos',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: onPrimary,
          fontWeight: FontWeight.w900,
          fontSize: 18,
          letterSpacing: 0.2,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _viewMode == 0
                ? Icons.grid_view_rounded
                : Icons.view_agenda_rounded,
          ),
          tooltip: _viewMode == 0 ? 'Ver em grade' : 'Ver em lista',
          onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 2),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Recarregar permissões',
          onPressed: _carregarPermissoes,
        ),
        if (_podeCriarEvento)
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Novo evento',
            onPressed: () => _abrirCadastroEvento(),
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildHero(Map<String, int> resumo) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: primary.withAlpha(36)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary.withAlpha(31),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: primary.withAlpha(41)),
                ),
                child: Icon(Icons.event_note_rounded, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Eventos, inscrições, banners e publicação no portfólio em uma central única.',
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              final cards = [
                _ResumoMiniCard(
                  label: 'Total',
                  value: '${resumo['todos'] ?? 0}',
                  icon: Icons.event_rounded,
                  color: t.primary,
                ),
                _ResumoMiniCard(
                  label: 'Andamento',
                  value: '${resumo['andamento'] ?? 0}',
                  icon: Icons.play_circle_fill_rounded,
                  color: t.success,
                ),
                _ResumoMiniCard(
                  label: 'Finalizados',
                  value: '${resumo['finalizado'] ?? 0}',
                  icon: Icons.history_rounded,
                  color: t.textSecondary,
                ),
                _ResumoMiniCard(
                  label: 'No site',
                  value: '${resumo['site'] ?? 0}',
                  icon: Icons.public_rounded,
                  color: t.info,
                ),
              ];

              if (compact) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cards.map((card) {
                    return SizedBox(
                      width: (constraints.maxWidth - 8) / 2,
                      child: _buildResumoMiniCard(card),
                    );
                  }).toList(),
                );
              }

              return Row(
                children: cards.map((card) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildResumoMiniCard(card),
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

  Widget _buildResumoMiniCard(_ResumoMiniCard data) {
    final t = context.uai;
    final accent = _ensureVisible(data.color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(23), t.cardAlt),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: accent.withAlpha(41)),
      ),
      child: Column(
        children: [
          Icon(data.icon, color: accent, size: 20),
          const SizedBox(height: 5),
          Text(
            data.value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(color: t.textPrimary),
            decoration:
                _inputDecoration(
                  label: 'Buscar',
                  hint: 'Buscar por nome, cidade ou tipo...',
                  icon: Icons.search_rounded,
                ).copyWith(
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: t.textSecondary,
                          ),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  prefixIcon: Icon(Icons.search_rounded, color: primary),
                ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFiltroChip('Todos', 'todos', Icons.event_rounded),
                _buildFiltroChip(
                  'Em andamento',
                  'andamento',
                  Icons.play_circle_rounded,
                ),
                _buildFiltroChip(
                  'Finalizados',
                  'finalizado',
                  Icons.history_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String label, String value, IconData icon) {
    final t = context.uai;
    final selected = _statusFiltro == value;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    final foreground = selected ? _readableOn(primary) : primary;

    return ChoiceChip(
      selected: selected,
      avatar: Icon(icon, size: 16, color: foreground),
      label: Text(label),
      selectedColor: primary,
      backgroundColor: Color.alphaBlend(primary.withAlpha(23), t.cardAlt),
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w900),
      side: BorderSide(color: selected ? primary : primary.withAlpha(46)),
      onSelected: (_) => setState(() => _statusFiltro = value),
    );
  }

  Future<void> _abrirPreviewPublico(EventoModel evento) async {
    final id = evento.id;
    if (id == null || id.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(id)
          .get();
      if (!mounted) return;
      final entry = _portfolioRepository.entryFromEventDoc(doc);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PortfolioDetailScreen(entry: entry)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a prévia do evento: $e')),
      );
    }
  }

  Future<void> _abrirPreviewModuloEventos(EventoModel evento) async {
    final id = evento.id;
    if (id == null || id.isEmpty || !mounted) return;

    final Widget screen = evento.status == 'andamento'
        ? DetalhesEventoAndamentoScreen(evento: evento, eventoId: id)
        : DetalhesEventoScreen(
            evento: evento,
            eventoId: id,
            adminMode: true,
          );

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _buildListView(List<EventoModel> eventos) {
    return ListView.builder(
      key: const ValueKey('eventos_lista'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: eventos.length,
      itemBuilder: (context, index) {
        return _buildListEventCard(eventos[index]);
      },
    );
  }

  Widget _buildListEventCard(EventoModel evento) {
    final t = context.uai;
    final status = evento.status;
    final corStatus = _ensureVisible(_statusColor(status), t.card);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrirPreviewPublico(evento),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                _buildEventImage(evento, corStatus, width: 92, height: 104),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEventInfo(evento, corStatus, compact: false),
                ),
                const SizedBox(width: 6),
                _buildActionColumn(evento),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(List<EventoModel> eventos) {
    return LayoutBuilder(
      key: const ValueKey('eventos_grade'),
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1380
            ? 4
            : width >= 980
            ? 3
            : width >= 620
            ? 2
            : width >= 360
            ? 2
            : 1;

        const gap = 14.0;
        final cellWidth = (width - (gap * (crossAxisCount - 1))) / crossAxisCount;
        final coverAspect = cellWidth <= 260
            ? 1.0
            : cellWidth <= 420
                ? 4 / 3
                : 16 / 9;
        final bodyHeight = cellWidth <= 260 ? 104.0 : 112.0;
        final tileHeight = (cellWidth / coverAspect) + bodyHeight + 3;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: eventos.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, index) {
            return _buildGridEventCard(
              eventos[index],
              coverAspectRatio: coverAspect,
              bodyHeight: bodyHeight,
              dense: cellWidth <= 260,
            );
          },
        );
      },
    );
  }

  Widget _buildGridEventCard(
    EventoModel evento, {
    required double coverAspectRatio,
    required double bodyHeight,
    required bool dense,
  }) {
    final t = context.uai;
    final corStatus = _ensureVisible(_statusColor(evento.status), t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirPreviewPublico(evento),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: coverAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildEventImage(
                      evento,
                      corStatus,
                      width: double.infinity,
                      height: double.infinity,
                      radius: 0,
                    ),
                    Positioned(
                      left: 7,
                      top: 7,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildPortfolioPill(evento),
                          const SizedBox(height: 6),
                          _buildStatusShortcut(evento),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 7,
                      top: 7,
                      child: _buildAdminActionsMenu(evento),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: bodyHeight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    dense ? 10 : 12,
                    9,
                    dense ? 10 : 12,
                    9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatarData(evento.data),
                        style: TextStyle(
                          color: t.primary,
                          fontSize: dense ? 10.5 : 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        evento.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: dense ? 12.5 : 13.5,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const Spacer(),
                      if (evento.cidade.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: t.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                evento.cidade,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textMuted,
                                  fontSize: dense ? 10.5 : 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirGerenciamentoParticipacoes(EventoModel evento) async {
    if (evento.id == null) return;

    final Widget destino = evento.status == 'andamento'
        ? ParticipantesEventoScreen(
            eventoId: evento.id!,
            eventoNome: evento.nome,
            evento: evento,
          )
        : GerenciarParticipacoesScreen(
            eventoId: evento.id!,
            eventoNome: evento.nome,
            evento: evento,
          );

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => destino),
    );
  }

  Widget _buildStatusShortcut(EventoModel evento) {
    if (!_podeEditarEvento || evento.id == null) return const SizedBox.shrink();
    final emAndamento = evento.status == 'andamento';
    final color = emAndamento ? context.uai.error : context.uai.success;
    return Tooltip(
      message: emAndamento ? 'Finalizar evento' : 'Iniciar evento',
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _alterarStatus(evento.id!, evento.status),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              emAndamento ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminActionsMenu(EventoModel evento) {
    final t = context.uai;
    return Material(
      color: Colors.black.withAlpha(148),
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        tooltip: 'Ações do evento',
        color: t.surface,
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.more_vert_rounded,
          color: Colors.white,
          size: 20,
        ),
        onSelected: (value) {
          if (value == 'module_preview') {
            _abrirPreviewModuloEventos(evento);
          } else if (value == 'participants') {
            _abrirGerenciamentoParticipacoes(evento);
          } else if (value == 'edit') {
            _abrirCadastroEvento(evento: evento);
          } else if (value == 'visibility' && evento.id != null) {
            _alternarPortfolioWeb(
              evento.id!,
              evento.mostrarNoPortfolioWeb,
            );
          } else if (value == 'status' && evento.id != null) {
            _alterarStatus(evento.id!, evento.status);
          } else if (value == 'delete' && evento.id != null) {
            _excluirEvento(evento.id!, evento.nome);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'module_preview',
            child: Row(
              children: [
                Icon(Icons.visibility_rounded, size: 20),
                SizedBox(width: 12),
                Text('Visualizar no módulo Eventos'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'participants',
            child: Row(
              children: [
                Icon(Icons.groups_2_rounded, size: 20),
                SizedBox(width: 12),
                Text('Gerenciar participações'),
              ],
            ),
          ),
          if (_podeEditarEvento)
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Editar evento'),
                ],
              ),
            ),
          if (_podeEditarEvento)
            PopupMenuItem(
              value: 'visibility',
              child: Row(
                children: [
                  Icon(
                    evento.mostrarNoPortfolioWeb
                        ? Icons.public_off_rounded
                        : Icons.public_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    evento.mostrarNoPortfolioWeb
                        ? 'Remover do site'
                        : 'Adicionar ao site',
                  ),
                ],
              ),
            ),
          if (_podeEditarEvento)
            PopupMenuItem(
              value: 'status',
              child: Row(
                children: [
                  Icon(
                    evento.status == 'andamento'
                        ? Icons.stop_circle_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    evento.status == 'andamento'
                        ? 'Finalizar evento'
                        : 'Iniciar evento',
                  ),
                ],
              ),
            ),
          if (_podeEditarEvento)
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Excluir'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactEventMenu(EventoModel evento) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.visibility_rounded),
                  title: const Text('Visualizar no módulo Eventos'),
                  onTap: () {
                    Navigator.pop(context);
                    _abrirPreviewModuloEventos(evento);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.groups_2_rounded),
                  title: const Text('Gerenciar participações'),
                  onTap: () {
                    Navigator.pop(context);
                    _abrirGerenciamentoParticipacoes(evento);
                  },
                ),
                if (_podeEditarEvento)
                  ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Editar evento'), onTap: () { Navigator.pop(context); _abrirCadastroEvento(evento: evento); }),
                if (_podeEditarEvento)
                  ListTile(leading: const Icon(Icons.public_rounded), title: Text(evento.mostrarNoPortfolioWeb ? 'Remover do site' : 'Adicionar ao site'), onTap: () { Navigator.pop(context); _alternarPortfolioWeb(evento.id!, evento.mostrarNoPortfolioWeb); }),
                if (_podeEditarEvento)
                  ListTile(leading: Icon(evento.status == 'andamento' ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded), title: Text(evento.status == 'andamento' ? 'Finalizar evento' : 'Iniciar evento'), onTap: () { Navigator.pop(context); _alterarStatus(evento.id!, evento.status); }),
                if (_podeEditarEvento)
                  ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Excluir'), onTap: () { Navigator.pop(context); _excluirEvento(evento.id!, evento.nome); }),
              ],
            ),
          ),
        ),
        icon: const Icon(Icons.more_horiz_rounded, size: 18),
        label: const Text('AÇÕES'),
      ),
    );
  }

  Widget _buildEventImage(
    EventoModel evento,
    Color corStatus, {
    required double width,
    required double height,
    double radius = 16,
  }) {
    final t = context.uai;
    final borderRadius = BorderRadius.circular(radius);

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: width,
        height: height,
        color: Color.alphaBlend(corStatus.withAlpha(20), t.cardAlt),
        child: evento.linkBanner != null && evento.linkBanner!.isNotEmpty
            ? PortfolioCoverImage(
                url: evento.linkBanner!,
                positionX: evento.portfolioCoverPositionX,
                positionY: evento.portfolioCoverPositionY,
                scale: evento.portfolioCoverScale,
                placeholder: _buildFallbackImage(evento, corStatus),
              )
            : _buildFallbackImage(evento, corStatus),
      ),
    );
  }

  Widget _buildFallbackImage(EventoModel evento, Color corStatus) {
    return Center(child: Icon(evento.iconeDoTipo, color: corStatus, size: 42));
  }

  Widget _buildEventInfo(
    EventoModel evento,
    Color corStatus, {
    required bool compact,
  }) {
    final t = context.uai;

    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!compact) _buildStatusPill(evento.status),
        if (!compact) const SizedBox(height: 7),
        Text(
          evento.nome,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: compact ? 12.5 : 14.5,
            height: 1.12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          evento.tipo,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textSecondary,
            fontSize: compact ? 10.5 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        _miniInfo(
          icon: Icons.calendar_month_rounded,
          text: evento.dataFormatada.isNotEmpty
              ? evento.dataFormatada
              : _formatarData(evento.data),
          compact: compact,
        ),
        const SizedBox(height: 4),
        _miniInfo(
          icon: Icons.location_on_rounded,
          text: evento.cidade.isEmpty ? 'Cidade não informada' : evento.cidade,
          compact: compact,
        ),
        if (evento.valorInscricao > 0) ...[
          const SizedBox(height: 4),
          _miniInfo(
            icon: Icons.payments_rounded,
            text: 'R\$ ${evento.valorInscricao.toStringAsFixed(2)}',
            compact: compact,
            color: _ensureVisible(t.success, t.card),
          ),
        ],
      ],
    );
  }

  Widget _miniInfo({
    required IconData icon,
    required String text,
    required bool compact,
    Color? color,
  }) {
    final t = context.uai;
    final c = color ?? t.textSecondary;

    return Row(
      mainAxisAlignment: compact
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(icon, size: compact ? 11 : 13, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            textAlign: compact ? TextAlign.center : TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c,
              fontSize: compact ? 10 : 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill(String status) {
    final t = context.uai;
    final color = _ensureVisible(_statusColor(status), t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withAlpha(26), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withAlpha(46)),
      ),
      child: Text(
        _statusLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildPortfolioPill(EventoModel evento) {
    final t = context.uai;
    final ativo = evento.mostrarNoPortfolioWeb;
    final color = ativo ? t.info : t.textSecondary;

    return Tooltip(
      message: ativo ? 'Remover do site' : 'Adicionar ao site',
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _podeEditarEvento && evento.id != null
              ? () => _alternarPortfolioWeb(
                    evento.id!,
                    evento.mostrarNoPortfolioWeb,
                  )
              : null,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: t.softShadow,
            ),
            child: Icon(
              ativo ? Icons.public_rounded : Icons.public_off_rounded,
              color: _readableOn(color),
              size: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionColumn(EventoModel evento) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPortfolioAction(evento),
        _buildStatusAction(evento),
        _buildEditAction(evento),
        _buildDeleteAction(evento),
      ],
    );
  }

  Widget _buildActionRow(EventoModel evento) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPortfolioAction(evento, small: true),
        _buildStatusAction(evento, small: true),
        _buildEditAction(evento, small: true),
        _buildDeleteAction(evento, small: true),
      ],
    );
  }

  Widget _buildPortfolioAction(EventoModel evento, {bool small = false}) {
    if (!_podeEditarEvento) return const SizedBox.shrink();

    return _actionButton(
      icon: Icons.public_rounded,
      color: evento.mostrarNoPortfolioWeb
          ? context.uai.info
          : context.uai.textSecondary,
      tooltip: evento.mostrarNoPortfolioWeb
          ? 'Remover do site'
          : 'Adicionar ao site',
      onTap: () =>
          _alternarPortfolioWeb(evento.id!, evento.mostrarNoPortfolioWeb),
      small: small,
    );
  }

  Widget _buildStatusAction(EventoModel evento, {bool small = false}) {
    if (!_podeEditarEvento) return const SizedBox.shrink();

    final emAndamento = evento.status == 'andamento';

    return _actionButton(
      icon: emAndamento
          ? Icons.stop_circle_rounded
          : Icons.play_circle_fill_rounded,
      color: emAndamento ? context.uai.textSecondary : context.uai.success,
      tooltip: emAndamento ? 'Finalizar evento' : 'Iniciar evento',
      onTap: () => _alterarStatus(evento.id!, evento.status),
      small: small,
    );
  }

  Widget _buildEditAction(EventoModel evento, {bool small = false}) {
    if (!_podeEditarEvento) return const SizedBox.shrink();

    return _actionButton(
      icon: Icons.edit_rounded,
      color: context.uai.warning,
      tooltip: 'Editar evento',
      onTap: () => _abrirCadastroEvento(evento: evento),
      small: small,
    );
  }

  Widget _buildDeleteAction(EventoModel evento, {bool small = false}) {
    if (!_podeExcluirEvento) return const SizedBox.shrink();

    return _actionButton(
      icon: Icons.delete_outline_rounded,
      color: context.uai.error,
      tooltip: 'Excluir evento',
      onTap: () => _excluirEvento(evento.id!, evento.nome),
      small: small,
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    bool small = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Color.alphaBlend(accent.withAlpha(23), t.cardAlt),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: small ? 32 : 36,
            height: small ? 32 : 36,
            margin: EdgeInsets.symmetric(
              horizontal: small ? 2 : 0,
              vertical: small ? 0 : 3,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withAlpha(41)),
            ),
            child: Icon(icon, color: accent, size: small ? 18 : 20),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String titulo,
    required String mensagem,
    required bool mostrarBotao,
  }) {
    final t = context.uai;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 32, 18, 18),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy_rounded, size: 64, color: t.textMuted),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (mostrarBotao) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _abrirCadastroEvento(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('CRIAR EVENTO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: _readableOn(t.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErroState(String mensagem) {
    final t = context.uai;
    final error = _ensureVisible(t.error, t.card);

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 32, 18, 18),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: error.withAlpha(46)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 64, color: error),
          const SizedBox(height: 12),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: error,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;

    return Center(
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              const SizedBox(height: 14),
              Text(
                'Carregando eventos...',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumoMiniCard {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ResumoMiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

enum _SnackType { success, error, warning, info, neutral }
