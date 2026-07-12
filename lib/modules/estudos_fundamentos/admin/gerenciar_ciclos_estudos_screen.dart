import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_ciclos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/estudos_midias_storage_service.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/exclusao_estudos_admin_service.dart';

enum _CiclosSortOption { ordem, numero, titulo, atualizadoEm }

class GerenciarCiclosEstudosScreen extends StatefulWidget {
  const GerenciarCiclosEstudosScreen({super.key});

  @override
  State<GerenciarCiclosEstudosScreen> createState() =>
      _GerenciarCiclosEstudosScreenState();
}

class _GerenciarCiclosEstudosScreenState
    extends State<GerenciarCiclosEstudosScreen> {
  final EstudosCiclosRepository _repository = EstudosCiclosRepository();
  final ExclusaoEstudosAdminService _exclusaoService =
      ExclusaoEstudosAdminService();
  final TextEditingController _buscaController = TextEditingController();

  String _statusFiltro = 'todos';
  _CiclosSortOption _sort = _CiclosSortOption.ordem;
  bool _salvando = false;
  int _reloadKey = 0;
  List<EstudoCicloModel> _ciclosAtuais = const [];

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  void _logErro(Object error, StackTrace? stackTrace) {
    if (!kDebugMode) return;
    if (error is FirebaseException) {
      debugPrint(
        'Erro Firebase ao carregar ciclos: code=${error.code} message=${error.message}',
      );
    } else {
      debugPrint('Erro ao carregar ciclos: $error');
    }
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }

  void _recarregar() {
    setState(() => _reloadKey++);
  }

  Future<void> _abrirFormulario([EstudoCicloModel? ciclo]) async {
    final resultado = await showDialog<EstudoCicloModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CicloFormDialog(ciclo: ciclo, ciclos: _ciclosAtuais),
    );

    if (resultado == null) return;

    setState(() => _salvando = true);
    try {
      if (resultado.id.isEmpty) {
        await _repository.criarCiclo(resultado);
        if (mounted) _mostrarMensagem('Ciclo criado.');
      } else {
        await _repository.atualizarCiclo(resultado);
        if (mounted) _mostrarMensagem('Ciclo atualizado.');
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível salvar o ciclo.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _abrirEstudosDoCiclo(EstudoCicloModel ciclo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GerenciarEstudosScreen(cicloInicialId: ciclo.id),
      ),
    );
  }

  Future<void> _alterarStatus(EstudoCicloModel ciclo, String status) async {
    if (ciclo.id.isEmpty || ciclo.status == status) return;

    final precisaConfirmar =
        status == EstudoCicloStatus.arquivado ||
        status == EstudoCicloStatus.oculto ||
        (status == EstudoCicloStatus.rascunho &&
            ciclo.status == EstudoCicloStatus.publicado) ||
        (status == EstudoCicloStatus.publicado && _cicloIncompleto(ciclo));

    if (precisaConfirmar) {
      final confirmar = await _confirmarStatus(ciclo, status);
      if (confirmar != true) return;
    }

    setState(() => _salvando = true);
    try {
      await _repository.alterarStatus(ciclo.id, status);
      if (mounted) {
        _mostrarMensagem(
          'Status alterado para ${EstudoCicloStatus.label(status)}.',
        );
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível alterar o status.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  bool _cicloIncompleto(EstudoCicloModel ciclo) {
    return ciclo.titulo.trim().isEmpty ||
        ciclo.numero <= 0 ||
        ciclo.ordem <= 0 ||
        ciclo.descricao.trim().isEmpty;
  }

  Future<bool?> _confirmarStatus(EstudoCicloModel ciclo, String status) {
    var titulo = 'Alterar status?';
    var mensagem = 'Confirme a alteração de status deste ciclo.';
    var acao = 'Confirmar';

    if (status == EstudoCicloStatus.publicado) {
      titulo = 'Publicar ciclo?';
      mensagem = _cicloIncompleto(ciclo)
          ? 'Este ciclo tem dados incompletos. Ele pode ser publicado, mas revise antes de liberar aos alunos futuramente.'
          : 'O ciclo ficará marcado como publicado.';
      acao = 'Publicar';
    } else if (status == EstudoCicloStatus.oculto) {
      titulo = 'Ocultar ciclo?';
      mensagem = 'O ciclo não será exibido para alunos futuramente.';
      acao = 'Ocultar';
    } else if (status == EstudoCicloStatus.arquivado) {
      titulo = 'Arquivar ciclo?';
      mensagem =
          'O ciclo ficará guardado no admin e não aparecerá para alunos futuramente.';
      acao = 'Arquivar';
    } else if (status == EstudoCicloStatus.rascunho) {
      titulo = 'Voltar para rascunho?';
      mensagem = 'O ciclo deixará de ser considerado publicado.';
      acao = 'Voltar';
    }

    return _confirmar(titulo: titulo, mensagem: mensagem, acao: acao);
  }

  Future<void> _duplicar(EstudoCicloModel ciclo) async {
    setState(() => _salvando = true);
    try {
      await _repository.duplicarCiclo(ciclo);
      if (mounted) _mostrarMensagem('Ciclo duplicado como rascunho.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível duplicar o ciclo.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _apagarCicloCompleto(EstudoCicloModel ciclo) async {
    final ok = await _confirmarExclusaoForte(
      titulo: 'Apagar ciclo?',
      mensagem:
          'Esta ação é irreversível. O ciclo, estudos, perguntas, gabaritos, tentativas, resultados e progressos relacionados serão apagados.',
    );
    if (!ok) return;
    setState(() => _salvando = true);
    try {
      final resumo = await _exclusaoService.excluir(
        tipo: 'ciclo',
        id: ciclo.id,
      );
      if (mounted) {
        _mostrarMensagem('Exclusão concluída: ${resumo.textoResumo}');
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível apagar o ciclo.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _moverOrdem(EstudoCicloModel ciclo, int delta) async {
    setState(() => _salvando = true);
    try {
      await _repository.atualizarOrdem(ciclo, ciclo.ordem + delta);
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível alterar a ordem.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _criarCiclosPadrao() async {
    final confirmar = await _confirmar(
      titulo: 'Criar ciclos padrão?',
      mensagem:
          'Serão criados 10 ciclos base como rascunho. Nenhum ciclo será publicado automaticamente.',
      acao: 'Criar',
    );
    if (confirmar != true) return;

    setState(() => _salvando = true);
    try {
      await _repository.criarCiclosPadrao();
      if (mounted) _mostrarMensagem('Ciclos padrão criados.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível criar os ciclos padrão.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
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
          'Gerenciar ciclos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor: _readableOn(
          Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _salvando ? null : () => _abrirFormulario(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo ciclo'),
      ),
      body: StreamBuilder<List<EstudoCicloModel>>(
        key: ValueKey(_reloadKey),
        stream: _repository.watchCiclosAdmin(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            _logErro(snapshot.error!, snapshot.stackTrace);
            return _buildErro(snapshot.error);
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }

          final ciclos = snapshot.data ?? const <EstudoCicloModel>[];
          _ciclosAtuais = ciclos;
          final filtrados = _filtrarOrdenar(ciclos);
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
                      _buildHeader(ciclos),
                      const SizedBox(height: 12),
                      _buildFerramentas(ciclos),
                      const SizedBox(height: 12),
                      if (ciclos.isEmpty)
                        _buildMensagemCard(
                          icon: Icons.timeline_rounded,
                          titulo: 'Nenhum ciclo cadastrado.',
                          texto:
                              'Crie o primeiro ciclo ou use os ciclos padrao como ponto de partida.',
                          action: FilledButton.icon(
                            onPressed: _salvando ? null : _criarCiclosPadrao,
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text('Criar ciclos padrao'),
                          ),
                        )
                      else if (filtrados.isEmpty)
                        _buildMensagemCard(
                          icon: Icons.search_off_rounded,
                          titulo: 'Nenhum ciclo encontrado.',
                          texto:
                              'Ajuste a busca ou o filtro de status para ver outros ciclos.',
                        )
                      else
                        ...filtrados.map((ciclo) => _buildCicloCard(ciclo)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<EstudoCicloModel> _filtrarOrdenar(List<EstudoCicloModel> ciclos) {
    final termo = _buscaController.text.trim().toLowerCase();
    final filtrados = ciclos.where((ciclo) {
      if (_statusFiltro != 'todos' && ciclo.status != _statusFiltro) {
        return false;
      }
      if (termo.isEmpty) return true;
      final alvo = [
        ciclo.numero.toString(),
        ciclo.titulo,
        ciclo.subtitulo,
        ciclo.descricao,
        ciclo.periodoHistorico,
      ].join(' ').toLowerCase();
      return alvo.contains(termo);
    }).toList();

    filtrados.sort((a, b) {
      switch (_sort) {
        case _CiclosSortOption.numero:
          return a.numero.compareTo(b.numero);
        case _CiclosSortOption.titulo:
          return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
        case _CiclosSortOption.atualizadoEm:
          final aDate =
              a.atualizadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate =
              b.atualizadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        case _CiclosSortOption.ordem:
          final ordem = a.ordem.compareTo(b.ordem);
          if (ordem != 0) return ordem;
          return a.numero.compareTo(b.numero);
      }
    });

    return filtrados;
  }

  Widget _buildHeader(List<EstudoCicloModel> ciclos) {
    final t = context.uai;
    final resumo = EstudosCiclosResumo.fromCiclos(ciclos);
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
                child: Icon(Icons.timeline_rounded, color: onPrimary, size: 32),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ciclos de Estudos',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Organize a linha do tempo da formação teórica da capoeira.',
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
              _headerMetric(
                'Publicados',
                resumo.publicados.toString(),
                onPrimary,
              ),
              _headerMetric(
                'Rascunhos',
                resumo.rascunhos.toString(),
                onPrimary,
              ),
              _headerMetric('Em breve', resumo.emBreve.toString(), onPrimary),
              _headerMetric('Ocultos', resumo.ocultos.toString(), onPrimary),
              _headerMetric(
                'Arquivados',
                resumo.arquivados.toString(),
                onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildFerramentas(List<EstudoCicloModel> ciclos) {
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
          TextField(
            controller: _buscaController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Buscar por título, descrição, período ou número',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterChip('todos', 'Todos'),
              _filterChip(EstudoCicloStatus.publicado, 'Publicados'),
              _filterChip(EstudoCicloStatus.rascunho, 'Rascunhos'),
              _filterChip(EstudoCicloStatus.emBreve, 'Em breve'),
              _filterChip(EstudoCicloStatus.oculto, 'Ocultos'),
              _filterChip(EstudoCicloStatus.arquivado, 'Arquivados'),
              _sortMenu(),
              if (ciclos.isEmpty)
                FilledButton.icon(
                  onPressed: _salvando ? null : _criarCiclosPadrao,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Criar ciclos padrao'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final t = context.uai;
    final selected = _statusFiltro == value;

    return FilterChip(
      selected: selected,
      label: Text(label),
      selectedColor: Color.alphaBlend(
        t.primary.withValues(alpha: 0.16),
        t.card,
      ),
      checkmarkColor: t.primary,
      onSelected: (_) => setState(() => _statusFiltro = value),
    );
  }

  Widget _sortMenu() {
    final t = context.uai;
    return PopupMenuButton<_CiclosSortOption>(
      onSelected: (value) => setState(() => _sort = value),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _CiclosSortOption.ordem,
          child: Text('Ordenar por ordem'),
        ),
        PopupMenuItem(
          value: _CiclosSortOption.numero,
          child: Text('Ordenar por numero'),
        ),
        PopupMenuItem(
          value: _CiclosSortOption.titulo,
          child: Text('Ordenar por título'),
        ),
        PopupMenuItem(
          value: _CiclosSortOption.atualizadoEm,
          child: Text('Ordenar por atualizado'),
        ),
      ],
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
            Icon(Icons.sort_rounded, color: t.primary, size: 17),
            const SizedBox(width: 6),
            Text(
              'Ordenação',
              style: TextStyle(color: t.primary, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCicloCard(EstudoCicloModel ciclo) {
    final t = context.uai;
    final statusColor = _statusColor(ciclo.status);
    final updated = ciclo.atualizadoEm == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(ciclo.atualizadoEm!);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(t.cardRadius),
        onTap: _salvando ? null : () => _abrirEstudosDoCiclo(ciclo),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        statusColor.withValues(alpha: 0.12),
                        t.cardAlt,
                      ),
                      borderRadius: BorderRadius.circular(t.cardRadius - 4),
                    ),
                    child: Center(
                      child: Text(
                        ciclo.numero.toString(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ciclo.titulo.isEmpty
                              ? 'Ciclo sem título'
                              : ciclo.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 17,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (ciclo.subtitulo.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            ciclo.subtitulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _statusChip(ciclo.status),
                            _miniChip(
                              Icons.swap_vert_rounded,
                              'Ordem ${ciclo.ordem}',
                            ),
                            if (ciclo.periodoHistorico.isNotEmpty)
                              _miniChip(
                                Icons.history_rounded,
                                ciclo.periodoHistorico,
                              ),
                            _miniChip(
                              ciclo.mostrarNaLinhaDoTempo
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              ciclo.mostrarNaLinhaDoTempo
                                  ? 'Na linha do tempo'
                                  : 'Fora da linha do tempo',
                            ),
                            if (ciclo.mostrarComoEmBreve)
                              _miniChip(Icons.schedule_rounded, 'Em breve'),
                            if (updated.isNotEmpty)
                              _miniChip(Icons.update_rounded, updated),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (ciclo.descricao.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  ciclo.descricao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _smallButton(
                    icon: Icons.edit_rounded,
                    label: 'Editar',
                    onTap: _salvando ? null : () => _abrirFormulario(ciclo),
                  ),
                  _smallButton(
                    icon: Icons.copy_rounded,
                    label: 'Duplicar',
                    onTap: _salvando ? null : () => _duplicar(ciclo),
                  ),
                  _smallButton(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Subir',
                    onTap: _salvando ? null : () => _moverOrdem(ciclo, -1),
                  ),
                  _smallButton(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Descer',
                    onTap: _salvando ? null : () => _moverOrdem(ciclo, 1),
                  ),
                  _acaoStatus(
                    ciclo,
                    EstudoCicloStatus.publicado,
                    Icons.publish_rounded,
                    'Publicar',
                  ),
                  _acaoStatus(
                    ciclo,
                    EstudoCicloStatus.rascunho,
                    Icons.edit_note_rounded,
                    'Rascunho',
                  ),
                  _acaoStatus(
                    ciclo,
                    EstudoCicloStatus.emBreve,
                    Icons.schedule_rounded,
                    'Em breve',
                  ),
                  _acaoStatus(
                    ciclo,
                    EstudoCicloStatus.oculto,
                    Icons.visibility_off_rounded,
                    'Ocultar',
                  ),
                  _acaoStatus(
                    ciclo,
                    EstudoCicloStatus.arquivado,
                    Icons.archive_rounded,
                    'Arquivar',
                    danger: true,
                  ),
                  _smallButton(
                    icon: Icons.delete_forever_rounded,
                    label: 'Apagar',
                    danger: true,
                    onTap: _salvando ? null : () => _apagarCicloCompleto(ciclo),
                  ),
                  if (ciclo.status == EstudoCicloStatus.arquivado)
                    _acaoStatus(
                      ciclo,
                      EstudoCicloStatus.rascunho,
                      Icons.restore_rounded,
                      'Restaurar',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _acaoStatus(
    EstudoCicloModel ciclo,
    String status,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    if (ciclo.status == status && status != EstudoCicloStatus.rascunho) {
      return const SizedBox.shrink();
    }
    return _smallButton(
      icon: icon,
      label: label,
      danger: danger,
      onTap: _salvando ? null : () => _alterarStatus(ciclo, status),
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
        EstudoCicloStatus.label(status),
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
        return t.success;
      case EstudoCicloStatus.emBreve:
        return t.info;
      case EstudoCicloStatus.oculto:
        return t.textMuted;
      case EstudoCicloStatus.arquivado:
        return t.error;
      case EstudoCicloStatus.rascunho:
      default:
        return t.warning;
    }
  }

  Widget _buildErro(Object? error) {
    var detalhe = '';
    if (kDebugMode && error is FirebaseException) {
      detalhe = ' (${error.code}: ${error.message ?? ''})';
    }

    return _buildMensagemCentral(
      icon: Icons.error_outline_rounded,
      titulo: 'Não foi possível carregar os ciclos.',
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
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
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
}

class _CicloFormDialog extends StatefulWidget {
  final EstudoCicloModel? ciclo;
  final List<EstudoCicloModel> ciclos;

  const _CicloFormDialog({this.ciclo, required this.ciclos});

  @override
  State<_CicloFormDialog> createState() => _CicloFormDialogState();
}

class _CicloFormDialogState extends State<_CicloFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numeroController;
  late final TextEditingController _ordemController;
  late final TextEditingController _tituloController;
  late final TextEditingController _subtituloController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _periodoController;
  late final TextEditingController _capaController;
  final EstudosMidiasStorageService _midiasService =
      EstudosMidiasStorageService();

  late String _capaStoragePath;
  late double _capaFocoX;
  late double _capaFocoY;
  int _compressaoMidia = 15;
  bool _enviandoMidia = false;
  String _ultimoUploadResumo = '';

  late String _status;
  late bool _mostrarNaLinhaDoTempo;
  late bool _mostrarComoEmBreve;

  @override
  void initState() {
    super.initState();
    final ciclo = widget.ciclo ?? EstudoCicloModel.empty();
    final proximoNumero = widget.ciclos.isEmpty
        ? 1
        : widget.ciclos.map((c) => c.numero).reduce((a, b) => a > b ? a : b) +
              1;
    final proximaOrdem = widget.ciclos.isEmpty
        ? 1
        : widget.ciclos.map((c) => c.ordem).reduce((a, b) => a > b ? a : b) + 1;
    _numeroController = TextEditingController(
      text: ciclo.numero <= 0
          ? proximoNumero.toString()
          : ciclo.numero.toString(),
    );
    _ordemController = TextEditingController(
      text: ciclo.ordem <= 0 ? proximaOrdem.toString() : ciclo.ordem.toString(),
    );
    _tituloController = TextEditingController(text: ciclo.titulo);
    _subtituloController = TextEditingController(text: ciclo.subtitulo);
    _descricaoController = TextEditingController(text: ciclo.descricao);
    _periodoController = TextEditingController(text: ciclo.periodoHistorico);
    _capaController = TextEditingController(text: ciclo.capaUrl);
    _capaStoragePath = ciclo.capaStoragePath;
    _capaFocoX = ciclo.capaFocoX;
    _capaFocoY = ciclo.capaFocoY;
    _status = ciclo.status;
    _mostrarNaLinhaDoTempo = ciclo.mostrarNaLinhaDoTempo;
    _mostrarComoEmBreve = ciclo.mostrarComoEmBreve;
  }

  @override
  void dispose() {
    _numeroController.dispose();
    _ordemController.dispose();
    _tituloController.dispose();
    _subtituloController.dispose();
    _descricaoController.dispose();
    _periodoController.dispose();
    _capaController.dispose();
    super.dispose();
  }

  Future<void> _salvar({String? statusForcado}) async {
    final novoStatus = statusForcado ?? _status;
    if (!_formKey.currentState!.validate()) return;

    if (novoStatus == EstudoCicloStatus.publicado &&
        _descricaoController.text.trim().isEmpty) {
      final confirmar = await _confirmarPublicacaoIncompleta();
      if (confirmar != true) return;
    }

    final base = widget.ciclo ?? EstudoCicloModel.empty();
    final ciclo = base.copyWith(
      numero: int.parse(_numeroController.text.trim()),
      ordem: int.parse(_ordemController.text.trim()),
      titulo: _tituloController.text.trim(),
      subtitulo: _subtituloController.text.trim(),
      descricao: _descricaoController.text.trim(),
      periodoHistorico: _periodoController.text.trim(),
      capaUrl: _capaController.text.trim(),
      capaStoragePath: _capaStoragePath,
      capaFocoX: _capaFocoX,
      capaFocoY: _capaFocoY,
      status: novoStatus,
      mostrarNaLinhaDoTempo: _mostrarNaLinhaDoTempo,
      mostrarComoEmBreve: _mostrarComoEmBreve,
    );

    if (mounted) Navigator.pop(context, ciclo);
  }

  Future<void> _enviarCapa() async {
    final cicloId = widget.ciclo?.id ?? '';
    if (cicloId.isEmpty) {
      _mostrarMensagemLocal('Salve o ciclo antes de enviar a capa.');
      return;
    }
    setState(() => _enviandoMidia = true);
    try {
      final resultado = await _midiasService.enviarCapaCiclo(
        cicloId: cicloId,
        compressaoPercentual: _compressaoMidia,
      );
      if (resultado == null) return;
      setState(() {
        _capaController.text = resultado.downloadUrl;
        _capaStoragePath = resultado.storagePath;
        _ultimoUploadResumo = resultado.resumoTamanho;
      });
      _mostrarMensagemLocal('Capa enviada: ${resultado.resumoTamanho}');
    } on EstudosMidiasUploadException catch (e) {
      _mostrarMensagemLocal(e.message);
    } on FirebaseException catch (e) {
      final mensagem = e.code == 'permission-denied'
          ? 'Sem permissão para enviar imagem. Será necessário revisar Storage Rules.'
          : 'Não foi possível enviar a imagem.';
      _mostrarMensagemLocal(mensagem);
    } finally {
      if (mounted) setState(() => _enviandoMidia = false);
    }
  }

  void _mostrarMensagemLocal(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool?> _confirmarPublicacaoIncompleta() {
    final t = context.uai;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text(
          'Publicar sem descrição?',
          style: TextStyle(color: t.textPrimary),
        ),
        content: Text(
          'A descrição está vazia. O ciclo pode ser salvo como publicado, mas revise antes de liberar aos alunos futuramente.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final editando = widget.ciclo != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timeline_rounded, color: t.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            editando ? 'Editar ciclo' : 'Novo ciclo',
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
                    const SizedBox(height: 14),
                    _formSection('Identificação', [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 560) {
                            return Column(
                              children: [
                                _numberField(
                                  _numeroController,
                                  'Número do ciclo',
                                ),
                                const SizedBox(height: 10),
                                _numberField(_ordemController, 'Ordem'),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: _numberField(
                                  _numeroController,
                                  'Número do ciclo',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _numberField(_ordemController, 'Ordem'),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        controller: _tituloController,
                        label: 'Título',
                        requiredField: true,
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        controller: _subtituloController,
                        label: 'Subtítulo',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _formSection('Conteúdo', [
                      _textField(
                        controller: _descricaoController,
                        label: 'Descrição',
                        maxLines: 4,
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        controller: _periodoController,
                        label: 'Período histórico',
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        controller: _capaController,
                        label: 'Capa URL opcional',
                      ),
                      const SizedBox(height: 10),
                      _midiaControls(),
                    ]),
                    const SizedBox(height: 12),
                    _formSection('Publicação e visibilidade', [
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: EstudoCicloStatus.values
                            .map(
                              (status) => DropdownMenuItem<String>(
                                value: status,
                                child: Text(EstudoCicloStatus.label(status)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _status = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusHelp(_status),
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _switchRow(
                        title: 'Mostrar na linha do tempo',
                        value: _mostrarNaLinhaDoTempo,
                        onChanged: (value) =>
                            setState(() => _mostrarNaLinhaDoTempo = value),
                      ),
                      const SizedBox(height: 8),
                      _switchRow(
                        title: 'Mostrar como em breve',
                        value: _mostrarComoEmBreve,
                        onChanged: (value) =>
                            setState(() => _mostrarComoEmBreve = value),
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
                            statusForcado: EstudoCicloStatus.rascunho,
                          ),
                          icon: const Icon(Icons.edit_note_rounded),
                          label: const Text('Salvar rascunho'),
                        ),
                        FilledButton.icon(
                          onPressed: _salvar,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Salvar'),
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

  Widget _formSection(String title, List<Widget> children) {
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

  String _statusHelp(String status) {
    switch (status) {
      case EstudoCicloStatus.publicado:
        return 'Publicado: aluno podera ver futuramente, se o modulo estiver ativo.';
      case EstudoCicloStatus.emBreve:
        return 'Em breve: aluno podera ver bloqueado se a configuracao permitir.';
      case EstudoCicloStatus.oculto:
        return 'Oculto: aluno nao ve.';
      case EstudoCicloStatus.arquivado:
        return 'Arquivado: fica guardado no admin.';
      case EstudoCicloStatus.rascunho:
      default:
        return 'Rascunho: apenas administradores veem.';
    }
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = int.tryParse(value?.trim() ?? '');
        if (number == null || number <= 0) return 'Informe um numero valido';
        return null;
      },
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    bool requiredField = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (requiredField && (value?.trim().isEmpty ?? true)) {
          return 'Campo obrigatorio';
        }
        return null;
      },
    );
  }

  Widget _midiaControls() {
    final t = context.uai;
    final cicloId = widget.ciclo?.id.trim() ?? '';
    final podeEnviarCapa = cicloId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _compressaoMidia,
          decoration: const InputDecoration(labelText: 'Compressão'),
          items: EstudosMidiasStorageService.compressoesPermitidas
              .map(
                (valor) => DropdownMenuItem<int>(
                  value: valor,
                  child: Text('$valor% compressão'),
                ),
              )
              .toList(),
          onChanged: _enviandoMidia
              ? null
              : (value) => setState(() => _compressaoMidia = value ?? 15),
        ),
        const SizedBox(height: 10),
        if (_capaController.text.trim().isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: Image.network(
                _capaController.text.trim(),
                fit: BoxFit.cover,
                alignment: Alignment(
                  (_capaFocoX * 2) - 1,
                  (_capaFocoY * 2) - 1,
                ),
                errorBuilder: (context, error, stackTrace) => Container(
                  color: t.cardAlt,
                  alignment: Alignment.center,
                  child: Text(
                    'Imagem não carregada',
                    style: TextStyle(color: t.textMuted),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: _enviandoMidia || !podeEnviarCapa ? null : _enviarCapa,
          icon: _enviandoMidia
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_rounded),
          label: Text(_enviandoMidia ? 'Enviando...' : 'Enviar capa'),
        ),
        if (!podeEnviarCapa) ...[
          const SizedBox(height: 6),
          Text(
            'Salve o ciclo primeiro para enviar a capa.',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _focoCapaControls(),
        if (_ultimoUploadResumo.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _ultimoUploadResumo,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _focoCapaControls() {
    final t = context.uai;
    const pontos = <_FocoCapaOpcao>[
      _FocoCapaOpcao('Superior esquerda', 0, 0),
      _FocoCapaOpcao('Superior', 0.5, 0),
      _FocoCapaOpcao('Superior direita', 1, 0),
      _FocoCapaOpcao('Esquerda', 0, 0.5),
      _FocoCapaOpcao('Centro', 0.5, 0.5),
      _FocoCapaOpcao('Direita', 1, 0.5),
      _FocoCapaOpcao('Inferior esquerda', 0, 1),
      _FocoCapaOpcao('Inferior', 0.5, 1),
      _FocoCapaOpcao('Inferior direita', 1, 1),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foco da capa',
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: pontos.map((ponto) {
            final selected =
                (_capaFocoX - ponto.x).abs() < 0.01 &&
                (_capaFocoY - ponto.y).abs() < 0.01;
            return ChoiceChip(
              label: Text(ponto.label),
              selected: selected,
              onSelected: (_) => setState(() {
                _capaFocoX = ponto.x;
                _capaFocoY = ponto.y;
              }),
            );
          }).toList(),
        ),
        Slider(
          value: _capaFocoX,
          min: 0,
          max: 1,
          divisions: 100,
          label: 'X ${(_capaFocoX * 100).round()}%',
          onChanged: (value) => setState(() => _capaFocoX = value),
        ),
        Slider(
          value: _capaFocoY,
          min: 0,
          max: 1,
          divisions: 100,
          label: 'Y ${(_capaFocoY * 100).round()}%',
          onChanged: (value) => setState(() => _capaFocoY = value),
        ),
      ],
    );
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
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

class _FocoCapaOpcao {
  final String label;
  final double x;
  final double y;

  const _FocoCapaOpcao(this.label, this.x, this.y);
}
