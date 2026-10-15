import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/estudos_acompanhamento_admin_service.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/reset_estudos_aluno_admin_service.dart';

class AlunoEstudosDashboardScreen extends StatefulWidget {
  final String alunoId;

  const AlunoEstudosDashboardScreen({super.key, required this.alunoId});

  @override
  State<AlunoEstudosDashboardScreen> createState() =>
      _AlunoEstudosDashboardScreenState();
}

class _AlunoEstudosDashboardScreenState
    extends State<AlunoEstudosDashboardScreen>
    with SingleTickerProviderStateMixin {
  final EstudosAcompanhamentoAdminService _service =
      EstudosAcompanhamentoAdminService();
  final ResetEstudosAlunoAdminService _resetService =
      ResetEstudosAlunoAdminService();
  late final TabController _tabController;
  Future<AlunoEstudosDashboard>? _future;
  bool _resetando = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _carregar() {
    if (!mounted) return;
    setState(() {
      _future = _service.carregarDashboardAluno(widget.alunoId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Dashboard do Aluno',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded), text: 'Visão geral'),
            Tab(icon: Icon(Icons.menu_book_rounded), text: 'Estudos'),
            Tab(icon: Icon(Icons.quiz_rounded), text: 'Tentativas'),
          ],
        ),
      ),
      body: FutureBuilder<AlunoEstudosDashboard>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }
          if (snapshot.hasError) {
            return _estadoCentral(
              Icons.error_outline_rounded,
              'Não foi possível carregar o aluno.',
              snapshot.error.toString(),
            );
          }
          final dados = snapshot.data;
          if (dados == null) {
            return _estadoCentral(
              Icons.person_search_rounded,
              'Aluno não encontrado.',
              'Atualize a tela para tentar novamente.',
            );
          }
          return TabBarView(
            controller: _tabController,
            children: [
              _tabVisaoGeral(dados),
              _tabEstudos(dados),
              _tabTentativas(dados),
            ],
          );
        },
      ),
    );
  }

  Widget _tabVisaoGeral(AlunoEstudosDashboard dados) {
    return _page(
      children: [
        _headerAluno(dados),
        const SizedBox(height: 14),
        _kpis(dados),
        const SizedBox(height: 14),
        _section(
          'Progresso por ciclo',
          Icons.timeline_rounded,
          Column(children: _cicloCards(dados)),
        ),
        const SizedBox(height: 14),
        _section(
          'O que observar nesse aluno',
          Icons.health_and_safety_rounded,
          _diagnostico(dados),
        ),
        if (dados.registrosAntigos > 0) ...[
          const SizedBox(height: 14),
          _registrosAntigosCard(dados),
        ],
        const SizedBox(height: 14),
        _zonaPerigo(dados),
      ],
    );
  }

  Widget _tabEstudos(AlunoEstudosDashboard dados) {
    final entries = dados.estudosPorCiclo.entries.toList();
    return _page(
      children: [
        for (final entry in entries) ...[
          _section(
            _cicloTitulo(dados, entry.key),
            Icons.menu_book_rounded,
            Column(
              children: entry.value.map((item) => _estudoTile(item)).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (entries.isEmpty)
          _estadoCentral(
            Icons.menu_book_outlined,
            'Sem estudos publicados.',
            'Quando houver estudos publicados, eles aparecerão aqui.',
          ),
      ],
    );
  }

  Widget _tabTentativas(AlunoEstudosDashboard dados) {
    return _page(
      children: [
        if (dados.tentativas.isEmpty)
          _estadoCentral(
            Icons.quiz_outlined,
            'Nenhuma tentativa registrada.',
            'As avaliações do aluno aparecerão aqui quando forem realizadas.',
          )
        else
          _section(
            'Tentativas e avaliações',
            Icons.quiz_rounded,
            Column(
              children: dados.tentativas
                  .map((tentativa) => _tentativaTile(dados, tentativa))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _page({required List<Widget> children}) {
    return RefreshIndicator(
      onRefresh: () async {
        _carregar();
        await _future;
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
          16,
          MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
          28,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerAluno(AlunoEstudosDashboard dados) {
    final t = context.uai;
    final aluno = dados.aluno;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(aluno, 66),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  aluno.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                _infoLine(
                  Icons.school_rounded,
                  [
                    aluno.turma,
                    aluno.academia,
                    aluno.graduacao,
                  ].where((e) => e.isNotEmpty).join(' • '),
                ),
                if (aluno.contaEmail.isNotEmpty)
                  _infoLine(Icons.mail_rounded, aluno.contaEmail),
                if (aluno.contaNome.isNotEmpty)
                  _infoLine(Icons.person_rounded, aluno.contaNome),
                if (aluno.metodoVinculo.isNotEmpty)
                  _infoLine(Icons.verified_user_rounded, 'Acesso: ${aluno.metodoVinculo}'),
                _infoLine(
                  Icons.schedule_rounded,
                  'Último acesso: ${formatarDataCurta(dados.resumo.ultimoAcesso)}',
                ),
              ],
            ),
          ),
          _statusPill(dados.resumo.statusLabel, _statusColor(dados.resumo)),
        ],
      ),
    );
  }

  Widget _registrosAntigosCard(AlunoEstudosDashboard dados) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.warning.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history_rounded, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registros antigos encontrados',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Este aluno possui ${dados.registrosAntigos} registro(s) antigo(s) de estudos que não estão mais disponíveis. Eles não entram no progresso atual.',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _resetando ? null : () => _confirmarReset(dados),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Resetar estudos do aluno'),
            style: OutlinedButton.styleFrom(foregroundColor: t.error),
          ),
        ],
      ),
    );
  }

  Widget _zonaPerigo(AlunoEstudosDashboard dados) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.error.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: t.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resetar estudos do aluno',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Apaga progresso, resultados e tentativas deste aluno no módulo Estudos/Fundamentos. Não apaga o cadastro do aluno.',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _resetando ? null : () => _confirmarReset(dados),
            icon: _resetando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_rounded),
            label: Text(_resetando ? 'Resetando...' : 'Resetar estudos'),
            style: FilledButton.styleFrom(backgroundColor: t.error),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarReset(AlunoEstudosDashboard dados) async {
    final controller = TextEditingController();
    var confirmado = false;
    final deveResetar = await showDialog<bool>(
      context: context,
      barrierDismissible: !_resetando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Resetar estudos do aluno'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aluno: ${dados.aluno.nome}'),
                  const SizedBox(height: 10),
                  const Text(
                    'Esta ação não apaga o cadastro do aluno. Ela apaga progresso dos estudos, resultados e tentativas/avaliações do módulo Estudos/Fundamentos.',
                  ),
                  const SizedBox(height: 12),
                  const Text('Digite APAGAR para confirmar.'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'APAGAR',
                    ),
                    onChanged: (value) {
                      setDialogState(() => confirmado = value == 'APAGAR');
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: confirmado
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Confirmar reset'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    if (deveResetar != true || !mounted) return;

    setState(() {
      _resetando = true;
    });
    try {
      await _resetService.resetarEstudosAluno(alunoId: dados.aluno.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Estudos do aluno resetados com sucesso.'),
        ),
      );
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível resetar os estudos: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _resetando = false;
        });
      }
    }
  }

  Widget _kpis(AlunoEstudosDashboard dados) {
    final resumo = dados.resumo;
    final items = [
      _Kpi(
        Icons.library_books_rounded,
        'Disponíveis',
        resumo.totalEstudos.toString(),
      ),
      _Kpi(Icons.play_arrow_rounded, 'Iniciados', resumo.iniciados.toString()),
      _Kpi(
        Icons.check_circle_rounded,
        'Concluídos',
        resumo.concluidos.toString(),
      ),
      _Kpi(Icons.verified_rounded, 'Aprovados', resumo.aprovados.toString()),
      _Kpi(
        Icons.pending_actions_rounded,
        'Pendentes',
        resumo.pendentes.toString(),
      ),
      _Kpi(Icons.quiz_rounded, 'Tentativas', resumo.tentativas.toString()),
      _Kpi(Icons.grade_rounded, 'Nota média', formatarNota(resumo.notaMedia)),
      _Kpi(Icons.star_rounded, 'Melhor nota', formatarNota(resumo.melhorNota)),
      _Kpi(Icons.percent_rounded, 'Progresso', '${resumo.percentual}%'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : (constraints.maxWidth >= 650 ? 2 : 1);
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map((item) => SizedBox(width: width, child: _kpiCard(item)))
              .toList(),
        );
      },
    );
  }

  List<Widget> _cicloCards(AlunoEstudosDashboard dados) {
    return dados.base.ciclos.map((ciclo) {
      final estudos = dados.estudos
          .where((item) => item.estudo.cicloId == ciclo.id)
          .toList();
      final concluidos = estudos.where((item) => item.concluido).length;
      final total = estudos.length;
      final percent = total <= 0 ? 0 : ((concluidos / total) * 100).round();
      final t = context.uai;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ciclo ${ciclo.numero}: ${ciclo.titulo}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '$concluidos/$total',
                  style: TextStyle(
                    color: t.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 8,
                color: _statusColor(dados.resumo),
                backgroundColor: t.cardAlt,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _diagnostico(AlunoEstudosDashboard dados) {
    final mensagens = <String>[];
    final resumo = dados.resumo;
    if (resumo.iniciados == 0) {
      mensagens.add('Aluno ainda não iniciou nenhum estudo.');
    }
    if (resumo.iniciados > 0 && resumo.concluidos == 0) {
      mensagens.add('Aluno iniciou, mas ainda não concluiu estudos.');
    }
    if (resumo.tentativas != null &&
        resumo.tentativas! >= 3 &&
        resumo.aprovados == 0) {
      mensagens.add('Aluno fez várias tentativas e ainda não aprovou.');
    }
    if (resumo.percentual >= 50 && resumo.concluidos < resumo.totalEstudos) {
      mensagens.add('Aluno está com bom avanço.');
    }
    if (resumo.totalEstudos > 0 && resumo.concluidos >= resumo.totalEstudos) {
      mensagens.add('Aluno concluiu todos os estudos disponíveis.');
    }
    if (mensagens.isEmpty) {
      mensagens.add(
        'Acompanhe os próximos acessos para identificar o ritmo do aluno.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: mensagens.map((msg) => _alerta(msg)).toList(),
    );
  }

  Widget _estudoTile(EstudoProgressoAdmin item) {
    final t = context.uai;
    final color = _estudoColor(item);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.article_rounded, color: color),
        title: Text(
          'Estudo ${item.estudo.numero}: ${item.estudo.titulo}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${item.statusLabel} • Progresso ${item.progresso?.percentual ?? 0}% • Tentativas ${item.tentativas.length}${item.resultado?.nota == null ? '' : ' • Nota ${formatarNota(item.resultado?.nota)}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: t.textMuted),
        onTap: () => _showEstudoDetalhe(item),
      ),
    );
  }

  Widget _tentativaTile(
    AlunoEstudosDashboard dados,
    TentativaEstudoAdmin tentativa,
  ) {
    final estudo = dados.base.estudoPorId[tentativa.estudoId];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          tentativa.aprovado
              ? Icons.verified_rounded
              : Icons.assignment_rounded,
          color: tentativa.aprovado ? context.uai.success : context.uai.warning,
        ),
        title: Text(
          estudo?.titulo ?? 'Tentativa ${tentativa.id}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${formatarDataCurta(tentativa.dataReferencia)} • Nota ${formatarNota(tentativa.nota)} • ${tentativa.acertos}/${tentativa.total} acertos • ${tentativa.status.isEmpty ? 'sem status' : tentativa.status}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _showTentativaDetalhe(dados, tentativa),
      ),
    );
  }

  void _showEstudoDetalhe(EstudoProgressoAdmin item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _detalheSheet(
        title: item.estudo.titulo,
        children: [
          _detailRow(
            'Ciclo',
            item.ciclo?.titulo ?? item.estudo.cicloTituloSnapshot,
          ),
          _detailRow('Status', item.statusLabel),
          _detailRow('Progresso', '${item.progresso?.percentual ?? 0}%'),
          _detailRow('Nota', formatarNota(item.resultado?.nota)),
          _detailRow(
            'Aprovado',
            item.resultado?.aprovado == true ? 'Sim' : 'Não',
          ),
          _detailRow('Tentativas', item.tentativas.length.toString()),
          _detailRow('Início', formatarDataCurta(item.progresso?.iniciadoEm)),
          _detailRow(
            'Último acesso',
            formatarDataCurta(item.progresso?.dataReferencia),
          ),
          _detailRow(
            'Conclusão',
            formatarDataCurta(item.progresso?.concluidoEm),
          ),
        ],
      ),
    );
  }

  void _showTentativaDetalhe(
    AlunoEstudosDashboard dados,
    TentativaEstudoAdmin tentativa,
  ) {
    final estudo = dados.base.estudoPorId[tentativa.estudoId];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _detalheSheet(
        title: estudo?.titulo ?? 'Tentativa ${tentativa.id}',
        children: [
          _detailRow('Data', formatarDataCurta(tentativa.dataReferencia)),
          _detailRow('Nota', formatarNota(tentativa.nota)),
          _detailRow('Acertos', '${tentativa.acertos}/${tentativa.total}'),
          _detailRow('Aprovado', tentativa.aprovado ? 'Sim' : 'Não'),
          _detailRow('Status', tentativa.status),
          _detailRow('Origem', tentativa.origem),
          if (tentativa.respostas.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Respostas registradas',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...tentativa.respostas
                .take(30)
                .map((resposta) => _respostaTile(resposta)),
          ],
        ],
      ),
    );
  }

  Widget _detalheSheet({
    required String title,
    required List<Widget> children,
  }) {
    final t = context.uai;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _respostaTile(dynamic resposta) {
    final text = resposta is Map
        ? resposta.entries.map((e) => '${e.key}: ${e.value}').join('\n')
        : resposta.toString();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.uai.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.uai.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: context.uai.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, Widget child) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: t.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _kpiCard(_Kpi item) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: t.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            item.value,
            style: TextStyle(
              color: t.primary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final t = context.uai;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, color: t.textMuted, size: 15),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final t = context.uai;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '--' : value,
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

  Widget _alerta(String text) {
    final t = context.uai;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.info.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _avatar(AlunoVinculadoEstudos aluno, double size) {
    final t = context.uai;
    if (aluno.fotoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          aluno.fotoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _avatarFallback(aluno, size),
        ),
      );
    }
    return _avatarFallback(aluno, size, color: t.primary);
  }

  Widget _avatarFallback(
    AlunoVinculadoEstudos aluno,
    double size, {
    Color? color,
  }) {
    final t = context.uai;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: (color ?? t.primary).withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        aluno.nome.isEmpty ? '?' : aluno.nome.characters.first.toUpperCase(),
        style: TextStyle(
          color: color ?? t.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.22)),
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

  Color _statusColor(AlunoEstudosResumo item) {
    final t = context.uai;
    return switch (item.statusLabel) {
      'Concluiu tudo' => t.success,
      'Avançando' => t.primary,
      'Precisa atenção' => t.warning,
      'Não iniciou' => t.textMuted,
      _ => t.info,
    };
  }

  Color _estudoColor(EstudoProgressoAdmin item) {
    final t = context.uai;
    return switch (item.statusLabel) {
      'Aprovado' || 'Concluído' => t.success,
      'Reprovado' => t.warning,
      'Iniciado' => t.info,
      _ => t.textMuted,
    };
  }

  String _cicloTitulo(AlunoEstudosDashboard dados, String cicloId) {
    final ciclo = dados.base.cicloPorId[cicloId];
    if (ciclo == null) return 'Ciclo não identificado';
    return 'Ciclo ${ciclo.numero}: ${ciclo.titulo}';
  }

  Widget _estadoCentral(
    IconData icon,
    String title,
    String text, {
    Widget? action,
  }) {
    final t = context.uai;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: t.primary, size: 46),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }
}

class _Kpi {
  final IconData icon;
  final String label;
  final String value;

  const _Kpi(this.icon, this.label, this.value);
}
