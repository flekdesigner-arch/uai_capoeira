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

  Color _onPrimary() => _readableOn(context.uai.primary);

  Future<void> _carregarConfiguracao() async {
    try {
      final doc =
      await _firestore.collection('configuracoes').doc('inscricoes').get();

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
        body: Center(child: CircularProgressIndicator(color: t.primary)),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Configurar Inscrições'),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: _onPrimary(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    children: [
                      _buildHeroCard(),
                      const SizedBox(height: 14),
                      _buildStatusCards(),
                      const SizedBox(height: 14),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildMainSettingsColumn()),
                            const SizedBox(width: 14),
                            Expanded(child: _buildResumoColumn()),
                          ],
                        )
                      else ...[
                        _buildMainSettingsColumn(),
                        const SizedBox(height: 14),
                        _buildResumoColumn(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
            boxShadow: t.softShadow,
          ),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: _onPrimary(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR CONFIGURAÇÕES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _onPrimary(),
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
    final onPrimary = _onPrimary();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.app_registration_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Inscrições da Aula Experimental',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Controle vagas, idade permitida, assinatura digital e status público do formulário.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
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

  Widget _buildStatusCards() {
    final t = context.uai;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 680 ? 2 : 4;
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
          children:
          cards.map((card) => SizedBox(width: width, child: card)).toList(),
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

    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(color: accent),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 25),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
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
        const SizedBox(height: 14),
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
        const SizedBox(height: 14),
        _buildAgeCard(),
        const SizedBox(height: 14),
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
        const SizedBox(height: 14),
        _buildInfoCard(),
        const SizedBox(height: 14),
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
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: accent),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.12), t.cardAlt),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: accent.withOpacity(0.16)),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildAgeCard() {
    final t = context.uai;
    final valido = _idadeMinima <= _idadeMaxima;
    final color = valido ? t.warning : t.error;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(16),
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
                  children: [
                    fields[0],
                    const SizedBox(height: 10),
                    fields[1],
                  ],
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
      padding: const EdgeInsets.all(16),
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
                      style: TextStyle(fontSize: 10, color: t.textSecondary),
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
                  children: [
                    input,
                    const SizedBox(height: 10),
                    counter,
                  ],
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
                fontWeight: FontWeight.w800,
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
      padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: accent),
      child: Row(
        children: [
          Icon(Icons.info_rounded, color: accent, size: 28),
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

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textSecondary),
        prefixIcon: Icon(icon, color: t.primary),
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
          borderSide: BorderSide(color: t.primary, width: 1.4),
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
              fontWeight: FontWeight.w700,
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
