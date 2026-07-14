import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_gabarito_pergunta_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_perguntas_estudo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/preview_estudo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/pergunta_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_ciclos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/perguntas_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/exclusao_estudos_admin_service.dart';

class DetalheAdminEstudoScreen extends StatefulWidget {
  const DetalheAdminEstudoScreen({super.key, required this.estudo});

  final EstudoModel estudo;

  @override
  State<DetalheAdminEstudoScreen> createState() =>
      _DetalheAdminEstudoScreenState();
}

class _DetalheAdminEstudoScreenState extends State<DetalheAdminEstudoScreen> {
  final EstudosRepository _estudosRepository = EstudosRepository();
  final EstudosCiclosRepository _ciclosRepository = EstudosCiclosRepository();
  final PerguntasEstudosRepository _perguntasRepository =
      PerguntasEstudosRepository();
  final ExclusaoEstudosAdminService _exclusaoService =
      ExclusaoEstudosAdminService();

  bool _salvando = false;
  EstudoModel? _estudoAtualizado;
  final Set<String> _perguntasSelecionadas = <String>{};

  EstudoModel get _estudo => _estudoAtualizado ?? widget.estudo;

  Color _readableOn(Color background) => background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : Colors.white;

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  void _logErro(Object error, StackTrace? stackTrace) {
    if (!kDebugMode) return;
    if (error is FirebaseException) {
      debugPrint(
        'Erro Firebase no detalhe do estudo: code=${error.code} message=${error.message}',
      );
    } else {
      debugPrint('Erro no detalhe do estudo: $error');
    }
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }

  Future<bool?> _confirmar({
    required String titulo,
    required String mensagem,
    required String acao,
  }) {
    final t = context.uai;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text(titulo, style: TextStyle(color: t.textPrimary)),
        content: Text(mensagem, style: TextStyle(color: t.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(acao),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmarExclusaoForte({
    required String titulo,
    required String mensagem,
  }) async {
    final t = context.uai;
    final controller = TextEditingController();
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.surface,
        title: Text(titulo, style: TextStyle(color: t.error)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mensagem, style: TextStyle(color: t.textSecondary)),
            const SizedBox(height: 12),
            const Text('Digite APAGAR para confirmar.'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Confirmação'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: t.error),
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim().toUpperCase() == 'APAGAR',
            ),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Apagar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return resultado == true;
  }

  Future<void> _editarEstudo(List<EstudoCicloModel> ciclos) async {
    final resultado = await showDialog<EstudoModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EstudoFormDialog(ciclos: ciclos, estudo: _estudo),
    );
    if (resultado == null) return;

    setState(() => _salvando = true);
    try {
      await _estudosRepository.atualizarEstudo(resultado);
      if (!mounted) return;
      setState(() => _estudoAtualizado = resultado);
      _mostrarMensagem('Estudo atualizado.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível atualizar o estudo.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _abrirPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewEstudoScreen(estudo: _estudo)),
    );
  }

  Future<void> _duplicarEstudo() async {
    final ok = await _confirmar(
      titulo: 'Duplicar estudo?',
      mensagem: 'A copia nascera como rascunho.',
      acao: 'Duplicar',
    );
    if (ok != true) return;
    setState(() => _salvando = true);
    try {
      await _estudosRepository.duplicarEstudo(_estudo);
      if (mounted) _mostrarMensagem('Estudo duplicado como rascunho.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível duplicar o estudo.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _apagarEstudoCompleto() async {
    final ok = await _confirmarExclusaoForte(
      titulo: 'Apagar estudo?',
      mensagem:
          'Esta ação é irreversível. O estudo, perguntas, gabaritos, tentativas, resultados e progressos relacionados serão apagados.',
    );
    if (!ok) return;
    setState(() => _salvando = true);
    try {
      final resumo = await _exclusaoService.excluir(
        tipo: 'estudo',
        id: _estudo.id,
      );
      if (!mounted) return;
      _mostrarMensagem('Exclusão concluída: ${resumo.textoResumo}');
      Navigator.pop(context);
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível apagar o estudo.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _apagarPergunta(PerguntaEstudoModel pergunta) async {
    final ok = await _confirmarExclusaoForte(
      titulo: 'Apagar pergunta?',
      mensagem:
          'Esta ação é irreversível. A pergunta e o gabarito vinculado serão apagados. Tentativas históricas não são apagadas ao apagar somente a pergunta.',
    );
    if (!ok) return;
    setState(() => _salvando = true);
    try {
      final resumo = await _exclusaoService.excluir(
        tipo: 'pergunta',
        id: pergunta.id,
      );
      if (mounted) {
        _mostrarMensagem('Exclusão concluída: ${resumo.textoResumo}');
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível apagar a pergunta.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _alterarStatusEstudo(String status) async {
    if (_estudo.id.isEmpty || _estudo.status == status) return;
    final ok = await _confirmar(
      titulo: 'Alterar status?',
      mensagem:
          'Alterar status para ${EstudoCicloStatus.label(status)} neste estudo?',
      acao: 'Confirmar',
    );
    if (ok != true) return;
    setState(() => _salvando = true);
    try {
      await _estudosRepository.alterarStatus(_estudo.id, status);
      if (!mounted) return;
      setState(() => _estudoAtualizado = _estudo.copyWith(status: status));
      _mostrarMensagem(
        'Status alterado para ${EstudoCicloStatus.label(status)}.',
      );
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível alterar o status.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _novaPergunta(
    List<EstudoCicloModel> ciclos,
    List<PerguntaEstudoModel> perguntas,
  ) async {
    if (_estudo.id.trim().isEmpty || _estudo.cicloId.trim().isEmpty) {
      _mostrarMensagem('Salve o estudo com ciclo antes de criar perguntas.');
      return;
    }

    final proximaOrdem = perguntas.isEmpty
        ? 1
        : perguntas.map((p) => p.ordem).reduce((a, b) => a > b ? a : b) + 1;
    final pergunta = PerguntaEstudoModel.empty().copyWith(
      cicloId: _estudo.cicloId,
      cicloTituloSnapshot: _estudo.cicloTituloSnapshot,
      estudoId: _estudo.id,
      estudoTituloSnapshot: _estudo.titulo,
      estudoNumeroSnapshot: _estudo.numero,
      tipo: PerguntaEstudoTipo.multiplaEscolha,
      dificuldade: PerguntaEstudoDificuldade.facil,
      peso: 1,
      ordem: proximaOrdem,
      status: PerguntaEstudoStatus.rascunho,
      podeAparecerEmAvaliacao: true,
    );

    await _abrirFormularioPergunta(ciclos, pergunta);
  }

  Future<void> _editarPergunta(
    List<EstudoCicloModel> ciclos,
    PerguntaEstudoModel pergunta,
  ) {
    return _abrirFormularioPergunta(ciclos, pergunta);
  }

  Future<void> _abrirFormularioPergunta(
    List<EstudoCicloModel> ciclos,
    PerguntaEstudoModel pergunta,
  ) async {
    final cicloAtual = ciclos.where((c) => c.id == _estudo.cicloId).toList();
    if (cicloAtual.isEmpty) {
      _mostrarMensagem(
        'Não foi possível carregar o ciclo deste estudo para editar perguntas.',
      );
      return;
    }

    final resultado = await showDialog<PerguntaEstudoModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PerguntaFormDialog(
        ciclos: cicloAtual,
        estudos: [_estudo],
        pergunta: pergunta,
      ),
    );
    if (resultado == null) return;

    setState(() => _salvando = true);
    try {
      if (resultado.id.isEmpty) {
        await _perguntasRepository.criarPergunta(resultado);
        if (mounted) _mostrarMensagem('Pergunta criada neste estudo.');
      } else {
        await _perguntasRepository.atualizarPergunta(resultado);
        if (mounted) _mostrarMensagem('Pergunta atualizada.');
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível salvar a pergunta.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _duplicarPergunta(PerguntaEstudoModel pergunta) async {
    final ok = await _confirmar(
      titulo: 'Duplicar pergunta?',
      mensagem: 'A copia nascera como rascunho e sem gabarito.',
      acao: 'Duplicar',
    );
    if (ok != true) return;
    setState(() => _salvando = true);
    try {
      await _perguntasRepository.duplicarPergunta(pergunta);
      if (mounted) _mostrarMensagem('Pergunta duplicada como rascunho.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível duplicar a pergunta.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  bool _perguntaIncompleta(PerguntaEstudoModel pergunta) {
    return pergunta.cicloId.isEmpty ||
        pergunta.estudoId.isEmpty ||
        pergunta.enunciado.isEmpty ||
        pergunta.ordem <= 0 ||
        pergunta.peso <= 0 ||
        pergunta.alternativasPublicas
                .where((a) => a.texto.trim().isNotEmpty)
                .length <
            2;
  }

  Future<void> _alterarStatusPergunta(
    PerguntaEstudoModel pergunta,
    String status,
  ) async {
    if (pergunta.id.isEmpty || pergunta.status == status) return;
    if (status == PerguntaEstudoStatus.ativa && _perguntaIncompleta(pergunta)) {
      final ok = await _confirmar(
        titulo: 'Ativar pergunta incompleta?',
        mensagem:
            'Esta pergunta ainda parece incompleta. Deseja ativar mesmo assim?',
        acao: 'Ativar',
      );
      if (ok != true) return;
    } else {
      final ok = await _confirmar(
        titulo: 'Alterar status?',
        mensagem:
            'Alterar status para ${PerguntaEstudoStatus.label(status)} nesta pergunta?',
        acao: 'Confirmar',
      );
      if (ok != true) return;
    }
    setState(() => _salvando = true);
    try {
      await _perguntasRepository.alterarStatus(pergunta.id, status);
      if (mounted) {
        _mostrarMensagem(
          'Status alterado para ${PerguntaEstudoStatus.label(status)}.',
        );
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível alterar o status.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _alternarSelecaoPergunta(String perguntaId, bool selecionada) {
    if (perguntaId.isEmpty) return;
    setState(() {
      if (selecionada) {
        _perguntasSelecionadas.add(perguntaId);
      } else {
        _perguntasSelecionadas.remove(perguntaId);
      }
    });
  }

  void _selecionarTodasPerguntas(List<PerguntaEstudoModel> perguntas) {
    setState(() {
      _perguntasSelecionadas
        ..clear()
        ..addAll(
          perguntas
              .map((pergunta) => pergunta.id)
              .where((id) => id.trim().isNotEmpty),
        );
    });
  }

  void _limparSelecaoPerguntas() {
    if (_perguntasSelecionadas.isEmpty) return;
    setState(_perguntasSelecionadas.clear);
  }

  Future<void> _alterarStatusPerguntasSelecionadas(
    List<PerguntaEstudoModel> perguntas,
    String status,
  ) async {
    final selecionadas = perguntas
        .where((pergunta) => _perguntasSelecionadas.contains(pergunta.id))
        .where(
          (pergunta) =>
              pergunta.status != status ||
              status == PerguntaEstudoStatus.rascunho,
        )
        .toList(growable: false);
    if (selecionadas.isEmpty) {
      _mostrarMensagem('Nenhuma pergunta selecionada precisa desta alteração.');
      return;
    }

    final incompletas = status == PerguntaEstudoStatus.ativa
        ? selecionadas.where(_perguntaIncompleta).toList(growable: false)
        : const <PerguntaEstudoModel>[];
    final mensagemBase =
        '${PerguntaEstudoStatus.label(status)} ${selecionadas.length} pergunta(s) selecionada(s)?';
    final mensagem = incompletas.isEmpty
        ? mensagemBase
        : '$mensagemBase ${incompletas.length} pergunta(s) parecem incompletas e seguirão a mesma regra da ativação individual.';
    final ok = await _confirmar(
      titulo: 'Alterar perguntas selecionadas?',
      mensagem: mensagem,
      acao: 'Confirmar',
    );
    if (ok != true) return;

    setState(() => _salvando = true);
    try {
      for (final pergunta in selecionadas) {
        await _perguntasRepository.alterarStatus(pergunta.id, status);
      }
      if (!mounted) return;
      setState(_perguntasSelecionadas.clear);
      _mostrarMensagem(
        '${selecionadas.length} perguntas atualizadas com sucesso.',
      );
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) {
        _mostrarMensagem(
          'Não foi possível atualizar as perguntas selecionadas.',
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _abrirGabarito(PerguntaEstudoModel pergunta) {
    if (pergunta.id.trim().isEmpty) {
      _mostrarMensagem('Salve a pergunta antes de cadastrar gabarito.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GerenciarGabaritoPerguntaScreen(pergunta: pergunta),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Detalhe do estudo',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor: _readableOn(
          Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        ),
      ),
      body: StreamBuilder<List<EstudoCicloModel>>(
        stream: _ciclosRepository.watchCiclosAdmin(),
        builder: (context, ciclosSnapshot) {
          if (ciclosSnapshot.hasError) return _erro(ciclosSnapshot.error);
          if (!ciclosSnapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }
          final ciclos = ciclosSnapshot.data ?? const <EstudoCicloModel>[];
          return StreamBuilder<List<PerguntaEstudoModel>>(
            stream: _perguntasRepository.watchPerguntasPorEstudo(_estudo.id),
            builder: (context, perguntasSnapshot) {
              if (perguntasSnapshot.hasError) {
                return _erro(perguntasSnapshot.error);
              }
              if (!perguntasSnapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: t.primary),
                );
              }
              final perguntas =
                  perguntasSnapshot.data ?? const <PerguntaEstudoModel>[];
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                  16,
                  MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                  96,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _estudoHeader(ciclos),
                          const SizedBox(height: 12),
                          _perguntasHeader(ciclos, perguntas),
                          const SizedBox(height: 10),
                          if (perguntas.isEmpty)
                            _mensagemCard(
                              icon: Icons.quiz_rounded,
                              titulo: 'Nenhuma pergunta neste estudo.',
                              texto:
                                  'Crie perguntas ja vinculadas a este estudo.',
                            )
                          else
                            ...perguntas.map(
                              (pergunta) => _perguntaCard(ciclos, pergunta),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _estudoHeader(List<EstudoCicloModel> ciclos) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _statusChip(_estudo.status),
              _miniChip(Icons.timeline_rounded, _estudo.cicloTituloSnapshot),
              _miniChip(
                Icons.tag_rounded,
                'Estudo ${_estudo.numero.toString().padLeft(3, '0')}',
              ),
              _miniChip(Icons.swap_vert_rounded, 'Ordem ${_estudo.ordem}'),
              if (_estudo.duracaoEstimadaMin > 0)
                _miniChip(
                  Icons.schedule_rounded,
                  '${_estudo.duracaoEstimadaMin} min',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _estudo.titulo.isEmpty ? 'Estudo sem título' : _estudo.titulo,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 22,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (_estudo.subtitulo.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              _estudo.subtitulo,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (_estudo.resumo.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _estudo.resumo,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                Icons.open_in_new_rounded,
                'Abrir preview',
                _salvando ? null : _abrirPreview,
              ),
              _actionButton(
                Icons.edit_rounded,
                'Editar',
                _salvando ? null : () => _editarEstudo(ciclos),
              ),
              _actionButton(
                Icons.copy_rounded,
                'Duplicar',
                _salvando ? null : _duplicarEstudo,
              ),
              _actionButton(
                Icons.delete_forever_rounded,
                'Apagar estudo',
                _salvando ? null : _apagarEstudoCompleto,
                danger: true,
              ),
              for (final status in EstudoCicloStatus.values)
                if (_estudo.status != status)
                  _actionButton(
                    _statusIcon(status),
                    EstudoCicloStatus.label(status),
                    _salvando ? null : () => _alterarStatusEstudo(status),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _perguntasHeader(
    List<EstudoCicloModel> ciclos,
    List<PerguntaEstudoModel> perguntas,
  ) {
    final t = context.uai;
    final selecionadas = _perguntasSelecionadas.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                selecionadas > 0
                    ? '$selecionadas perguntas selecionadas'
                    : '${perguntas.length} perguntas vinculadas',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (selecionadas == 0) ...[
                OutlinedButton.icon(
                  onPressed: perguntas.isEmpty || _salvando
                      ? null
                      : () => _selecionarTodasPerguntas(perguntas),
                  icon: const Icon(Icons.checklist_rounded),
                  label: const Text('Selecionar perguntas'),
                ),
                FilledButton.icon(
                  onPressed: _salvando
                      ? null
                      : () => _novaPergunta(ciclos, perguntas),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nova pergunta neste estudo'),
                ),
              ],
            ],
          ),
          if (selecionadas > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _batchButton(
                  Icons.select_all_rounded,
                  'Selecionar todas',
                  _salvando ? null : () => _selecionarTodasPerguntas(perguntas),
                ),
                _batchButton(
                  Icons.clear_rounded,
                  'Limpar seleção',
                  _salvando ? null : _limparSelecaoPerguntas,
                ),
                _batchButton(
                  Icons.check_circle_rounded,
                  'Ativar selecionadas',
                  _salvando
                      ? null
                      : () => _alterarStatusPerguntasSelecionadas(
                          perguntas,
                          PerguntaEstudoStatus.ativa,
                        ),
                ),
                _batchButton(
                  Icons.visibility_off_rounded,
                  'Desativar selecionadas',
                  _salvando
                      ? null
                      : () => _alterarStatusPerguntasSelecionadas(
                          perguntas,
                          PerguntaEstudoStatus.inativa,
                        ),
                ),
                _batchButton(
                  Icons.edit_note_rounded,
                  'Rascunho selecionadas',
                  _salvando
                      ? null
                      : () => _alterarStatusPerguntasSelecionadas(
                          perguntas,
                          PerguntaEstudoStatus.rascunho,
                        ),
                ),
                _batchButton(
                  Icons.archive_rounded,
                  'Arquivar selecionadas',
                  _salvando
                      ? null
                      : () => _alterarStatusPerguntasSelecionadas(
                          perguntas,
                          PerguntaEstudoStatus.arquivada,
                        ),
                  danger: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _perguntaCard(
    List<EstudoCicloModel> ciclos,
    PerguntaEstudoModel pergunta,
  ) {
    final t = context.uai;
    final selecionada = _perguntasSelecionadas.contains(pergunta.id);
    final emModoSelecao = _perguntasSelecionadas.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selecionada
            ? Color.alphaBlend(t.primary.withValues(alpha: 0.08), t.card)
            : t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(
          color: selecionada ? t.primary.withValues(alpha: 0.45) : t.border,
        ),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selecionada,
                onChanged: _salvando
                    ? null
                    : (value) =>
                          _alternarSelecaoPergunta(pergunta.id, value ?? false),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _statusChip(pergunta.status),
                    _miniChip(
                      Icons.category_rounded,
                      PerguntaEstudoTipo.label(pergunta.tipo),
                    ),
                    _miniChip(
                      Icons.signal_cellular_alt_rounded,
                      PerguntaEstudoDificuldade.label(pergunta.dificuldade),
                    ),
                    _miniChip(Icons.score_rounded, 'Peso ${pergunta.peso}'),
                    _miniChip(
                      Icons.swap_vert_rounded,
                      'Ordem ${pergunta.ordem}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            pergunta.enunciado.isEmpty
                ? 'Pergunta sem enunciado'
                : pergunta.enunciado,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (!emModoSelecao) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  Icons.edit_rounded,
                  'Editar',
                  _salvando ? null : () => _editarPergunta(ciclos, pergunta),
                ),
                _actionButton(
                  Icons.key_rounded,
                  'Gabarito',
                  _salvando ? null : () => _abrirGabarito(pergunta),
                ),
                _actionButton(
                  Icons.copy_rounded,
                  'Duplicar',
                  _salvando ? null : () => _duplicarPergunta(pergunta),
                ),
                _actionButton(
                  Icons.delete_forever_rounded,
                  'Apagar',
                  _salvando ? null : () => _apagarPergunta(pergunta),
                  danger: true,
                ),
                for (final status in PerguntaEstudoStatus.values)
                  if (pergunta.status != status)
                    _actionButton(
                      _statusIcon(status),
                      PerguntaEstudoStatus.label(status),
                      _salvando
                          ? null
                          : () => _alterarStatusPergunta(pergunta, status),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _batchButton(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool danger = false,
  }) {
    final t = context.uai;
    final color = danger ? t.error : t.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: danger ? t.error : t.border),
      ),
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool danger = false,
  }) {
    final t = context.uai;
    final color = danger ? t.error : t.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: danger ? t.error : t.border),
      ),
    );
  }

  Widget _miniChip(IconData icon, String label) {
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
          Icon(icon, color: t.primary, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final t = context.uai;
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.11), t.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        EstudoCicloStatus.isValid(status)
            ? EstudoCicloStatus.label(status)
            : PerguntaEstudoStatus.label(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    final t = context.uai;
    switch (status) {
      case EstudoCicloStatus.publicado:
      case PerguntaEstudoStatus.ativa:
        return t.success;
      case EstudoCicloStatus.emBreve:
        return t.info;
      case EstudoCicloStatus.oculto:
      case PerguntaEstudoStatus.inativa:
        return t.warning;
      case EstudoCicloStatus.arquivado:
      case PerguntaEstudoStatus.arquivada:
        return t.error;
      default:
        return t.textMuted;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case EstudoCicloStatus.publicado:
      case PerguntaEstudoStatus.ativa:
        return Icons.check_circle_rounded;
      case EstudoCicloStatus.emBreve:
        return Icons.hourglass_empty_rounded;
      case EstudoCicloStatus.oculto:
      case PerguntaEstudoStatus.inativa:
        return Icons.visibility_off_rounded;
      case EstudoCicloStatus.arquivado:
      case PerguntaEstudoStatus.arquivada:
        return Icons.archive_rounded;
      default:
        return Icons.edit_note_rounded;
    }
  }

  Widget _mensagemCard({
    required IconData icon,
    required String titulo,
    required String texto,
  }) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: t.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(texto, style: TextStyle(color: t.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _erro(Object? error) {
    final t = context.uai;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Text(
          'Não foi possível carregar: $error',
          style: TextStyle(color: t.error, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
