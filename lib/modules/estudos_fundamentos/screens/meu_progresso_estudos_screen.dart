import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/progresso_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/progresso_estudos_repository.dart';

class MeuProgressoEstudosScreen extends StatelessWidget {
  final String alunoId;
  final List<EstudoCicloModel> ciclos;
  final List<EstudoModel> estudosPublicados;
  final List<ProgressoEstudoModel> progressos;

  const MeuProgressoEstudosScreen({
    super.key,
    required this.alunoId,
    required this.ciclos,
    required this.estudosPublicados,
    required this.progressos,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final repo = ProgressoEstudosRepository();
    final resumo = repo.calcularResumo(
      estudosObrigatoriosIds: estudosPublicados.map((e) => e.id),
      progressos: progressos,
    );
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Meu progresso',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _resumoCard(context, resumo),
                const SizedBox(height: 12),
                _aviso(context),
                const SizedBox(height: 12),
                if (estudosPublicados.isEmpty)
                  _mensagem(context, 'Nenhum estudo publicado ainda.')
                else ...[
                  Text(
                    'Progresso por ciclo',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...ciclos.map((ciclo) => _cicloCard(context, repo, ciclo)),
                  const SizedBox(height: 12),
                  Text(
                    'Estudos',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...estudosPublicados.map(
                    (estudo) => _estudoLinha(context, estudo),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resumoCard(BuildContext context, EstudosProgressoResumo resumo) {
    final t = context.uai;
    return Container(
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
            children: [
              Icon(Icons.auto_graph_rounded, color: t.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Seu progresso',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
            '${resumo.percentual}% da jornada concluída',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aviso(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.info.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.info.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: t.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este progresso representa leitura dos estudos. Avaliações e certificados serão implementados futuramente.',
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

  Widget _cicloCard(
    BuildContext context,
    ProgressoEstudosRepository repo,
    EstudoCicloModel ciclo,
  ) {
    final t = context.uai;
    final estudos = estudosPublicados
        .where((e) => e.cicloId == ciclo.id)
        .toList();
    final resumo = repo.calcularResumo(
      estudosObrigatoriosIds: estudos.map((e) => e.id),
      progressos: progressos,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ciclo.titulo,
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: resumo.total <= 0 ? 0 : resumo.percentual / 100,
              minHeight: 8,
              backgroundColor: t.cardAlt,
              color: t.success,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${resumo.concluidos} de ${resumo.total} estudos concluídos (${resumo.percentual}%)',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estudoLinha(BuildContext context, EstudoModel estudo) {
    final progresso = _progressoDoEstudo(estudo.id);
    final concluido = progresso?.concluido == true;
    final iniciado = progresso?.iniciado == true;
    final t = context.uai;
    final label = concluido
        ? 'Concluído'
        : (iniciado ? 'Em andamento' : 'Não iniciado');
    final color = concluido ? t.success : (iniciado ? t.info : t.textMuted);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Estudo ${estudo.numero.toString().padLeft(3, '0')} - ${estudo.titulo}',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
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
          ),
        ],
      ),
    );
  }

  ProgressoEstudoModel? _progressoDoEstudo(String estudoId) {
    for (final progresso in progressos) {
      if (progresso.estudoId == estudoId) return progresso;
    }
    return null;
  }

  Widget _mensagem(BuildContext context, String texto) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
