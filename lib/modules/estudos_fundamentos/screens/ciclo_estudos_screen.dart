import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/progresso_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/progresso_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/screens/detalhe_estudo_screen.dart';

class CicloEstudosScreen extends StatefulWidget {
  final EstudoCicloModel ciclo;
  final bool mostrarEmBreve;
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> authPayload;

  const CicloEstudosScreen({
    super.key,
    required this.ciclo,
    required this.mostrarEmBreve,
    required this.aluno,
    required this.authPayload,
  });

  @override
  State<CicloEstudosScreen> createState() => _CicloEstudosScreenState();
}

class _CicloEstudosScreenState extends State<CicloEstudosScreen> {
  final EstudosRepository _repository = EstudosRepository();
  final ProgressoEstudosRepository _progressoRepository =
      ProgressoEstudosRepository();
  int _reloadKey = 0;

  void _recarregar() => setState(() => _reloadKey++);

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

  bool get _cicloDisponivel =>
      widget.ciclo.status == EstudoCicloStatus.publicado;

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          widget.ciclo.titulo.isEmpty
              ? 'Ciclo de estudos'
              : widget.ciclo.titulo,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: !_cicloDisponivel
          ? _estadoCentral(
              icon: Icons.lock_outline_rounded,
              titulo: 'Este ciclo sera liberado em breve.',
              texto: 'Volte mais tarde para acessar os estudos deste ciclo.',
            )
          : StreamBuilder<List<EstudoModel>>(
              key: ValueKey(_reloadKey),
              stream: _repository.watchEstudosVisiveisPorCiclo(
                cicloId: widget.ciclo.id,
                mostrarEmBreve: widget.mostrarEmBreve,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _estadoCentral(
                    icon: Icons.error_outline_rounded,
                    titulo: 'Nao foi possivel carregar os estudos.',
                    texto: 'Verifique sua conexao e tente novamente.',
                    action: FilledButton.icon(
                      onPressed: _recarregar,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: t.primary),
                  );
                }
                final estudos = snapshot.data ?? const <EstudoModel>[];
                return StreamBuilder<List<ProgressoEstudoModel>>(
                  stream: _progressoRepository.watchProgressoAluno(_alunoId),
                  builder: (context, progressoSnapshot) {
                    final progressos =
                        progressoSnapshot.data ??
                        const <ProgressoEstudoModel>[];
                    return _conteudo(context, estudos, progressos);
                  },
                );
              },
            ),
    );
  }

  Widget _conteudo(
    BuildContext context,
    List<EstudoModel> estudos,
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
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, estudos, progressos),
                const SizedBox(height: 12),
                if (estudos.isEmpty)
                  _mensagemCard(
                    context,
                    icon: Icons.article_rounded,
                    titulo: 'Nenhum estudo publicado neste ciclo ainda.',
                    texto:
                        'Quando uma aula for liberada, ela aparecera nesta lista.',
                  )
                else
                  ...estudos.map(
                    (estudo) => _estudoCard(context, estudo, progressos),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    List<EstudoModel> estudos,
    List<ProgressoEstudoModel> progressos,
  ) {
    final t = context.uai;
    final publicados = estudos
        .where((e) => e.status == EstudoCicloStatus.publicado)
        .map((e) => e.id);
    final resumo = _progressoRepository.calcularResumo(
      estudosObrigatoriosIds: publicados,
      progressos: progressos,
    );
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
          if (widget.ciclo.capaUrl.isNotEmpty) ...[
            _capaImagem(context, widget.ciclo.capaUrl, aspectRatio: 16 / 6),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniChip(
                context,
                Icons.timeline_rounded,
                'Ciclo ${widget.ciclo.numero}',
              ),
              _miniChip(
                context,
                Icons.article_rounded,
                '${resumo.total} estudos',
              ),
              _miniChip(
                context,
                Icons.check_circle_rounded,
                '${resumo.concluidos} concluidos',
              ),
              if (widget.ciclo.periodoHistorico.isNotEmpty)
                _miniChip(
                  context,
                  Icons.event_rounded,
                  widget.ciclo.periodoHistorico,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.ciclo.titulo,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 24,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (widget.ciclo.subtitulo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.ciclo.subtitulo,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (widget.ciclo.descricao.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              widget.ciclo.descricao,
              style: TextStyle(
                color: t.textSecondary,
                height: 1.42,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: resumo.total <= 0 ? 0 : resumo.percentual / 100,
              minHeight: 9,
              backgroundColor: t.cardAlt,
              color: t.success,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${resumo.concluidos} de ${resumo.total} estudos concluidos (${resumo.percentual}%)',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estudoCard(
    BuildContext context,
    EstudoModel estudo,
    List<ProgressoEstudoModel> progressos,
  ) {
    final t = context.uai;
    final bloqueado = estudo.status == EstudoCicloStatus.emBreve;
    final progresso = progressos
        .where((p) => p.estudoId == estudo.id)
        .firstOrNull;
    final concluido = progresso?.concluido == true;
    final iniciado = progresso?.iniciado == true;
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
          if (estudo.capaUrl.isNotEmpty) ...[
            _capaImagem(context, estudo.capaUrl, aspectRatio: 16 / 8),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _statusChip(
                context,
                bloqueado ? 'Em breve' : 'Disponivel',
                bloqueado,
              ),
              _miniChip(
                context,
                Icons.article_rounded,
                'Estudo ${estudo.numero.toString().padLeft(3, '0')}',
              ),
              _miniChip(
                context,
                Icons.swap_vert_rounded,
                'Ordem ${estudo.ordem}',
              ),
              if (concluido)
                _statusChip(context, 'Concluido', false)
              else if (iniciado)
                _miniChip(
                  context,
                  Icons.play_circle_outline_rounded,
                  'Iniciado',
                ),
              if (estudo.duracaoEstimadaMin > 0)
                _miniChip(
                  context,
                  Icons.schedule_rounded,
                  '${estudo.duracaoEstimadaMin} min',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            estudo.titulo.isEmpty ? 'Estudo sem titulo' : estudo.titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              height: 1.12,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (estudo.subtitulo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              estudo.subtitulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (estudo.perguntaPrincipal.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              estudo.perguntaPrincipal,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.primary, fontWeight: FontWeight.w900),
            ),
          ],
          if (estudo.resumo.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              estudo.resumo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: bloqueado ? null : () => _abrirEstudo(estudo),
              icon: Icon(
                bloqueado
                    ? Icons.lock_outline_rounded
                    : Icons.menu_book_rounded,
              ),
              label: Text(bloqueado ? 'Em breve' : 'Ler estudo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capaImagem(
    BuildContext context,
    String url, {
    required double aspectRatio,
  }) {
    final t = context.uai;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Image.network(
          EstudoModel.normalizarImagemUrl(url),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(Icons.image_not_supported_rounded, color: t.textMuted),
          ),
        ),
      ),
    );
  }

  void _abrirEstudo(EstudoModel estudo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalheEstudoScreen(
          ciclo: widget.ciclo,
          estudo: estudo,
          mostrarEmBreve: widget.mostrarEmBreve,
          alunoId: _alunoId,
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

  Widget _estadoCentral({
    required IconData icon,
    required String titulo,
    required String texto,
    Widget? action,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(18),
        child: _mensagemCard(
          context,
          icon: icon,
          titulo: titulo,
          texto: texto,
          action: action,
        ),
      ),
    );
  }

  Widget _mensagemCard(
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
