import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/progresso_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/progresso_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/screens/responder_estudo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/widgets/estudo_artigo_renderer.dart';

class DetalheEstudoScreen extends StatefulWidget {
  final EstudoCicloModel ciclo;
  final EstudoModel estudo;
  final bool mostrarEmBreve;
  final String alunoId;

  const DetalheEstudoScreen({
    super.key,
    required this.ciclo,
    required this.estudo,
    required this.mostrarEmBreve,
    required this.alunoId,
  });

  @override
  State<DetalheEstudoScreen> createState() => _DetalheEstudoScreenState();
}

class _DetalheEstudoScreenState extends State<DetalheEstudoScreen> {
  final ProgressoEstudosRepository _progressoRepository =
      ProgressoEstudosRepository();
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
          content: Text('Nao foi possivel registrar o inicio da leitura.'),
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
          const SnackBar(content: Text('Estudo marcado como concluido.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel salvar o progresso.')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _abrirAtividade() {
    if (widget.alunoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acesse novamente pela Area do Aluno.')),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
  }

  Widget _buildBody(BuildContext context) {
    if (widget.alunoId.isEmpty) {
      return _estadoBloqueado(
        context,
        'Nao foi possivel identificar o aluno selecionado.',
        'Volte para a Area do Aluno e acesse novamente.',
      );
    }
    if (!_cicloPublicado || (!_estudoPublicado && !_estudoEmBreve)) {
      return _estadoBloqueado(
        context,
        'Este estudo ainda nao esta disponivel.',
        'Quando for liberado pelo professor, ele aparecera para leitura.',
      );
    }
    if (_estudoEmBreve) {
      return _estadoBloqueado(
        context,
        'Este estudo sera liberado em breve.',
        'Volte mais tarde para acessar este conteudo.',
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
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _progressoCard(context, concluido),
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
                        onPressed: _abrirAtividade,
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
                              ? 'Estudo concluido'
                              : 'Marcar como concluido',
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
                  ? 'Estudo concluido. Este registro representa leitura, nao aprovacao em avaliacao.'
                  : 'Leitura iniciada. Concluir leitura nao equivale a aprovacao em avaliacao.',
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
