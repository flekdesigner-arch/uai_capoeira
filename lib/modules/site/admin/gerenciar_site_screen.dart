import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

import 'regimento_interno_screen.dart';
import 'biografia_screen.dart';
import 'graduacoes_site_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/admin/configurar_inscricoes_screen.dart';
import 'gerenciar_timeline_screen.dart';
import 'package:uai_capoeira/modules/campeonatos/admin/configurar_campeonato_screen.dart';
import 'configurar_menu_screen.dart';

import 'package:uai_capoeira/modules/site/screens/editar_textos_screen.dart';
import 'package:uai_capoeira/modules/rastreio/screens/dashboard_estatisticas_screen.dart';
import 'package:uai_capoeira/modules/site/services/site_config_service.dart';
import 'package:uai_capoeira/modules/sistema/admin/configurar_assistente_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/admin/area_aluno_admin_screen.dart';

class GerenciarSiteScreen extends StatefulWidget {
  const GerenciarSiteScreen({super.key});

  @override
  State<GerenciarSiteScreen> createState() => _GerenciarSiteScreenState();
}

class _GerenciarSiteScreenState extends State<GerenciarSiteScreen> {
  final SiteConfigService _configService = SiteConfigService();

  bool _carregando = true;
  String? _erro;

  Map<String, dynamic> _configuracoes = {};
  Map<String, dynamic> _configAreaAluno = {};

  final List<Map<String, dynamic>> _secoesBase = [
    {
      'id': 'regimento',
      'titulo': 'REGIMENTO INTERNO',
      'icone': Icons.description_rounded,
      'cor': Colors.blue,
      'colecao': 'site_regimento',
      'descricao': 'Editar regras e normas do grupo',
      'tela': 'regimento',
      'ordem_padrao': 1,
    },
    {
      'id': 'biografia',
      'titulo': 'BIOGRAFIA',
      'icone': Icons.auto_stories_rounded,
      'cor': Colors.green,
      'colecao': 'site_biografia',
      'descricao': 'Editar história do grupo',
      'tela': 'biografia',
      'ordem_padrao': 2,
    },
    {
      'id': 'graduacoes',
      'titulo': 'GRADUAÇÕES',
      'icone': Icons.workspace_premium_rounded,
      'cor': Colors.orange,
      'colecao': 'site_graduacoes',
      'descricao': 'Editar sistema de cordas',
      'tela': 'graduacoes',
      'ordem_padrao': 3,
    },
    {
      'id': 'inscricao',
      'titulo': 'INSCRIÇÃO',
      'icone': Icons.app_registration_rounded,
      'cor': Colors.red,
      'colecao': 'site_inscricao',
      'descricao': 'Configurar inscrições para aula experimental',
      'tela': 'inscricao',
      'ordem_padrao': 4,
    },
    {
      'id': 'area_aluno',
      'titulo': 'ÁREA DO ALUNO',
      'icone': Icons.school_rounded,
      'cor': Colors.indigo,
      'colecao': 'configuracoes_site/area_aluno',
      'descricao': 'Configurar acesso público dos alunos',
      'tela': 'area_aluno',
      'ordem_padrao': 5,
      'destaque': true,
    },
    {
      'id': 'campeonato',
      'titulo': 'CAMPEONATO',
      'icone': Icons.emoji_events_rounded,
      'cor': Colors.amber,
      'colecao': 'campeonato_inscricoes',
      'descricao': 'Configurar 1° Campeonato UAI Capoeira',
      'tela': 'campeonato',
      'ordem_padrao': 6,
    },
    {
      'id': 'portfolio',
      'titulo': 'LINHA DO TEMPO',
      'icone': Icons.timeline_rounded,
      'cor': Colors.purple,
      'colecao': 'timeline_publicacoes',
      'descricao': 'Gerenciar publicações do site',
      'tela': 'timeline',
      'ordem_padrao': 7,
    },
  ];

  late List<Map<String, dynamic>> _secoes;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

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

  Color _onPrimary() => _readableOn(context.uai.primary);

  Color _cardAccent(Color color) {
    return _ensureVisible(_iconColor(color), context.uai.card);
  }

  Color _softBg(Color color, Color base, [double opacity = 0.10]) {
    return Color.alphaBlend(color.withOpacity(opacity), base);
  }

  InputDecoration _uaiInputDecoration({
    required String label,
    required IconData icon,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: t.textSecondary),
      prefixIcon: Icon(icon, color: accent),
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
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }

  Future<void> _carregarConfiguracoes() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final configs = await _configService.carregarConfiguracoesSite();
      final areaAlunoConfig = await _configService.carregarConfiguracoesAreaAluno();

      if (!mounted) return;

      setState(() {
        _configuracoes = configs;
        _configAreaAluno = areaAlunoConfig;

        _secoes = _secoesBase.map((secao) {
          final Map<String, dynamic> secaoModificada = Map.from(secao);

          if (configs['titulos'] != null &&
              configs['titulos'][secao['id']] != null) {
            secaoModificada['titulo'] = configs['titulos'][secao['id']];
          }

          if (configs['descricoes'] != null &&
              configs['descricoes'][secao['id']] != null) {
            secaoModificada['descricao'] = configs['descricoes'][secao['id']];
          }

          if (configs['visibilidade'] != null &&
              configs['visibilidade'][secao['id']] == false) {
            secaoModificada['oculto'] = true;
          }

          if (secao['id'] == 'area_aluno') {
            final visivelArea = areaAlunoConfig['visivel_site'] == true;

            secaoModificada['oculto'] = !visivelArea;
            secaoModificada['descricao'] = visivelArea
                ? 'Área ativa no site. Configure segurança, dados e logs.'
                : 'Área criada, mas oculta no site. Toque para configurar.';
          }

          return secaoModificada;
        }).toList();

        if (configs['ordem'] != null && configs['ordem'].isNotEmpty) {
          _secoes.sort((a, b) {
            final indexA = configs['ordem'].indexOf(a['id']);
            final indexB = configs['ordem'].indexOf(b['id']);

            if (indexA == -1 && indexB == -1) {
              return (a['ordem_padrao'] ?? 999)
                  .compareTo(b['ordem_padrao'] ?? 999);
            }

            if (indexA == -1) return 1;
            if (indexB == -1) return -1;
            return indexA.compareTo(indexB);
          });
        } else {
          _secoes.sort(
                (a, b) => (a['ordem_padrao'] ?? 999)
                .compareTo(b['ordem_padrao'] ?? 999),
          );
        }

        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _erro = 'Erro ao carregar configurações: $e';
        _carregando = false;
        _secoes = List.from(_secoesBase);
      });
    }
  }

  int get _totalSecoes => _secoes.length;

  int get _secoesVisiveis {
    return _secoes.where((secao) => secao['oculto'] != true).length;
  }

  int get _secoesOcultas {
    return _secoes.where((secao) => secao['oculto'] == true).length;
  }

  bool get _areaAlunoVisivel {
    return _configAreaAluno['visivel_site'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Gerenciar Site',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DashboardEstatisticasScreen(),
                ),
              );
            },
            tooltip: 'Dashboard de Visitas',
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _mostrarDialogoConfiguracoes,
            tooltip: 'Configurações do Site',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _carregarConfiguracoes,
            tooltip: 'Recarregar',
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
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_carregando) {
      return Center(child: CircularProgressIndicator(color: context.uai.primary));
    }

    if (_erro != null) {
      return _buildErro();
    }

    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _carregarConfiguracoes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderResumo(),
                  const SizedBox(height: 14),
                  _buildAtalhosSuperiores(),
                  const SizedBox(height: 16),
                  _buildSectionTitle(
                    icon: Icons.dashboard_customize_rounded,
                    title: 'Seções do site',
                    subtitle: 'Toque em uma seção para configurar o conteúdo',
                  ),
                  const SizedBox(height: 10),
                  ..._secoes.map((secao) {
                    if (secao['id'] == 'area_aluno') {
                      return _buildAreaAlunoCard(secao);
                    }

                    if (secao['oculto'] == true) {
                      return _buildHiddenSectionCard(secao);
                    }

                    return _buildSecaoCard(secao);
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErro() {
    final t = context.uai;
    final errorColor = _ensureVisible(t.error, t.background);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 68, color: errorColor),
              const SizedBox(height: 16),
              Text(
                'Ops! Algo deu errado',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _carregarConfiguracoes,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderResumo() {
    final t = context.uai;
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: onPrimary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: onPrimary.withOpacity(0.13)),
                ),
                child: Icon(
                  Icons.public_rounded,
                  color: onPrimary,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Central do Site',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Conteúdo público, menu, inscrições, área do aluno e estatísticas.',
                      style: TextStyle(
                        color: onPrimary.withOpacity(0.80),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildHeaderMetric(
                  label: 'Seções',
                  value: '$_totalSecoes',
                  icon: Icons.widgets_rounded,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _buildHeaderMetric(
                  label: 'Visíveis',
                  value: '$_secoesVisiveis',
                  icon: Icons.visibility_rounded,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _buildHeaderMetric(
                  label: 'Ocultas',
                  value: '$_secoesOcultas',
                  icon: Icons.visibility_off_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onPrimary.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: onPrimary, size: 19),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: onPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: onPrimary.withOpacity(0.74),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAtalhosSuperiores() {
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final cards = [
          _buildAtalhoCard(
            icon: Icons.analytics_rounded,
            title: 'Visitas',
            subtitle: 'Dashboard',
            color: t.info,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DashboardEstatisticasScreen(),
                ),
              );
            },
          ),
          _buildAtalhoCard(
            icon: Icons.smart_toy_rounded,
            title: 'Assistente',
            subtitle: 'Chat IA',
            color: t.inscricoes,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ConfigurarAssistenteScreen(),
                ),
              );
            },
          ),
          _buildAtalhoCard(
            icon: Icons.school_rounded,
            title: 'Aluno',
            subtitle: _areaAlunoVisivel ? 'Ativo' : 'Oculto',
            color: _areaAlunoVisivel ? t.associacao : t.textMuted,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AreaAlunoAdminScreen(),
                ),
              ).then((_) => _carregarConfiguracoes());
            },
          ),
        ];

        if (narrow) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 10),
              cards[2],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
            const SizedBox(width: 10),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _buildAtalhoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius - 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        splashColor: accent.withOpacity(0.12),
        highlightColor: accent.withOpacity(0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius - 6),
            border: Border.all(color: accent.withOpacity(0.12)),
            boxShadow: t.softShadow,
          ),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.background);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: t.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaAlunoCard(Map<String, dynamic> secao) {
    final t = context.uai;
    final bool oculto = secao['oculto'] == true;
    final Color color = oculto ? t.textMuted : t.associacao;
    final accent = _ensureVisible(color, t.card);
    final bg = oculto
        ? _softBg(t.textMuted, t.card, 0.08)
        : _softBg(t.associacao, t.card, 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bg, t.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(t.cardRadius - 2),
        border: Border.all(color: accent.withOpacity(0.18)),
        boxShadow: t.softShadow,
      ),
      child: InkWell(
        onTap: () => _abrirSecao(secao),
        borderRadius: BorderRadius.circular(t.cardRadius - 2),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.school_rounded, color: accent, size: 30),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ÁREA DO ALUNO',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                            _buildStatusChip(
                              texto: oculto ? 'OCULTA' : 'ATIVA',
                              color: oculto ? t.textMuted : t.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          secao['descricao'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, color: accent),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 430;
                  final infos = [
                    _buildMiniInfo(
                      icon: Icons.verified_user_rounded,
                      label: 'Segurança',
                      value: _configAreaAluno['exigir_telefone_confirmacao'] == true
                          ? 'Telefone'
                          : 'Simples',
                      color: t.info,
                    ),
                    _buildMiniInfo(
                      icon: Icons.person_pin_rounded,
                      label: 'Status',
                      value: _configAreaAluno['aceitar_apenas_ativos'] == true
                          ? 'Só ativos'
                          : 'Todos',
                      color: t.warning,
                    ),
                    _buildMiniInfo(
                      icon: Icons.history_rounded,
                      label: 'Logs',
                      value: 'Ativos',
                      color: t.success,
                    ),
                  ];

                  if (narrow) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: infos
                          .map((w) => SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        child: w,
                      ))
                          .toList(),
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: infos[0]),
                      const SizedBox(width: 8),
                      Expanded(child: infos[1]),
                      const SizedBox(width: 8),
                      Expanded(child: infos[2]),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniInfo({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: t.textPrimary,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoCard(Map<String, dynamic> secao) {
    final t = context.uai;
    final Color color = secao['cor'];
    final accent = _cardAccent(color);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: InkWell(
        onTap: () => _abrirSecao(secao),
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        splashColor: accent.withOpacity(0.12),
        highlightColor: accent.withOpacity(0.06),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(secao['icone'], color: accent, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secao['titulo'],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      secao['descricao'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildStatusChip(texto: 'VISÍVEL', color: t.success),
                        const SizedBox(width: 6),
                        if (secao['colecao'] != null)
                          Expanded(
                            child: Text(
                              '${secao['colecao']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: t.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHiddenSectionCard(Map<String, dynamic> secao) {
    final t = context.uai;
    final Color color = secao['cor'] ?? t.textMuted;
    final muted = _ensureVisible(t.textMuted, t.cardAlt);
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: t.border),
      ),
      child: InkWell(
        onTap: () => _mostrarDialogoVisibilidade(secao),
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: muted.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(secao['icone'], color: muted, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secao['titulo'],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Seção oculta no site. Toque para gerenciar ou tornar visível.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildStatusChip(texto: 'OCULTO', color: t.textMuted),
                  ],
                ),
              ),
              Icon(Icons.visibility_off_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String texto,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: accent,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _abrirSecao(Map<String, dynamic> secao) {
    switch (secao['tela']) {
      case 'regimento':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RegimentoInternoScreen()),
        ).then(_handleResult);
        break;
      case 'biografia':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BiografiaScreen()),
        ).then(_handleResult);
        break;
      case 'graduacoes':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GraduacoesSiteScreen()),
        ).then(_handleResult);
        break;
      case 'inscricao':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ConfigurarInscricoesScreen()),
        ).then(_handleResult);
        break;
      case 'area_aluno':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AreaAlunoAdminScreen()),
        ).then((_) => _carregarConfiguracoes());
        break;
      case 'campeonato':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ConfigurarCampeonatoScreen()),
        ).then(_handleResult);
        break;
      case 'timeline':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GerenciarTimelineScreen()),
        ).then(_handleResult);
        break;
      default:
        _mostrarEmBreve(secao);
    }
  }

  void _mostrarDialogoConfiguracoes() {
    final t = context.uai;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.cardRadius)),
        title: Row(
          children: [
            Icon(Icons.tune_rounded, color: t.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Configurações do Site',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogOption(
                icone: Icons.swap_vert_rounded,
                cor: t.inscricoes,
                titulo: 'Ordem do Menu',
                descricao: 'Reordenar botões do site',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConfigurarMenuScreen(
                        secoes: _secoesBase,
                        onSalvo: _carregarConfiguracoes,
                      ),
                    ),
                  );
                },
              ),
              Divider(height: 16, color: t.border),
              _buildDialogOption(
                icone: Icons.edit_note_rounded,
                cor: t.warning,
                titulo: 'Títulos e Textos',
                descricao: 'Personalizar nomes e descrições',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditarTextosScreen(
                        secoes: _secoesBase,
                        onSalvo: _carregarConfiguracoes,
                      ),
                    ),
                  );
                },
              ),
              Divider(height: 16, color: t.border),
              _buildDialogOption(
                icone: Icons.school_rounded,
                cor: t.associacao,
                titulo: 'Área do Aluno',
                descricao: 'Acesso, segurança, dados e logs',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AreaAlunoAdminScreen(),
                    ),
                  ).then((_) => _carregarConfiguracoes());
                },
              ),
              Divider(height: 16, color: t.border),
              _buildDialogOption(
                icone: Icons.chat_rounded,
                cor: t.info,
                titulo: 'Assistente Chat',
                descricao: 'Configurar assistente virtual com IA',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ConfigurarAssistenteScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 16, color: t.border),
              _buildDialogOption(
                icone: Icons.lock_rounded,
                cor: t.error,
                titulo: 'Senha do App',
                descricao: 'Alterar senha de acesso dos professores',
                onTap: () {
                  Navigator.pop(context);
                  _mostrarDialogoAlterarSenha();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogOption({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String descricao,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(cor, t.surface);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 49,
              height: 49,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icone, color: accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descricao,
                    style: TextStyle(
                      fontSize: 12,
                      color: t.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: accent),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoVisibilidade(Map<String, dynamic> secao) {
    final bool isAreaAluno = secao['id'] == 'area_aluno';
    final t = context.uai;
    final accent = _ensureVisible(secao['cor'] ?? t.primary, t.surface);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.cardRadius)),
        title: Row(
          children: [
            Icon(secao['icone'], color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                secao['titulo'],
                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Esta seção está atualmente oculta no site.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              isAreaAluno
                  ? 'Você pode abrir o painel da Área do Aluno ou torná-la visível agora.'
                  : 'Deseja torná-la visível novamente?',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          if (isAreaAluno)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _abrirSecao(secao);
              },
              child: const Text('CONFIGURAR'),
            ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              if (isAreaAluno) {
                await _configService.alterarVisibilidadeAreaAluno(true);
              } else {
                await _configService.alterarVisibilidade(secao['id'], true);
              }

              await _carregarConfiguracoes();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${secao['titulo']} agora está visível'),
                    backgroundColor: t.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.success,
              foregroundColor: _readableOn(t.success),
            ),
            child: const Text('TORNAR VISÍVEL'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAlterarSenha() {
    final TextEditingController senhaController = TextEditingController();
    final TextEditingController confirmarController = TextEditingController();
    final t = context.uai;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.cardRadius)),
        title: Column(
          children: [
            Icon(Icons.lock_rounded, size: 42, color: t.primary),
            const SizedBox(height: 8),
            Text(
              'Alterar Senha do App',
              style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Essa senha libera o acesso ao app para professores e monitores.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: senhaController,
                obscureText: true,
                decoration: _uaiInputDecoration(
                  label: 'Nova senha',
                  icon: Icons.password_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmarController,
                obscureText: true,
                decoration: _uaiInputDecoration(
                  label: 'Confirmar nova senha',
                  icon: Icons.password_rounded,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              final novaSenha = senhaController.text.trim();
              final confirmar = confirmarController.text.trim();

              if (novaSenha.isEmpty) {
                _mostrarErro('A senha não pode estar vazia');
                return;
              }

              if (novaSenha.length < 6) {
                _mostrarErro('A senha deve ter pelo menos 6 caracteres');
                return;
              }

              if (novaSenha != confirmar) {
                _mostrarErro('As senhas não coincidem');
                return;
              }

              Navigator.pop(context);
              await _configService.alterarSenhaApp(novaSenha);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✅ Senha alterada com sucesso!'),
                    backgroundColor: t.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
            ),
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $mensagem'),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleResult(dynamic result) {
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Configurações salvas com sucesso!'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );

      _carregarConfiguracoes();
    }
  }

  void _mostrarEmBreve(Map<String, dynamic> secao) {
    final t = context.uai;
    final accent = _ensureVisible(secao['cor'] ?? t.primary, t.surface);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.cardRadius)),
        title: Row(
          children: [
            Icon(secao['icone'], color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                secao['titulo'],
                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hourglass_empty_rounded, size: 50, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Esta tela está em desenvolvimento',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Em breve você poderá editar ${secao['titulo'].toLowerCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Color _iconColor(Color color) {
    if (color is MaterialColor) return color.shade700;
    return color;
  }
}
