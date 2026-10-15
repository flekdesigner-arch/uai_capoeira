import 'dart:async';
import 'package:uai_capoeira/core/session_log/session_log_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/inscricoes/public/visualizar_termo_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/services/inscricao_archive_service.dart';

/// Optional boundaries for widget tests. The normal screen uses the existing services.
class InscricaoHistoricoRecord {
  const InscricaoHistoricoRecord(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;
}

class InscricoesAprovadasOperations {
  const InscricoesAprovadasOperations({
    required this.records,
    required this.reactivate,
    required this.delete,
    required this.record,
  });

  final Stream<List<InscricaoHistoricoRecord>> Function(bool approved) records;
  final Future<void> Function(String inscricaoId) reactivate;
  final Future<void> Function(String inscricaoId, bool arquivada) delete;
  final void Function(String inscricaoId, String operation, String result) record;
}

class InscricoesAprovadasDialog extends StatefulWidget {
  final bool podeReativarArquivada;
  final bool podeExcluirPermanente;
  final InscricoesAprovadasOperations? operations;

  const InscricoesAprovadasDialog({
    super.key,
    this.podeReativarArquivada = false,
    this.podeExcluirPermanente = false,
    this.operations,
  });

  @override
  State<InscricoesAprovadasDialog> createState() =>
      _InscricoesAprovadasDialogState();
}

class _InscricoesAprovadasDialogState extends State<InscricoesAprovadasDialog>
    with SingleTickerProviderStateMixin {
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final InscricaoArchiveService _archiveService = InscricaoArchiveService();

  void _recordOperation(String id, String operation, String result) {
    if (widget.operations != null) {
      widget.operations!.record(id, operation, result);
      return;
    }
    unawaited(SessionLogService.instance.recordEntityOperation(
      module: 'inscricoes', entityType: 'inscricao', entityId: id,
      operation: operation, result: result,
    ));
  }

  void _closeLoadingRoute(Route<dynamic>? route) {
    final navigator = route?.navigator;
    if (route == null || !route.isActive || navigator == null || !navigator.mounted) {
      return;
    }
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  Stream<List<InscricaoHistoricoRecord>> _history(bool approved) {
    if (widget.operations != null) return widget.operations!.records(approved);
    return _firestore
        .collection(approved ? 'inscricoes_aprovadas' : 'inscricoes_arquivadas')
        .orderBy(approved ? 'aprovado_em' : 'arquivada_em', descending: true)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs)
                InscricaoHistoricoRecord(
                  doc.id,
                  Map<String, dynamic>.from(doc.data()),
                ),
            ]);
  }
  late final TabController _tabs;
  final TextEditingController _buscaController = TextEditingController();
  String _busca = '';
  String _periodo = 'todos';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
          maxWidth: 620,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(46),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            _header(),
            Container(
              color: t.cardAlt,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: TabBar(
                controller: _tabs,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: t.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.primary.withAlpha(56)),
                ),
                labelColor: t.primary,
                unselectedLabelColor: t.textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                tabs: const [
                  Tab(text: 'APROVADAS'),
                  Tab(text: 'ARQUIVADAS'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                children: [
                  TextField(
                    controller: _buscaController,
                    onChanged: (v) => setState(() => _busca = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nome, CPF, telefone, responsável, turma ou motivo...',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _periodoChip('todos', 'Todo período'),
                        const SizedBox(width: 6),
                        _periodoChip('mes', 'Este mês'),
                        const SizedBox(width: 6),
                        _periodoChip('3m', '3 meses'),
                        const SizedBox(width: 6),
                        _periodoChip('ano', 'Este ano'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _historicoAprovadas(),
                  _historicoArquivadas(),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.cardAlt,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(26)),
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('FECHAR'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final t = context.uai;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.success, Color.alphaBlend(t.primary.withAlpha(64), t.success)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(41),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.inventory_2_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Histórico de Inscrições',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Conversões em alunos e solicitações arquivadas',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }


  Widget _periodoChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _periodo == value,
      onSelected: (_) => setState(() => _periodo = value),
    );
  }

  String _normalizar(String value) {
    var s = value.toLowerCase().trim();
    const mapa = {
      'á':'a','à':'a','ã':'a','â':'a','ä':'a',
      'é':'e','è':'e','ê':'e','ë':'e',
      'í':'i','ì':'i','î':'i','ï':'i',
      'ó':'o','ò':'o','õ':'o','ô':'o','ö':'o',
      'ú':'u','ù':'u','û':'u','ü':'u','ç':'c',
    };
    mapa.forEach((a,b) => s = s.replaceAll(a,b));
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  bool _passaPeriodo(Map<String, dynamic> data, {required bool aprovado}) {
    if (_periodo == 'todos') return true;
    final raw = aprovado ? data['aprovado_em'] : data['arquivada_em'];
    DateTime? date;
    if (raw is Timestamp) date = raw.toDate();
    if (date == null) return false;
    final now = DateTime.now();
    if (_periodo == 'mes') return date.year == now.year && date.month == now.month;
    if (_periodo == 'ano') return date.year == now.year;
    if (_periodo == '3m') return date.isAfter(DateTime(now.year, now.month - 3, now.day));
    return true;
  }

  bool _matchBusca(Map<String, dynamic> data, {required bool aprovado}) {
    if (!_passaPeriodo(data, aprovado: aprovado)) return false;
    final q = _normalizar(_busca);
    if (q.isEmpty) return true;
    final telefone = '${data['contato_aluno'] ?? ''} ${data['contato_responsavel'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final cpf = '${data['cpf'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final partes = [
      data['nome'], data['aluno_nome'], data['apelido'], data['aluno_apelido'],
      data['nome_responsavel'], data['turma_nome'], data['academia_nome'],
      data['motivo_recusa'], data['observacao_recusa'], data['etapa_atendimento'],
      telefone, cpf,
    ].map((e) => _normalizar(e?.toString() ?? '')).join(' ');
    final qDigits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return partes.contains(q) || (qDigits.length >= 3 && (telefone.contains(qDigits) || cpf.contains(qDigits)));
  }

  Widget _historicoAprovadas() {
    return StreamBuilder<List<InscricaoHistoricoRecord>>(
      stream: _history(true),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _erro(snapshot.error);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!
            .where((record) => _matchBusca(record.data, aprovado: true))
            .toList();
        if (docs.isEmpty) {
          return _vazio(
            Icons.how_to_reg_rounded,
            'Nenhuma inscrição aprovada',
            'As inscrições convertidas em alunos aparecerão aqui.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data;
            return _AprovadaCard(
              inscricaoId: doc.id,
              data: data,
              onOpen: () => _abrirDetalhes(doc.id, data, aprovado: true),
            );
          },
        );
      },
    );
  }

  Widget _historicoArquivadas() {
    return StreamBuilder<List<InscricaoHistoricoRecord>>(
      stream: _history(false),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _erro(snapshot.error);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!
            .where((record) => _matchBusca(record.data, aprovado: false))
            .toList();
        if (docs.isEmpty) {
          return _vazio(
            Icons.archive_outlined,
            'Nenhuma inscrição arquivada',
            'Solicitações recusadas permanecerão preservadas aqui.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data;
            return _HistoricoCard(
              data: data,
              aprovado: false,
              onOpen: () => _abrirDetalhes(doc.id, data, aprovado: false),
            );
          },
        );
      },
    );
  }

  void _abrirDetalhes(
    String id,
    Map<String, dynamic> data, {
    required bool aprovado,
  }) {
    final t = context.uai;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(10),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .88,
            maxWidth: 620,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(26),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _avatar(data['foto_url']?.toString(), radius: 31),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${data['aluno_nome'] ?? data['nome'] ?? 'Aluno'}',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            aprovado ? 'INSCRIÇÃO APROVADA' : 'INSCRIÇÃO ARQUIVADA',
                            style: TextStyle(
                              color: aprovado ? t.success : t.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!aprovado && widget.podeExcluirPermanente)
                      IconButton(
                        tooltip: 'Excluir permanentemente',
                        onPressed: () => _confirmarExclusaoDefinitiva(
                          sheetContext,
                          id,
                          '${data['aluno_nome'] ?? data['nome'] ?? 'Aluno'}',
                        ),
                        icon: Icon(Icons.delete_forever_rounded, color: t.error),
                      ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _linha('Data da inscrição', _date(data['data_inscricao'])),
                if (aprovado) ...[
                  _linha('Aprovada em', _date(data['aprovado_em'])),
                  _linha('Turma', '${data['turma_nome'] ?? 'Não informado'}'),
                  _linha('Academia', '${data['academia_nome'] ?? 'Não informado'}'),
                  _linha('Convertida por', '${data['aprovado_por'] ?? 'Não informado'}'),
                ] else ...[
                  _linha('Arquivada em', _date(data['arquivada_em'])),
                  _linha('Motivo', '${data['motivo_recusa'] ?? 'Não informado'}'),
                  _linha('Arquivada por', '${data['recusada_por_email'] ?? 'Não informado'}'),
                  _linha(
                    'Foto otimizada',
                    data['foto_compactada_85'] == true
                        ? 'Sim • JPEG qualidade 85'
                        : 'Arquivo preservado',
                  ),
                ],
                const SizedBox(height: 12),
                if ((data['assinatura_url']?.toString().trim().isNotEmpty ?? false))
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VisualizarTermoScreen(
                            dados: data,
                            inscricaoId: id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.draw_rounded),
                    label: const Text('VER TERMO E ASSINATURA'),
                  ),
                if (!aprovado && widget.podeReativarArquivada) ...[
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _confirmarReativacao(
                      sheetContext,
                      id,
                      '${data['aluno_nome'] ?? data['nome'] ?? 'Aluno'}',
                    ),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('REATIVAR INSCRIÇÃO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A inscrição voltará para a fila de pendentes com os dados, foto, termo e assinatura preservados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textMuted, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }



  Future<void> _confirmarExclusaoDefinitiva(
    BuildContext sheetContext,
    String inscricaoId,
    String nome,
  ) async {
    final confirmado = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.uai.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: dialogContext.uai.error),
            const SizedBox(width: 10),
            const Expanded(child: Text('Excluir permanentemente?')),
          ],
        ),
        content: Text(
          'Esta ação apaga $nome definitivamente, incluindo dados, foto e assinatura do Storage. Não poderá ser desfeita.',
          style: TextStyle(color: dialogContext.uai.textSecondary, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: dialogContext.uai.error,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted || !sheetContext.mounted) return;

    final loadingReady = Completer<Route<dynamic>?>();
    final loadingFuture = showDialog<void>(
      context: sheetContext,
      barrierDismissible: false,
      builder: (ctx) {
        if (!loadingReady.isCompleted) loadingReady.complete(ModalRoute.of(ctx));
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: ctx.uai.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: ctx.uai.error),
                  const SizedBox(height: 16),
                  const Text('Excluindo inscrição definitivamente...'),
                ],
              ),
            ),
          ),
        );
      },
    );
    unawaited(loadingFuture.then((_) {
      if (!loadingReady.isCompleted) loadingReady.complete(null);
    }));
    final loadingRoute = await loadingReady.future;

    try {
      if (widget.operations == null) {
        await _archiveService.excluirInscricaoPermanente(
          inscricaoId: inscricaoId,
          arquivada: true,
        );
      } else {
        await widget.operations!.delete(inscricaoId, true);
      }
      _recordOperation(inscricaoId, 'excluiu', 'sucesso');
      _closeLoadingRoute(loadingRoute);
      if (sheetContext.mounted && ModalRoute.of(sheetContext)?.isCurrent == true) {
        Navigator.pop(sheetContext);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inscrição arquivada excluída permanentemente.'),
          backgroundColor: context.uai.success,
        ),
      );
    } catch (e) {
      _recordOperation(inscricaoId, 'excluiu', 'falha');
      _closeLoadingRoute(loadingRoute);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível excluir: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  Future<void> _confirmarReativacao(
    BuildContext sheetContext,
    String inscricaoId,
    String nome,
  ) async {
    final confirmado = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.uai.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.restore_rounded, color: dialogContext.uai.success),
            const SizedBox(width: 10),
            const Expanded(child: Text('Reativar inscrição?')),
          ],
        ),
        content: Text(
          '$nome voltará para a lista de inscrições pendentes e poderá seguir novamente pelo fluxo de contato, aula experimental, aprovação ou arquivamento.',
          style: TextStyle(color: dialogContext.uai.textSecondary, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('REATIVAR'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted || !sheetContext.mounted) return;

    final loadingReady = Completer<Route<dynamic>?>();
    final loadingFuture = showDialog<void>(
      context: sheetContext,
      barrierDismissible: false,
      builder: (ctx) {
        if (!loadingReady.isCompleted) loadingReady.complete(ModalRoute.of(ctx));
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: ctx.uai.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: ctx.uai.success),
                  const SizedBox(height: 16),
                  Text(
                    'Reativando inscrição...',
                    style: TextStyle(
                      color: ctx.uai.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Devolvendo a inscrição para a fila de pendentes com todos os dados preservados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ctx.uai.textSecondary, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    unawaited(loadingFuture.then((_) {
      if (!loadingReady.isCompleted) loadingReady.complete(null);
    }));
    final loadingRoute = await loadingReady.future;

    try {
      if (widget.operations == null) {
        await _archiveService.reativarInscricao(inscricaoId: inscricaoId);
      } else {
        await widget.operations!.reactivate(inscricaoId);
      }
      _recordOperation(inscricaoId, 'reativou', 'sucesso');
      _closeLoadingRoute(loadingRoute);
      if (!mounted) return;
      if (sheetContext.mounted && ModalRoute.of(sheetContext)?.isCurrent == true) {
        Navigator.of(sheetContext).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Inscrição de $nome reativada e devolvida para pendentes.'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _recordOperation(inscricaoId, 'reativou', 'falha');
      _closeLoadingRoute(loadingRoute);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao reativar inscrição: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _linha(String label, String value) {
    final t = context.uai;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.textMuted, fontSize: 11))),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? url, {double radius = 27}) {
    final t = context.uai;
    if (url == null || url.trim().isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: t.cardAlt,
        child: Icon(Icons.person_rounded, color: t.textMuted),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: t.cardAlt,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => Icon(Icons.person_rounded, color: t.textMuted),
        ),
      ),
    );
  }

  Widget _erro(Object? e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível carregar o histórico.\n${e ?? ''}',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.uai.error),
          ),
        ),
      );

  Widget _vazio(IconData icon, String title, String subtitle) {
    final t = context.uai;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: t.textMuted),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary)),
          ],
        ),
      ),
    );
  }

  String _date(dynamic value) {
    if (value is Timestamp) return DateFormat('dd/MM/yyyy HH:mm').format(value.toDate());
    return 'Não informado';
  }
}

class _AprovadaCard extends StatefulWidget {
  final String inscricaoId;
  final Map<String, dynamic> data;
  final VoidCallback onOpen;
  const _AprovadaCard({
    required this.inscricaoId,
    required this.data,
    required this.onOpen,
  });

  @override
  State<_AprovadaCard> createState() => _AprovadaCardState();
}

class _AprovadaCardState extends State<_AprovadaCard> {
  String? _fotoAlunoAtual;

  @override
  void initState() {
    super.initState();
    _carregarFotoAtual();
  }

  Future<void> _carregarFotoAtual() async {
    final alunoId = widget.data['aluno_id']?.toString();
    if (alunoId == null || alunoId.isEmpty) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('alunos').doc(alunoId).get();
      final url = snap.data()?['foto_perfil_aluno']?.toString();
      if (mounted && url != null && url.isNotEmpty) {
        setState(() => _fotoAlunoAtual = url);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return _HistoricoCard(
      data: data,
      aprovado: true,
      fotoOverride: _fotoAlunoAtual,
      onOpen: widget.onOpen,
    );
  }
}

class _HistoricoCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool aprovado;
  final String? fotoOverride;
  final VoidCallback onOpen;

  const _HistoricoCard({
    required this.data,
    required this.aprovado,
    required this.onOpen,
    this.fotoOverride,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final nome = '${data['aluno_nome'] ?? data['nome'] ?? 'Aluno'}';
    final foto = fotoOverride ?? data['foto_url']?.toString();
    final dateValue = aprovado ? data['aprovado_em'] : data['arquivada_em'];
    final date = dateValue is Timestamp
        ? DateFormat('dd/MM/yyyy').format(dateValue.toDate())
        : 'Sem data';
    final secondary = aprovado
        ? '${data['turma_nome'] ?? 'Turma não informada'}'
        : '${data['motivo_recusa'] ?? 'Sem motivo informado'}';
    final accent = aprovado ? t.success : t.error;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withAlpha(46)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: t.cardAlt,
                child: foto == null || foto.isEmpty
                    ? Icon(Icons.person_rounded, color: t.textMuted)
                    : ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: foto,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              Icon(Icons.person_rounded, color: t.textMuted),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _chip(
                          context,
                          aprovado ? 'APROVADA' : 'ARQUIVADA',
                          accent,
                        ),
                        Text(date,
                            style: TextStyle(color: t.textMuted, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}
