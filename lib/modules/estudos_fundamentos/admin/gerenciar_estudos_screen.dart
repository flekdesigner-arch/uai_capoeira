import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_ciclos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/estudos_midias_storage_service.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/detalhe_admin_estudo_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_ciclos_estudos_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/preview_estudo_screen.dart';

enum _EstudosSortOption { cicloOrdem, numero, titulo, atualizadoEm }

class GerenciarEstudosScreen extends StatefulWidget {
  const GerenciarEstudosScreen({super.key});

  @override
  State<GerenciarEstudosScreen> createState() => _GerenciarEstudosScreenState();
}

class _GerenciarEstudosScreenState extends State<GerenciarEstudosScreen> {
  final EstudosRepository _repository = EstudosRepository();
  final EstudosCiclosRepository _ciclosRepository = EstudosCiclosRepository();
  final TextEditingController _buscaController = TextEditingController();

  String _statusFiltro = 'todos';
  String _cicloFiltro = 'todos';
  _EstudosSortOption _sort = _EstudosSortOption.cicloOrdem;
  bool _salvando = false;
  int _reloadKey = 0;

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
        'Erro Firebase em estudos: code=${error.code} message=${error.message}',
      );
    } else {
      debugPrint('Erro em estudos: $error');
    }
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }

  void _recarregar() => setState(() => _reloadKey++);
  Future<void> _abrirFormulario(
    List<EstudoCicloModel> ciclos, [
    EstudoModel? estudo,
  ]) async {
    if (ciclos.isEmpty) {
      _mostrarMensagem('Cadastre pelo menos um ciclo antes de criar estudos.');
      return;
    }

    final resultado = await showDialog<EstudoModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EstudoFormDialog(estudo: estudo, ciclos: ciclos),
    );
    if (resultado == null) return;

    setState(() => _salvando = true);
    try {
      if (resultado.id.isEmpty) {
        await _repository.criarEstudo(resultado);
        if (mounted) _mostrarMensagem('Estudo criado.');
      } else {
        await _repository.atualizarEstudo(resultado);
        if (mounted) _mostrarMensagem('Estudo atualizado.');
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Nao foi possivel salvar o estudo.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _abrirGerenciarCiclos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GerenciarCiclosEstudosScreen()),
    );
  }

  void _abrirDetalhe(EstudoModel estudo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalheAdminEstudoScreen(estudo: estudo),
      ),
    );
  }

  void _abrirPreview(EstudoModel estudo) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewEstudoScreen(estudo: estudo)),
    );
  }

  Future<void> _alterarStatus(EstudoModel estudo, String status) async {
    if (estudo.id.isEmpty || estudo.status == status) return;
    final sensivel =
        status == EstudoCicloStatus.arquivado ||
        status == EstudoCicloStatus.oculto ||
        (status == EstudoCicloStatus.rascunho &&
            estudo.status == EstudoCicloStatus.publicado) ||
        (status == EstudoCicloStatus.publicado && _estudoIncompleto(estudo));
    if (sensivel) {
      final ok = await _confirmarStatus(estudo, status);
      if (ok != true) {
        return;
      }
    }
    setState(() => _salvando = true);
    try {
      await _repository.alterarStatus(estudo.id, status);
      if (mounted) {
        _mostrarMensagem(
          'Status alterado para ${EstudoCicloStatus.label(status)}.',
        );
      }
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) {
        _mostrarMensagem('Nao foi possivel alterar o status.');
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  bool _estudoIncompleto(EstudoModel estudo) {
    return estudo.cicloId.isEmpty ||
        estudo.titulo.isEmpty ||
        estudo.numero <= 0 ||
        estudo.ordem <= 0 ||
        (estudo.resumo.isEmpty && estudo.textoAprofundado.isEmpty);
  }

  Future<bool?> _confirmarStatus(EstudoModel estudo, String status) {
    var titulo = 'Alterar status?';
    var mensagem = 'Confirme a alteracao de status deste estudo.';
    var acao = 'Confirmar';
    if (status == EstudoCicloStatus.publicado) {
      titulo = 'Publicar estudo?';
      mensagem = _estudoIncompleto(estudo)
          ? 'Este estudo tem conteudo incompleto. Ele pode ser publicado, mas revise antes de liberar aos alunos futuramente.'
          : 'O estudo ficara marcado como publicado.';
      acao = 'Publicar';
    } else if (status == EstudoCicloStatus.oculto) {
      titulo = 'Ocultar estudo?';
      mensagem = 'O estudo nao sera exibido para alunos futuramente.';
      acao = 'Ocultar';
    } else if (status == EstudoCicloStatus.arquivado) {
      titulo = 'Arquivar estudo?';
      mensagem =
          'O estudo ficara guardado no admin e nao aparecera para alunos futuramente.';
      acao = 'Arquivar';
    } else if (status == EstudoCicloStatus.rascunho) {
      titulo = 'Voltar para rascunho?';
      mensagem = 'O estudo deixara de ser considerado publicado.';
      acao = 'Voltar';
    }
    return _confirmar(titulo: titulo, mensagem: mensagem, acao: acao);
  }

  Future<void> _duplicar(EstudoModel estudo) async {
    setState(() => _salvando = true);
    try {
      await _repository.duplicarEstudo(estudo);
      if (mounted) _mostrarMensagem('Estudo duplicado como rascunho.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Nao foi possivel duplicar o estudo.');
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

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Gerenciar estudos',
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
          if (ciclosSnapshot.connectionState == ConnectionState.waiting &&
              !ciclosSnapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }
          final ciclos = ciclosSnapshot.data ?? const <EstudoCicloModel>[];
          if (ciclos.isEmpty) {
            return _buildMensagemCentral(
              icon: Icons.timeline_rounded,
              titulo: 'Crie um ciclo antes de cadastrar estudos.',
              texto:
                  'Os estudos precisam estar vinculados a um ciclo da formacao teorica.',
              action: FilledButton.icon(
                onPressed: _abrirGerenciarCiclos,
                icon: const Icon(Icons.timeline_rounded),
                label: const Text('Gerenciar ciclos'),
              ),
            );
          }
          return StreamBuilder<List<EstudoModel>>(
            stream: _repository.watchEstudosAdmin(),
            builder: (context, estudosSnapshot) {
              if (estudosSnapshot.hasError) {
                return _buildErro(estudosSnapshot.error);
              }
              if (estudosSnapshot.connectionState == ConnectionState.waiting &&
                  !estudosSnapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: t.primary),
                );
              }
              final estudos = estudosSnapshot.data ?? const <EstudoModel>[];
              final filtrados = _filtrarOrdenar(estudos);
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
                          _buildHeader(estudos),
                          const SizedBox(height: 12),
                          _buildFerramentas(ciclos),
                          const SizedBox(height: 12),
                          if (estudos.isEmpty)
                            _buildMensagemCard(
                              icon: Icons.article_rounded,
                              titulo: 'Nenhum estudo cadastrado.',
                              texto:
                                  'Crie o primeiro artigo/aula vinculado a um ciclo.',
                              action: FilledButton.icon(
                                onPressed: _salvando
                                    ? null
                                    : () => _abrirFormulario(ciclos),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Novo estudo'),
                              ),
                            )
                          else if (filtrados.isEmpty)
                            _buildMensagemCard(
                              icon: Icons.search_off_rounded,
                              titulo: 'Nenhum estudo encontrado.',
                              texto:
                                  'Ajuste a busca, ciclo ou filtro de status.',
                            )
                          else
                            ...filtrados.map(
                              (estudo) => _buildEstudoCard(estudo, ciclos),
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
      floatingActionButton: StreamBuilder<List<EstudoCicloModel>>(
        stream: _ciclosRepository.watchCiclosAdmin(),
        builder: (context, snapshot) {
          final ciclos = snapshot.data ?? const <EstudoCicloModel>[];
          return FloatingActionButton.extended(
            onPressed: _salvando || ciclos.isEmpty
                ? null
                : () => _abrirFormulario(ciclos),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Novo estudo'),
          );
        },
      ),
    );
  }

  List<EstudoModel> _filtrarOrdenar(List<EstudoModel> estudos) {
    final termo = _buscaController.text.trim().toLowerCase();
    final filtrados = estudos.where((e) {
      if (_statusFiltro != 'todos' && e.status != _statusFiltro) return false;
      if (_cicloFiltro != 'todos' && e.cicloId != _cicloFiltro) return false;
      if (termo.isEmpty) return true;
      final alvo = [
        e.numero.toString(),
        e.titulo,
        e.subtitulo,
        e.resumo,
        e.perguntaPrincipal,
        e.textoAprofundado,
      ].join(' ').toLowerCase();
      return alvo.contains(termo);
    }).toList();
    filtrados.sort((a, b) {
      switch (_sort) {
        case _EstudosSortOption.numero:
          return a.numero.compareTo(b.numero);
        case _EstudosSortOption.titulo:
          return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
        case _EstudosSortOption.atualizadoEm:
          final ad = a.atualizadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.atualizadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        case _EstudosSortOption.cicloOrdem:
          final ciclo = a.cicloTituloSnapshot.toLowerCase().compareTo(
            b.cicloTituloSnapshot.toLowerCase(),
          );
          if (ciclo != 0) return ciclo;
          final ordem = a.ordem.compareTo(b.ordem);
          if (ordem != 0) return ordem;
          return a.numero.compareTo(b.numero);
      }
    });
    return filtrados;
  }

  Widget _buildHeader(List<EstudoModel> estudos) {
    final t = context.uai;
    final resumo = EstudosResumo.fromEstudos(estudos);
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
                child: Icon(Icons.article_rounded, color: onPrimary, size: 32),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estudos e Artigos',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Monte as aulas teoricas da linha do tempo da capoeira.',
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
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _abrirGerenciarCiclos,
                icon: const Icon(Icons.timeline_rounded),
                label: const Text('Gerenciar ciclos'),
              ),
              FilledButton.icon(
                onPressed: ciclos.isEmpty
                    ? null
                    : () => _abrirFormulario(ciclos),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Novo estudo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscaController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText:
                  'Buscar por titulo, resumo, pergunta, numero ou conteudo',
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
              _cicloMenu(ciclos),
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

  Widget _cicloMenu(List<EstudoCicloModel> ciclos) {
    final t = context.uai;
    return PopupMenuButton<String>(
      onSelected: (value) => setState(() => _cicloFiltro = value),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'todos', child: Text('Todos os ciclos')),
        ...ciclos.map(
          (c) => PopupMenuItem(
            value: c.id,
            child: Text('Ciclo ${c.numero} - ${c.titulo}'),
          ),
        ),
      ],
      child: _menuChip(
        Icons.timeline_rounded,
        _cicloFiltro == 'todos' ? 'Ciclo' : 'Ciclo filtrado',
        t.primary,
      ),
    );
  }

  Widget _sortMenu() {
    final t = context.uai;
    return PopupMenuButton<_EstudosSortOption>(
      onSelected: (value) => setState(() => _sort = value),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _EstudosSortOption.cicloOrdem,
          child: Text('Ordenar por ciclo/ordem'),
        ),
        PopupMenuItem(
          value: _EstudosSortOption.numero,
          child: Text('Ordenar por numero'),
        ),
        PopupMenuItem(
          value: _EstudosSortOption.titulo,
          child: Text('Ordenar por titulo'),
        ),
        PopupMenuItem(
          value: _EstudosSortOption.atualizadoEm,
          child: Text('Ordenar por atualizado'),
        ),
      ],
      child: _menuChip(Icons.sort_rounded, 'Ordenacao', t.primary),
    );
  }

  Widget _menuChip(IconData icon, String label, Color color) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildEstudoCard(EstudoModel estudo, List<EstudoCicloModel> ciclos) {
    final t = context.uai;
    final statusColor = _statusColor(estudo.status);
    final updated = estudo.atualizadoEm == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(estudo.atualizadoEm!);
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    statusColor.withValues(alpha: 0.12),
                    t.cardAlt,
                  ),
                  borderRadius: BorderRadius.circular(t.cardRadius - 4),
                ),
                child: Center(
                  child: Text(
                    estudo.numero.toString().padLeft(3, '0'),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 15,
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
                      estudo.titulo.isEmpty
                          ? 'Estudo sem titulo'
                          : estudo.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 17,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (estudo.subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        estudo.subtitulo,
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
                        _statusChip(estudo.status),
                        _miniChip(
                          Icons.timeline_rounded,
                          estudo.cicloTituloSnapshot.isEmpty
                              ? 'Sem ciclo'
                              : estudo.cicloTituloSnapshot,
                        ),
                        _miniChip(
                          Icons.swap_vert_rounded,
                          'Ordem ${estudo.ordem}',
                        ),
                        if (estudo.duracaoEstimadaMin > 0)
                          _miniChip(
                            Icons.schedule_rounded,
                            '${estudo.duracaoEstimadaMin} min',
                          ),
                        _miniChip(
                          estudo.mostrarNaLinhaDoTempo
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          estudo.mostrarNaLinhaDoTempo
                              ? 'Na linha do tempo'
                              : 'Fora da linha do tempo',
                        ),
                        if (estudo.mostrarComoEmBreve)
                          _miniChip(Icons.hourglass_empty_rounded, 'Em breve'),
                        if (estudo.videoYoutubeUrl.isNotEmpty)
                          _miniChip(Icons.smart_display_rounded, 'Video'),
                        if (estudo.fontesLista.isNotEmpty)
                          _miniChip(Icons.source_rounded, 'Fontes'),
                        if (estudo.reflexaoFinal.isNotEmpty)
                          _miniChip(Icons.psychology_rounded, 'Reflexao'),
                        if (updated.isNotEmpty)
                          _miniChip(Icons.update_rounded, updated),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (estudo.perguntaPrincipal.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              estudo.perguntaPrincipal,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.primary, fontWeight: FontWeight.w900),
            ),
          ],
          if (estudo.resumo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              estudo.resumo,
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
                icon: Icons.open_in_new_rounded,
                label: 'Abrir',
                onTap: _salvando ? null : () => _abrirDetalhe(estudo),
              ),
              _smallButton(
                icon: Icons.edit_rounded,
                label: 'Editar',
                onTap: _salvando
                    ? null
                    : () => _abrirFormulario(ciclos, estudo),
              ),
              _smallButton(
                icon: Icons.visibility_rounded,
                label: 'Pre-visualizar',
                onTap: _salvando ? null : () => _abrirPreview(estudo),
              ),
              _smallButton(
                icon: Icons.copy_rounded,
                label: 'Duplicar',
                onTap: _salvando ? null : () => _duplicar(estudo),
              ),
              _acaoStatus(
                estudo,
                EstudoCicloStatus.publicado,
                Icons.publish_rounded,
                'Publicar',
              ),
              _acaoStatus(
                estudo,
                EstudoCicloStatus.rascunho,
                Icons.edit_note_rounded,
                'Rascunho',
              ),
              _acaoStatus(
                estudo,
                EstudoCicloStatus.emBreve,
                Icons.schedule_rounded,
                'Em breve',
              ),
              _acaoStatus(
                estudo,
                EstudoCicloStatus.oculto,
                Icons.visibility_off_rounded,
                'Ocultar',
              ),
              _acaoStatus(
                estudo,
                EstudoCicloStatus.arquivado,
                Icons.archive_rounded,
                'Arquivar',
                danger: true,
              ),
              if (estudo.status == EstudoCicloStatus.arquivado)
                _acaoStatus(
                  estudo,
                  EstudoCicloStatus.rascunho,
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
    EstudoModel estudo,
    String status,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    if (estudo.status == status && status != EstudoCicloStatus.rascunho) {
      return const SizedBox.shrink();
    }
    return _smallButton(
      icon: icon,
      label: label,
      danger: danger,
      onTap: _salvando ? null : () => _alterarStatus(estudo, status),
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
    _logErro(error ?? 'Erro desconhecido', null);
    var detalhe = '';
    if (kDebugMode && error is FirebaseException) {
      detalhe = ' (${error.code}: ${error.message ?? ''})';
    }
    return _buildMensagemCentral(
      icon: Icons.error_outline_rounded,
      titulo: 'Nao foi possivel carregar os estudos.',
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

class EstudoFormDialog extends StatefulWidget {
  final EstudoModel? estudo;
  final List<EstudoCicloModel> ciclos;

  const EstudoFormDialog({super.key, required this.ciclos, this.estudo});

  @override
  State<EstudoFormDialog> createState() => EstudoFormDialogState();
}

class EstudoFormDialogState extends State<EstudoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numero;
  late final TextEditingController _ordem;
  late final TextEditingController _titulo;
  late final TextEditingController _subtitulo;
  late final TextEditingController _pergunta;
  late final TextEditingController _duracao;
  late final TextEditingController _resumo;
  late final TextEditingController _texto;
  late final TextEditingController _mito;
  late final TextEditingController _sabia;
  late final TextEditingController _palavras;
  late final TextEditingController _reflexao;
  late final TextEditingController _fontes;
  late final TextEditingController _capa;
  late final TextEditingController _imagens;
  late final TextEditingController _youtube;
  late final TextEditingController _link;
  final EstudosMidiasStorageService _midiasService =
      EstudosMidiasStorageService();

  late String _capaStoragePath;
  late List<String> _imagensStoragePaths;
  int _compressaoMidia = 15;
  bool _enviandoMidia = false;
  String _ultimoUploadResumo = '';

  late String _cicloId;
  late String _status;
  late bool _mostrarNaLinhaDoTempo;
  late bool _mostrarComoEmBreve;

  @override
  void initState() {
    super.initState();
    final e = widget.estudo ?? EstudoModel.empty();
    _cicloId = e.cicloId.isNotEmpty ? e.cicloId : widget.ciclos.first.id;
    _numero = TextEditingController(
      text: e.numero <= 0 ? '' : e.numero.toString(),
    );
    _ordem = TextEditingController(
      text: e.ordem <= 0 ? '' : e.ordem.toString(),
    );
    _titulo = TextEditingController(text: e.titulo);
    _subtitulo = TextEditingController(text: e.subtitulo);
    _pergunta = TextEditingController(text: e.perguntaPrincipal);
    _duracao = TextEditingController(
      text: e.duracaoEstimadaMin <= 0 ? '' : e.duracaoEstimadaMin.toString(),
    );
    _resumo = TextEditingController(text: e.resumo);
    _texto = TextEditingController(text: e.textoAprofundado);
    _mito = TextEditingController(text: e.mitoOuFato);
    _sabia = TextEditingController(text: e.voceSabia);
    _palavras = TextEditingController(text: e.palavrasImportantes);
    _reflexao = TextEditingController(text: e.reflexaoFinal);
    _fontes = TextEditingController(text: e.fontes);
    _capa = TextEditingController(text: e.capaUrl);
    _capaStoragePath = e.capaStoragePath.trim();
    _imagensStoragePaths = List<String>.from(e.imagensStoragePaths);
    _imagens = TextEditingController(text: e.imagensUrls.join('\n'));
    _youtube = TextEditingController(text: e.videoYoutubeUrl);
    _link = TextEditingController(text: e.linkExterno);
    _status = e.status;
    _mostrarNaLinhaDoTempo = e.mostrarNaLinhaDoTempo;
    _mostrarComoEmBreve = e.mostrarComoEmBreve;
  }

  @override
  void dispose() {
    for (final c in [
      _numero,
      _ordem,
      _titulo,
      _subtitulo,
      _pergunta,
      _duracao,
      _resumo,
      _texto,
      _mito,
      _sabia,
      _palavras,
      _reflexao,
      _fontes,
      _capa,
      _imagens,
      _youtube,
      _link,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar({String? statusForcado}) async {
    final novoStatus = statusForcado ?? _status;
    if (!_formKey.currentState!.validate()) return;
    if (novoStatus == EstudoCicloStatus.publicado &&
        _publicacaoPrecisaAviso()) {
      final ok = await _confirmarPublicacaoIncompleta();
      if (ok != true) {
        return;
      }
    }
    final ciclo = widget.ciclos.firstWhere(
      (c) => c.id == _cicloId,
      orElse: () => widget.ciclos.first,
    );
    final base = widget.estudo ?? EstudoModel.empty();
    final estudo = base.copyWith(
      cicloId: ciclo.id,
      cicloTituloSnapshot: 'Ciclo ${ciclo.numero} - ${ciclo.titulo}',
      numero: int.parse(_numero.text.trim()),
      ordem: int.parse(_ordem.text.trim()),
      titulo: _titulo.text.trim(),
      subtitulo: _subtitulo.text.trim(),
      perguntaPrincipal: _pergunta.text.trim(),
      duracaoEstimadaMin: int.tryParse(_duracao.text.trim()) ?? 0,
      resumo: _resumo.text.trim(),
      textoAprofundado: _texto.text.trim(),
      mitoOuFato: _mito.text.trim(),
      voceSabia: _sabia.text.trim(),
      palavrasImportantes: _palavras.text.trim(),
      reflexaoFinal: _reflexao.text.trim(),
      fontes: _fontes.text.trim(),
      capaUrl: EstudoModel.normalizarImagemUrl(_capa.text),
      capaStoragePath: _capaStoragePath,
      imagensUrls: EstudoModel.normalizarListaUrls(_imagens.text),
      imagensStoragePaths: EstudoModel.normalizarListaStoragePaths(
        _imagensStoragePaths,
      ),
      videoYoutubeUrl: _youtube.text.trim(),
      linkExterno: _link.text.trim(),
      status: novoStatus,
      mostrarNaLinhaDoTempo: _mostrarNaLinhaDoTempo,
      mostrarComoEmBreve: _mostrarComoEmBreve,
    );
    if (mounted) Navigator.pop(context, estudo);
  }

  Future<void> _enviarCapaEstudo() async {
    final estudoId = widget.estudo?.id ?? '';
    if (estudoId.isEmpty) {
      _mostrarMensagemLocal('Salve o estudo antes de enviar a capa.');
      return;
    }
    setState(() => _enviandoMidia = true);
    try {
      final resultado = await _midiasService.enviarCapaEstudo(
        cicloId: _cicloId,
        estudoId: estudoId,
        compressaoPercentual: _compressaoMidia,
      );
      if (resultado == null) return;
      setState(() {
        _capa.text = resultado.downloadUrl;
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

  Future<void> _enviarImagemEstudo() async {
    final estudoId = widget.estudo?.id ?? '';
    if (estudoId.isEmpty) {
      _mostrarMensagemLocal('Salve o estudo antes de enviar imagens internas.');
      return;
    }
    setState(() => _enviandoMidia = true);
    try {
      final resultado = await _midiasService.enviarImagemEstudo(
        cicloId: _cicloId,
        estudoId: estudoId,
        compressaoPercentual: _compressaoMidia,
      );
      if (resultado == null) return;
      final urls = EstudoModel.normalizarListaUrls(_imagens.text).toList();
      urls.add(resultado.downloadUrl);
      _imagensStoragePaths.add(resultado.storagePath);
      setState(() {
        _imagens.text = urls.join('\n');
        _ultimoUploadResumo = resultado.resumoTamanho;
      });
      _mostrarMensagemLocal('Imagem enviada: ${resultado.resumoTamanho}');
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

  bool _publicacaoPrecisaAviso() {
    return _resumo.text.trim().isEmpty ||
        _texto.text.trim().isEmpty ||
        _pergunta.text.trim().isEmpty ||
        _fontes.text.trim().isEmpty ||
        _reflexao.text.trim().isEmpty;
  }

  Future<bool?> _confirmarPublicacaoIncompleta() {
    final t = context.uai;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text(
          'Este estudo ainda parece incompleto.',
          style: TextStyle(color: t.textPrimary),
        ),
        content: Text(
          'Faltam itens editoriais recomendados, como resumo, texto aprofundado, pergunta principal, fontes ou reflexao final. Deseja publicar mesmo assim?',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publicar mesmo assim'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final editando = widget.estudo != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
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
                        Icon(Icons.article_rounded, color: t.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            editando ? 'Editar estudo' : 'Novo estudo',
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
                    _section('Identificacao', [
                      DropdownButtonFormField<String>(
                        initialValue: _cicloId,
                        decoration: const InputDecoration(labelText: 'Ciclo'),
                        items: widget.ciclos
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text('Ciclo ${c.numero} - ${c.titulo}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _cicloId = v ?? _cicloId),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Selecione um ciclo'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 560) {
                            return Column(
                              children: [
                                _numberField(_numero, 'Numero do estudo'),
                                const SizedBox(height: 10),
                                _numberField(_ordem, 'Ordem'),
                                const SizedBox(height: 10),
                                _numberField(
                                  _duracao,
                                  'Duracao estimada min',
                                  requiredField: false,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: _numberField(
                                  _numero,
                                  'Numero do estudo',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: _numberField(_ordem, 'Ordem')),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _numberField(
                                  _duracao,
                                  'Duracao min',
                                  requiredField: false,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _textField(_titulo, 'Titulo', requiredField: true),
                      const SizedBox(height: 10),
                      _textField(_subtitulo, 'Subtitulo'),
                      const SizedBox(height: 10),
                      _textField(_pergunta, 'Pergunta principal'),
                    ]),
                    const SizedBox(height: 12),
                    _section('Conteudo principal', [
                      _help(
                        'Escreva o resumo e o corpo principal do artigo. Estes campos ajudam a futura leitura do aluno.',
                      ),
                      const SizedBox(height: 10),
                      _textField(_resumo, 'Resumo', maxLines: 4),
                      const SizedBox(height: 10),
                      _textField(_texto, 'Texto aprofundado', maxLines: 9),
                    ]),
                    const SizedBox(height: 12),
                    _section('Blocos pedagogicos', [
                      _help(
                        'Use estes blocos para destacar conceitos, curiosidades e fechamento reflexivo.',
                      ),
                      const SizedBox(height: 10),
                      _textField(_mito, 'Mito ou fato', maxLines: 4),
                      const SizedBox(height: 10),
                      _textField(_sabia, 'Voce sabia?', maxLines: 4),
                      const SizedBox(height: 10),
                      _textField(
                        _palavras,
                        'Palavras importantes',
                        maxLines: 3,
                        helperText:
                            'Separe por virgula ou por quebra de linha.',
                      ),
                      const SizedBox(height: 10),
                      _textField(_reflexao, 'Reflexao final', maxLines: 4),
                    ]),
                    const SizedBox(height: 12),
                    _section('Midia e fontes', [
                      _help(
                        'Informe links por enquanto. Upload e player embutido ficam para fases futuras.',
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        _capa,
                        'Capa URL opcional',
                        validator: _validarUrlGenerica,
                      ),
                      const SizedBox(height: 10),
                      _midiaControls(),
                      const SizedBox(height: 10),
                      _textField(
                        _imagens,
                        'Imagens do estudo',
                        maxLines: 4,
                        helperText:
                            'Uma URL por linha. Links do Google Drive precisam estar públicos; uploads usam Firebase Storage.',
                        validator: _validarUrlsImagem,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _enviandoMidia ? null : _enviarImagemEstudo,
                        icon: const Icon(Icons.add_photo_alternate_rounded),
                        label: const Text('Enviar imagem'),
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        _youtube,
                        'Video YouTube URL opcional',
                        validator: _validarUrlVideo,
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        _link,
                        'Link externo opcional',
                        validator: _validarUrlGenerica,
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        _fontes,
                        'Fontes/referencias',
                        maxLines: 4,
                        helperText: 'Informe uma fonte por linha.',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _section('Publicacao e visibilidade', [
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: EstudoCicloStatus.values
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(EstudoCicloStatus.label(s)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _status = v ?? _status),
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
                        'Mostrar na linha do tempo',
                        _mostrarNaLinhaDoTempo,
                        (v) => setState(() => _mostrarNaLinhaDoTempo = v),
                      ),
                      const SizedBox(height: 8),
                      _switchRow(
                        'Mostrar como em breve',
                        _mostrarComoEmBreve,
                        (v) => setState(() => _mostrarComoEmBreve = v),
                      ),
                      const SizedBox(height: 12),
                      _checklistEditorial(),
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
                        FilledButton.icon(
                          onPressed: () => _salvar(
                            statusForcado: EstudoCicloStatus.publicado,
                          ),
                          icon: const Icon(Icons.publish_rounded),
                          label: const Text('Publicar'),
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

  Widget _help(String text) {
    final t = context.uai;
    return Text(
      text,
      style: TextStyle(
        color: t.textSecondary,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _checklistEditorial() {
    final items = <_EditorChecklistItem>[
      _EditorChecklistItem('Ciclo', _cicloId.isNotEmpty),
      _EditorChecklistItem('Titulo', _titulo.text.trim().isNotEmpty),
      _EditorChecklistItem(
        'Numero',
        (int.tryParse(_numero.text.trim()) ?? 0) > 0,
      ),
      _EditorChecklistItem('Resumo', _resumo.text.trim().isNotEmpty),
      _EditorChecklistItem('Texto', _texto.text.trim().isNotEmpty),
      _EditorChecklistItem('Pergunta', _pergunta.text.trim().isNotEmpty),
      _EditorChecklistItem('Reflexao', _reflexao.text.trim().isNotEmpty),
      _EditorChecklistItem('Fontes', _fontes.text.trim().isNotEmpty),
      _EditorChecklistItem(
        'Video',
        _youtube.text.trim().isNotEmpty,
        optional: true,
      ),
      _EditorChecklistItem('Publicado', _status == EstudoCicloStatus.publicado),
      _EditorChecklistItem('Linha do tempo', _mostrarNaLinhaDoTempo),
    ];
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, color: t.primary, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Checklist editorial',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: items.map(_checkChip).toList(),
          ),
        ],
      ),
    );
  }

  Widget _checkChip(_EditorChecklistItem item) {
    final t = context.uai;
    final color = item.ok
        ? t.success
        : (item.optional ? t.textMuted : t.warning);
    final icon = item.ok
        ? Icons.check_circle_rounded
        : (item.optional
              ? Icons.radio_button_unchecked_rounded
              : Icons.warning_amber_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _statusHelp(String status) {
    switch (status) {
      case EstudoCicloStatus.publicado:
        return 'Publicado: aluno podera ver futuramente se o ciclo tambem estiver publicado.';
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

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool requiredField = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (!requiredField && text.isEmpty) return null;
        final n = int.tryParse(text);
        if (n == null || n <= 0) return 'Informe um numero positivo';
        return null;
      },
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool requiredField = false,
    int maxLines = 1,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, helperText: helperText),
      onChanged: (_) => setState(() {}),
      validator:
          validator ??
          (value) {
            if (requiredField && (value?.trim().isEmpty ?? true)) {
              return 'Campo obrigatorio';
            }
            return null;
          },
    );
  }

  String? _validarUrlsImagem(String? value) {
    final linhas = (value ?? '')
        .split(RegExp(r'\r?\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    for (final linha in linhas) {
      final url = EstudoModel.normalizarImagemUrl(linha);
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        return 'Informe URLs válidas, uma por linha';
      }
    }
    return null;
  }

  String? _validarUrlVideo(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      return 'Informe uma URL valida';
    }
    final host = uri.host.toLowerCase();
    if (!host.contains('youtube.com') && !host.contains('youtu.be')) {
      return 'Informe uma URL do YouTube';
    }
    return null;
  }

  String? _validarUrlGenerica(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      return 'Informe uma URL valida';
    }
    return null;
  }

  Widget _midiaControls() {
    final t = context.uai;
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
        if (_capa.text.trim().isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: Image.network(
                _capa.text.trim(),
                fit: BoxFit.cover,
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
          onPressed: _enviandoMidia ? null : _enviarCapaEstudo,
          icon: _enviandoMidia
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_rounded),
          label: Text(_enviandoMidia ? 'Enviando...' : 'Enviar capa do estudo'),
        ),
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

class _EditorChecklistItem {
  final String label;
  final bool ok;
  final bool optional;

  const _EditorChecklistItem(this.label, this.ok, {this.optional = false});
}
