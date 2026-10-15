import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudos_config_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/pergunta_avaliacao_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/resultado_tentativa_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/screens/resultado_estudo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/avaliacao_estudos_service.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/theme/estudos_aluno_theme.dart';

class ResponderEstudoScreen extends StatefulWidget {
  final String alunoId;
  final String estudoId;
  final String cicloId;
  final String estudoTitulo;
  final String cicloTitulo;
  final bool permitirTentarNovamente;
  final EstudosConfigModel? config;

  const ResponderEstudoScreen({
    super.key,
    required this.alunoId,
    required this.estudoId,
    required this.cicloId,
    required this.estudoTitulo,
    required this.cicloTitulo,
    this.permitirTentarNovamente = true,
    this.config,
  });

  @override
  State<ResponderEstudoScreen> createState() => _ResponderEstudoScreenState();
}

class _ResponderEstudoScreenState extends State<ResponderEstudoScreen> {
  final AvaliacaoEstudosService _service = AvaliacaoEstudosService();
  final Map<String, String> _selecoes = {};
  late Future<PerguntasEstudoAvaliacaoResult> _futurePerguntas;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _futurePerguntas = _carregarPerguntas();
  }

  Future<PerguntasEstudoAvaliacaoResult> _carregarPerguntas() {
    return _service.buscarPerguntasEstudo(
      alunoId: widget.alunoId,
      estudoId: widget.estudoId,
    );
  }

  void _recarregar() {
    setState(() {
      _selecoes.clear();
      _futurePerguntas = _carregarPerguntas();
    });
  }

  Future<void> _enviar(List<PerguntaAvaliacaoEstudoModel> perguntas) async {
    if (_enviando) return;

    final objetivas = perguntas
        .where((pergunta) => pergunta.isSelecaoUnica)
        .toList();
    final semResposta = objetivas
        .where((pergunta) => (_selecoes[pergunta.perguntaId] ?? '').isEmpty)
        .toList();
    final naoSuportadas = perguntas
        .where((pergunta) => !pergunta.isSelecaoUnica)
        .toList();

    if (naoSuportadas.isNotEmpty) {
      _mostrarMensagem(
        'Esta atividade tem um tipo de pergunta que ainda não é suportado no app.',
      );
      return;
    }
    if (semResposta.isNotEmpty) {
      _mostrarMensagem('Responda todas as perguntas antes de enviar.');
      return;
    }

    setState(() => _enviando = true);
    try {
      final resultado = await _service.finalizarTentativaEstudo(
        alunoId: widget.alunoId,
        estudoId: widget.estudoId,
        clientAttemptId: _gerarClientAttemptId(),
        respostas: objetivas
            .map(
              (pergunta) => {
                'perguntaId': pergunta.perguntaId,
                'alternativaSelecionadaId': _selecoes[pergunta.perguntaId],
              },
            )
            .toList(),
      );
      if (!mounted) return;
      _abrirResultado(resultado);
    } on FirebaseFunctionsException catch (e) {
      _logFunctionError('finalizarTentativaEstudo', e);
      if (!mounted) return;
      _mostrarMensagem(_mensagemFunction(e));
    } catch (e, stack) {
      debugPrint('finalizarTentativaEstudo erro inesperado: $e');
      debugPrint('finalizarTentativaEstudo stack: $stack');
      if (!mounted) return;
      _mostrarMensagem('Não foi possível enviar a atividade. Tente novamente.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _gerarClientAttemptId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const maxRandom = 999999999;
    int randomValue;
    try {
      randomValue = Random.secure().nextInt(maxRandom);
    } catch (_) {
      randomValue = Random().nextInt(maxRandom);
    }
    final randomText = randomValue.toString().padLeft(9, '0');
    return 'tentativa_${timestamp}_$randomText';
  }

  void _abrirResultado(ResultadoTentativaEstudoModel resultado) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultadoEstudoScreen(
          estudoTitulo: widget.estudoTitulo,
          resultado: resultado,
          permitirTentarNovamente: widget.permitirTentarNovamente,
          config: widget.config,
          tentarNovamenteBuilder: widget.permitirTentarNovamente
              ? (_) => ResponderEstudoScreen(
                  alunoId: widget.alunoId,
                  estudoId: widget.estudoId,
                  cicloId: widget.cicloId,
                  estudoTitulo: widget.estudoTitulo,
                  cicloTitulo: widget.cicloTitulo,
                  permitirTentarNovamente: widget.permitirTentarNovamente,
                  config: widget.config,
                )
              : null,
        ),
      ),
    );
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  void _logFunctionError(
    String functionName,
    FirebaseFunctionsException error,
  ) {
    debugPrint('$functionName FirebaseFunctionsException code: ${error.code}');
    debugPrint(
      '$functionName FirebaseFunctionsException message: ${error.message}',
    );
    debugPrint(
      '$functionName FirebaseFunctionsException details: ${error.details}',
    );
  }

  String _mensagemFunction(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Entre novamente na sua Conta UAI para enviar a atividade.';
      case 'permission-denied':
        return 'Seu acesso de aluno não foi confirmado para esta atividade.';
      case 'failed-precondition':
        return 'Esta atividade ainda não está pronta para correção. Confira se todas as perguntas têm gabarito ativo.';
      case 'invalid-argument':
        return 'Alguma resposta está inválida. Recarregue a atividade e tente novamente.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Falha de conexão com o servidor. Tente novamente.';
      case 'not-found':
        return 'Não encontramos este estudo ou aluno.';
      default:
        return 'Não foi possível concluir a atividade. Tente novamente.';
    }
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
                widget.estudoTitulo.isEmpty ? 'Atividade' : widget.estudoTitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              actions: [
                IconButton(
                  onPressed: _enviando ? null : _recarregar,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Atualizar',
                ),
              ],
            ),
            body: FutureBuilder<PerguntasEstudoAvaliacaoResult>(
              future: _futurePerguntas,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: t.primary),
                  );
                }
                if (snapshot.hasError) {
                  return _estadoCentral(
                    context,
                    icon: Icons.error_outline_rounded,
                    titulo: 'Não foi possível carregar as perguntas.',
                    texto: snapshot.error is FirebaseFunctionsException
                        ? _mensagemFunction(
                            snapshot.error! as FirebaseFunctionsException,
                          )
                        : 'Verifique sua conexão e tente novamente.',
                    action: OutlinedButton.icon(
                      onPressed: _recarregar,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  );
                }

                final result = snapshot.data;
                final perguntas =
                    result?.perguntas ?? const <PerguntaAvaliacaoEstudoModel>[];
                if (perguntas.isEmpty) {
                  return _estadoCentral(
                    context,
                    icon: Icons.assignment_outlined,
                    titulo: 'Nenhuma pergunta disponível.',
                    texto:
                        'Este estudo ainda não possui perguntas liberadas para resposta.',
                    action: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Voltar ao estudo'),
                    ),
                  );
                }

                return _conteudo(context, perguntas);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _conteudo(
    BuildContext context,
    List<PerguntaAvaliacaoEstudoModel> perguntas,
  ) {
    final t = context.uai;
    final respondidas = perguntas
        .where((pergunta) => (_selecoes[pergunta.perguntaId] ?? '').isNotEmpty)
        .length;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _cabecalho(context, respondidas, perguntas.length),
              const SizedBox(height: 12),
              _avisoEducativo(context),
              const SizedBox(height: 12),
              ...perguntas.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _perguntaCard(context, entry.key, entry.value),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _enviando ? null : () => _enviar(perguntas),
                icon: _enviando
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_enviando ? 'Enviando...' : 'Enviar respostas'),
              ),
              const SizedBox(height: 8),
              Text(
                'A correção oficial será feita no servidor.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avisoEducativo(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.accent.withValues(alpha: 0.12), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.psychology_alt_rounded, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tente responder primeiro com o que você aprendeu aqui. Isso fortalece sua memória, sua atenção e sua compreensão da Capoeira.',
              style: TextStyle(
                color: t.textPrimary,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho(BuildContext context, int respondidas, int total) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.quiz_rounded, color: t.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.cicloTitulo.isEmpty
                      ? 'Atividade do estudo'
                      : widget.cicloTitulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$respondidas de $total perguntas respondidas',
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
    );
  }

  Widget _perguntaCard(
    BuildContext context,
    int index,
    PerguntaAvaliacaoEstudoModel pergunta,
  ) {
    final t = context.uai;
    final selected = _selecoes[pergunta.perguntaId];
    final suportada = pergunta.isSelecaoUnica;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: t.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pergunta.enunciado.isEmpty ? 'Pergunta' : pergunta.enunciado,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!suportada)
            _tipoNaoSuportado(context)
          else if (pergunta.alternativasPublicas.isEmpty)
            _semAlternativas(context)
          else
            ...pergunta.alternativasPublicas.map((alternativa) {
              final selecionada = selected == alternativa.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(t.cardRadius),
                  onTap: _enviando
                      ? null
                      : () => setState(
                          () => _selecoes[pergunta.perguntaId] = alternativa.id,
                        ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selecionada
                          ? Color.alphaBlend(
                              t.accent.withValues(alpha: 0.16),
                              t.cardAlt,
                            )
                          : t.cardAlt,
                      borderRadius: BorderRadius.circular(t.cardRadius),
                      border: Border.all(
                        color: selecionada ? t.accent : t.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: selecionada
                              ? t.accent.withValues(alpha: 0.18)
                              : t.surface,
                          child: Text(
                            alternativa.displayLabel,
                            style: TextStyle(
                              color: selecionada ? t.accent : t.textSecondary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            alternativa.texto.isEmpty
                                ? alternativa.displayLabel
                                : alternativa.texto,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          selecionada
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selecionada ? t.accent : t.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _tipoNaoSuportado(BuildContext context) {
    return _avisoPergunta(
      context,
      icon: Icons.block_rounded,
      texto: 'Tipo de pergunta ainda não suportado no app.',
    );
  }

  Widget _semAlternativas(BuildContext context) {
    return _avisoPergunta(
      context,
      icon: Icons.warning_amber_rounded,
      texto: 'Pergunta sem alternativas disponíveis.',
    );
  }

  Widget _avisoPergunta(
    BuildContext context, {
    required IconData icon,
    required String texto,
  }) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.warning.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.warning.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
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

  Widget _estadoCentral(
    BuildContext context, {
    required IconData icon,
    required String titulo,
    required String texto,
    Widget? action,
  }) {
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
            Icon(icon, color: t.textMuted, size: 52),
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
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }
}
