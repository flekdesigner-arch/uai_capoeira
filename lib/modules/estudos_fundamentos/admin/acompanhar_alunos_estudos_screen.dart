import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/aluno_estudos_dashboard_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/estudos_acompanhamento_admin_service.dart';

class AcompanharAlunosEstudosScreen extends StatefulWidget {
  const AcompanharAlunosEstudosScreen({super.key});

  @override
  State<AcompanharAlunosEstudosScreen> createState() =>
      _AcompanharAlunosEstudosScreenState();
}

class _AcompanharAlunosEstudosScreenState
    extends State<AcompanharAlunosEstudosScreen> {
  final EstudosAcompanhamentoAdminService _service =
      EstudosAcompanhamentoAdminService();
  final TextEditingController _buscaController = TextEditingController();

  Future<EstudosAcompanhamentoGeral>? _future;
  String _busca = '';
  String _filtro = 'todos';
  String _ordenacao = 'nome';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _carregar() {
    if (!mounted) return;
    setState(() {
      _future = _service.carregarResumoAlunosVinculados();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Acompanhar Alunos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<EstudosAcompanhamentoGeral>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }
          if (snapshot.hasError) {
            return _estadoCentral(
              Icons.error_outline_rounded,
              'Não foi possível carregar o acompanhamento.',
              snapshot.error.toString(),
              action: FilledButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            );
          }
          final dados = snapshot.data;
          if (dados == null) {
            return _estadoCentral(
              Icons.groups_rounded,
              'Sem dados para exibir.',
              'Atualize a tela para tentar novamente.',
            );
          }
          final alunos = _filtrarOrdenar(dados.alunos);
          return RefreshIndicator(
            color: t.primary,
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
                      children: [
                        _header(dados),
                        const SizedBox(height: 14),
                        _filtros(),
                        const SizedBox(height: 14),
                        if (alunos.isEmpty)
                          _estadoListaVazia()
                        else
                          _gridAlunos(alunos),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<AlunoEstudosResumo> _filtrarOrdenar(List<AlunoEstudosResumo> source) {
    final query = _busca.trim().toLowerCase();
    var alunos = source.where((item) {
      final matchBusca = query.isEmpty || item.aluno.busca.contains(query);
      final matchFiltro = switch (_filtro) {
        'nao_iniciaram' => item.iniciados == 0,
        'andamento' =>
          item.iniciados > 0 && item.concluidos < item.totalEstudos,
        'concluiram' =>
          item.totalEstudos > 0 && item.concluidos >= item.totalEstudos,
        'tentativas' => (item.tentativas ?? 0) > 0,
        'atencao' => item.precisaAtencao,
        _ => true,
      };
      return matchBusca && matchFiltro;
    }).toList();

    alunos.sort((a, b) {
      switch (_ordenacao) {
        case 'maior_progresso':
          return b.percentual.compareTo(a.percentual);
        case 'menor_progresso':
          return a.percentual.compareTo(b.percentual);
        case 'ultimo_acesso':
          return _compareDateDesc(a.ultimoAcesso, b.ultimoAcesso);
        case 'mais_tentativas':
          return _compareTentativasDesc(a.tentativas, b.tentativas);
        case 'nome':
        default:
          return a.aluno.nome.toLowerCase().compareTo(
            b.aluno.nome.toLowerCase(),
          );
      }
    });
    return alunos;
  }

  int _compareTentativasDesc(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  String _formatTentativas(int? value) =>
      value == null ? '--' : value.toString();
  int _compareDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  Widget _header(EstudosAcompanhamentoGeral dados) {
    return _section(
      title: 'Resumo geral',
      icon: Icons.analytics_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1000 ? 3 : (width >= 650 ? 2 : 1);
          final itemWidth = (width - ((columns - 1) * 10)) / columns;
          final items = [
            _Kpi(
              Icons.groups_rounded,
              'Alunos vinculados',
              dados.totalVinculados.toString(),
            ),
            _Kpi(
              Icons.play_circle_rounded,
              'Iniciaram estudos',
              dados.iniciaram.toString(),
            ),
            _Kpi(
              Icons.hourglass_empty_rounded,
              'Sem iniciar',
              dados.semIniciar.toString(),
            ),
            _Kpi(
              Icons.trending_up_rounded,
              'Média de progresso',
              '${dados.mediaProgresso}%',
            ),
            _Kpi(
              Icons.quiz_rounded,
              'Total de tentativas',
              dados.temTentativasDesconhecidas
                  ? '${dados.totalTentativas} parcial'
                  : dados.totalTentativas.toString(),
            ),
            _Kpi(
              Icons.verified_rounded,
              'Concluídos/aprovados',
              dados.totalConcluidos.toString(),
            ),
          ];
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map(
                  (item) => SizedBox(width: itemWidth, child: _kpiCard(item)),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _filtros() {
    final t = context.uai;
    return _section(
      title: 'Busca e filtros',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _buscaController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              labelText: 'Buscar por nome, turma, graduação ou conta vinculada',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) => setState(() => _busca = value),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filtroChip('todos', 'Todos'),
              _filtroChip('nao_iniciaram', 'Não iniciaram'),
              _filtroChip('andamento', 'Em andamento'),
              _filtroChip('concluiram', 'Concluíram'),
              _filtroChip('tentativas', 'Com tentativas'),
              _filtroChip('atencao', 'Precisam atenção'),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _ordenacao,
            decoration: InputDecoration(
              labelText: 'Ordenar por',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'nome', child: Text('Nome')),
              DropdownMenuItem(
                value: 'maior_progresso',
                child: Text('Maior progresso'),
              ),
              DropdownMenuItem(
                value: 'menor_progresso',
                child: Text('Menor progresso'),
              ),
              DropdownMenuItem(
                value: 'ultimo_acesso',
                child: Text('Último acesso'),
              ),
              DropdownMenuItem(
                value: 'mais_tentativas',
                child: Text('Mais tentativas'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _ordenacao = value ?? _ordenacao),
          ),
          const SizedBox(height: 2),
          Text(
            'Somente leitura. Este painel não altera progresso, resultados ou tentativas.',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridAlunos(List<AlunoEstudosResumo> alunos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 3 : (width >= 720 ? 2 : 1);
        final cardWidth = (width - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: alunos
              .map(
                (aluno) => SizedBox(width: cardWidth, child: _alunoCard(aluno)),
              )
              .toList(),
        );
      },
    );
  }

  Widget _alunoCard(AlunoEstudosResumo item) {
    final t = context.uai;
    final color = _statusColor(item);
    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlunoEstudosDashboardScreen(alunoId: item.aluno.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(t.cardRadius),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatar(item.aluno, 54),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.aluno.nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _smallText(
                          [
                            item.aluno.turma,
                            item.aluno.graduacao,
                          ].where((e) => e.isNotEmpty).join(' • '),
                        ),
                        if (item.aluno.contaEmail.isNotEmpty)
                          _smallText(item.aluno.contaEmail),
                        if (item.aluno.metodoVinculo.isNotEmpty)
                          _smallText('Acesso: ${item.aluno.metodoVinculo}'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statusPill(item.statusLabel, color),
                  const Spacer(),
                  Text(
                    '${item.percentual}%',
                    style: TextStyle(
                      color: t.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: item.percentual.clamp(0, 100) / 100,
                  minHeight: 8,
                  color: color,
                  backgroundColor: t.cardAlt,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metric('Iniciados', item.iniciados.toString()),
                  _metric('Concluídos', item.concluidos.toString()),
                  _metric('Tentativas', _formatTentativas(item.tentativas)),
                  _metric('Média', formatarNota(item.notaMedia)),
                ],
              ),
              const SizedBox(height: 10),
              _smallText(
                'Último acesso: ${formatarDataCurta(item.ultimoAcesso)}',
              ),
              if (item.ultimoEstudoTitulo.isNotEmpty)
                _smallText('Último estudo: ${item.ultimoEstudoTitulo}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
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
        color: t.cardAlt,
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
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtroChip(String value, String label) {
    return FilterChip(
      selected: _filtro == value,
      label: Text(label),
      onSelected: (_) => setState(() => _filtro = value),
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

  Widget _smallText(String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final t = context.uai;
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: t.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _metric(String label, String value) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
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

  Widget _estadoListaVazia() {
    return _estadoCentral(
      Icons.search_off_rounded,
      'Nenhum aluno encontrado.',
      'Ajuste a busca ou os filtros para ver outros alunos vinculados.',
    );
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
            if (action != null) ...[const SizedBox(height: 12), action],
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
