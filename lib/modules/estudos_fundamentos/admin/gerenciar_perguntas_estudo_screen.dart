import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_gabarito_pergunta_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/importar_ciclo_completo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/pergunta_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_ciclos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/perguntas_estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/exclusao_estudos_admin_service.dart';

enum _PerguntasSortOption { vinculoOrdem, atualizado, dificuldade }

class GerenciarPerguntasEstudoScreen extends StatefulWidget {
  const GerenciarPerguntasEstudoScreen({super.key});

  @override
  State<GerenciarPerguntasEstudoScreen> createState() =>
      _GerenciarPerguntasEstudoScreenState();
}

class _GerenciarPerguntasEstudoScreenState
    extends State<GerenciarPerguntasEstudoScreen> {
  final PerguntasEstudosRepository _repository = PerguntasEstudosRepository();
  final ExclusaoEstudosAdminService _exclusaoService =
      ExclusaoEstudosAdminService();
  final EstudosCiclosRepository _ciclosRepository = EstudosCiclosRepository();
  final EstudosRepository _estudosRepository = EstudosRepository();
  final TextEditingController _buscaController = TextEditingController();

  String _statusFiltro = 'todos';
  String _tipoFiltro = 'todos';
  String _cicloFiltro = 'todos';
  String _estudoFiltro = 'todos';
  _PerguntasSortOption _sort = _PerguntasSortOption.vinculoOrdem;
  bool _salvando = false;
  int _reloadKey = 0;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _recarregar() => setState(() => _reloadKey++);

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  void _logErro(Object error, StackTrace? stackTrace) {
    if (!kDebugMode) return;
    if (error is FirebaseException) {
      debugPrint(
        'Erro Firebase em perguntas: code=${error.code} message=${error.message}',
      );
    } else {
      debugPrint('Erro em perguntas: $error');
    }
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }

  Color _readableOn(Color background) => background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : Colors.white;

  Future<void> _abrirFormulario(
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudos, [
    PerguntaEstudoModel? pergunta,
  ]) async {
    if (ciclos.isEmpty || estudos.isEmpty) {
      _mostrarMensagem(
        'Cadastre pelo menos um ciclo e um estudo antes de criar perguntas.',
      );
      return;
    }
    final resultado = await showDialog<PerguntaEstudoModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PerguntaFormDialog(
        ciclos: ciclos,
        estudos: estudos,
        pergunta: pergunta,
      ),
    );
    if (resultado == null) return;
    setState(() => _salvando = true);
    try {
      if (resultado.id.isEmpty) {
        await _repository.criarPergunta(resultado);
        if (mounted) _mostrarMensagem('Pergunta criada sem gabarito.');
      } else {
        await _repository.atualizarPergunta(resultado);
        if (mounted) _mostrarMensagem('Pergunta atualizada.');
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível salvar a pergunta.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _alterarStatus(
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
    }
    if (status == PerguntaEstudoStatus.arquivada) {
      final ok = await _confirmar(
        titulo: 'Arquivar pergunta?',
        mensagem: 'A pergunta ficara guardada no admin.',
        acao: 'Arquivar',
      );
      if (ok != true) return;
    }
    setState(() => _salvando = true);
    try {
      await _repository.alterarStatus(pergunta.id, status);
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

  Future<void> _duplicar(PerguntaEstudoModel pergunta) async {
    final ok = await _confirmar(
      titulo: 'Duplicar pergunta?',
      mensagem: 'A copia nascera como rascunho e sem gabarito.',
      acao: 'Duplicar',
    );
    if (ok != true) return;
    setState(() => _salvando = true);
    try {
      await _repository.duplicarPergunta(pergunta);
      if (mounted) _mostrarMensagem('Pergunta duplicada como rascunho.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível duplicar a pergunta.');
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

  void _abrirImportarPerguntasNesteEstudo(
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudos,
  ) {
    if (_cicloFiltro == 'todos' || _estudoFiltro == 'todos') {
      _mostrarMensagem(
        'Selecione ciclo e estudo nos filtros antes de importar perguntas.',
      );
      return;
    }
    final ciclo = ciclos.where((c) => c.id == _cicloFiltro).toList();
    final estudo = estudos.where((e) => e.id == _estudoFiltro).toList();
    if (ciclo.isEmpty || estudo.isEmpty) {
      _mostrarMensagem('Ciclo ou estudo selecionado nao encontrado.');
      return;
    }
    final c = ciclo.first;
    final e = estudo.first;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImportarCicloCompletoScreen(
          modoInicial: 'estudo_existente',
          cicloId: c.id,
          cicloNumero: c.numero,
          cicloTitulo: c.titulo,
          estudoId: e.id,
          estudoNumero: e.numero,
          estudoTitulo: e.titulo,
        ),
      ),
    );
  }

  void _abrirGabarito(PerguntaEstudoModel pergunta) {
    if (pergunta.id.trim().isEmpty) {
      _mostrarMensagem(
        'Pergunta sem id. Salve a pergunta antes de cadastrar gabarito.',
      );
      return;
    }
    if (pergunta.estudoId.trim().isEmpty || pergunta.cicloId.trim().isEmpty) {
      _mostrarMensagem('Pergunta sem ciclo ou estudo. Corrija a pergunta.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GerenciarGabaritoPerguntaScreen(pergunta: pergunta),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Gerenciar perguntas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor: _readableOn(
          Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        ),
        actions: [
          IconButton(
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: StreamBuilder<List<EstudoCicloModel>>(
        key: ValueKey(_reloadKey),
        stream: _ciclosRepository.watchCiclosAdmin(),
        builder: (context, ciclosSnapshot) {
          if (ciclosSnapshot.hasError) return _buildErro(ciclosSnapshot.error);
          if (!ciclosSnapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }
          final ciclos = ciclosSnapshot.data ?? const <EstudoCicloModel>[];
          return StreamBuilder<List<EstudoModel>>(
            stream: _estudosRepository.watchEstudosAdmin(),
            builder: (context, estudosSnapshot) {
              if (estudosSnapshot.hasError) {
                return _buildErro(estudosSnapshot.error);
              }
              if (!estudosSnapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: t.primary),
                );
              }
              final estudos = estudosSnapshot.data ?? const <EstudoModel>[];
              if (ciclos.isEmpty || estudos.isEmpty) {
                return _buildMensagemCentral(
                  icon: Icons.quiz_rounded,
                  titulo: 'Crie ciclo e estudo antes de cadastrar perguntas.',
                  texto:
                      'Perguntas de avaliação precisam estar vinculadas a um estudo.',
                );
              }
              return StreamBuilder<List<PerguntaEstudoModel>>(
                stream: _repository.watchPerguntasAdmin(),
                builder: (context, perguntasSnapshot) {
                  if (perguntasSnapshot.hasError) {
                    return _buildErro(perguntasSnapshot.error);
                  }
                  if (!perguntasSnapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: t.primary),
                    );
                  }
                  final perguntas =
                      perguntasSnapshot.data ?? const <PerguntaEstudoModel>[];
                  final filtradas = _filtrarOrdenar(perguntas);
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
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(perguntas),
                              const SizedBox(height: 12),
                              _buildFerramentas(ciclos, estudos),
                              const SizedBox(height: 12),
                              if (perguntas.isEmpty)
                                _buildMensagemCard(
                                  icon: Icons.quiz_rounded,
                                  titulo: 'Nenhuma pergunta cadastrada.',
                                  texto:
                                      'Crie perguntas públicas de avaliação, ainda sem gabarito.',
                                  action: FilledButton.icon(
                                    onPressed: _salvando
                                        ? null
                                        : () =>
                                              _abrirFormulario(ciclos, estudos),
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Nova pergunta'),
                                  ),
                                )
                              else if (filtradas.isEmpty)
                                _buildMensagemCard(
                                  icon: Icons.search_off_rounded,
                                  titulo: 'Nenhuma pergunta encontrada.',
                                  texto: 'Ajuste filtros ou busca.',
                                )
                              else
                                ...filtradas.map(
                                  (pergunta) => _buildPerguntaCard(
                                    pergunta,
                                    ciclos,
                                    estudos,
                                  ),
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
          );
        },
      ),
    );
  }

  List<PerguntaEstudoModel> _filtrarOrdenar(
    List<PerguntaEstudoModel> perguntas,
  ) {
    final termo = _buscaController.text.trim().toLowerCase();
    final filtradas = perguntas.where((p) {
      if (_statusFiltro != 'todos' && p.status != _statusFiltro) return false;
      if (_tipoFiltro != 'todos' && p.tipo != _tipoFiltro) return false;
      if (_cicloFiltro != 'todos' && p.cicloId != _cicloFiltro) return false;
      if (_estudoFiltro != 'todos' && p.estudoId != _estudoFiltro) return false;
      if (termo.isEmpty) return true;
      final texto =
          '${p.enunciado} ${p.tags.join(' ')} ${p.cicloTituloSnapshot} ${p.estudoTituloSnapshot}'
              .toLowerCase();
      return texto.contains(termo);
    }).toList();
    filtradas.sort((a, b) {
      switch (_sort) {
        case _PerguntasSortOption.atualizado:
          final ad = a.atualizadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.atualizadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        case _PerguntasSortOption.dificuldade:
          final d = a.dificuldade.compareTo(b.dificuldade);
          if (d != 0) return d;
          return a.ordem.compareTo(b.ordem);
        case _PerguntasSortOption.vinculoOrdem:
          final ciclo = a.cicloTituloSnapshot.compareTo(b.cicloTituloSnapshot);
          if (ciclo != 0) return ciclo;
          final estudo = a.estudoNumeroSnapshot.compareTo(
            b.estudoNumeroSnapshot,
          );
          if (estudo != 0) return estudo;
          return a.ordem.compareTo(b.ordem);
      }
    });
    return filtradas;
  }

  Widget _buildHeader(List<PerguntaEstudoModel> perguntas) {
    final t = context.uai;
    final resumo = PerguntasResumo.fromPerguntas(perguntas);
    final onPrimary = _readableOn(t.primary);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 4),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: onPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(t.cardRadius),
                ),
                child: Icon(Icons.quiz_rounded, color: onPrimary, size: 32),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Perguntas de Avaliacao',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Cadastre perguntas publicas vinculadas aos estudos. Gabarito fica para fase futura protegida.',
                      style: TextStyle(
                        color: onPrimary.withValues(alpha: 0.84),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _headerMetric('Total', resumo.total.toString(), onPrimary),
              _headerMetric('Ativas', resumo.ativas.toString(), onPrimary),
              _headerMetric(
                'Rascunhos',
                resumo.rascunhos.toString(),
                onPrimary,
              ),
              _headerMetric('Inativas', resumo.inativas.toString(), onPrimary),
              _headerMetric(
                'Arquivadas',
                resumo.arquivadas.toString(),
                onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerMetric(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.16)),
    ),
    child: Text(
      '$value $label',
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900),
    ),
  );
  Widget _buildFerramentas(
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudos,
  ) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _salvando
                    ? null
                    : () => _abrirFormulario(ciclos, estudos),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nova pergunta'),
              ),
              OutlinedButton.icon(
                onPressed: _salvando
                    ? null
                    : () => _abrirImportarPerguntasNesteEstudo(ciclos, estudos),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Importar perguntas neste estudo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscaController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Buscar por enunciado, tag, ciclo ou estudo',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip('todos', 'Todos'),
              _filterChip(PerguntaEstudoStatus.ativa, 'Ativas'),
              _filterChip(PerguntaEstudoStatus.rascunho, 'Rascunhos'),
              _filterChip(PerguntaEstudoStatus.inativa, 'Inativas'),
              _filterChip(PerguntaEstudoStatus.arquivada, 'Arquivadas'),
              _tipoMenu(),
              _cicloMenu(ciclos),
              _estudoMenu(estudos),
              _sortMenu(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final t = context.uai;
    return FilterChip(
      selected: _statusFiltro == value,
      label: Text(label),
      selectedColor: Color.alphaBlend(
        t.primary.withValues(alpha: 0.16),
        t.card,
      ),
      checkmarkColor: t.primary,
      onSelected: (_) => setState(() => _statusFiltro = value),
    );
  }

  Widget _tipoMenu() => _popup<String>(
    Icons.category_rounded,
    _tipoFiltro == 'todos' ? 'Tipo' : PerguntaEstudoTipo.label(_tipoFiltro),
    ['todos', ...PerguntaEstudoTipo.values],
    (v) => v == 'todos' ? 'Todos os tipos' : PerguntaEstudoTipo.label(v),
    (v) => setState(() => _tipoFiltro = v),
  );
  Widget _cicloMenu(List<EstudoCicloModel> ciclos) => _popup<String>(
    Icons.timeline_rounded,
    _cicloFiltro == 'todos' ? 'Ciclo' : 'Ciclo filtrado',
    ['todos', ...ciclos.map((c) => c.id)],
    (v) => v == 'todos'
        ? 'Todos os ciclos'
        : ciclos.firstWhere((c) => c.id == v).titulo,
    (v) => setState(() {
      _cicloFiltro = v;
      _estudoFiltro = 'todos';
    }),
  );
  Widget _estudoMenu(List<EstudoModel> estudos) {
    final filtrados = _cicloFiltro == 'todos'
        ? estudos
        : estudos.where((e) => e.cicloId == _cicloFiltro).toList();
    return _popup<String>(
      Icons.article_rounded,
      _estudoFiltro == 'todos' ? 'Estudo' : 'Estudo filtrado',
      ['todos', ...filtrados.map((e) => e.id)],
      (v) => v == 'todos'
          ? 'Todos os estudos'
          : filtrados.firstWhere((e) => e.id == v).titulo,
      (v) => setState(() => _estudoFiltro = v),
    );
  }

  Widget _sortMenu() => _popup<_PerguntasSortOption>(
    Icons.sort_rounded,
    'Ordenacao',
    _PerguntasSortOption.values,
    (v) => switch (v) {
      _PerguntasSortOption.atualizado => 'Ordenar por atualizado',
      _PerguntasSortOption.dificuldade => 'Ordenar por dificuldade',
      _ => 'Ordenar por ciclo/estudo/ordem',
    },
    (v) => setState(() => _sort = v),
  );

  Widget _popup<T>(
    IconData icon,
    String label,
    List<T> values,
    String Function(T) text,
    ValueChanged<T> onSelected,
  ) {
    final t = context.uai;
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (_) => values
          .map((v) => PopupMenuItem(value: v, child: Text(text(v))))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: t.cardAlt,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: t.primary, size: 17),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: t.primary, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerguntaCard(
    PerguntaEstudoModel pergunta,
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudos,
  ) {
    final t = context.uai;
    final updated = pergunta.atualizadoEm == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(pergunta.atualizadoEm!);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
              _miniChip(Icons.swap_vert_rounded, 'Ordem ${pergunta.ordem}'),
              if (updated.isNotEmpty) _miniChip(Icons.update_rounded, updated),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            pergunta.enunciado.isEmpty
                ? 'Pergunta sem enunciado'
                : pergunta.enunciado,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 17,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${pergunta.cicloTituloSnapshot} > Estudo ${pergunta.estudoNumeroSnapshot.toString().padLeft(3, '0')} - ${pergunta.estudoTituloSnapshot}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _miniChip(
                Icons.list_alt_rounded,
                '${pergunta.alternativasPublicas.length} alternativas publicas',
              ),
              if (pergunta.podeAparecerEmAvaliacao)
                _miniChip(
                  Icons.check_circle_outline_rounded,
                  'Pode aparecer em avaliação',
                ),
              ...pergunta.tags
                  .take(4)
                  .map((tag) => _miniChip(Icons.sell_rounded, tag)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _smallButton(
                icon: Icons.edit_rounded,
                label: 'Editar',
                onTap: _salvando
                    ? null
                    : () => _abrirFormulario(ciclos, estudos, pergunta),
              ),
              _smallButton(
                icon: Icons.copy_rounded,
                label: 'Duplicar',
                onTap: _salvando ? null : () => _duplicar(pergunta),
              ),
              _smallButton(
                icon: Icons.delete_forever_rounded,
                label: 'Apagar',
                danger: true,
                onTap: _salvando ? null : () => _apagarPergunta(pergunta),
              ),
              _smallButton(
                icon: Icons.key_rounded,
                label: 'Gabarito',
                onTap: _salvando ? null : () => _abrirGabarito(pergunta),
              ),
              _acaoStatus(
                pergunta,
                PerguntaEstudoStatus.ativa,
                Icons.check_circle_rounded,
                'Ativar',
              ),
              _acaoStatus(
                pergunta,
                PerguntaEstudoStatus.rascunho,
                Icons.edit_note_rounded,
                'Rascunho',
              ),
              _acaoStatus(
                pergunta,
                PerguntaEstudoStatus.inativa,
                Icons.pause_circle_rounded,
                'Inativar',
              ),
              _acaoStatus(
                pergunta,
                PerguntaEstudoStatus.arquivada,
                Icons.archive_rounded,
                'Arquivar',
                danger: true,
              ),
              if (pergunta.status == PerguntaEstudoStatus.arquivada)
                _acaoStatus(
                  pergunta,
                  PerguntaEstudoStatus.rascunho,
                  Icons.restore_rounded,
                  'Restaurar',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _acaoStatus(
    PerguntaEstudoModel pergunta,
    String status,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    if (pergunta.status == status && status != PerguntaEstudoStatus.rascunho) {
      return const SizedBox.shrink();
    }
    return _smallButton(
      icon: icon,
      label: label,
      danger: danger,
      onTap: _salvando ? null : () => _alterarStatus(pergunta, status),
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
          Icon(icon, size: 13, color: t.textSecondary),
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

  Widget _smallButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final t = context.uai;
    final color = danger ? t.error : t.primary;
    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(99),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: t.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: onTap == null ? t.textMuted : color, size: 16),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null ? t.textMuted : color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final t = context.uai;
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        PerguntaEstudoStatus.label(status),
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
      case PerguntaEstudoStatus.ativa:
        return t.success;
      case PerguntaEstudoStatus.inativa:
        return t.textMuted;
      case PerguntaEstudoStatus.arquivada:
        return t.error;
      case PerguntaEstudoStatus.rascunho:
      default:
        return t.warning;
    }
  }

  Widget _buildErro(Object? error) {
    _logErro(error ?? 'Erro desconhecido', null);
    var detalhe = '';
    if (kDebugMode && error is FirebaseException) {
      detalhe = ' (${error.code}: ${error.message ?? ''})';
    }
    return _buildMensagemCentral(
      icon: Icons.error_outline_rounded,
      titulo: 'Não foi possível carregar as perguntas.',
      texto: 'Verifique sua conexao e tente novamente.$detalhe',
      action: FilledButton.icon(
        onPressed: _recarregar,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Tentar novamente'),
      ),
    );
  }

  Widget _buildMensagemCard({
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

  Widget _buildMensagemCentral({
    required IconData icon,
    required String titulo,
    required String texto,
    Widget? action,
  }) => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.all(18),
      child: _buildMensagemCard(
        icon: icon,
        titulo: titulo,
        texto: texto,
        action: action,
      ),
    ),
  );
}

class PerguntaFormDialog extends StatefulWidget {
  final List<EstudoCicloModel> ciclos;
  final List<EstudoModel> estudos;
  final PerguntaEstudoModel? pergunta;

  const PerguntaFormDialog({
    super.key,
    required this.ciclos,
    required this.estudos,
    this.pergunta,
  });

  @override
  State<PerguntaFormDialog> createState() => PerguntaFormDialogState();
}

class PerguntaFormDialogState extends State<PerguntaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ordem;
  late final TextEditingController _peso;
  late final TextEditingController _enunciado;
  late final TextEditingController _tags;
  late String _cicloId;
  late String _estudoId;
  late String _tipo;
  late String _dificuldade;
  late String _status;
  late bool _podeAparecer;
  late List<TextEditingController> _alternativas;

  @override
  void initState() {
    super.initState();
    final p = widget.pergunta ?? PerguntaEstudoModel.empty();
    _cicloId = widget.ciclos.any((c) => c.id == p.cicloId)
        ? p.cicloId
        : (widget.ciclos.isNotEmpty ? widget.ciclos.first.id : '');
    final estudosDoCiclo = widget.estudos
        .where((e) => e.cicloId == _cicloId)
        .toList();
    _estudoId = estudosDoCiclo.any((e) => e.id == p.estudoId)
        ? p.estudoId
        : (estudosDoCiclo.isNotEmpty ? estudosDoCiclo.first.id : '');
    _tipo = p.tipo;
    _dificuldade = p.dificuldade;
    _status = p.status;
    _podeAparecer = p.podeAparecerEmAvaliacao;
    _ordem = TextEditingController(
      text: p.ordem <= 0 ? '1' : p.ordem.toString(),
    );
    _peso = TextEditingController(text: p.peso <= 0 ? '1' : p.peso.toString());
    _enunciado = TextEditingController(text: p.enunciado);
    _tags = TextEditingController(text: p.tags.join(', '));
    final alternativas = p.alternativasPublicas.isEmpty
        ? List.generate(4, AlternativaPerguntaModel.empty)
        : p.alternativasPublicas;
    _alternativas = alternativas
        .map((a) => TextEditingController(text: a.texto))
        .toList();
    if (_tipo == PerguntaEstudoTipo.verdadeiroFalso &&
        widget.pergunta == null) {
      _definirVerdadeiroFalso();
    }
  }

  @override
  void dispose() {
    _ordem.dispose();
    _peso.dispose();
    _enunciado.dispose();
    _tags.dispose();
    for (final c in _alternativas) {
      c.dispose();
    }
    super.dispose();
  }

  List<EstudoModel> get _estudosDoCiclo => _estudosDoCicloId(_cicloId);

  List<EstudoModel> _estudosDoCicloId(String cicloId) =>
      widget.estudos.where((e) => e.cicloId == cicloId).toList();

  String? _cicloIdValido() {
    if (widget.ciclos.any((c) => c.id == _cicloId)) return _cicloId;
    return widget.ciclos.isNotEmpty ? widget.ciclos.first.id : null;
  }

  String? _estudoIdValido(List<EstudoModel> estudos) {
    if (estudos.any((e) => e.id == _estudoId)) return _estudoId;
    return estudos.isNotEmpty ? estudos.first.id : null;
  }

  void _selecionarCiclo(String? cicloId) {
    final novoCicloId = cicloId ?? _cicloId;
    final estudos = _estudosDoCicloId(novoCicloId);
    setState(() {
      _cicloId = novoCicloId;
      _estudoId = estudos.any((e) => e.id == _estudoId)
          ? _estudoId
          : (estudos.isNotEmpty ? estudos.first.id : '');
    });
  }

  void _definirVerdadeiroFalso() {
    for (final c in _alternativas) {
      c.dispose();
    }
    _alternativas = [
      TextEditingController(text: 'Verdadeiro'),
      TextEditingController(text: 'Falso'),
    ];
  }

  Future<void> _salvar({String? statusForcado}) async {
    final novoStatus = statusForcado ?? _status;
    if (novoStatus != PerguntaEstudoStatus.rascunho &&
        !_formKey.currentState!.validate()) {
      return;
    }
    if (novoStatus == PerguntaEstudoStatus.rascunho &&
        _enunciado.text.trim().isEmpty) {
      _enunciado.text = 'Pergunta em rascunho';
    }
    final alternativas = <AlternativaPerguntaModel>[];
    for (var i = 0; i < _alternativas.length; i++) {
      final texto = _alternativas[i].text.trim();
      if (texto.isEmpty && novoStatus == PerguntaEstudoStatus.rascunho) {
        continue;
      }
      alternativas.add(
        AlternativaPerguntaModel(
          id: String.fromCharCode(97 + i),
          texto: texto,
          ordem: i + 1,
        ),
      );
    }
    if (novoStatus == PerguntaEstudoStatus.ativa &&
        alternativas.where((a) => a.texto.isNotEmpty).length < 2) {
      _mostrarAviso(
        'Pergunta ativa precisa ter pelo menos 2 alternativas publicas.',
      );
      return;
    }
    final cicloIdValido = _cicloIdValido();
    if (cicloIdValido == null || cicloIdValido.isEmpty) {
      _mostrarAviso('Selecione um ciclo antes de salvar a pergunta.');
      return;
    }
    final estudosDoCiclo = _estudosDoCicloId(cicloIdValido);
    if (estudosDoCiclo.isEmpty) {
      _mostrarAviso(
        'Este ciclo nao possui estudos. Crie um estudo antes de salvar a pergunta.',
      );
      return;
    }
    final estudoIdValido = estudosDoCiclo.any((e) => e.id == _estudoId)
        ? _estudoId
        : '';
    if (estudoIdValido.isEmpty) {
      _mostrarAviso('Selecione um estudo deste ciclo antes de salvar.');
      return;
    }
    final ciclo = widget.ciclos.firstWhere((c) => c.id == cicloIdValido);
    final estudo = estudosDoCiclo.firstWhere((e) => e.id == estudoIdValido);
    final base = widget.pergunta ?? PerguntaEstudoModel.empty();
    final pergunta = base.copyWith(
      cicloId: ciclo.id,
      cicloTituloSnapshot: 'Ciclo ${ciclo.numero} - ${ciclo.titulo}',
      estudoId: estudo.id,
      estudoTituloSnapshot: estudo.titulo,
      estudoNumeroSnapshot: estudo.numero,
      enunciado: _enunciado.text.trim(),
      tipo: _tipo,
      alternativasPublicas: alternativas,
      dificuldade: _dificuldade,
      peso: int.tryParse(_peso.text.trim()) ?? 1,
      ordem: int.tryParse(_ordem.text.trim()) ?? 1,
      status: novoStatus,
      tags: PerguntaEstudoModel.parseTags(_tags.text),
      podeAparecerEmAvaliacao: _podeAparecer,
    );
    if (mounted) Navigator.pop(context, pergunta);
  }

  void _mostrarAviso(String mensagem) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final editando = widget.pergunta != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.cardRadius + 4),
            border: Border.all(color: t.border),
            boxShadow: t.cardShadow,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.quiz_rounded, color: t.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            editando ? 'Editar pergunta' : 'Nova pergunta',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close_rounded,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _avisoSeguranca(),
                    const SizedBox(height: 12),
                    _section('Vinculo', [
                      DropdownButtonFormField<String>(
                        key: ValueKey('ciclo_$_cicloId'),
                        initialValue: _cicloIdValido(),
                        decoration: const InputDecoration(labelText: 'Ciclo'),
                        items: widget.ciclos
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text('Ciclo ${c.numero} - ${c.titulo}'),
                              ),
                            )
                            .toList(),
                        onChanged: _selecionarCiclo,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Selecione um ciclo'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final estudosDoCiclo = _estudosDoCiclo;
                          final estudoIdValido = _estudoIdValido(
                            estudosDoCiclo,
                          );
                          return DropdownButtonFormField<String>(
                            key: ValueKey('estudo_$_cicloId-$estudoIdValido'),
                            initialValue: estudoIdValido,
                            decoration: const InputDecoration(
                              labelText: 'Estudo',
                            ),
                            items: estudosDoCiclo
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.id,
                                    child: Text(
                                      'Estudo ${e.numero.toString().padLeft(3, '0')} - ${e.titulo}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _estudoId = v ?? ''),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Selecione um estudo'
                                : null,
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _numberField(_ordem, 'Ordem')),
                          const SizedBox(width: 10),
                          Expanded(child: _numberField(_peso, 'Peso')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _switchRow(
                        'Pode aparecer em avaliação futuramente',
                        _podeAparecer,
                        (v) => setState(() => _podeAparecer = v),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _section('Pergunta', [
                      _textField(
                        _enunciado,
                        'Enunciado',
                        requiredField: true,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _tipo,
                              decoration: const InputDecoration(
                                labelText: 'Tipo',
                              ),
                              items: PerguntaEstudoTipo.values
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(PerguntaEstudoTipo.label(v)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _tipo = v ?? _tipo;
                                if (_tipo ==
                                    PerguntaEstudoTipo.verdadeiroFalso) {
                                  _definirVerdadeiroFalso();
                                }
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _dificuldade,
                              decoration: const InputDecoration(
                                labelText: 'Dificuldade',
                              ),
                              items: PerguntaEstudoDificuldade.values
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                        PerguntaEstudoDificuldade.label(v),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () => _dificuldade = v ?? _dificuldade,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        _tags,
                        'Tags',
                        helperText: 'Separe por virgula ou quebra de linha.',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _section('Alternativas públicas', [
                      Text(
                        'Não marque a alternativa correta nesta fase. O gabarito será separado futuramente.',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._alternativas.asMap().entries.map(
                        (entry) => _alternativaField(entry.key),
                      ),
                      if (_tipo == PerguntaEstudoTipo.multiplaEscolha)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => setState(
                              () => _alternativas.add(TextEditingController()),
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Adicionar alternativa'),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    _section('Status', [
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: PerguntaEstudoStatus.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(PerguntaEstudoStatus.label(v)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _status = v ?? _status),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _salvar(
                            statusForcado: PerguntaEstudoStatus.rascunho,
                          ),
                          icon: const Icon(Icons.edit_note_rounded),
                          label: const Text('Salvar rascunho'),
                        ),
                        FilledButton.icon(
                          onPressed: _salvar,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Salvar'),
                        ),
                        FilledButton.icon(
                          onPressed: () => _salvar(
                            statusForcado: PerguntaEstudoStatus.ativa,
                          ),
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('Ativar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avisoSeguranca() {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.warning.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.warning.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.security_rounded, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'O gabarito desta pergunta será cadastrado em uma fase futura, após proteção das regras Firestore/Cloud Functions.',
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

  Widget _section(String title, List<Widget> children) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _alternativaField(int index) {
    final t = context.uai;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: t.border),
            ),
            child: Center(
              child: Text(
                String.fromCharCode(65 + index),
                style: TextStyle(color: t.primary, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _textField(
              _alternativas[index],
              'Alternativa ${index + 1}',
              requiredField: _status == PerguntaEstudoStatus.ativa,
            ),
          ),
          if (_tipo == PerguntaEstudoTipo.multiplaEscolha &&
              _alternativas.length > 2)
            IconButton(
              onPressed: () => setState(() {
                final c = _alternativas.removeAt(index);
                c.dispose();
              }),
              icon: Icon(Icons.delete_outline_rounded, color: t.error),
            ),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final n = int.tryParse(value?.trim() ?? '');
          if (n == null || n <= 0) return 'Informe numero positivo';
          return null;
        },
      );
  Widget _textField(
    TextEditingController controller,
    String label, {
    bool requiredField = false,
    int maxLines = 1,
    String? helperText,
  }) => TextFormField(
    controller: controller,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label, helperText: helperText),
    validator: (value) {
      if (requiredField && (value?.trim().isEmpty ?? true)) {
        return 'Campo obrigatorio';
      }
      return null;
    },
  );
  Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged) {
    final t = context.uai;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(t.cardRadius - 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Switch(
                value: value,
                activeThumbColor: t.primary,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
