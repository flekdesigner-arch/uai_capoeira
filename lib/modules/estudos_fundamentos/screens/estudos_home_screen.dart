import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudos_config_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/progresso_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_ciclos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/progresso_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/screens/ciclo_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/screens/meu_progresso_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/estudos_config_service.dart';

class EstudosHomeScreen extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> authPayload;

  const EstudosHomeScreen({
    super.key,
    required this.aluno,
    required this.authPayload,
  });

  @override
  State<EstudosHomeScreen> createState() => _EstudosHomeScreenState();
}

class _EstudosHomeScreenState extends State<EstudosHomeScreen> {
  final EstudosConfigService _configService = EstudosConfigService();
  final EstudosCiclosRepository _ciclosRepository = EstudosCiclosRepository();
  final EstudosRepository _estudosRepository = EstudosRepository();
  final ProgressoEstudosRepository _progressoRepository =
      ProgressoEstudosRepository();
  int _reloadKey = 0;

  String get _alunoId {
    final values = [
      widget.aluno['aluno_id'],
      widget.aluno['alunoId'],
      widget.aluno['id'],
      widget.authPayload['alunoSelecionadoId'],
      widget.authPayload['aluno_id'],
      widget.authPayload['alunoId'],
    ];
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  void _recarregar() => setState(() => _reloadKey++);

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
        actions: [
          IconButton(
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: StreamBuilder<EstudosConfigModel>(
        key: ValueKey(_reloadKey),
        stream: _configService.watchConfig(),
        builder: (context, configSnapshot) {
          if (configSnapshot.hasError) {
            return _buildEstadoCentral(
              icon: Icons.error_outline_rounded,
              titulo: 'Não foi possível carregar os estudos.',
              texto: 'Verifique sua conexao e tente novamente.',
              action: _retryButton(),
            );
          }
          if (!configSnapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }

          final config = configSnapshot.data ?? EstudosConfigModel.defaults();
          if (!config.ativo ||
              !config.mostrarCardAreaAluno ||
              _alunoId.isEmpty) {
            return _buildEstadoCentral(
              icon: Icons.lock_outline_rounded,
              titulo:
                  'Os Estudos e Fundamentos ainda nao estao disponiveis para os alunos.',
              texto:
                  'Quando o modulo for liberado, a linha do tempo aparecera aqui.',
            );
          }

          return StreamBuilder<List<EstudoCicloModel>>(
            stream: _ciclosRepository.watchCiclosVisiveisParaAluno(
              mostrarEmBreve: config.mostrarEmBreve,
            ),
            builder: (context, ciclosSnapshot) {
              if (ciclosSnapshot.hasError) {
                return _buildEstadoCentral(
                  icon: Icons.error_outline_rounded,
                  titulo: 'Não foi possível carregar os estudos.',
                  texto: 'Verifique sua conexao e tente novamente.',
                  action: _retryButton(),
                );
              }
              if (!ciclosSnapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: t.primary),
                );
              }
              final ciclos = ciclosSnapshot.data ?? const <EstudoCicloModel>[];
              return StreamBuilder<List<EstudoModel>>(
                stream: _estudosRepository.watchEstudosPublicadosVisiveis(),
                builder: (context, estudosSnapshot) {
                  final todosEstudos =
                      estudosSnapshot.data ?? const <EstudoModel>[];
                  final ciclosIds = ciclos
                      .where((c) => c.status == EstudoCicloStatus.publicado)
                      .map((c) => c.id)
                      .toSet();
                  final estudosPublicados = todosEstudos
                      .where((estudo) => ciclosIds.contains(estudo.cicloId))
                      .toList();
                  return StreamBuilder<List<ProgressoEstudoModel>>(
                    stream: _progressoRepository.watchProgressoAluno(_alunoId),
                    builder: (context, progressoSnapshot) {
                      final progressos =
                          progressoSnapshot.data ??
                          const <ProgressoEstudoModel>[];
                      return _buildConteudo(
                        context,
                        config,
                        ciclos,
                        estudosPublicados,
                        progressos,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildConteudo(
    BuildContext context,
    EstudosConfigModel config,
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudosPublicados,
    List<ProgressoEstudoModel> progressos,
  ) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
        16,
        MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
        32,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, ciclos.length),
                const SizedBox(height: 12),
                _progressoGeralCard(
                  context,
                  ciclos,
                  estudosPublicados,
                  progressos,
                ),
                const SizedBox(height: 12),
                if (ciclos.isEmpty)
                  _cardMensagem(
                    context,
                    icon: Icons.timeline_rounded,
                    titulo: 'Nenhum ciclo publicado ainda.',
                    texto:
                        'Os conteúdos aparecerão aqui quando forem liberados para alunos.',
                  )
                else
                  ...ciclos.asMap().entries.map(
                    (entry) => _cicloCard(
                      context,
                      config,
                      entry.value,
                      entry.key,
                      estudosPublicados,
                      progressos,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _progressoGeralCard(
    BuildContext context,
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudosPublicados,
    List<ProgressoEstudoModel> progressos,
  ) {
    final t = context.uai;
    final resumo = _progressoRepository.calcularResumo(
      estudosObrigatoriosIds: estudosPublicados.map((e) => e.id),
      progressos: progressos,
    );
    final estudosPorId = {
      for (final estudo in estudosPublicados) estudo.id: estudo,
    };
    EstudoModel? ultimoEstudo;
    for (final progresso in progressos) {
      final estudo = estudosPorId[progresso.estudoId];
      if (estudo != null) {
        ultimoEstudo = estudo;
        break;
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_graph_rounded, color: t.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Seu progresso',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    _abrirMeuProgresso(ciclos, estudosPublicados, progressos),
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Meu progresso'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: resumo.total <= 0 ? 0 : resumo.percentual / 100,
              minHeight: 10,
              backgroundColor: t.cardAlt,
              color: t.success,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${resumo.concluidos} de ${resumo.total} estudos concluídos',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          Text(
            '${resumo.percentual}% da jornada concluida',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (ultimoEstudo != null) ...[
            const SizedBox(height: 6),
            Text(
              '?ltimo acesso: Estudo ${ultimoEstudo.numero.toString().padLeft(3, '0')} - ${ultimoEstudo.titulo}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _abrirMeuProgresso(
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudosPublicados,
    List<ProgressoEstudoModel> progressos,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeuProgressoEstudosScreen(
          alunoId: _alunoId,
          ciclos: ciclos
              .where((c) => c.status == EstudoCicloStatus.publicado)
              .toList(),
          estudosPublicados: estudosPublicados,
          progressos: progressos,
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int totalCiclos) {
    final t = context.uai;
    final onPrimary = t.primary.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
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
            child: Icon(Icons.history_edu_rounded, color: onPrimary, size: 34),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estudos e Fundamentos',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 24,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sua jornada de formação teórica na capoeira.',
                  style: TextStyle(
                    color: onPrimary.withValues(alpha: 0.84),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _headerChip(
                      context,
                      '$totalCiclos ciclos liberados',
                      onPrimary,
                    ),
                    _headerChip(context, 'Modulo ativo', onPrimary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _cicloCard(
    BuildContext context,
    EstudosConfigModel config,
    EstudoCicloModel ciclo,
    int index,
    List<EstudoModel> estudosPublicados,
    List<ProgressoEstudoModel> progressos,
  ) {
    final t = context.uai;
    final bloqueado = ciclo.status == EstudoCicloStatus.emBreve;
    return StreamBuilder(
      stream: _estudosRepository.watchEstudosVisiveisPorCiclo(
        cicloId: ciclo.id,
        mostrarEmBreve: config.mostrarEmBreve,
      ),
      builder: (context, snapshot) {
        final estudosDoCiclo = estudosPublicados
            .where((e) => e.cicloId == ciclo.id)
            .toList();
        final resumo = _progressoRepository.calcularResumo(
          estudosObrigatoriosIds: estudosDoCiclo.map((e) => e.id),
          progressos: progressos,
        );
        final count = snapshot.data?.length;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius + 2),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ciclo.capaUrl.isNotEmpty) ...[
                _capaCiclo(context, ciclo),
                const SizedBox(height: 12),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            t.primary.withValues(alpha: 0.10),
                            t.cardAlt,
                          ),
                          borderRadius: BorderRadius.circular(t.cardRadius),
                        ),
                        child: Center(
                          child: Text(
                            ciclo.numero.toString(),
                            style: TextStyle(
                              color: t.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      if (index < 99)
                        Container(width: 2, height: 42, color: t.border),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _statusChip(
                              context,
                              bloqueado ? 'Em breve' : 'Publicado',
                              bloqueado,
                            ),
                            if (count != null)
                              _miniChip(
                                context,
                                Icons.article_rounded,
                                '$count estudos',
                              ),
                            if (!bloqueado)
                              _miniChip(
                                context,
                                Icons.check_circle_rounded,
                                '${resumo.concluidos}/${resumo.total} concluídos',
                              ),
                            if (ciclo.periodoHistorico.isNotEmpty)
                              _miniChip(
                                context,
                                Icons.event_rounded,
                                ciclo.periodoHistorico,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ciclo.titulo.isEmpty
                              ? 'Ciclo sem título'
                              : ciclo.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 18,
                            height: 1.12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (ciclo.subtitulo.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            ciclo.subtitulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        if (ciclo.descricao.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            ciclo.descricao,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (!bloqueado) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: resumo.total <= 0
                                  ? 0
                                  : resumo.percentual / 100,
                              minHeight: 8,
                              backgroundColor: t.cardAlt,
                              color: t.success,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${resumo.percentual}% - ${resumo.statusLabel}',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: bloqueado
                                ? null
                                : () => _abrirCiclo(context, config, ciclo),
                            icon: Icon(
                              bloqueado
                                  ? Icons.lock_outline_rounded
                                  : Icons.menu_book_rounded,
                            ),
                            label: Text(
                              bloqueado
                                  ? 'Este ciclo sera liberado em breve'
                                  : 'Ver estudos',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _capaCiclo(BuildContext context, EstudoCicloModel ciclo) {
    final t = context.uai;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: Image.network(
          EstudoModel.normalizarImagemUrl(ciclo.capaUrl),
          fit: BoxFit.cover,
          alignment: Alignment(
            (ciclo.capaFocoX * 2) - 1,
            (ciclo.capaFocoY * 2) - 1,
          ),
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(Icons.image_not_supported_rounded, color: t.textMuted),
          ),
        ),
      ),
    );
  }

  void _abrirCiclo(
    BuildContext context,
    EstudosConfigModel config,
    EstudoCicloModel ciclo,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CicloEstudosScreen(
          ciclo: ciclo,
          mostrarEmBreve: config.mostrarEmBreve,
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String label, bool bloqueado) {
    final t = context.uai;
    final color = bloqueado ? t.info : t.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _miniChip(BuildContext context, IconData icon, String label) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: t.textSecondary, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _retryButton() {
    return FilledButton.icon(
      onPressed: _recarregar,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Tentar novamente'),
    );
  }

  Widget _buildEstadoCentral({
    required IconData icon,
    required String titulo,
    required String texto,
    Widget? action,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(18),
        child: _cardMensagem(
          context,
          icon: icon,
          titulo: titulo,
          texto: texto,
          action: action,
        ),
      ),
    );
  }

  Widget _cardMensagem(
    BuildContext context, {
    required IconData icon,
    required String titulo,
    required String texto,
    Widget? action,
  }) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: t.primary, size: 48),
          const SizedBox(height: 10),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }
}
