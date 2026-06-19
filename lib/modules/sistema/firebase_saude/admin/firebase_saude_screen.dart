import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/sistema/firebase_saude/models/firebase_saude_models.dart';
import 'package:uai_capoeira/modules/sistema/firebase_saude/services/firebase_saude_service.dart';

class FirebaseSaudeScreen extends StatefulWidget {
  const FirebaseSaudeScreen({super.key});

  @override
  State<FirebaseSaudeScreen> createState() => _FirebaseSaudeScreenState();
}

class _FirebaseSaudeScreenState extends State<FirebaseSaudeScreen> {
  final FirebaseSaudeService _service = FirebaseSaudeService();
  final PermissaoService _permissaoService = PermissaoService();
  final TextEditingController _buscaController = TextEditingController();

  bool _verificandoAcesso = true;
  bool _temAcesso = false;
  bool _carregando = false;
  bool _carregandoDocumentos = false;
  String? _erro;
  FirebaseSaudeResumo? _resumo;
  List<FirebaseSaudeColecao> _colecoes = const [];
  List<FirebaseSaudeStorageItem> _storage = const [];
  List<FirebaseSaudeFunctionInfo> _functions = const [];
  String? _colecaoSelecionada;
  List<FirebaseSaudeDocumento> _documentos = const [];
  String? _nextPageToken;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final admin = await _permissaoService.usuarioAtualEhAdmin();
    if (!mounted) return;

    setState(() {
      _temAcesso = admin;
      _verificandoAcesso = false;
    });

    if (admin) {
      await _carregarTudo();
    }
  }

  Future<void> _carregarTudo() async {
    if (_carregando) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _service.obterResumo(),
        _service.listarColecoes(),
        _service.listarStorage(),
        _service.listarFunctions(),
      ]);

      if (!mounted) return;

      final colecoes = results[1] as List<FirebaseSaudeColecao>;
      final selecionada = _colecaoInicial(colecoes);

      setState(() {
        _resumo = results[0] as FirebaseSaudeResumo;
        _colecoes = colecoes;
        _storage = results[2] as List<FirebaseSaudeStorageItem>;
        _functions = results[3] as List<FirebaseSaudeFunctionInfo>;
        _colecaoSelecionada = selecionada;
      });

      if (selecionada != null) {
        await _listarDocumentos(reset: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _erroAmigavel(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _listarDocumentos({required bool reset}) async {
    final colecao = _colecaoSelecionada;
    if (colecao == null || _carregandoDocumentos) return;

    setState(() {
      _carregandoDocumentos = true;
      if (reset) {
        _documentos = const [];
        _nextPageToken = null;
        _hasMore = false;
      }
    });

    try {
      final page = await _service.listarDocumentos(
        colecao: colecao,
        startAfter: reset ? null : _nextPageToken,
        filtro: _buscaController.text,
      );

      if (!mounted) return;

      setState(() {
        _documentos = reset
            ? page.documentos
            : [..._documentos, ...page.documentos];
        _nextPageToken = page.nextPageToken;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(_erroAmigavel(e), color: context.uai.error);
    } finally {
      if (mounted) setState(() => _carregandoDocumentos = false);
    }
  }

  String? _colecaoInicial(List<FirebaseSaudeColecao> colecoes) {
    if (_colecaoSelecionada != null &&
        colecoes.any((item) => item.nome == _colecaoSelecionada)) {
      return _colecaoSelecionada;
    }

    for (final colecao in colecoes) {
      if (colecao.podeVisualizarDetalhes) return colecao.nome;
    }

    return null;
  }

  Future<void> _abrirDocumento(FirebaseSaudeDocumento doc) async {
    final colecao = _colecaoSelecionada;
    if (colecao == null) return;

    try {
      final completo = await _service.obterDocumento(
        colecao: colecao,
        docId: doc.id,
      );
      if (!mounted) return;
      _mostrarDocumento(completo);
    } catch (e) {
      if (!mounted) return;
      _snack(_erroAmigavel(e), color: context.uai.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Saúde Firebase',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando || !_temAcesso ? null : _carregarTudo,
            icon: _carregando
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final t = context.uai;

    if (_verificandoAcesso) {
      return Center(child: CircularProgressIndicator(color: t.primary));
    }

    if (!_temAcesso) {
      return _emptyState(
        icon: Icons.lock_rounded,
        title: 'Acesso restrito',
        message: 'Este painel é exclusivo para admin/master com conta ativa.',
      );
    }

    if (_erro != null && _resumo == null) {
      return _emptyState(
        icon: Icons.error_outline_rounded,
        title: 'Não foi possível carregar',
        message: _erro!,
        action: FilledButton.icon(
          onPressed: _carregarTudo,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 700 ? 14.0 : 22.0;
        final maxWidth = constraints.maxWidth >= 1200 ? 1180.0 : 980.0;

        return RefreshIndicator(
          onRefresh: _carregarTudo,
          color: t.primary,
          child: ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildResumoCards(),
                      const SizedBox(height: 14),
                      _buildVisaoGeral(),
                      const SizedBox(height: 14),
                      _buildFirestore(),
                      const SizedBox(height: 14),
                      _buildStorage(),
                      const SizedBox(height: 14),
                      _buildFunctions(),
                      const SizedBox(height: 14),
                      _buildUsoCustos(),
                      const SizedBox(height: 14),
                      _buildIntegridade(),
                      const SizedBox(height: 14),
                      _buildExplorer(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResumoCards() {
    final t = context.uai;
    final contadores = _resumo?.contadores ?? const <String, int>{};
    final alertas =
        _resumo?.diagnosticos
            .where((item) => item.quantidade > 0 && item.nivel != 'info')
            .length ??
        0;

    final cards = [
      _MetricCard(
        'Firestore',
        '${_sumDocsPrincipais(contadores)}',
        'docs mapeados',
        Icons.storage_rounded,
        t.primary,
      ),
      _MetricCard(
        'Storage',
        '${_storage.length}',
        'itens listados',
        Icons.folder_rounded,
        t.info,
      ),
      _MetricCard(
        'Functions',
        '${_functions.length}',
        'funções mapeadas',
        Icons.cloud_done_rounded,
        t.success,
      ),
      _MetricCard(
        'Atualizações',
        _valorAtualizacao('versaoAtual'),
        'versão atual',
        Icons.system_update_alt_rounded,
        t.warning,
      ),
      _MetricCard(
        'Logs',
        '${contadores['logs_recentes'] ?? 0}',
        'eventos recentes',
        Icons.receipt_long_rounded,
        t.associacao,
      ),
      _MetricCard(
        'Alertas',
        '$alertas',
        'diagnósticos ativos',
        Icons.health_and_safety_rounded,
        alertas > 0 ? t.warning : t.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map(
                (card) => SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 10) / columns,
                  child: _metricCard(card),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildVisaoGeral() {
    final resumo = _resumo;
    final atualizacoes = resumo?.atualizacoes ?? const <String, dynamic>{};

    return _section(
      icon: Icons.dashboard_rounded,
      title: 'Visão Geral',
      subtitle: 'Resumo seguro do ambiente e configurações principais.',
      child: _infoGrid([
        _InfoItem('Status geral', resumo?.statusGeral ?? 'carregando'),
        _InfoItem('Última sincronização', _formatDateTime(resumo?.timestamp)),
        _InfoItem(
          'Projeto',
          resumo?.projeto.isNotEmpty == true
              ? resumo!.projeto
              : 'não informado',
        ),
        _InfoItem('Versão atual', _stringValue(atualizacoes['versaoAtual'])),
        _InfoItem('Versão mínima', _stringValue(atualizacoes['versaoMinima'])),
        _InfoItem(
          'Obrigatória',
          atualizacoes['obrigatoria'] == true ? 'sim' : 'não',
        ),
      ]),
    );
  }

  Widget _buildFirestore() {
    final t = context.uai;

    return _section(
      icon: Icons.account_tree_rounded,
      title: 'Firestore',
      subtitle:
          'Coleções principais em allowlist, com contagem limitada/segura.',
      child: Column(
        children: _colecoes.map((colecao) {
          final color = _riskColor(colecao.risco);
          return _tile(
            icon: Icons.table_rows_rounded,
            color: color,
            title: colecao.nome,
            subtitle:
                '${colecao.descricao}\n${colecao.quantidade} documentos • risco ${colecao.risco}',
            trailing: colecao.podeVisualizarDetalhes
                ? TextButton.icon(
                    onPressed: () {
                      setState(() => _colecaoSelecionada = colecao.nome);
                      _listarDocumentos(reset: true);
                    },
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('Ver documentos'),
                  )
                : Icon(Icons.lock_rounded, color: t.textMuted),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStorage() {
    final totalBytes = _storage.fold<int>(0, (sum, item) => sum + item.tamanho);

    return _section(
      icon: Icons.folder_copy_rounded,
      title: 'Storage',
      subtitle:
          'Somente prefixos seguros conhecidos, sem URL pública ou exclusão.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _infoGrid([
            _InfoItem('Itens listados', '${_storage.length}'),
            _InfoItem('Tamanho aproximado', _formatBytes(totalBytes)),
          ]),
          const SizedBox(height: 8),
          ..._storage
              .take(16)
              .map(
                (item) => _tile(
                  icon: item.pasta
                      ? Icons.folder_rounded
                      : Icons.insert_drive_file_rounded,
                  color: context.uai.info,
                  title: item.nome,
                  subtitle:
                      '${item.path}\n${_formatBytes(item.tamanho)} • ${item.contentType.isEmpty ? 'sem contentType' : item.contentType}',
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFunctions() {
    return _section(
      icon: Icons.cloud_done_rounded,
      title: 'Functions',
      subtitle: 'Lista informativa manual das funções importantes do backend.',
      child: Column(
        children: _functions
            .map(
              (item) => _tile(
                icon: Icons.bolt_rounded,
                color: context.uai.success,
                title: item.nome,
                subtitle: '${item.descricao}\nStatus: ${item.status}',
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildUsoCustos() {
    final uso = _resumo?.usoCustos ?? const <String, dynamic>{};

    return _section(
      icon: Icons.payments_rounded,
      title: 'Uso e Custos',
      subtitle:
          'Sem inventar métricas de billing, tráfego, leituras ou escritas.',
      child: _notice(
        icon: Icons.info_rounded,
        color: context.uai.info,
        title: _stringValue(
          uso['status'],
          fallback: 'Cloud Monitoring não conectado',
        ),
        message: _stringValue(
          uso['orientacao'],
          fallback:
              'Configure Google Cloud Monitoring/Billing para métricas reais de leituras, escritas, tráfego e custos.',
        ),
      ),
    );
  }

  Widget _buildIntegridade() {
    final diagnosticos =
        _resumo?.diagnosticos ?? const <FirebaseSaudeDiagnostico>[];

    return _section(
      icon: Icons.fact_check_rounded,
      title: 'Integridade dos Dados',
      subtitle: 'Diagnósticos de leitura com consultas limitadas no backend.',
      child: diagnosticos.isEmpty
          ? _notice(
              icon: Icons.check_circle_rounded,
              color: context.uai.success,
              title: 'Nenhum alerta retornado',
              message:
                  'As verificações disponíveis não encontraram inconsistências.',
            )
          : Column(
              children: diagnosticos
                  .map(
                    (item) => _tile(
                      icon: item.quantidade > 0
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_rounded,
                      color: _diagnosticColor(item),
                      title: item.titulo,
                      subtitle:
                          '${item.descricao}\n${item.quantidade} ocorrência(s) em amostra segura',
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildExplorer() {
    final t = context.uai;
    final colecoesVisualizaveis = _colecoes
        .where((item) => item.podeVisualizarDetalhes)
        .toList();

    return _section(
      icon: Icons.manage_search_rounded,
      title: 'Explorador Controlado',
      subtitle:
          'Leitura paginada, allowlist fixa e campos sensíveis mascarados.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _colecaoSelecionada,
                  decoration: _inputDecoration('Coleção'),
                  items: colecoesVisualizaveis
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item.nome,
                          child: Text(
                            item.nome,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _colecaoSelecionada = value);
                    _listarDocumentos(reset: true);
                  },
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _buscaController,
                  decoration: _inputDecoration('Busca simples por texto/id')
                      .copyWith(
                        suffixIcon: IconButton(
                          tooltip: 'Buscar',
                          onPressed: () => _listarDocumentos(reset: true),
                          icon: const Icon(Icons.search_rounded),
                        ),
                      ),
                  onSubmitted: (_) => _listarDocumentos(reset: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_carregandoDocumentos && _documentos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: t.primary)),
            )
          else if (_documentos.isEmpty)
            _notice(
              icon: Icons.inbox_rounded,
              color: t.textMuted,
              title: 'Nenhum documento carregado',
              message: 'Selecione uma coleção permitida ou ajuste a busca.',
            )
          else
            ..._documentos.map(
              (doc) => _tile(
                icon: Icons.description_rounded,
                color: t.primary,
                title: doc.id,
                subtitle: _previewDoc(doc.dados),
                trailing: TextButton.icon(
                  onPressed: () => _abrirDocumento(doc),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Detalhe'),
                ),
              ),
            ),
          if (_hasMore) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _carregandoDocumentos
                  ? null
                  : () => _listarDocumentos(reset: false),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                _carregandoDocumentos ? 'Carregando...' : 'Carregar mais',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
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
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: 0.11),
                    t.cardAlt,
                  ),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withValues(alpha: 0.14)),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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

  Widget _metricCard(_MetricCard item) {
    final t = context.uai;
    final accent = _ensureVisible(item.color, t.card);

    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                accent.withValues(alpha: 0.12),
                t.cardAlt,
              ),
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
            child: Icon(item.icon, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoGrid(List<_InfoItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (item) => SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                  child: _infoBox(item.label, item.value),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _infoBox(String label, String value) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  Widget _notice({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    final t = context.uai;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: t.textMuted),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.35),
              ),
              if (action != null) ...[const SizedBox(height: 14), action],
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDocumento(FirebaseSaudeDocumento doc) {
    final t = context.uai;
    final json = const JsonEncoder.withIndent('  ').convert(doc.dados);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.86;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          doc.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SelectableText(
                      json,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label) {
    final t = context.uai;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  void _snack(String message, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _riskColor(String risco) {
    final value = risco.toLowerCase();
    if (value == 'alto') return context.uai.error;
    if (value == 'medio' || value == 'médio') return context.uai.warning;
    return context.uai.success;
  }

  Color _diagnosticColor(FirebaseSaudeDiagnostico item) {
    if (item.quantidade == 0) return context.uai.success;
    if (item.nivel == 'alto') return context.uai.error;
    if (item.nivel == 'medio' || item.nivel == 'médio') {
      return context.uai.warning;
    }
    return context.uai.info;
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;
    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  String _valorAtualizacao(String key) {
    final value = _resumo?.atualizacoes[key];
    return _stringValue(value, fallback: '-');
  }

  int _sumDocsPrincipais(Map<String, int> contadores) {
    const keys = [
      'usuarios_total',
      'alunos_total',
      'turmas_total',
      'eventos_total',
      'participacoes_total',
      'logs_recentes',
      'solicitacoes_pendentes',
    ];
    return keys.fold<int>(0, (sum, key) => sum + (contadores[key] ?? 0));
  }

  String _previewDoc(Map<String, dynamic> dados) {
    final entries = dados.entries
        .take(5)
        .map((entry) {
          final value = entry.value;
          final text = value is Map || value is List
              ? jsonEncode(value)
              : value.toString();
          return '${entry.key}: $text';
        })
        .join(' • ');
    return entries.isEmpty ? 'Documento sem campos visíveis' : entries;
  }

  String _stringValue(dynamic value, {String fallback = 'não informado'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'não informado';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _erroAmigavel(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? error.code;
    }
    return error.toString();
  }
}

class _MetricCard {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricCard(
    this.title,
    this.value,
    this.subtitle,
    this.icon,
    this.color,
  );
}

class _InfoItem {
  final String label;
  final String value;

  const _InfoItem(this.label, this.value);
}
