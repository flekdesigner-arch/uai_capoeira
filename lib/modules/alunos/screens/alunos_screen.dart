import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/core/theme/app_theme.dart';

import 'aluno_detalhe_screen.dart';
import 'editar_aluno_screen.dart';

class AlunosScreen extends StatefulWidget {
  const AlunosScreen({super.key});

  @override
  State<AlunosScreen> createState() => _AlunosScreenState();
}

class _AlunosScreenState extends State<AlunosScreen> {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  String? _svgContent;
  String _searchQuery = '';
  String _statusFilter = 'ATIVO(A)';
  int _viewMode = 0;

  final List<IconData> _viewModeIcons = [
    Icons.view_list_rounded,
    Icons.grid_view_rounded,
    Icons.format_list_bulleted_rounded,
  ];

  final List<String> _viewModeTooltips = [
    'Visualizar em Lista',
    'Visualizar em Grade',
    'Visualização Compacta',
  ];

  Timer? _searchDebounce;

  final Map<String, Map<String, dynamic>> _graduacoesCache = {};
  final Map<String, String> _svgCache = {};
  final Map<String, bool> _graduacaoValidaCache = {};

  @override
  void initState() {
    super.initState();
    _loadSvg();
    _preloadGraduacoes();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  String _normalizeString(String text) {
    if (text.isEmpty) return '';

    const withAccents =
        'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇñÑ';
    const withoutAccents =
        'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUCnN';

    var normalized = text;
    for (var i = 0; i < withAccents.length; i++) {
      normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
    }

    normalized = normalized.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');
    return normalized.toLowerCase().trim();
  }

  bool _alunoCorrespondeBusca(Map<String, dynamic> data, String termoBusca) {
    if (termoBusca.isEmpty) return true;

    final termoNormalizado = _normalizeString(termoBusca);
    if (termoNormalizado.isEmpty) return true;

    final camposParaBuscar = [
      _normalizeString(data['nome'] ?? ''),
      _normalizeString(data['apelido'] ?? ''),
      _normalizeString(data['nome_responsavel'] ?? ''),
      _normalizeString(data['contato_aluno'] ?? ''),
      _normalizeString(data['contato_responsavel'] ?? ''),
    ];

    if (RegExp(r'^\d+$').hasMatch(termoNormalizado)) {
      return camposParaBuscar.any((campo) => campo.contains(termoNormalizado));
    }

    final palavrasBusca = termoNormalizado.split(RegExp(r'\s+'));
    return palavrasBusca.every((palavra) {
      if (palavra.length <= 2 && !RegExp(r'^\d+$').hasMatch(palavra)) {
        return true;
      }

      return camposParaBuscar.any((campo) => campo.contains(palavra));
    });
  }

  Future<void> _loadSvg() async {
    try {
      final content =
      await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');

      if (mounted) {
        setState(() => _svgContent = content);
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar SVG: $e');
    }
  }

  Future<void> _preloadGraduacoes() async {
    try {
      final snapshot =
      await FirebaseFirestore.instance.collection('graduacoes').get();

      for (final doc in snapshot.docs) {
        final nomeGraduacao = doc['nome_graduacao']?.toString();

        if (nomeGraduacao != null && nomeGraduacao.isNotEmpty) {
          _graduacoesCache[nomeGraduacao] = {
            'id': doc.id,
            'hex_cor1': doc['hex_cor1'],
            'hex_cor2': doc['hex_cor2'],
            'hex_ponta1': doc['hex_ponta1'],
            'hex_ponta2': doc['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
          };
        }
      }

      debugPrint('✅ ${_graduacoesCache.length} graduações carregadas');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar graduações: $e');
    }
  }

  Future<void> _atualizarDados() async {
    _graduacoesCache.clear();
    _svgCache.clear();
    _graduacaoValidaCache.clear();
    await _preloadGraduacoes();
  }

  int _calculateAge(Timestamp? birthDate) {
    if (birthDate == null) return 0;

    final today = DateTime.now();
    final birth = birthDate.toDate();

    var age = today.year - birth.year;
    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) {
      age--;
    }

    return age;
  }

  String _obterNomeGraduacaoAluno(Map<String, dynamic> data) {
    final graduacaoId = data['graduacao_id']?.toString();

    if (graduacaoId != null && graduacaoId.isNotEmpty) {
      for (final entry in _graduacoesCache.entries) {
        if (entry.value['id'] == graduacaoId) return entry.key;
      }
    }

    final graduacaoNome = data['graduacao_nome']?.toString();
    if (graduacaoNome != null && graduacaoNome.isNotEmpty) {
      return graduacaoNome;
    }

    final graduacaoAtual = data['graduacao_atual']?.toString();
    if (graduacaoAtual != null && graduacaoAtual.isNotEmpty) {
      return graduacaoAtual;
    }

    return 'SEM GRADUAÇÃO';
  }

  Future<String?> _getModifiedSvg(Map<String, dynamic> data) async {
    final nomeGraduacao = _obterNomeGraduacaoAluno(data);

    if (nomeGraduacao.isEmpty ||
        nomeGraduacao == 'SEM GRADUAÇÃO' ||
        _svgContent == null) {
      return null;
    }

    final cacheKey = 'svg_$nomeGraduacao';
    if (_svgCache.containsKey(cacheKey)) return _svgCache[cacheKey];

    Map<String, dynamic>? coresGraduacao;

    if (_graduacoesCache.containsKey(nomeGraduacao)) {
      coresGraduacao = _graduacoesCache[nomeGraduacao];
    } else {
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('graduacoes')
            .where('nome_graduacao', isEqualTo: nomeGraduacao)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          final doc = querySnapshot.docs.first;

          coresGraduacao = {
            'id': doc.id,
            'hex_cor1': doc['hex_cor1'],
            'hex_cor2': doc['hex_cor2'],
            'hex_ponta1': doc['hex_ponta1'],
            'hex_ponta2': doc['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
          };

          _graduacoesCache[nomeGraduacao] = coresGraduacao;
        } else {
          return null;
        }
      } catch (e) {
        debugPrint('❌ Erro ao buscar graduação: $e');
        return null;
      }
    }

    if (coresGraduacao == null) return null;

    final document = xml.XmlDocument.parse(_svgContent!);

    Color colorFromHex(String? hexColor) {
      if (hexColor == null || hexColor.length < 7) return context.uai.textMuted;

      try {
        return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
      } catch (_) {
        return context.uai.textMuted;
      }
    }

    void changeColor(String id, Color color) {
      final element =
      document.rootElement.descendants.whereType<xml.XmlElement>().firstWhere(
            (e) => e.getAttribute('id') == id,
        orElse: () => xml.XmlElement(xml.XmlName('')),
      );

      if (element.name.local.isNotEmpty) {
        final style = element.getAttribute('style') ?? '';
        final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
        final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
        element.setAttribute('style', 'fill:$hex;$newStyle');
      }
    }

    changeColor('cor1', colorFromHex(coresGraduacao['hex_cor1']));
    changeColor('cor2', colorFromHex(coresGraduacao['hex_cor2']));
    changeColor('corponta1', colorFromHex(coresGraduacao['hex_ponta1']));
    changeColor('corponta2', colorFromHex(coresGraduacao['hex_ponta2']));

    final svgString = document.toXmlString();
    _svgCache[cacheKey] = svgString;
    return svgString;
  }

  Future<bool> _hasValidGraduation(Map<String, dynamic> data) async {
    final nomeGraduacao = _obterNomeGraduacaoAluno(data);

    if (nomeGraduacao.isEmpty || nomeGraduacao == 'SEM GRADUAÇÃO') {
      return false;
    }

    if (_graduacaoValidaCache.containsKey(nomeGraduacao)) {
      return _graduacaoValidaCache[nomeGraduacao]!;
    }

    if (_graduacoesCache.containsKey(nomeGraduacao)) {
      _graduacaoValidaCache[nomeGraduacao] = true;
      return true;
    }

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('graduacoes')
          .where('nome_graduacao', isEqualTo: nomeGraduacao)
          .limit(1)
          .get();

      final isValid = querySnapshot.docs.isNotEmpty;
      _graduacaoValidaCache[nomeGraduacao] = isValid;

      if (isValid) {
        final doc = querySnapshot.docs.first;

        _graduacoesCache[nomeGraduacao] = {
          'id': doc.id,
          'hex_cor1': doc['hex_cor1'],
          'hex_cor2': doc['hex_cor2'],
          'hex_ponta1': doc['hex_ponta1'],
          'hex_ponta2': doc['hex_ponta2'],
          'nome_graduacao': nomeGraduacao,
        };
      }

      return isValid;
    } catch (e) {
      debugPrint('Erro ao verificar graduação: $e');
      _graduacaoValidaCache[nomeGraduacao] = false;
      return false;
    }
  }

  String _getGraduacaoNome(Map<String, dynamic> data) {
    return _obterNomeGraduacaoAluno(data);
  }

  void _abrirDetalheAluno(String alunoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlunoDetalheScreen(alunoId: alunoId),
      ),
    );
  }

  void _abrirCadastroAluno() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarAlunoScreen(),
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _alunosStream() {
    return FirebaseFirestore.instance.collection('alunos').orderBy('nome').snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrarAlunos(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    return docs.where((doc) {
      final data = doc.data();
      final status = data['status_atividade'] as String? ?? '';

      if (_statusFilter != 'TODOS' && status != _statusFilter) {
        return false;
      }

      return _alunoCorrespondeBusca(data, _searchQuery);
    }).toList();
  }

  PreferredSizeWidget _buildAppBar() {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(appBarBg);

    return AppBar(
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      elevation: 0,
      titleSpacing: 16,
      title: Text(
        'Alunos',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(_viewModeIcons[_viewMode], color: appBarFg),
          tooltip: _viewModeTooltips[_viewMode],
          onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 3),
        ),
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded),
          tooltip: 'Cadastrar Novo Aluno',
          onPressed: _abrirCadastroAluno,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 430;

              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(
                        color: appBarFg,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: narrow ? 'Buscar...' : 'Buscar por nome...',
                        hintStyle: TextStyle(color: appBarFg.withOpacity(0.72)),
                        prefixIcon:
                        Icon(Icons.search_rounded, color: appBarFg),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: appBarFg,
                          ),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                            : null,
                        filled: true,
                        fillColor: appBarFg.withOpacity(0.12),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                          borderSide: BorderSide(
                            color: appBarFg.withOpacity(0.14),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                          borderSide: BorderSide(
                            color: appBarFg.withOpacity(0.14),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                          borderSide: BorderSide(
                            color: appBarFg,
                            width: 1.2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (_searchDebounce?.isActive ?? false) {
                          _searchDebounce!.cancel();
                        }

                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                              () => setState(() => _searchQuery = value),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: 10),
                  PopupMenuButton<String>(
                    tooltip: 'Filtrar por Status',
                    icon: Icon(Icons.filter_list_rounded, color: appBarFg),
                    color: t.surface,
                    surfaceTintColor: Colors.transparent,
                    onSelected: (value) => setState(() => _statusFilter = value),
                    itemBuilder: (context) {
                      return ['ATIVO(A)', 'INATIVO(A)', 'TODOS'].map((choice) {
                        final selected = choice == _statusFilter;

                        return PopupMenuItem<String>(
                          value: choice,
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: selected ? t.primary : t.textMuted,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                choice,
                                style: TextStyle(
                                  color: selected ? t.primary : t.textPrimary,
                                  fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList();
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResumoHeader({
    required int totalFiltrado,
    required int totalGeral,
  }) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: t.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
            child: Icon(Icons.groups_rounded, color: t.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusFilter == 'TODOS' ? 'Todos os alunos' : _statusFilter,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _searchQuery.isEmpty
                      ? '$totalFiltrado aluno${totalFiltrado == 1 ? '' : 's'} encontrado${totalFiltrado == 1 ? '' : 's'}'
                      : '$totalFiltrado resultado${totalFiltrado == 1 ? '' : 's'} para a busca',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (totalGeral != totalFiltrado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: t.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: t.primary.withOpacity(0.18)),
              ),
              child: Text(
                '$totalFiltrado/$totalGeral',
                style: TextStyle(
                  color: t.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    final t = context.uai;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            SizedBox(height: 16),
            Text(
              'Carregando alunos...',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(String message) {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline_rounded, size: 72, color: t.textMuted),
              SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  fontSize: 17,
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _abrirCadastroAluno,
                icon: Icon(Icons.person_add_alt_1_rounded),
                label: Text('CADASTRAR ALUNO'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsView() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 72, color: t.textMuted),
              const SizedBox(height: 16),
              Text(
                'Nenhum resultado encontrado',
                style: TextStyle(
                  fontSize: 18,
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Busca: "$_searchQuery"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: t.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
              SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => setState(() => _searchQuery = ''),
                icon: Icon(Icons.close_rounded),
                label: Text('LIMPAR BUSCA'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getCurrentView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    switch (_viewMode) {
      case 0:
        return _buildListView(docs);
      case 1:
        return _buildGridView(docs);
      case 2:
        return _buildCompactView(docs);
      default:
        return _buildListView(docs);
    }
  }

  Widget _buildListView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _atualizarDados,
      child: ListView.builder(
        key: const ValueKey('listView'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 6, 12, 18),
        itemCount: docs.length,
        itemBuilder: (context, index) => _buildAlunoListCard(docs[index]),
      ),
    );
  }

  Widget _buildGridView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _atualizarDados,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width >= 1100
              ? 5
              : width >= 850
              ? 4
              : width >= 620
              ? 3
              : 2;

          return GridView.builder(
            key: const ValueKey('gridView'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: width < 390 ? 0.72 : 0.78,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) => _buildAlunoGridCard(docs[index]),
          );
        },
      ),
    );
  }

  Widget _buildCompactView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _atualizarDados,
      child: ListView.builder(
        key: const ValueKey('compactView'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(10, 6, 10, 18),
        itemCount: docs.length,
        itemBuilder: (context, index) => _buildAlunoCompactCard(docs[index]),
      ),
    );
  }

  Widget _buildAlunoListCard(QueryDocumentSnapshot<Map<String, dynamic>> aluno) {
    final t = context.uai;
    final data = aluno.data();
    final nomeAluno = data['nome'] ?? 'Nome não informado';
    final fotoUrl = data['foto_perfil_aluno'] as String?;
    final idade = _calculateAge(data['data_nascimento']);
    final graduacaoNome = _getGraduacaoNome(data);

    return FutureBuilder<bool>(
      future: _hasValidGraduation(data),
      builder: (context, graduationSnapshot) {
        final hasValidGraduation = graduationSnapshot.data ?? false;

        return FutureBuilder<String?>(
          future: hasValidGraduation ? _getModifiedSvg(data) : Future.value(null),
          builder: (context, svgSnapshot) {
            final modifiedSvg = svgSnapshot.data;
            final isLoadingSvg =
                svgSnapshot.connectionState == ConnectionState.waiting;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: t.card,
                borderRadius: BorderRadius.circular(t.cardRadius - 5),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _abrirDetalheAluno(aluno.id),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.cardRadius - 5),
                      border: Border.all(color: t.border),
                      boxShadow: t.softShadow,
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            SizedBox(
                              width: 92,
                              height: 92,
                              child: fotoUrl != null && fotoUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                imageUrl: fotoUrl,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) =>
                                    _placeholderIcon(),
                              )
                                  : _placeholderIcon(),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 23,
                                color: t.primary.withOpacity(0.92),
                                child: Center(
                                  child: Text(
                                    '$idade ANOS',
                                    style: TextStyle(
                                      color: _readableOn(t.primary),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nomeAluno,
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w900,
                                    height: 1.15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (graduacaoNome.isNotEmpty &&
                                    graduacaoNome != 'SEM GRADUAÇÃO') ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    graduacaoNome,
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (hasValidGraduation)
                          Container(
                            width: 66,
                            padding: const EdgeInsets.only(right: 8),
                            child: isLoadingSvg
                                ? Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.primary,
                              ),
                            )
                                : modifiedSvg != null
                                ? SvgPicture.string(modifiedSvg, height: 62)
                                : SizedBox.shrink(),
                          ),
                        SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAlunoGridCard(QueryDocumentSnapshot<Map<String, dynamic>> aluno) {
    final t = context.uai;
    final data = aluno.data();
    final nomeAluno = data['nome'] ?? 'Nome não informado';
    final fotoUrl = data['foto_perfil_aluno'] as String?;
    final idade = _calculateAge(data['data_nascimento']);
    final graduacaoNome = _getGraduacaoNome(data);

    return FutureBuilder<bool>(
      future: _hasValidGraduation(data),
      builder: (context, graduationSnapshot) {
        final hasValidGraduation = graduationSnapshot.data ?? false;

        return FutureBuilder<String?>(
          future: hasValidGraduation ? _getModifiedSvg(data) : Future.value(null),
          builder: (context, svgSnapshot) {
            final modifiedSvg = svgSnapshot.data;
            final isLoadingSvg =
                svgSnapshot.connectionState == ConnectionState.waiting;

            return Material(
              color: t.card,
              borderRadius: BorderRadius.circular(t.cardRadius - 5),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _abrirDetalheAluno(aluno.id),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.cardRadius - 5),
                    border: Border.all(color: t.border),
                    boxShadow: t.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: fotoUrl != null && fotoUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                imageUrl: fotoUrl,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) =>
                                    _placeholderIcon(size: 74),
                              )
                                  : _placeholderIcon(size: 74),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 27,
                                color: t.primary.withOpacity(0.92),
                                child: Center(
                                  child: Text(
                                    '$idade ANOS',
                                    style: TextStyle(
                                      color: _readableOn(t.primary),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(11),
                        color: t.card,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    nomeAluno.toUpperCase(),
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      height: 1.15,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (graduacaoNome.isNotEmpty &&
                                      graduacaoNome != 'SEM GRADUAÇÃO') ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      graduacaoNome,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: t.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (hasValidGraduation) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 38,
                                height: 46,
                                child: isLoadingSvg
                                    ? Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: t.primary,
                                  ),
                                )
                                    : modifiedSvg != null
                                    ? SvgPicture.string(modifiedSvg, height: 44)
                                    : SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAlunoCompactCard(QueryDocumentSnapshot<Map<String, dynamic>> aluno) {
    final t = context.uai;
    final data = aluno.data();
    final nomeAluno = data['nome'] ?? 'Nome não informado';
    final fotoUrl = data['foto_perfil_aluno'] as String?;

    return FutureBuilder<bool>(
      future: _hasValidGraduation(data),
      builder: (context, graduationSnapshot) {
        final hasValidGraduation = graduationSnapshot.data ?? false;

        return FutureBuilder<String?>(
          future: hasValidGraduation ? _getModifiedSvg(data) : Future.value(null),
          builder: (context, svgSnapshot) {
            final modifiedSvg = svgSnapshot.data;
            final isLoadingSvg =
                svgSnapshot.connectionState == ConnectionState.waiting;

            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: t.card,
                borderRadius: BorderRadius.circular(t.cardRadius - 8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _abrirDetalheAluno(aluno.id),
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.cardRadius - 8),
                      border: Border.all(color: t.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.cardAlt,
                          ),
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: fotoUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Icon(
                                Icons.person_rounded,
                                size: 28,
                                color: t.textMuted,
                              ),
                            ),
                          )
                              : Icon(
                            Icons.person_rounded,
                            size: 28,
                            color: t.textMuted,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            nomeAluno,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasValidGraduation) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 30,
                            height: 38,
                            child: isLoadingSvg
                                ? Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.primary,
                              ),
                            )
                                : modifiedSvg != null
                                ? SvgPicture.string(modifiedSvg, height: 36)
                                : SizedBox.shrink(),
                          ),
                        ],
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: t.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _placeholderIcon({double size = 50}) {
    return Container(
      color: context.uai.cardAlt,
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: size,
          color: context.uai.textMuted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: _buildAppBar(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _alunosStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingView();
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyView('Nenhum aluno encontrado.');
          }

          final allDocs = snapshot.data!.docs;
          final filteredDocs = _filtrarAlunos(allDocs);

          if (filteredDocs.isEmpty && _searchQuery.isNotEmpty) {
            return _buildNoSearchResultsView();
          }

          if (filteredDocs.isEmpty) {
            return _buildEmptyView('Nenhum aluno encontrado para este filtro.');
          }

          return Column(
            children: [
              _buildResumoHeader(
                totalFiltrado: filteredDocs.length,
                totalGeral: allDocs.length,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _getCurrentView(filteredDocs),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
