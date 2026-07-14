import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudos_config_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/progresso_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/resultado_estudo_aluno_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/progresso_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/resultados_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/screens/responder_estudo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/widgets/estudo_artigo_renderer.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/theme/estudos_aluno_theme.dart';

class DetalheEstudoScreen extends StatefulWidget {
  final EstudoCicloModel ciclo;
  final EstudoModel estudo;
  final bool mostrarEmBreve;
  final String alunoId;
  final EstudosConfigModel? config;

  const DetalheEstudoScreen({
    super.key,
    required this.ciclo,
    required this.estudo,
    required this.mostrarEmBreve,
    required this.alunoId,
    this.config,
  });

  @override
  State<DetalheEstudoScreen> createState() => _DetalheEstudoScreenState();
}

class _DetalheEstudoScreenState extends State<DetalheEstudoScreen> {
  final ProgressoEstudosRepository _progressoRepository =
      ProgressoEstudosRepository();
  final ResultadosEstudosRepository _resultadosRepository =
      ResultadosEstudosRepository();
  bool _salvando = false;
  bool _inicioRegistrado = false;

  bool get _cicloPublicado =>
      widget.ciclo.status == EstudoCicloStatus.publicado;
  bool get _estudoPublicado =>
      widget.estudo.status == EstudoCicloStatus.publicado;
  bool get _estudoEmBreve => widget.estudo.status == EstudoCicloStatus.emBreve;
  bool get _disponivel =>
      _cicloPublicado && _estudoPublicado && widget.alunoId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registrarInicio());
  }

  Future<void> _registrarInicio() async {
    if (_inicioRegistrado || !_disponivel) return;
    _inicioRegistrado = true;
    try {
      await _progressoRepository.iniciarEstudo(
        alunoId: widget.alunoId,
        estudoId: widget.estudo.id,
        cicloId: widget.ciclo.id,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível registrar o início da leitura.'),
        ),
      );
    }
  }

  Future<void> _marcarConcluido() async {
    if (!_disponivel || _salvando) return;
    setState(() => _salvando = true);
    try {
      await _progressoRepository.marcarConcluido(
        alunoId: widget.alunoId,
        estudoId: widget.estudo.id,
        cicloId: widget.ciclo.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estudo marcado como concluído.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar o progresso.')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _abrirAtividade() {
    if (widget.alunoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acesse novamente pela Área do Aluno.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResponderEstudoScreen(
          alunoId: widget.alunoId,
          estudoId: widget.estudo.id,
          cicloId: widget.ciclo.id,
          estudoTitulo: widget.estudo.titulo,
          cicloTitulo: widget.ciclo.titulo,
          permitirTentarNovamente: widget.estudo.permitirTentarNovamente,
          config: widget.config,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EstudosAlunoTheme(
      config: widget.config,
      child: Builder(
        builder: (context) {
          final t = context.uai;
          return Scaffold(
            backgroundColor: t.background,
            appBar: AppBar(
              title: Text(
                widget.estudo.titulo.isEmpty ? 'Estudo' : widget.estudo.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            body: _buildBody(context),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.alunoId.isEmpty) {
      return _estadoBloqueado(
        context,
        'Não foi possível identificar o aluno selecionado.',
        'Volte para a Área do Aluno e acesse novamente.',
      );
    }
    if (!_cicloPublicado || (!_estudoPublicado && !_estudoEmBreve)) {
      return _estadoBloqueado(
        context,
        'Este estudo ainda não está disponível.',
        'Quando for liberado pelo professor, ele aparecerá para leitura.',
      );
    }
    if (_estudoEmBreve) {
      return _estadoBloqueado(
        context,
        'Este estudo será liberado em breve.',
        'Volte mais tarde para acessar este conteúdo.',
      );
    }

    return StreamBuilder<ProgressoEstudoModel?>(
      stream: _progressoRepository.watchProgressoEstudo(
        alunoId: widget.alunoId,
        estudoId: widget.estudo.id,
      ),
      builder: (context, snapshot) {
        final progresso = snapshot.data;
        final concluido = progresso?.concluido == true;
        return StreamBuilder<List<ResultadoEstudoAlunoModel>>(
          stream: _resultadosRepository.watchResultadosAluno(widget.alunoId),
          builder: (context, resultadosSnapshot) {
            final resultado =
                (resultadosSnapshot.data ?? const <ResultadoEstudoAlunoModel>[])
                    .where((item) => item.estudoId == widget.estudo.id)
                    .firstOrNull;
            final tentativaBloqueada =
                !widget.estudo.permitirTentarNovamente && resultado != null;
            return SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _progressoCard(context, concluido),
                      if (tentativaBloqueada) ...[
                        const SizedBox(height: 12),
                        _tentativaUnicaCard(context),
                      ],
                      const SizedBox(height: 12),
                      EstudoArtigoRenderer(
                        estudo: widget.estudo,
                        mostrarMetadados: false,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('Voltar para o ciclo'),
                          ),
                          FilledButton.icon(
                            onPressed: tentativaBloqueada
                                ? null
                                : _abrirAtividade,
                            icon: const Icon(Icons.quiz_rounded),
                            label: const Text('Fazer atividade'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: concluido || _salvando
                                ? null
                                : _marcarConcluido,
                            icon: Icon(
                              concluido
                                  ? Icons.check_circle_rounded
                                  : Icons.done_all_rounded,
                            ),
                            label: Text(
                              concluido
                                  ? 'Estudo concluído'
                                  : 'Marcar como concluído',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _progressoCard(BuildContext context, bool concluido) {
    final t = context.uai;
    final color = concluido ? t.success : t.info;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.08), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(
            concluido
                ? Icons.check_circle_rounded
                : Icons.play_circle_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              concluido
                  ? 'Estudo concluído. Este registro representa leitura, não aprovação em avaliação.'
                  : 'Leitura iniciada. Concluir leitura não equivale a aprovação em avaliação.',
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

  Widget _tentativaUnicaCard(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.warning.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.warning.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock_rounded, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Esta avaliação permite apenas uma tentativa. Procure o professor se precisar revisar sua situação.',
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

  Widget _estadoBloqueado(BuildContext context, String titulo, String texto) {
    final t = context.uai;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(18),
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
            Icon(Icons.lock_outline_rounded, color: t.textMuted, size: 52),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
