import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_session_service.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';
import 'package:uai_capoeira/modules/site/screens/biografia_screen.dart';
import 'package:uai_capoeira/modules/site/screens/graduacoes_screen.dart';
import 'package:uai_capoeira/modules/site/screens/landing_page.dart';
import 'package:uai_capoeira/modules/site/screens/portfolio_web_screen.dart';
import 'package:uai_capoeira/modules/site/screens/regimento_screen.dart';

import 'area_aluno_certificados_screen.dart';
import 'area_aluno_frequencia_screen.dart';
import 'area_aluno_solicitar_alteracao_screen.dart';

class AreaAlunoDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> config;
  final Map<String, dynamic> authPayload;

  const AreaAlunoDashboardScreen({
    super.key,
    required this.aluno,
    required this.config,
    required this.authPayload,
  });

  @override
  State<AreaAlunoDashboardScreen> createState() =>
      _AreaAlunoDashboardScreenState();
}

class _AreaAlunoDashboardScreenState extends State<AreaAlunoDashboardScreen> {
  String? _svgContent;
  String? _cordaSvg;

  final RastreioSiteService _rastreioService = RastreioSiteService();
  final AreaAlunoSessionService _sessionService = AreaAlunoSessionService();

  String get _nome => _safeText(widget.aluno['nome'], 'Aluno');
  String get _apelido => _safeText(widget.aluno['apelido'], '');
  String get _foto => _safeText(widget.aluno['foto_perfil_aluno'], '');
  String get _status => _safeText(widget.aluno['status_atividade'], '');

  Map<String, dynamic> get _turmaInfo {
    final data = widget.aluno['turma_info'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  String get _graduacao {
    return _safeText(
      widget.aluno['graduacao_nome'] ??
          widget.aluno['graduacao_atual'] ??
          widget.aluno['graduacao'],
      'Não informada',
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCordaSvg();

    _rastreioService.iniciarTela(
      'area_aluno_dashboard',
      origem: 'area_aluno_login',
      metadata: {
        'aluno_nome': _nome,
        'aluno_apelido': _apelido,
        'status': _status,
        'graduacao': _graduacao,
        'turma': widget.aluno['turma']?.toString() ?? '',
      },
    );
    _rastreioService.marcarTempo('area_aluno_dashboard_tempo');
  }

  @override
  void dispose() {
    _rastreioService.registrarTempoMarcador(
      chave: 'area_aluno_dashboard_tempo',
      tipo: 'tempo_tela',
      nome: 'area_aluno_dashboard',
      origem: 'dispose',
      limparMarcador: true,
    );
    _rastreioService.finalizarTela(destino: 'saida_area_aluno_dashboard');
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Future<void> _loadCordaSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

      if (!mounted) return;

      setState(() {
        _svgContent = content;
        _cordaSvg = _montarCordaSvg(widget.aluno);
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar corda.svg no dashboard do aluno: $e');
    }
  }

  String? _montarCordaSvg(Map<String, dynamic> aluno) {
    if (_svgContent == null) return null;

    final cor1 = _pegarCor(aluno, ['graduacao_cor1', 'hex_cor1']);
    final cor2 = _pegarCor(aluno, ['graduacao_cor2', 'hex_cor2']);
    final ponta1 = _pegarCor(aluno, ['graduacao_ponta1', 'hex_ponta1']);
    final ponta2 = _pegarCor(aluno, ['graduacao_ponta2', 'hex_ponta2']);

    if (cor1 == null && cor2 == null && ponta1 == null && ponta2 == null) {
      return null;
    }

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      void changeColor(String id, String? hexColor) {
        if (hexColor == null || hexColor.trim().isEmpty) return;

        final hex = _normalizarHex(hexColor);
        if (hex == null) return;

        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );

        if (element.name.local.isEmpty) return;

        final style = element.getAttribute('style') ?? '';
        final newStyle = style.contains('fill:')
            ? style.replaceAll(
          RegExp(r'fill:#[0-9a-fA-F]{6}'),
          'fill:$hex',
        )
            : 'fill:$hex;$style';

        element.setAttribute('style', newStyle);
      }

      changeColor('cor1', cor1);
      changeColor('cor2', cor2);
      changeColor('corponta1', ponta1);
      changeColor('corponta2', ponta2);

      return document.toXmlString();
    } catch (e) {
      debugPrint('⚠️ Erro ao montar SVG da corda no dashboard: $e');
      return null;
    }
  }

  String? _pegarCor(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') return value;
    }

    return null;
  }

  String? _normalizarHex(String value) {
    var hex = value.trim();

    if (hex.isEmpty || hex == 'null') return null;

    hex = hex.replaceAll('0x', '').replaceAll('0X', '');
    if (!hex.startsWith('#')) hex = '#$hex';

    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return null;
    }

    return hex.toUpperCase();
  }

  Color _turmaColor() {
    final cor = _normalizarHex(_turmaInfo['cor_turma']?.toString() ?? '');

    if (cor == null) return context.uai.info;

    try {
      return Color(int.parse('FF${cor.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return context.uai.info;
    }
  }

  String _safeText(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  Future<void> _sairAreaAluno() async {
    await _sessionService.limparSessao();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingPage()),
          (route) => false,
    );
  }

  void _abrirTelaMenuAluno(Widget tela) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
  }

  Future<void> _abrirInfoAluno() async {
    _rastreioService.registrarClique(
      nome: 'abrir_informacoes_aluno',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    _showAlunoInfoSheet();
  }

  Future<void> _abrirSolicitarAlteracoes() async {
    _rastreioService.registrarClique(
      nome: 'abrir_solicitar_alteracoes',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoSolicitarAlteracaoScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirFrequencia() async {
    _rastreioService.registrarClique(
      nome: 'abrir_frequencia',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoFrequenciaScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirCertificados() async {
    _rastreioService.registrarClique(
      nome: 'abrir_certificados',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoCertificadosScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirSelecionarTemaPublico() async {
    final t = context.uai;
    final controller = AppThemeController.instance;

    final presets = UaiThemePreset.values
        .where((preset) => preset != UaiThemePreset.usuarioPersonalizado)
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.86,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 4),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: t.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              gradient: t.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.palette_rounded,
                              color: _readableOn(t.primary),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Escolher tema',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Temas prontos para a Área do Aluno',
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                        itemCount: presets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final preset = presets[index];
                          final selected =
                              controller.currentPreset == preset &&
                                  controller.activeSavedThemeId == null;

                          return _buildThemePresetTile(
                            preset: preset,
                            selected: selected,
                            onTap: () async {
                              await controller.apply(
                                preset: preset,
                                mode: preset.isDark
                                    ? ThemeMode.dark
                                    : ThemeMode.light,
                              );

                              if (mounted) Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemePresetTile({
    required UaiThemePreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(preset.previewColor, t.card);

    return Material(
      color: selected
          ? Color.alphaBlend(accent.withOpacity(0.11), t.cardAlt)
          : t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(
              color: selected ? accent.withOpacity(0.35) : t.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  preset.icon,
                  color: _readableOn(accent),
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? accent : t.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerMenu() {
    final t = context.uai;

    final itens = [
      _AreaAlunoMenuItem('Início', Icons.home_rounded, () {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LandingPage()),
              (route) => false,
        );
      }),
      _AreaAlunoMenuItem('Regimento Interno', Icons.description_rounded, () {
        _abrirTelaMenuAluno(const RegimentoScreen());
      }),
      _AreaAlunoMenuItem('Biografia', Icons.auto_stories_rounded, () {
        _abrirTelaMenuAluno(const BiografiaScreen());
      }),
      _AreaAlunoMenuItem('Graduações', Icons.emoji_events_rounded, () {
        _abrirTelaMenuAluno(const GraduacoesScreen());
      }),
      _AreaAlunoMenuItem('Área do Aluno', Icons.school_rounded, () {
        Navigator.pop(context);
      }, selecionado: true),
      _AreaAlunoMenuItem('Portfólio', Icons.photo_library_rounded, () {
        _abrirTelaMenuAluno(const PortfolioWebScreen());
      }),
    ];

    final onPrimary = _readableOn(t.primary);

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
            decoration: BoxDecoration(gradient: t.primaryGradient),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: onPrimary.withOpacity(0.15),
                  backgroundImage: _foto.isNotEmpty ? NetworkImage(_foto) : null,
                  child: _foto.isEmpty
                      ? Icon(Icons.person_rounded, color: onPrimary)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Área do Aluno',
                        style: TextStyle(
                          color: onPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onPrimary.withOpacity(0.78),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              itemCount: itens.length,
              separatorBuilder: (_, __) => const SizedBox(height: 3),
              itemBuilder: (context, index) {
                final item = itens[index];
                final color = item.selecionado ? t.primary : t.textPrimary;
                final visible = _ensureVisible(color, t.surface);

                return Material(
                  color: item.selecionado
                      ? Color.alphaBlend(visible.withOpacity(0.08), t.surface)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: item.selecionado
                                  ? visible
                                  : Color.alphaBlend(
                                visible.withOpacity(0.08),
                                t.card,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              item.icon,
                              color: item.selecionado
                                  ? _readableOn(visible)
                                  : visible,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: item.selecionado
                                    ? visible
                                    : t.textPrimary,
                                fontWeight: item.selecionado
                                    ? FontWeight.w900
                                    : FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          if (item.selecionado)
                            Icon(
                              Icons.check_circle_rounded,
                              color: visible,
                              size: 18,
                            )
                          else
                            Icon(
                              Icons.chevron_right_rounded,
                              color: t.textMuted,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: t.cardAlt,
              border: Border(top: BorderSide(color: t.border)),
            ),
            child: OutlinedButton.icon(
              onPressed: _sairAreaAluno,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('SAIR DA ÁREA DO ALUNO'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ensureVisible(t.error, t.cardAlt),
                side: BorderSide(color: t.error.withOpacity(0.25)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = _readableOn(appBarBg);

    return Scaffold(
      backgroundColor: t.background,
      drawer: Drawer(
        backgroundColor: t.surface,
        width: MediaQuery.of(context).size.width.clamp(280.0, 330.0),
        child: _buildDrawerMenu(),
      ),
      appBar: AppBar(
        title: const Text(
          'Minha Área',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Abrir menu',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Escolher tema',
              child: Material(
                color: appBarFg.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _abrirSelecionarTemaPublico,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: appBarFg.withOpacity(0.14)),
                    ),
                    child: Icon(
                      Icons.palette_rounded,
                      color: appBarFg,
                      size: 21,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final isMobile = maxWidth < 650;
          final contentWidth = maxWidth > 980 ? 980.0 : maxWidth;

          return RefreshIndicator(
            color: t.primary,
            backgroundColor: t.surface,
            onRefresh: () async => _loadCordaSvg(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 24,
                    14,
                    isMobile ? 14 : 24,
                    30,
                  ),
                  children: [
                    _buildHeader(isMobile),
                    const SizedBox(height: 14),
                    _buildResumoCards(isMobile),
                    const SizedBox(height: 16),
                    _buildSectionTitle(
                      icon: Icons.dashboard_customize_rounded,
                      title: 'Painel do aluno',
                      subtitle: 'Escolha o que deseja consultar',
                    ),
                    const SizedBox(height: 10),
                    _buildAcoesResponsive(maxWidth),
                    const SizedBox(height: 16),
                    _buildAvisoSomenteLeitura(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: EdgeInsets.all(isMobile ? 15 : 18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: t.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildAvatar(isMobile),
          SizedBox(width: isMobile ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.config['mensagem_topo']?.toString() ??
                      'Bem-vindo(a) à Área do Aluno',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.82),
                    fontSize: isMobile ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _nome,
                  maxLines: isMobile ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                if (_apelido.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _apelido,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onPrimary.withOpacity(0.78),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildStatusChip(_status),
                    if (widget.aluno['academia']?.toString().isNotEmpty == true)
                      _buildSmallWhiteChip(
                        widget.aluno['academia'].toString(),
                        Icons.home_work_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);
    final size = isMobile ? 74.0 : 86.0;

    if (_foto.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: onPrimary.withOpacity(0.16),
        child: Icon(
          Icons.person_rounded,
          color: onPrimary,
          size: size * 0.55,
        ),
      );
    }

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: onPrimary.withOpacity(0.20),
      child: ClipOval(
        child: Image.network(
          _foto,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Icon(
              Icons.person_rounded,
              color: onPrimary,
              size: size * 0.55,
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final ativo = status == 'ATIVO(A)' || status == 'ATIVO';
    final onPrimary = _readableOn(context.uai.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ativo
            ? Colors.green.withOpacity(0.20)
            : Colors.orange.withOpacity(0.20),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onPrimary.withOpacity(0.20)),
      ),
      child: Text(
        ativo
            ? 'ALUNO ATIVO'
            : (status.isEmpty ? 'STATUS NÃO INFORMADO' : status),
        style: TextStyle(
          color: onPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSmallWhiteChip(String text, IconData icon) {
    final onPrimary = _readableOn(context.uai.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onPrimary.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: onPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCards(bool isMobile) {
    final turmaCard = _buildTurmaResumoCard();
    final graduacaoCard = _buildGraduacaoResumoCard();

    if (isMobile) {
      return Column(
        children: [
          turmaCard,
          const SizedBox(height: 10),
          graduacaoCard,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: turmaCard),
        const SizedBox(width: 10),
        Expanded(child: graduacaoCard),
      ],
    );
  }

  Widget _buildTurmaResumoCard() {
    final t = context.uai;
    final color = _ensureVisible(_turmaColor(), t.card);
    final turmaNome = _safeText(widget.aluno['turma'], 'Não informada');
    final horarios = _turmaHorarios();

    String subtitle = 'Toque para ver informações da turma';

    if (horarios.isNotEmpty) {
      final primeiro = horarios.first;
      subtitle =
      '${primeiro['dia_nome'] ?? primeiro['dia'] ?? ''} • ${primeiro['horario_inicio'] ?? ''} às ${primeiro['horario_fim'] ?? ''}';
    }

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _abrirInfoTurma,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.13)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              _buildTurmaIcon(color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Turma',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      turmaNome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurmaIcon(Color color) {
    final t = context.uai;
    final logo = _turmaInfo['logo_url']?.toString() ?? '';

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
      ),
      child: logo.isNotEmpty
          ? ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          logo,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Icon(Icons.school_rounded, color: color, size: 30);
          },
        ),
      )
          : Icon(Icons.school_rounded, color: color, size: 30),
    );
  }

  Widget _buildGraduacaoResumoCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.13)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: accent,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Graduação',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _graduacao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (_cordaSvg != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              height: 52,
              child: SvgPicture.string(
                _cordaSvg!,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.background);

    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: Color.alphaBlend(primary.withOpacity(0.09), t.cardAlt),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: primary, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: t.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAcoesResponsive(double width) {
    final t = context.uai;

    final cards = [
      _DashboardCardData(
        icon: Icons.person_search_rounded,
        title: 'Informações do aluno',
        subtitle: 'Ver seus dados cadastrais',
        color: t.info,
        onTap: _abrirInfoAluno,
      ),
      _DashboardCardData(
        icon: Icons.edit_note_rounded,
        title: 'Solicitar alterações',
        subtitle: 'Pedir correção dos dados',
        color: t.associacao,
        onTap: _abrirSolicitarAlteracoes,
      ),
      _DashboardCardData(
        icon: Icons.fact_check_rounded,
        title: 'Frequência',
        subtitle: 'Acompanhar presenças',
        color: t.success,
        onTap: _abrirFrequencia,
      ),
      _DashboardCardData(
        icon: Icons.card_membership_rounded,
        title: 'Certificados',
        subtitle: 'Eventos e certificados',
        color: t.warning,
        onTap: _abrirCertificados,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        int columns;

        if (maxWidth < 390) {
          columns = 1;
        } else if (maxWidth < 760) {
          columns = 2;
        } else {
          columns = 4;
        }

        const spacing = 10.0;
        final cardWidth = (maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: cardWidth,
              child: _buildDashboardActionCard(card),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDashboardActionCard(_DashboardCardData card) {
    final t = context.uai;
    final accent = _ensureVisible(card.color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _rastreioService.registrarClique(
            nome: 'card_${card.title.toLowerCase().replaceAll(' ', '_')}',
            origem: 'area_aluno_dashboard',
            metadata: {
              'titulo': card.title,
              'subtitulo': card.subtitle,
            },
          );
          card.onTap();
        },
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 132),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withOpacity(0.13)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(card.icon, color: accent, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.5,
                        height: 1.20,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: accent,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvisoSomenteLeitura() {
    final t = context.uai;
    final accent = _ensureVisible(t.info, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esta área é somente leitura. Para alterar informações, use o card '
                  '“Solicitar alterações”. A coordenação analisará antes de atualizar o cadastro oficial.',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirInfoTurma() {
    _rastreioService.registrarClique(
      nome: 'abrir_informacoes_turma',
      origem: 'area_aluno_dashboard',
      metadata: {
        'turma': widget.aluno['turma']?.toString() ?? '',
      },
    );

    final turma = _turmaInfo;

    if (turma.isEmpty) {
      _mostrarAviso(
        titulo: 'Informações da turma',
        mensagem: 'As informações completas da turma ainda não foram encontradas.',
        icon: Icons.school_rounded,
        color: context.uai.info,
      );
      return;
    }

    final color = _ensureVisible(_turmaColor(), context.uai.surface);
    final horarios = _turmaHorarios();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 760
            ? 720
            : MediaQuery.of(context).size.width,
      ),
      builder: (_) {
        final t = context.uai;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.86,
              minChildSize: 0.45,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: t.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTurmaModalHeader(turma, color),
                    const SizedBox(height: 14),
                    _buildTurmaSection(
                      title: 'Horários de treino',
                      icon: Icons.calendar_month_rounded,
                      color: t.success,
                      children: horarios.isEmpty
                          ? [
                        _buildEmptyText(
                          'Nenhum horário cadastrado para esta turma.',
                        ),
                      ]
                          : horarios.map(_buildHorarioTile).toList(),
                    ),
                    if (_safeText(turma['observacoes'], '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildTurmaSection(
                        title: 'Observações',
                        icon: Icons.notes_rounded,
                        color: t.associacao,
                        children: [
                          _buildLongText(turma['observacoes'].toString()),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTurmaModalHeader(Map<String, dynamic> turma, Color color) {
    final t = context.uai;
    final logo = turma['logo_url']?.toString() ?? '';
    final onColor = _readableOn(color);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: onColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: logo.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                logo,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    Icons.school_rounded,
                    color: onColor,
                    size: 36,
                  );
                },
              ),
            )
                : Icon(Icons.school_rounded, color: onColor, size: 36),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _safeText(turma['nome'], 'Turma'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildWhiteMiniChip(_safeText(turma['nivel'], '')),
                    _buildWhiteMiniChip(_safeText(turma['faixa_etaria'], '')),
                    _buildWhiteMiniChip(_safeText(turma['status'], '')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteMiniChip(String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    final onPrimary = _readableOn(context.uai.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: onPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTurmaSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildHorarioTile(dynamic horario) {
    final t = context.uai;

    if (horario is! Map) {
      return _buildLongText(horario.toString());
    }

    final h = Map<String, dynamic>.from(horario);
    final dia = h['dia_nome'] ?? h['dia'] ?? 'Dia';
    final inicio = h['horario_inicio'] ?? '';
    final fim = h['horario_fim'] ?? '';
    final tipo = h['tipo_aula'] ?? h['tipo'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: t.primary, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              [
                dia,
                if (inicio.toString().isNotEmpty || fim.toString().isNotEmpty)
                  '$inicio às $fim',
                if (tipo.toString().isNotEmpty) tipo,
              ].join(' • '),
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLongText(String text) {
    final t = context.uai;

    return Text(
      text,
      style: TextStyle(
        color: t.textPrimary,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildEmptyText(String text) {
    final t = context.uai;

    return Text(
      text,
      style: TextStyle(
        color: t.textSecondary,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  List<Map<String, dynamic>> _turmaHorarios() {
    final raw = _turmaInfo['horarios'];

    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return [];
  }

  void _showAlunoInfoSheet() {
    final t = context.uai;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 760
            ? 720
            : MediaQuery.of(context).size.width,
      ),
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSheetHeader(
                    icon: Icons.person_search_rounded,
                    title: 'Informações do aluno',
                    color: t.info,
                  ),
                  const SizedBox(height: 14),
                  _infoRow('Nome', _nome),
                  _infoRow('Apelido', _apelido),
                  _infoRow('Status', _status),
                  _infoRow('Graduação', _graduacao),
                  _infoRow('Turma', _safeText(widget.aluno['turma'], 'Não informada')),
                  _infoRow('Academia', _safeText(widget.aluno['academia'], 'Não informada')),
                  _infoRow('Cidade', _safeText(widget.aluno['cidade'], 'Não informada')),
                  _infoRow('Contato', _safeText(widget.aluno['contato_aluno'], 'Não informado')),
                  _infoRow('Responsável', _safeText(widget.aluno['nome_responsavel'], 'Não informado')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withOpacity(0.10), t.card),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close_rounded, color: t.textSecondary),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAviso({
    required String titulo,
    required String mensagem,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(color: t.textPrimary),
                ),
              ),
            ],
          ),
          content: Text(
            mensagem,
            style: TextStyle(color: t.textSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'ENTENDI',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _AreaAlunoMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selecionado;

  const _AreaAlunoMenuItem(
      this.label,
      this.icon,
      this.onTap, {
        this.selecionado = false,
      });
}
