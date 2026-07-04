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
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/shared/services/svg_service.dart';

class DetalhesEventoScreen extends StatefulWidget {
  final EventoModel evento;
  final String eventoId;

  const DetalhesEventoScreen({
    super.key,
    required this.evento,
    required this.eventoId,
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
  Color _onCardMuted() => _onCard().withOpacity(0.68);
  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  late EventoModel _evento;
  bool _isLoading = false;
  late Future<List<Map<String, dynamic>>> _participantesFuture;
  bool _podeGerenciar = false; // Nova variável para armazenar permissão
  final _eventoService = EventoService();
  final _permissaoService = PermissaoService();
  final _participantesCacheService = EventoParticipantesCacheService();

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
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildStatusBadge(corStatus, textoStatus),
                        const SizedBox(height: 16),
                        _buildTituloEvento(),
                        const SizedBox(height: 8),
                        _buildTipoEvento(),
                        const SizedBox(height: 24),
                        _buildDataHorarioCard(),
                        const SizedBox(height: 24),
                        _buildLocalCard(),
                        const SizedBox(height: 24),
                        if (_formatarOrganizadores(_evento.organizadores) !=
                            'Não informado')
                          _buildOrganizadoresCard(),
                        const SizedBox(height: 24),
                        _buildLinksSection(),
                        if (status == 'finalizado') ...[
                          const SizedBox(height: 24),
                          _buildParticipantesEventoSection(),
                        ],
                        const SizedBox(height: 24),
                        // Usando a variável de permissão que já foi carregada
                        if (_podeGerenciar && status != 'finalizado')
                          _buildAdminActions(),
                        const SizedBox(height: 16),
                        _buildActionButtons(),
                        const SizedBox(height: 16),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  SliverAppBar _buildSliverAppBar(Color corStatus) {
    return SliverAppBar(
      expandedHeight: 250,
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
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              _evento.nome,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(Color corStatus, String textoStatus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: corStatus.withOpacity(0.1),
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
        color: context.uai.info.withOpacity(0.08),
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
        Text(
          '📅 Data e Horário',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.uai.textPrimary,
          ),
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
        Text(
          '📍 Local',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.uai.textPrimary,
          ),
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
        Text(
          '👥 Organizadores',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.uai.textPrimary,
          ),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildLinksSection() {
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
    return _buildSimpleSection(
      title: 'Participantes do evento',
      icon: Icons.assignment_ind_rounded,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _participantesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: CircularProgressIndicator(color: context.uai.primary),
              ),
            );
          }
          if (snapshot.hasError) {
            return _buildParticipantesInfo(
              Icons.error_outline_rounded,
              'Erro ao carregar participantes.',
              context.uai.error,
            );
          }
          final participantes = snapshot.data ?? [];
          if (participantes.isEmpty) {
            return _buildParticipantesInfo(
              Icons.people_outline_rounded,
              'Nenhum participante no cache deste evento.',
              context.uai.info,
            );
          }
          return Column(
            children: participantes
                .map((data) => _buildParticipanteCacheTile(data))
                .toList(),
          );
        },
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

  Widget _buildParticipanteCacheTile(Map<String, dynamic> data) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.uai.cardAlt,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: context.uai.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: _buildParticipanteFoto(nome, foto),
          title: Text(
            nome.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (graduacao != null)
                  _buildParticipanteChip(
                    Icons.emoji_events_rounded,
                    'Pegou $graduacao',
                    context.uai.warning,
                  ),
                if (certificado != null)
                  _buildParticipanteChip(
                    Icons.verified_rounded,
                    'Certificado',
                    context.uai.success,
                  ),
              ],
            ),
          ),
          trailing: _buildParticipanteCorda(data),
          children: [
            _buildParticipanteDetail('Data do evento', dataEvento),
            _buildParticipanteDetail(
              'Tipo registrado',
              _pickFirstClean(data, const ['tipo_evento', 'tipo']) ??
                  _evento.tipo,
            ),
            _buildParticipanteDetail(
              'Status',
              _pickFirstClean(data, const ['status']) ?? 'Finalizado',
            ),
            _buildParticipanteDetail(
              'Graduação neste evento',
              graduacao ?? 'Não registrada',
            ),
            if (certificado != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _abrirLink(certificado),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('ABRIR CERTIFICADO'),
                ),
              ),
            ],
          ],
        ),
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
                errorWidget: (_, __, ___) => Center(child: Text(initials)),
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
          return SvgPicture.string(svg, fit: BoxFit.contain);
        },
      ),
    );
  }

  Widget _buildParticipanteChip(IconData icon, String label, Color color) {
    final visible = _ensureVisible(color, context.uai.cardAlt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: visible.withOpacity(0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: visible, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: visible,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipanteDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.uai.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatarDataParticipante(dynamic data) {
    if (data is Timestamp)
      return DateFormat('dd/MM/yyyy').format(data.toDate());
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
        Text(
          '⚙️ Ações Administrativas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              side: BorderSide(color: context.uai.primary.withOpacity(0.5)),
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
            color: cor.withOpacity(0.1),
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
