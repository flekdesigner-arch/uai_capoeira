import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/acompanhar_alunos_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_ciclos_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_perguntas_estudo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_ciclos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/perguntas_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudos_config_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/pergunta_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/estudos_config_service.dart';

class GerenciarEstudosFundamentosScreen extends StatefulWidget {
  const GerenciarEstudosFundamentosScreen({super.key});

  @override
  State<GerenciarEstudosFundamentosScreen> createState() =>
      _GerenciarEstudosFundamentosScreenState();
}

class _GerenciarEstudosFundamentosScreenState
    extends State<GerenciarEstudosFundamentosScreen> {
  final EstudosConfigService _configService = EstudosConfigService();
  final EstudosCiclosRepository _ciclosRepository = EstudosCiclosRepository();
  final EstudosRepository _estudosRepository = EstudosRepository();
  final PerguntasEstudosRepository _perguntasRepository =
      PerguntasEstudosRepository();

  EstudosConfigModel _config = EstudosConfigModel.defaults();
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);

    try {
      final config = await _configService.buscarConfigGlobal(
        criarSeNaoExistir: true,
      );
      if (!mounted) return;
      setState(() => _config = config);
    } catch (e) {
      if (!mounted) return;
      _mostrarMensagem('Não foi possível carregar a configuração.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar(EstudosConfigModel config) async {
    if (_salvando) return;

    setState(() {
      _salvando = true;
      _config = config;
    });

    try {
      await _configService.salvarConfigGlobal(config);
      if (!mounted) return;
      _mostrarMensagem('Configuracao salva.');
    } catch (e) {
      if (!mounted) return;
      _mostrarMensagem('Não foi possível salvar a configuração.');
      await _carregar();
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarEmBreve() {
    _mostrarMensagem('Recurso será implementado na próxima fase.');
  }

  Future<void> _abrirGerenciarCiclos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GerenciarCiclosEstudosScreen()),
    );
  }

  Future<void> _abrirGerenciarEstudos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GerenciarEstudosScreen()),
    );
  }

  Future<void> _abrirGerenciarPerguntas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GerenciarPerguntasEstudoScreen()),
    );
  }

  Future<void> _abrirAcompanharAlunos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AcompanharAlunosEstudosScreen()),
    );
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Estudos e Fundamentos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor: _readableOn(
          Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando || _salvando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : RefreshIndicator(
              color: t.primary,
              onRefresh: _carregar,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                  16,
                  MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                  28,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 14),
                          _buildConfigPanel(),
                          const SizedBox(height: 14),
                          _buildResumoPanel(),
                          const SizedBox(height: 14),
                          _buildAtalhosPanel(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);
    final ativo = _config.ativo && _config.mostrarCardAreaAluno;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 4),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(t.cardRadius),
            ),
            child: Icon(Icons.history_edu_rounded, color: onPrimary, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estudos e Fundamentos',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Área de formação teórica da capoeira, preparada para ciclos, estudos, artigos, vídeos e avaliações.',
                  style: TextStyle(
                    color: onPrimary.withValues(alpha: 0.84),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _buildStatusChip(ativo),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool ativo) {
    final t = context.uai;
    final color = ativo ? t.success : t.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ativo ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 5),
          Text(
            ativo ? 'ativo' : 'inativo',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigPanel() {
    final t = context.uai;

    return _section(
      title: 'Configuração geral',
      icon: Icons.tune_rounded,
      children: [
        _switchTile(
          title: 'Ativar módulo na Área do Aluno',
          subtitle: 'Liga a base do módulo para uso dos alunos.',
          value: _config.ativo,
          onChanged: (value) => _salvar(_config.copyWith(ativo: value)),
        ),
        _switchTile(
          title: 'Mostrar card para alunos',
          subtitle: 'Exibe o atalho no painel da Area do Aluno.',
          value: _config.mostrarCardAreaAluno,
          onChanged: (value) =>
              _salvar(_config.copyWith(mostrarCardAreaAluno: value)),
        ),
        _switchTile(
          title: 'Mostrar conteúdos em breve',
          subtitle: 'Prepara exibição futura de ciclos/estudos bloqueados.',
          value: _config.mostrarEmBreve,
          onChanged: (value) =>
              _salvar(_config.copyWith(mostrarEmBreve: value)),
        ),
        if (_salvando)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(color: t.primary),
          ),
      ],
    );
  }

  Widget _buildResumoPanel() {
    return _section(
      title: 'Resumo editorial',
      icon: Icons.dashboard_customize_rounded,
      children: [
        StreamBuilder<EstudosCiclosResumo>(
          stream: _ciclosRepository.watchResumo(),
          builder: (context, ciclosSnapshot) {
            final ciclos =
                ciclosSnapshot.data ??
                const EstudosCiclosResumo(
                  total: 0,
                  publicados: 0,
                  rascunhos: 0,
                  emBreve: 0,
                  ocultos: 0,
                  arquivados: 0,
                );
            return StreamBuilder<EstudosResumo>(
              stream: _estudosRepository.watchResumo(),
              builder: (context, estudosSnapshot) {
                final estudos =
                    estudosSnapshot.data ??
                    const EstudosResumo(
                      total: 0,
                      publicados: 0,
                      rascunhos: 0,
                      emBreve: 0,
                      ocultos: 0,
                      arquivados: 0,
                    );
                return StreamBuilder<PerguntasResumo>(
                  stream: _perguntasRepository.watchResumo(),
                  builder: (context, perguntasSnapshot) {
                    final perguntas =
                        perguntasSnapshot.data ??
                        const PerguntasResumo(
                          total: 0,
                          ativas: 0,
                          rascunhos: 0,
                          inativas: 0,
                          arquivadas: 0,
                        );
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 720;
                        final items = [
                          _ResumoItem(
                            Icons.timeline_rounded,
                            'Ciclos cadastrados',
                            ciclos.total.toString(),
                          ),
                          _ResumoItem(
                            Icons.check_circle_rounded,
                            'Ciclos publicados',
                            ciclos.publicados.toString(),
                          ),
                          _ResumoItem(
                            Icons.article_rounded,
                            'Estudos cadastrados',
                            estudos.total.toString(),
                          ),
                          _ResumoItem(
                            Icons.fact_check_rounded,
                            'Estudos publicados',
                            estudos.publicados.toString(),
                          ),
                          _ResumoItem(
                            Icons.quiz_rounded,
                            'Perguntas cadastradas',
                            perguntas.total.toString(),
                          ),
                          _ResumoItem(
                            Icons.verified_rounded,
                            'Perguntas ativas',
                            perguntas.ativas.toString(),
                          ),
                          _ResumoItem(
                            Icons.edit_note_rounded,
                            'Conteudos em rascunho',
                            (ciclos.rascunhos +
                                    estudos.rascunhos +
                                    perguntas.rascunhos)
                                .toString(),
                          ),
                          _ResumoItem(
                            Icons.pause_circle_rounded,
                            'Perguntas inativas/arquivadas',
                            (perguntas.inativas + perguntas.arquivadas)
                                .toString(),
                          ),
                        ];

                        if (narrow) {
                          return Column(
                            children: items
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 9),
                                    child: _resumoCard(item),
                                  ),
                                )
                                .toList(),
                          );
                        }

                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: items
                              .map(
                                (item) => SizedBox(
                                  width: (constraints.maxWidth - 10) / 2,
                                  child: _resumoCard(item),
                                ),
                              )
                              .toList(),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildAtalhosPanel() {
    return _section(
      title: 'Proximas ferramentas',
      icon: Icons.account_tree_rounded,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final items = [
              _AtalhoItem(
                Icons.timeline_rounded,
                'Gerenciar ciclos',
                _abrirGerenciarCiclos,
                'Abrir',
              ),
              _AtalhoItem(
                Icons.article_rounded,
                'Gerenciar estudos',
                _abrirGerenciarEstudos,
                'Abrir',
              ),
              _AtalhoItem(
                Icons.quiz_rounded,
                'Gerenciar perguntas',
                _abrirGerenciarPerguntas,
                'Abrir',
              ),
              _AtalhoItem(
                Icons.analytics_rounded,
                'Acompanhar Alunos',
                _abrirAcompanharAlunos,
                'Abrir',
                'Veja o progresso, tentativas e avaliações dos alunos nos estudos.',
              ),
              _AtalhoItem(
                Icons.visibility_rounded,
                'Pre-visualizar como aluno',
              ),
              _AtalhoItem(Icons.bar_chart_rounded, 'Relatorios'),
            ];

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items
                  .map(
                    (item) => SizedBox(
                      width: constraints.maxWidth < 720
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 10) / 2,
                      child: _atalhoCard(item),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: t.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            border: Border.all(color: t.border),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              title,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            value: value,
            activeThumbColor: t.primary,
            onChanged: _salvando ? null : onChanged,
          ),
        ),
      ),
    );
  }

  Widget _resumoCard(_ResumoItem item) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: t.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            item.value,
            style: TextStyle(
              color: t.primary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _atalhoCard(_AtalhoItem item) {
    final t = context.uai;

    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.cardRadius - 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap ?? _mostrarEmBreve,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(item.icon, color: t.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.badge,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumoItem {
  final IconData icon;
  final String label;
  final String value;

  const _ResumoItem(this.icon, this.label, this.value);
}

class _AtalhoItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String badge;
  final String subtitle;

  const _AtalhoItem(
    this.icon,
    this.label, [
    this.onTap,
    this.badge = 'Em breve',
    this.subtitle = '',
  ]);
}
