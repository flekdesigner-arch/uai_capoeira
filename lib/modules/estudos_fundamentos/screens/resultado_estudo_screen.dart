import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/resultado_tentativa_estudo_model.dart';

class ResultadoEstudoScreen extends StatelessWidget {
  final String estudoTitulo;
  final ResultadoTentativaEstudoModel resultado;
  final WidgetBuilder? tentarNovamenteBuilder;

  const ResultadoEstudoScreen({
    super.key,
    required this.estudoTitulo,
    required this.resultado,
    this.tentarNovamenteBuilder,
  });

  @override
  Widget build(BuildContext context) {
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
        ? 'Aguardando correcao'
        : resultado.aprovado
        ? 'Atividade aprovada'
        : 'Atividade nao aprovada';

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
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(t.cardRadius + 4),
                    border: Border.all(color: t.border),
                    boxShadow: t.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(icon, color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 21,
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
                      _metricas(context),
                      if (resultado.possuiPendenciaManual) ...[
                        const SizedBox(height: 14),
                        _avisoManual(context),
                      ],
                      if (resultado.idempotente) ...[
                        const SizedBox(height: 14),
                        _avisoIdempotente(context),
                      ],
                    ],
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
                    if (tentarNovamenteBuilder != null)
                      FilledButton.icon(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: tentarNovamenteBuilder!),
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
  }

  Widget _metricas(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final cards = [
          _metricaCard(
            context,
            label: 'Percentual',
            value: '${resultado.percentualFormatado}%',
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
            label: 'Status',
            value: resultado.status.replaceAll('_', ' '),
          ),
        ];
        return GridView.count(
          crossAxisCount: narrow ? 2 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: narrow ? 1.55 : 1.25,
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
      text: 'Esta atividade possui questao pendente de correcao manual.',
    );
  }

  Widget _avisoIdempotente(BuildContext context) {
    final t = context.uai;
    return _aviso(
      context,
      icon: Icons.history_rounded,
      color: t.info,
      text: 'Este resultado ja havia sido registrado para esta tentativa.',
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
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
