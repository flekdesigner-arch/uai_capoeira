import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudos_config_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/resultado_tentativa_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/theme/estudos_aluno_theme.dart';

class ResultadoEstudoScreen extends StatelessWidget {
  final String estudoTitulo;
  final ResultadoTentativaEstudoModel resultado;
  final WidgetBuilder? tentarNovamenteBuilder;
  final bool permitirTentarNovamente;
  final EstudosConfigModel? config;

  const ResultadoEstudoScreen({
    super.key,
    required this.estudoTitulo,
    required this.resultado,
    this.tentarNovamenteBuilder,
    this.permitirTentarNovamente = true,
    this.config,
  });

  @override
  Widget build(BuildContext context) {
    return EstudosAlunoTheme(
      config: config,
      child: Builder(
        builder: (context) {
          final t = context.uai;
          final color = resultado.possuiPendenciaManual
              ? t.warning
              : resultado.aprovado
              ? t.success
              : t.error;
          final icon = resultado.possuiPendenciaManual
              ? Icons.pending_actions_rounded
              : resultado.aprovado
              ? Icons.verified_rounded
              : Icons.assignment_late_rounded;
          final titulo = resultado.possuiPendenciaManual
              ? 'Aguardando correção'
              : resultado.aprovado
              ? 'Avaliação concluída'
              : 'Hora de revisar';
          final mensagem = resultado.aprovado
              ? 'Parabéns! Você concluiu esta avaliação. Continue estudando para fortalecer ainda mais sua compreensão da Capoeira.'
              : 'Você respondeu, mas ainda pode revisar o estudo com calma. O aprendizado também acontece quando voltamos ao conteúdo e tentamos novamente.';

          return Scaffold(
            backgroundColor: t.background,
            appBar: AppBar(
              title: const Text(
                'Resultado',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.94, end: 1),
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        builder: (context, scale, child) => Opacity(
                          opacity: ((scale - 0.94) / 0.06).clamp(0.0, 1.0),
                          child: Transform.scale(scale: scale, child: child),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: t.card,
                            borderRadius: BorderRadius.circular(
                              t.cardRadius + 4,
                            ),
                            border: Border.all(
                              color: color.withValues(alpha: 0.22),
                            ),
                            boxShadow: t.softShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(icon, color: color, size: 32),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          titulo,
                                          style: TextStyle(
                                            color: t.textPrimary,
                                            fontSize: 22,
                                            height: 1.1,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          estudoTitulo.isEmpty
                                              ? 'Estudo'
                                              : estudoTitulo,
                                          style: TextStyle(
                                            color: t.textSecondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Center(
                                child: Text(
                                  '${resultado.percentualFormatado}%',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 46,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _metricas(context),
                              const SizedBox(height: 14),
                              _aviso(
                                context,
                                icon: Icons.menu_book_rounded,
                                color: color,
                                text: mensagem,
                              ),
                              if (resultado.possuiPendenciaManual) ...[
                                const SizedBox(height: 12),
                                _avisoManual(context),
                              ],
                              if (resultado.idempotente) ...[
                                const SizedBox(height: 12),
                                _avisoIdempotente(context),
                              ],
                              if (!permitirTentarNovamente) ...[
                                const SizedBox(height: 12),
                                _aviso(
                                  context,
                                  icon: Icons.lock_clock_rounded,
                                  color: t.warning,
                                  text:
                                      'Esta avaliação permite apenas uma tentativa. Procure o professor se precisar revisar sua situação.',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('Voltar ao estudo'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _voltarParaCiclo(context),
                            icon: const Icon(Icons.view_list_rounded),
                            label: const Text('Ver estudos do ciclo'),
                          ),
                          if (permitirTentarNovamente &&
                              tentarNovamenteBuilder != null)
                            FilledButton.icon(
                              onPressed: () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: tentarNovamenteBuilder!,
                                ),
                              ),
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text('Tentar novamente'),
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
      ),
    );
  }

  void _voltarParaCiclo(BuildContext context) {
    var rotasRemovidas = 0;
    Navigator.popUntil(context, (route) {
      if (route.isFirst || rotasRemovidas >= 2) return true;
      rotasRemovidas++;
      return false;
    });
  }

  Widget _metricas(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final cards = [
          _metricaCard(
            context,
            label: 'Questões',
            value: resultado.totalQuestoes.toString(),
          ),
          _metricaCard(
            context,
            label: 'Acertos',
            value: '${resultado.acertos}/${resultado.totalObjetivas}',
          ),
          _metricaCard(
            context,
            label: 'Respondidas',
            value: '${resultado.totalRespondidas}/${resultado.totalQuestoes}',
          ),
          _metricaCard(
            context,
            label: 'Critério',
            value:
                '${resultado.criterioAprovacaoPercentual.toStringAsFixed(0)}%',
          ),
        ];
        return GridView.count(
          crossAxisCount: narrow ? 2 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: narrow ? 1.7 : 1.35,
          children: cards,
        );
      },
    );
  }

  Widget _metricaCard(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoManual(BuildContext context) {
    final t = context.uai;
    return _aviso(
      context,
      icon: Icons.pending_rounded,
      color: t.warning,
      text: 'Esta atividade possui questão pendente de correção manual.',
    );
  }

  Widget _avisoIdempotente(BuildContext context) {
    final t = context.uai;
    return _aviso(
      context,
      icon: Icons.history_rounded,
      color: t.info,
      text: 'Este resultado já havia sido registrado para esta tentativa.',
    );
  }

  Widget _aviso(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: t.textPrimary,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
