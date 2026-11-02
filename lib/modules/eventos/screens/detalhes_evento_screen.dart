import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/services/evento_service.dart';
import 'package:uai_capoeira/modules/eventos/services/evento_participantes_cache_service.dart';
import 'package:uai_capoeira/modules/eventos/services/participacao_service.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/shared/services/svg_service.dart';

class DetalhesEventoScreen extends StatefulWidget {
  final EventoModel evento;
  final String eventoId;
  final bool adminMode;

  const DetalhesEventoScreen({
    super.key,
    required this.evento,
    required this.eventoId,
    this.adminMode = false,
  });

  @override
  State<DetalhesEventoScreen> createState() => _DetalhesEventoScreenState();
}

class _DetalhesEventoScreenState extends State<DetalhesEventoScreen> {
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

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withAlpha(173);
  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  late EventoModel _evento;
  bool _isLoading = false;
  late Future<List<Map<String, dynamic>>> _participantesFuture;
  bool _podeGerenciar = false; // Nova variável para armazenar permissão
  final _eventoService = EventoService();
  final _permissaoService = PermissaoService();
  final _participantesCacheService = EventoParticipantesCacheService();
  final _participacaoService = ParticipacaoService();

  @override
  void initState() {
    super.initState();
    _evento = widget.evento;
    _participantesFuture = _buscarParticipantesCache();
    _verificarStatusEvento();
    _verificarPermissoes(); // Verificar permissões ao iniciar
  }

  Future<void> _verificarPermissoes() async {
    // Verifica as permissões de forma assíncrona
    final podeEditar = await _permissaoService.temPermissao(
      'pode_editar_evento',
    );
    final podeCriar = await _permissaoService.temPermissao('pode_criar_evento');

    if (mounted) {
      setState(() {
        _podeGerenciar = podeEditar || podeCriar;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _buscarParticipantesCache({
    bool forceServer = false,
  }) {
    return _participantesCacheService.buscarCacheParticipantes(
      widget.eventoId,
      forceServer: forceServer,
    );
  }

  void _recarregarParticipantes({bool forceServer = false}) {
    setState(() {
      _participantesFuture = _buscarParticipantesCache(
        forceServer: forceServer,
      );
    });
  }

  Future<void> _atualizarTela() async {
    try {
      final eventoAtualizado = await _eventoService.buscarEventoPorId(
        widget.eventoId,
      );
      if (eventoAtualizado != null && mounted) {
        setState(() => _evento = eventoAtualizado);
      }
      if (_evento.status == 'finalizado') {
        await _participantesCacheService.reconstruirCacheParticipantes(
          widget.eventoId,
          forceServer: true,
        );
      }
    } catch (e) {
      debugPrint('Erro ao atualizar detalhes do evento: $e');
    } finally {
      if (mounted) _recarregarParticipantes(forceServer: true);
    }
  }

  Future<void> _verificarStatusEvento() async {
    // Se o evento estiver finalizado, não precisa verificar
    if (_evento.status == 'finalizado') return;

    setState(() => _isLoading = true);

    try {
      // Busca dados atualizados do evento
      final eventoAtualizado = await _eventoService.buscarEventoPorId(
        widget.eventoId,
      );
      if (eventoAtualizado != null && mounted) {
        setState(() {
          _evento = eventoAtualizado;
        });
      }
    } catch (e) {
      debugPrint('Erro ao verificar status do evento: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
            SnackBar(
              content: Text('Não foi possível abrir o link'),
              backgroundColor: context.uai.error,
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
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Future<void> _compartilharEvento() async {
    final String organizadores = _formatarOrganizadores(_evento.organizadores);

    String texto =
        '''
🎉 *${_evento.nome}*

📅 Data: ${_evento.dataFormatada} ${_evento.horario.isNotEmpty ? 'às ${_evento.horario}' : ''}
📍 Local: ${_evento.local} - ${_evento.cidade}

🏷️ Tipo: ${_evento.tipo}
👥 Organizadores: $organizadores

💰 Valor da inscrição: ${_evento.getValorTotal()}

${_evento.temCamisa ? '👕 Camisa: R\$ ${_evento.valorCamisa?.toStringAsFixed(2)}' : ''}

🔗 Links disponíveis no app UAI CAPOEIRA!
''';

    await Share.share(texto.trim());
  }

  String _formatarOrganizadores(dynamic organizadores) {
    if (organizadores == null) return 'Não informado';
    if (organizadores is List) {
      return organizadores.join(', ');
    }
    if (organizadores is String) {
      return organizadores;
    }
    return 'Não informado';
  }

  Future<void> _abrirNoMapa() async {
    if (_evento.local.isEmpty && _evento.cidade.isEmpty) return;

    final String query = Uri.encodeComponent(
      '${_evento.local} ${_evento.cidade}'.trim(),
    );
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _adicionarAoCalendario() async {
    // TODO: Implementar integração com calendário
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Funcionalidade em desenvolvimento'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _evento.status;
    final corStatus = status == 'finalizado'
        ? Colors.grey
        : context.uai.success;
    final textoStatus = status == 'finalizado' ? 'Finalizado' : 'Em andamento';

    return Scaffold(
      backgroundColor: context.uai.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: context.uai.primary,
              backgroundColor: context.uai.surface,
              onRefresh: _atualizarTela,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(corStatus),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                    sliver: SliverToBoxAdapter(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1320),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildEventIdentityCard(corStatus, textoStatus),
                              const SizedBox(height: 18),
                              _buildResponsiveOverview(),
                              if (status == 'finalizado') ...[
                                const SizedBox(height: 22),
                                _buildParticipantesEventoSection(),
                              ],
                              const SizedBox(height: 22),
                              if (_podeGerenciar && status != 'finalizado')
                                _buildAdminActions(),
                              const SizedBox(height: 14),
                              _buildActionButtons(),
                              const SizedBox(height: 16),
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

  SliverAppBar _buildSliverAppBar(Color corStatus) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: _appBarBg(),
      flexibleSpace: FlexibleSpaceBar(
        background: _evento.linkBanner != null && _evento.linkBanner!.isNotEmpty
            ? Image.network(
                _evento.linkBanner!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackBanner();
                },
              )
            : _buildFallbackBanner(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: _compartilharEvento,
          tooltip: 'Compartilhar',
        ),
      ],
    );
  }

  Widget _buildResponsiveOverview() {
    final hasOrganizadores =
        _formatarOrganizadores(_evento.organizadores) != 'Não informado';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDataHorarioCard(),
              const SizedBox(height: 18),
              _buildLocalCard(),
              if (hasOrganizadores) ...[
                const SizedBox(height: 18),
                _buildOrganizadoresCard(),
              ],
              const SizedBox(height: 18),
              _buildLinksSection(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  _buildDataHorarioCard(),
                  const SizedBox(height: 18),
                  _buildLocalCard(),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  if (hasOrganizadores) ...[
                    _buildOrganizadoresCard(),
                    const SizedBox(height: 18),
                  ],
                  _buildLinksSection(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      color: context.uai.primary,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _evento.iconeDoTipo,
              size: 50,
              color: Colors.white.withAlpha(128),
            ),
            const SizedBox(height: 8),
            Text(
              _evento.nome,
              style: TextStyle(color: Colors.white.withAlpha(179)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventIdentityCard(Color corStatus, String textoStatus) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.uai.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(11),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusBadge(corStatus, textoStatus),
              const Spacer(),
              Icon(Icons.history_rounded, color: context.uai.textMuted, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          _buildTituloEvento(),
          const SizedBox(height: 10),
          _buildTipoEvento(),
        ],
      ),
    );
  }

  Widget _buildSectionHeading({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: context.uai.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(Color corStatus, String textoStatus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: corStatus.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: corStatus),
          ),
          const SizedBox(width: 6),
          Text(
            textoStatus,
            style: TextStyle(color: corStatus, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTituloEvento() {
    return Text(
      _evento.nome,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: context.uai.textPrimary,
      ),
    );
  }

  Widget _buildTipoEvento() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.uai.info.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _evento.tipo,
        style: TextStyle(color: context.uai.info, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildDataHorarioCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          icon: Icons.event_rounded,
          title: 'Data e horário',
          color: context.uai.warning,
        ),
        SizedBox(height: 8),
        Card(
          elevation: 2,
          child: InkWell(
            onTap: _adicionarAoCalendario,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildIconWithBackground(
                    Icons.calendar_today,
                    context.uai.warning,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.uai.textSecondary,
                          ),
                        ),
                        Text(
                          _evento.dataFormatada,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _onCard(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  _buildIconWithBackground(Icons.access_time, context.uai.info),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Horário',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.uai.textSecondary,
                          ),
                        ),
                        Text(
                          _evento.horario.isNotEmpty
                              ? _evento.horario
                              : 'Não definido',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _onCard(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          icon: Icons.location_on_rounded,
          title: 'Local',
          color: context.uai.error,
        ),
        SizedBox(height: 8),
        Card(
          elevation: 2,
          child: InkWell(
            onTap: _abrirNoMapa,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildIconWithBackground(
                    Icons.location_on,
                    context.uai.error,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _evento.local.isNotEmpty
                              ? _evento.local
                              : 'Local não informado',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _onCard(),
                          ),
                        ),
                        if (_evento.cidade.isNotEmpty)
                          Text(
                            _evento.cidade,
                            style: TextStyle(
                              fontSize: 14,
                              color: context.uai.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: context.uai.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrganizadoresCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          icon: Icons.groups_rounded,
          title: 'Organizadores',
          color: context.uai.associacao,
        ),
        SizedBox(height: 8),
        Card(
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                _buildIconWithBackground(Icons.people, context.uai.associacao),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatarOrganizadores(_evento.organizadores),
                    style: TextStyle(
                      fontSize: 14,
                      color: _onCardMuted(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconWithBackground(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildLinksSection() {
    if (!_evento.linksHabilitados) return const SizedBox.shrink();
    final hasLinks =
        (_evento.linkBanner?.isNotEmpty ?? false) ||
        (_evento.linkFotosVideos?.isNotEmpty ?? false) ||
        (_evento.previaVideo?.isNotEmpty ?? false) ||
        (_evento.linkPlaylist?.isNotEmpty ?? false);

    if (!hasLinks) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🔗 Links Disponíveis',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.uai.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        if (_evento.linkBanner?.isNotEmpty ?? false)
          _buildLinkCard(
            icon: Icons.image,
            label: 'Banner do Evento',
            url: _evento.linkBanner!,
            cor: context.uai.associacao,
          ),
        if (_evento.linkFotosVideos?.isNotEmpty ?? false)
          _buildLinkCard(
            icon: Icons.photo_library,
            label: 'Fotos e Vídeos',
            url: _evento.linkFotosVideos!,
            cor: context.uai.info,
          ),
        if (_evento.previaVideo?.isNotEmpty ?? false)
          _buildLinkCard(
            icon: Icons.play_circle,
            label: 'Prévia do Evento',
            url: _evento.previaVideo!,
            cor: context.uai.error,
          ),
        if (_evento.linkPlaylist?.isNotEmpty ?? false)
          _buildLinkCard(
            icon: Icons.playlist_play,
            label: 'Playlist',
            url: _evento.linkPlaylist!,
            cor: context.uai.success,
          ),
      ],
    );
  }

  Widget _buildParticipantesEventoSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _participantesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSimpleSection(
            title: 'Participantes do evento',
            icon: Icons.groups_2_rounded,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: CircularProgressIndicator(color: context.uai.primary),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _buildSimpleSection(
            title: 'Participantes do evento',
            icon: Icons.groups_2_rounded,
            child: _buildParticipantesInfo(
              Icons.error_outline_rounded,
              'Erro ao carregar participantes.',
              context.uai.error,
            ),
          );
        }

        final participantes = snapshot.data ?? [];
        if (participantes.isEmpty) {
          return _buildSimpleSection(
            title: 'Participantes do evento',
            icon: Icons.groups_2_rounded,
            child: _buildParticipantesInfo(
              Icons.people_outline_rounded,
              'Nenhum participante no cache deste evento.',
              context.uai.info,
            ),
          );
        }

        return Card(
          color: context.uai.card,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: context.uai.primary.withAlpha(23),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.groups_2_rounded,
                        color: context.uai.primary,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Participantes do evento',
                            style: TextStyle(
                              color: context.uai.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Toque em um participante para ver os detalhes',
                            style: TextStyle(
                              color: context.uai.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.uai.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${participantes.length}',
                        style: TextStyle(
                          color: context.uai.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // Mantém a linguagem visual do primeiro modo de
                    // AlunosTurmaScreen: cartões horizontais em formato de lista.
                    // Em desktop muito largo usamos duas colunas apenas para não
                    // transformar cada linha em uma faixa enorme.
                    final columns = width >= 980 ? 2 : 1;
                    const gap = 10.0;
                    final cardWidth = (width - (columns - 1) * gap) / columns;

                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: participantes
                          .map(
                            (data) => SizedBox(
                              width: cardWidth,
                              child: _buildParticipantePremiumCard(data),
                            ),
                          )
                          .toList(),
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

  Widget _buildParticipantePremiumCard(Map<String, dynamic> data) {
    final t = context.uai;
    final nome =
        _pickFirstClean(data, const ['aluno_nome', 'nome']) ??
        'Aluno não informado';
    final graduacao = _pickFirstClean(data, const [
      'graduacao',
      'graduacao_nome',
    ]);
    final certificado = _pickFirstClean(data, const ['link_certificado']);
    final foto = _pickFirstClean(data, const ['aluno_foto_url']);

    return SizedBox(
      height: 94,
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 5),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrirParticipanteDetalhes(data),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 5),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mesmo desenho-base da lista de alunos da turma, mas sem a
                // faixa de idade: a foto ocupa toda a altura do cartão.
                SizedBox(
                  width: 94,
                  child: _buildParticipanteFotoLista(nome, foto),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          nome.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 14.2,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (graduacao != null && graduacao.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            'PEGOU $graduacao',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ensureVisible(t.warning, t.card),
                              fontSize: 11.2,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        if (certificado != null && certificado.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 13,
                                color: _ensureVisible(t.success, t.card),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'CERTIFICADO DISPONÍVEL',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _ensureVisible(t.success, t.card),
                                    fontSize: 9.8,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (graduacao != null && graduacao.isNotEmpty)
                  SizedBox(
                    width: 66,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: _buildParticipanteCorda(data)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Center(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: t.textMuted,
                      size: 19,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParticipanteFotoLista(String nome, String? fotoUrl) {
    final initials = _iniciaisNome(nome);
    final t = context.uai;
    return Container(
      color: t.cardAlt,
      alignment: Alignment.center,
      child: fotoUrl == null || fotoUrl.isEmpty
          ? Text(
              initials,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            )
          : CachedNetworkImage(
              imageUrl: fotoUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorWidget: (_, _, _) => Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildParticipanteCompactBadge(
    IconData icon,
    String label,
    Color color,
  ) {
    final visible = _ensureVisible(color, context.uai.cardAlt);
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: visible.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: visible),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visible,
                fontSize: 10.5,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirParticipanteDetalhes(Map<String, dynamic> data) async {
    final nome =
        _pickFirstClean(data, const ['aluno_nome', 'nome']) ??
        'Aluno não informado';
    final graduacao = _pickFirstClean(data, const [
      'graduacao',
      'graduacao_nome',
    ]);
    final certificado = _pickFirstClean(data, const ['link_certificado']);
    final foto = _pickFirstClean(data, const ['aluno_foto_url']);
    final dataEvento = _formatarDataParticipante(data['data_evento']);
    final tipo =
        _pickFirstClean(data, const ['tipo_evento', 'tipo']) ?? _evento.tipo;
    final status = _pickFirstClean(data, const ['status']) ?? 'Finalizado';

    Widget content(BuildContext sheetContext) {
      final t = sheetContext.uai;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildParticipanteFoto(nome, foto),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nome.toUpperCase(),
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 18,
                            height: 1.12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (graduacao != null) ...[
                          const SizedBox(height: 8),
                          _buildParticipanteCompactBadge(
                            Icons.emoji_events_rounded,
                            'Pegou $graduacao',
                            t.warning,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildParticipanteInfoRow(Icons.calendar_month_rounded, 'Data do evento', dataEvento),
              _buildParticipanteInfoRow(Icons.category_rounded, 'Tipo registrado', tipo),
              _buildParticipanteInfoRow(Icons.check_circle_outline_rounded, 'Status', status),
              _buildParticipanteInfoRow(Icons.military_tech_rounded, 'Graduação neste evento', graduacao ?? 'Não registrada'),
              if (certificado != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _abrirLink(certificado),
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('ABRIR CERTIFICADO'),
                  ),
                ),
              ],
              if (widget.adminMode && _podeGerenciar) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _removerParticipanteFinalizado(data, nome);
                    },
                    icon: const Icon(Icons.person_remove_alt_1_rounded),
                    label: const Text('REMOVER PARTICIPAÇÃO'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.error,
                      side: BorderSide(color: t.error.withAlpha(89)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 760) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: dialogContext.uai.card,
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: content(dialogContext),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.uai.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: content,
      );
    }
  }

  Future<void> _removerParticipanteFinalizado(
    Map<String, dynamic> data,
    String nome,
  ) async {
    final participacaoId = _pickFirstClean(data, const [
      'participacao_id',
      'participacaoId',
      'id',
    ]);
    if (participacaoId == null || participacaoId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível identificar esta participação.')),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover participação?'),
        content: Text(
          'Isso remove $nome apenas da participação deste evento. '
          'O cadastro do aluno e o histórico geral não serão excluídos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.person_remove_alt_1_rounded),
            label: const Text('REMOVER'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _participacaoService.removerParticipanteFinalizado(
        participacaoId: participacaoId,
        eventoId: widget.eventoId,
      );
      await _participantesCacheService.removerCacheDaParticipacao(
        widget.eventoId,
        participacaoId,
      );
      if (!mounted) return;
      _recarregarParticipantes(forceServer: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Participação de $nome removida.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível remover a participação: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  Widget _buildParticipanteInfoRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.uai.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.uai.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.uai.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSimpleSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      color: context.uai.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: context.uai.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantesInfo(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.uai.cardAlt,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: context.uai.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipanteFoto(String nome, String? fotoUrl) {
    final initials = _iniciaisNome(nome);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 62,
        color: context.uai.card,
        child: fotoUrl == null
            ? Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Center(child: Text(initials)),
              ),
      ),
    );
  }

  Widget _buildParticipanteCorda(Map<String, dynamic> data) {
    final cor1 =
        _colorFromHex(data['graduacao_hex_cor1']) ?? context.uai.warning;
    final cor2 = _colorFromHex(data['graduacao_hex_cor2']) ?? cor1;
    final ponta1 = _colorFromHex(data['graduacao_hex_ponta1']) ?? cor1;
    final ponta2 = _colorFromHex(data['graduacao_hex_ponta2']) ?? cor2;

    return SizedBox(
      width: 70,
      height: 42,
      child: FutureBuilder<String?>(
        future: SvgService.getSvgContent(context),
        builder: (context, snapshot) {
          final svg = SvgService.getModifiedSvg(
            svgContent: snapshot.data,
            cor1: cor1,
            cor2: cor2,
            ponta1: ponta1,
            ponta2: ponta2,
          );
          if (svg == null) {
            return Icon(
              Icons.military_tech_rounded,
              color: context.uai.warning,
            );
          }
          final sanitized = svg.replaceAll(
            RegExp(r'<style\b[^>]*>[\s\S]*?</style\s*>', caseSensitive: false),
            '',
          );
          return SvgPicture.string(sanitized, fit: BoxFit.contain);
        },
      ),
    );
  }



  String _formatarDataParticipante(dynamic data) {
    if (data is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(data.toDate());
    }
    if (data is DateTime) return DateFormat('dd/MM/yyyy').format(data);
    final text = data?.toString().trim() ?? '';
    if (text.isEmpty) return _evento.dataFormatada;
    final parsed = DateTime.tryParse(text);
    return parsed == null ? text : DateFormat('dd/MM/yyyy').format(parsed);
  }

  String? _pickFirstClean(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      return text;
    }
    return null;
  }

  Color? _colorFromHex(dynamic raw) {
    if (raw == null) return null;
    var value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    value = value.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  String _iniciaisNome(String nome) {
    final partes = nome
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters.take(2).join();
    return '${partes.first.characters.first}${partes.last.characters.first}';
  }

  Widget _buildAdminActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Ações administrativas',
          color: context.uai.primary,
        ),
        SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.people, color: context.uai.info),
                title: const Text('Gerenciar Participantes'),
                subtitle: const Text('Adicionar, remover ou marcar presença'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/participantes-evento',
                    arguments: {
                      'eventoId': widget.eventoId,
                      'eventoNome': _evento.nome,
                    },
                  );
                },
              ),
              Divider(height: 0),
              ListTile(
                leading: Icon(Icons.attach_money, color: context.uai.success),
                title: const Text('Gerenciar Financeiro'),
                subtitle: const Text('Registrar pagamentos e ver extrato'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/financeiro-evento',
                    arguments: {
                      'eventoId': widget.eventoId,
                      'eventoNome': _evento.nome,
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back),
            label: Text('VOLTAR'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: BorderSide(color: context.uai.primary.withAlpha(128)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _compartilharEvento,
            icon: const Icon(Icons.share),
            label: const Text('COMPARTILHAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _appBarBg(),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkCard({
    required IconData icon,
    required String label,
    required String url,
    required Color cor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cor.withAlpha(26),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: cor, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => _abrirLink(url),
      ),
    );
  }
}
