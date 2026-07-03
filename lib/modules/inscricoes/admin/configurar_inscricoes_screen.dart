import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

import 'gerenciar_inscricoes_screen.dart';

class ConfigurarInscricoesScreen extends StatefulWidget {
  const ConfigurarInscricoesScreen({super.key});

  @override
  State<ConfigurarInscricoesScreen> createState() =>
      _ConfigurarInscricoesScreenState();
}

class _ConfigurarInscricoesScreenState
    extends State<ConfigurarInscricoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _inscricoesAbertas = false;
  int _vagasDisponiveis = 0;
  int _totalInscricoes = 0;

  int _idadeMinima = 5;
  int _idadeMaxima = 16;

  bool _recolherAssinatura = true;

  final TextEditingController _idadeMinimaController = TextEditingController();
  final TextEditingController _idadeMaximaController = TextEditingController();
  final TextEditingController _vagasController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracao();
  }

  @override
  void dispose() {
    _idadeMinimaController.dispose();
    _idadeMaximaController.dispose();
    _vagasController.dispose();
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
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0).toDouble())
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);

  bool _temaPrimarioMuitoClaroEmFundoEscuro() {
    final t = context.uai;
    final primary = t.primary;
    final hsl = HSLColor.fromColor(primary);

    return primary.computeLuminance() > 0.50 &&
        t.background.computeLuminance() < 0.36 &&
        hsl.saturation > 0.55;
  }

  Color _safeHeroBase() {
    final t = context.uai;
    if (_temaPrimarioMuitoClaroEmFundoEscuro()) {
      return Color.alphaBlend(t.primary.withOpacity(0.58), t.surface);
    }
    return t.primary;
  }

  LinearGradient _safeHeroGradient() {
    final base = _safeHeroBase();
    final hsl = HSLColor.fromColor(base);
    final bgIsDark = base.computeLuminance() < 0.45;
    final endLightness = bgIsDark
        ? (hsl.lightness + 0.08).clamp(0.0, 1.0).toDouble()
        : (hsl.lightness - 0.08).clamp(0.0, 1.0).toDouble();
    final end = hsl
        .withLightness(endLightness)
        .withSaturation((hsl.saturation + 0.04).clamp(0.0, 1.0).toDouble())
        .toColor();

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [base, end],
    );
  }

  Color _onHero() {
    if (_temaPrimarioMuitoClaroEmFundoEscuro()) {
      return const Color(0xFFFFFFFF);
    }
    return _readableOn(_safeHeroBase());
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  bool get _isWideDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900;
  }

  bool get _isDesktopDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 1180;
  }

  double get _dashboardMaxWidth {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) return 1240;
    if (width >= 1180) return 1120;
    if (width >= 900) return 1040;
    return width;
  }

  EdgeInsets get _dashboardPagePadding {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1180) return const EdgeInsets.fromLTRB(22, 18, 22, 28);
    if (width >= 900) return const EdgeInsets.fromLTRB(18, 16, 18, 24);
    if (width <= 390) return const EdgeInsets.fromLTRB(14, 12, 14, 18);
    return const EdgeInsets.fromLTRB(16, 14, 16, 22);
  }

  Widget _dashboardWidthLimiter(Widget child) {
    if (!_isWideDashboard) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _dashboardMaxWidth),
        child: child,
      ),
    );
  }

  Widget _responsiveWrap({
    required List<Widget> children,
    double minItemWidth = 360,
    int maxColumns = 4,
    double spacing = 12,
    double runSpacing = 12,
    bool centerLastRow = true,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(children.length, (index) {
              final isLast = index == children.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : runSpacing),
                child: SizedBox(width: double.infinity, child: children[index]),
              );
            }),
          );
        }

        final columns = (width / minItemWidth)
            .floor()
            .clamp(1, maxColumns)
            .toInt();
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          alignment: centerLastRow ? WrapAlignment.center : WrapAlignment.start,
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }

  Future<void> _carregarConfiguracao() async {
    try {
      final doc = await _firestore
          .collection('configuracoes')
          .doc('inscricoes')
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        _inscricoesAbertas = data['inscricoes_abertas'] ?? false;
        _vagasDisponiveis = data['vagas_disponiveis'] ?? 0;
        _totalInscricoes = data['total_inscricoes'] ?? 0;
        _idadeMinima = data['idade_minima'] ?? 5;
        _idadeMaxima = data['idade_maxima'] ?? 16;
        _recolherAssinatura = data['recolher_assinatura'] ?? true;
      }

      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      _totalInscricoes = inscricoesSnapshot.docs.length;
      _idadeMinimaController.text = _idadeMinima.toString();
      _idadeMaximaController.text = _idadeMaxima.toString();
      _vagasController.text = _vagasDisponiveis.toString();

      if (mounted) {
        setState(() => _carregando = false);
      }
    } catch (e) {
      if (mounted) {
        _mostrarErro('Erro ao carregar: $e');
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _salvarConfiguracao() async {
    if (_salvando) return;
    setState(() => _salvando = true);

    try {
      final idadeMin = int.tryParse(_idadeMinimaController.text) ?? 0;
      final idadeMax = int.tryParse(_idadeMaximaController.text) ?? 0;
      final vagas = int.tryParse(_vagasController.text) ?? 0;

      if (idadeMin < 1) {
        _mostrarErro('Idade mínima deve ser maior que 0');
        setState(() => _salvando = false);
        return;
      }

      if (idadeMax < idadeMin) {
        _mostrarErro('Idade máxima não pode ser menor que a idade mínima');
        setState(() => _salvando = false);
        return;
      }

      if (idadeMax > 120) {
        _mostrarErro('Idade máxima inválida');
        setState(() => _salvando = false);
        return;
      }

      if (vagas < 0) {
        _mostrarErro('O número de vagas não pode ser negativo');
        setState(() => _salvando = false);
        return;
      }

      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'inscricoes_abertas': _inscricoesAbertas,
        'vagas_disponiveis': vagas,
        'total_inscricoes': _totalInscricoes,
        'idade_minima': idadeMin,
        'idade_maxima': idadeMax,
        'recolher_assinatura': _recolherAssinatura,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      setState(() {
        _idadeMinima = idadeMin;
        _idadeMaxima = idadeMax;
        _vagasDisponiveis = vagas;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Configurações salvas!'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int get _vagasRestantes {
    final restantes = _vagasDisponiveis - _totalInscricoes;
    return restantes < 0 ? 0 : restantes;
  }

  double get _percentualVagas {
    if (_vagasDisponiveis <= 0) return 0;
    return (_totalInscricoes / _vagasDisponiveis).clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregando) {
      return Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          title: const Text(
            'Configurar Inscrições',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: _buildLoadingState(),
      );
    }

    final showBottomSaveBar = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Configurar Inscrições',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: _appBarFg(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.cardAlt, t.background],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useTwoColumns = constraints.maxWidth >= 940;
            final pad = _dashboardPagePadding;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                pad.left,
                pad.top,
                pad.right,
                showBottomSaveBar ? 104 : pad.bottom,
              ),
              children: [
                Center(
                  child: _dashboardWidthLimiter(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(),
                        const SizedBox(height: 12),
                        _buildStatusCards(),
                        const SizedBox(height: 14),
                        if (useTwoColumns)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 11,
                                child: _buildMainSettingsColumn(),
                              ),
                              const SizedBox(width: 14),
                              Expanded(flex: 9, child: _buildResumoColumn()),
                            ],
                          )
                        else ...[
                          _buildMainSettingsColumn(),
                          const SizedBox(height: 14),
                          _buildResumoColumn(),
                        ],
                        if (!showBottomSaveBar) ...[
                          const SizedBox(height: 14),
                          _buildInlineSaveCard(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: showBottomSaveBar ? _buildBottomSaveBar() : null,
    );
  }

  Widget _buildInlineSaveCard() {
    final t = context.uai;
    final bg = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _salvando
                  ? 'Salvando alterações...'
                  : 'Revise os campos e salve as configurações.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: ElevatedButton.icon(
              onPressed: _salvando ? null : _salvarConfiguracao,
              icon: _salvando
                  ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: _readableOn(bg),
                  strokeWidth: 2,
                ),
              )
                  : const Icon(Icons.save_rounded),
              label: Text(_salvando ? 'SALVANDO...' : 'SALVAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: _readableOn(bg),
                padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildBottomSaveBar() {
    final t = context.uai;
    final bg = _ensureVisible(t.primary, t.surface);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(t.surface.withOpacity(0.94), t.background),
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: t.softShadow,
        ),
        child: _dashboardWidthLimiter(
          ElevatedButton.icon(
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: _readableOn(bg),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR CONFIGURAÇÕES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: _readableOn(bg),
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final t = context.uai;
    final onHero = _onHero();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_isDesktopDashboard ? 20 : 16),
      decoration: BoxDecoration(
        gradient: _safeHeroGradient(),
        borderRadius: BorderRadius.circular(t.cardRadius + 6),
        border: Border.all(color: onHero.withOpacity(0.13)),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: narrow ? 58 : 64,
            height: narrow ? 58 : 64,
            decoration: BoxDecoration(
              color: onHero.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onHero.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.app_registration_rounded,
              color: onHero,
              size: narrow ? 31 : 35,
            ),
          );

          final statusChip = _buildHeroStatusChip(narrow: narrow);

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Inscrições da Aula Experimental',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onHero,
                  fontSize: narrow ? 21 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Controle vagas, idade permitida, assinatura digital e status público do formulário.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onHero.withOpacity(0.82),
                  fontSize: narrow ? 12.2 : 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (narrow) ...[
                const SizedBox(height: 12),
                statusChip,
              ],
            ],
          );

          if (narrow) {
            return Column(
              children: [icon, const SizedBox(height: 13), text],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
              const SizedBox(width: 12),
              statusChip,
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroStatusChip({required bool narrow}) {
    final t = context.uai;
    final onHero = _onHero();
    final statusColor = _inscricoesAbertas ? t.success : t.error;
    final visibleStatus = _ensureVisible(statusColor, _safeHeroBase());

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 12 : 14,
        vertical: narrow ? 8 : 9,
      ),
      decoration: BoxDecoration(
        color: onHero.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onHero.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _inscricoesAbertas
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: visibleStatus,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(
            _inscricoesAbertas ? 'Formulário aberto' : 'Formulário fechado',
            style: TextStyle(
              color: onHero,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards() {
    final t = context.uai;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 760 ? 4 : 2;
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing * (cols - 1)) / cols;

        final cards = [
          _miniStat(
            title: 'Status',
            value: _inscricoesAbertas ? 'Aberta' : 'Fechada',
            icon: _inscricoesAbertas
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: _inscricoesAbertas ? t.success : t.error,
          ),
          _miniStat(
            title: 'Vagas',
            value: '$_vagasDisponiveis',
            icon: Icons.event_seat_rounded,
            color: t.info,
          ),
          _miniStat(
            title: 'Pendentes',
            value: '$_totalInscricoes',
            icon: Icons.pending_actions_rounded,
            color: t.warning,
          ),
          _miniStat(
            title: 'Restam',
            value: '$_vagasRestantes',
            icon: Icons.how_to_reg_rounded,
            color: t.associacao,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(),
        );
      },
    );
  }

  Widget _miniStat({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    final compact = MediaQuery.sizeOf(context).width < 430;

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 82 : 96),
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: _cardDecoration(color: accent),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.12), t.cardAlt),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: accent.withOpacity(0.14)),
            ),
            child: Icon(icon, color: accent, size: compact ? 19 : 21),
          ),
          SizedBox(height: compact ? 6 : 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainSettingsColumn() {
    final t = context.uai;

    return Column(
      children: [
        _buildSwitchCard(
          icon: Icons.public_rounded,
          title: 'Status das inscrições',
          subtitle: _inscricoesAbertas
              ? 'O formulário público está aceitando inscrições.'
              : 'O formulário público está fechado.',
          color: _inscricoesAbertas ? t.success : t.error,
          value: _inscricoesAbertas,
          onChanged: (value) => setState(() => _inscricoesAbertas = value),
        ),
        const SizedBox(height: 12),
        _buildSwitchCard(
          icon: Icons.draw_rounded,
          title: 'Assinatura digital',
          subtitle: _recolherAssinatura
              ? 'O responsável precisará assinar o termo digitalmente.'
              : 'A inscrição será concluída sem assinatura digital.',
          color: t.associacao,
          value: _recolherAssinatura,
          onChanged: (value) => setState(() => _recolherAssinatura = value),
        ),
        const SizedBox(height: 12),
        _buildAgeCard(),
        const SizedBox(height: 12),
        _buildVagasCard(),
      ],
    );
  }

  Widget _buildResumoColumn() {
    final t = context.uai;
    final info = _ensureVisible(t.info, t.card);

    return Column(
      children: [
        _buildResumoCard(),
        const SizedBox(height: 12),
        _buildInfoCard(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GerenciarInscricoesScreen(),
                ),
              );
            },
            icon: const Icon(Icons.list_alt_rounded),
            label: const Text('VER INSCRIÇÕES PENDENTES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: info,
              foregroundColor: _readableOn(info),
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final veryNarrow = constraints.maxWidth < 360;

          final iconBox = Container(
            width: veryNarrow ? 44 : 48,
            height: veryNarrow ? 44 : 48,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.12), t.cardAlt),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: accent.withOpacity(0.16)),
            ),
            child: Icon(icon, color: accent, size: veryNarrow ? 23 : 26),
          );

          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: veryNarrow ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 12),
              Expanded(child: text),
              const SizedBox(width: 8),
              Switch(
                value: value,
                activeColor: accent,
                onChanged: onChanged,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAgeCard() {
    final t = context.uai;
    final valido = _idadeMinima <= _idadeMaxima;
    final color = valido ? t.warning : t.error;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.cake_rounded,
            title: 'Faixa etária aceita',
            color: accent,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 460;

              final fields = [
                _numberField(
                  controller: _idadeMinimaController,
                  label: 'Idade mínima',
                  icon: Icons.child_care_rounded,
                  onChanged: (value) {
                    setState(() => _idadeMinima = int.tryParse(value) ?? 0);
                  },
                ),
                _numberField(
                  controller: _idadeMaximaController,
                  label: 'Idade máxima',
                  icon: Icons.elderly_rounded,
                  onChanged: (value) {
                    setState(() => _idadeMaxima = int.tryParse(value) ?? 0);
                  },
                ),
              ];

              if (narrow) {
                return Column(
                  children: [fields[0], const SizedBox(height: 10), fields[1]],
                );
              }

              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _noticeBox(
            icon: valido ? Icons.info_outline_rounded : Icons.warning_rounded,
            color: accent,
            text: valido
                ? 'Serão aceitos alunos com idade entre $_idadeMinima e $_idadeMaxima anos.'
                : 'Idade mínima não pode ser maior que a idade máxima.',
          ),
        ],
      ),
    );
  }

  Widget _buildVagasCard() {
    final t = context.uai;
    final estourou =
        _vagasDisponiveis > 0 && _totalInscricoes > _vagasDisponiveis;
    final color = estourou ? t.error : t.info;
    final accent = _ensureVisible(color, t.card);
    final progressColor = estourou ? t.error : t.success;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.event_seat_rounded,
            title: 'Controle de vagas',
            color: accent,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              final counter = Container(
                width: narrow ? double.infinity : 104,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withOpacity(0.14)),
                ),
                child: Column(
                  children: [
                    Text(
                      '$_totalInscricoes',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    Text(
                      'Pendentes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: t.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );

              final input = _numberField(
                controller: _vagasController,
                label: 'Vagas disponíveis',
                icon: Icons.event_available_rounded,
                onChanged: (value) {
                  setState(() {
                    _vagasDisponiveis = int.tryParse(value) ?? 0;
                  });
                },
              );

              if (narrow) {
                return Column(
                  children: [input, const SizedBox(height: 10), counter],
                );
              }

              return Row(
                children: [
                  Expanded(child: input),
                  const SizedBox(width: 10),
                  counter,
                ],
              );
            },
          ),
          if (_vagasDisponiveis > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: _percentualVagas,
                backgroundColor: t.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _ensureVisible(progressColor, t.border),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_percentualVagas * 100).toStringAsFixed(1)}% das vagas preenchidas',
              style: TextStyle(
                color: _ensureVisible(progressColor, t.card),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (estourou) ...[
            const SizedBox(height: 10),
            _noticeBox(
              icon: Icons.warning_rounded,
              color: _ensureVisible(t.error, t.card),
              text:
              '${_totalInscricoes - _vagasDisponiveis} inscrições excedem as vagas configuradas.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumoCard() {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: success),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.summarize_rounded,
            title: 'Resumo das configurações',
            color: success,
          ),
          const SizedBox(height: 12),
          _buildResumoRow(
            label: 'Status',
            value: _inscricoesAbertas ? 'ABERTAS' : 'FECHADAS',
            color: _inscricoesAbertas ? t.success : t.error,
          ),
          _buildResumoRow(
            label: 'Assinatura',
            value: _recolherAssinatura ? 'SIM' : 'NÃO',
            color: t.associacao,
          ),
          _buildResumoRow(
            label: 'Vagas',
            value: '$_vagasDisponiveis vagas',
            color: t.info,
          ),
          _buildResumoRow(
            label: 'Inscrições',
            value: '$_totalInscricoes pendentes',
            color: t.warning,
          ),
          _buildResumoRow(
            label: 'Idade',
            value: '$_idadeMinima a $_idadeMaxima anos',
            color: t.associacao,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.12), t.cardAlt),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: accent.withOpacity(0.14)),
            ),
            child: Icon(Icons.info_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Para aprovar, recusar ou acompanhar candidatos, acesse a lista de inscrições pendentes.',
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

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withOpacity(0.12), t.cardAlt),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.14)),
          ),
          child: Icon(icon, color: accent, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      cursorColor: accent,
      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textSecondary),
        prefixIcon: Icon(icon, color: accent),
        filled: true,
        fillColor: t.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
    );
  }

  Widget _noticeBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoRow({
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.07), t.cardAlt),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;
    final pad = _dashboardPagePadding;

    return Container(
      color: t.background,
      padding: pad,
      child: Center(
        child: _dashboardWidthLimiter(
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(_isDesktopDashboard ? 30 : 24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    color: t.primary,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Carregando configurações de inscrições...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _onCardMuted(),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({required Color color}) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: accent.withOpacity(0.12)),
      boxShadow: t.softShadow,
    );
  }
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 11:28
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================
