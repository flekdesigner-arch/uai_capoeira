import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/models/participacao_model.dart';
import 'package:xml/xml.dart' as xml;

class FinalizacaoMassaEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const FinalizacaoMassaEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<FinalizacaoMassaEventoScreen> createState() =>
      _FinalizacaoMassaEventoScreenState();
}

class _FinalizacaoMassaEventoScreenState
    extends State<FinalizacaoMassaEventoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PermissaoService _permissaoService = PermissaoService();
  final TextEditingController _buscaController = TextEditingController();
  final FocusNode _buscaFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final Set<String> _chamados = <String>{};
  final Set<String> _processandoIds = <String>{};
  final Set<String> _gruposAbertos = <String>{};

  final Map<String, Map<String, dynamic>> _graduacoesCache = {};
  final Map<String, String> _svgCache = {};
  final Map<String, Future<_AlunoExtraEventoData>> _alunoExtraFutures = {};
  final Map<String, _AlunoExtraEventoData> _alunoExtraCache = {};
  final Map<String, _AlunoExtraEventoData> _alunosExtraPorId = {};
  final Map<String, _AlunoExtraEventoData> _alunosExtraPorNome = {};
  Future<void>? _indexarAlunosFuture;

  bool _carregandoPermissao = true;
  bool _carregandoGraduacoes = true;
  bool _podeFinalizar = false;
  bool _processando = false;
  bool _isRefreshing = false;

  int _viewMode = 0;
  String _busca = '';
  String _filtroChamada = 'Todos';
  String _ordenacaoPrincipal = 'nome';
  Timer? _debounce;
  String? _svgContent;

  static const int _viewGraduacoes = 0;
  static const int _viewPrincipal = 1;

  @override
  void initState() {
    super.initState();
    _inicializarTela();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaController.dispose();
    _buscaFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _inicializarTela() async {
    await Future.wait([
      _verificarPermissao(),
      _loadSvg(),
      _preloadGraduacoes(),
      _garantirIndiceAlunos(),
    ]);
  }

  Future<void> _atualizarTudo() async {
    if (mounted) setState(() => _isRefreshing = true);

    try {
      _svgCache.clear();
      _alunoExtraCache.clear();
      _alunoExtraFutures.clear();
      _alunosExtraPorId.clear();
      _alunosExtraPorNome.clear();
      _indexarAlunosFuture = null;

      await Future.wait([
        _verificarPermissao(),
        _loadSvg(force: true),
        _preloadGraduacoes(forceServer: true),
        _garantirIndiceAlunos(),
      ]);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _verificarPermissao() async {
    if (mounted) setState(() => _carregandoPermissao = true);

    try {
      final permitido = await _permissaoService.temQualquerPermissaoDireta([
        'pode_concluir_participacao_evento',
      ]);

      if (!mounted) return;
      setState(() {
        _podeFinalizar = permitido;
        _carregandoPermissao = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissão de finalização em massa: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissao = false);
    }
  }

  Future<void> _loadSvg({bool force = false}) async {
    if (_svgContent != null && !force) return;

    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');
      if (!mounted) return;
      setState(() => _svgContent = content);
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar corda.svg na finalização em massa: $e');
    }
  }

  Future<void> _preloadGraduacoes({bool forceServer = false}) async {
    if (mounted) setState(() => _carregandoGraduacoes = true);

    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;

      if (forceServer) {
        snapshot = await _firestore
            .collection('graduacoes')
            .limit(800)
            .get(const GetOptions(source: Source.server));
      } else {
        try {
          snapshot = await _firestore
              .collection('graduacoes')
              .limit(800)
              .get(const GetOptions(source: Source.cache));

          if (snapshot.docs.isEmpty) {
            snapshot = await _firestore
                .collection('graduacoes')
                .limit(800)
                .get(const GetOptions(source: Source.server));
          }
        } catch (_) {
          snapshot = await _firestore
              .collection('graduacoes')
              .limit(800)
              .get(const GetOptions(source: Source.server));
        }
      }

      final cache = <String, Map<String, dynamic>>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final nomeGraduacao = data['nome_graduacao']?.toString() ??
            data['nome']?.toString() ??
            data['titulo']?.toString() ??
            '';

        if (nomeGraduacao.trim().isEmpty) continue;

        final item = <String, dynamic>{
          'id': doc.id,
          'hex_cor1': data['hex_cor1'],
          'hex_cor2': data['hex_cor2'],
          'hex_ponta1': data['hex_ponta1'],
          'hex_ponta2': data['hex_ponta2'],
          'nome_graduacao': nomeGraduacao,
          'nivel_graduacao':
          data['nivel_graduacao'] ?? data['nivel'] ?? data['ordem'] ?? 9999,
          'tipo_publico': data['tipo_publico'],
        };

        cache[doc.id] = item;
        cache[nomeGraduacao] = item;
        cache[nomeGraduacao.trim().toUpperCase()] = item;
        cache[_graduacaoKey(nomeGraduacao)] = item;
      }

      if (!mounted) return;
      setState(() {
        _graduacoesCache
          ..clear()
          ..addAll(cache);
        _carregandoGraduacoes = false;
      });

      debugPrint(
        '✅ ${snapshot.docs.length} graduações carregadas com hex_cor1/hex_cor2',
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar graduações na finalização: $e');
      if (!mounted) return;
      setState(() => _carregandoGraduacoes = false);
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation(((hsl.saturation + 0.10).clamp(0.0, 1.0)).toDouble())
        .toColor();
  }

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  Color _colorFromHexSeguro(String? hexColor, Color fallback) {
    if (hexColor == null || hexColor.trim().isEmpty) return fallback;

    try {
      final cleaned = hexColor.replaceAll('#', '').trim();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
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

  String _graduacaoKey(String value) {
    return _normalizeString(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _onBuscaChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _busca = value.trim());
    });
  }

  Map<String, dynamic>? _graduacaoMapDoParticipante(
      _FinalizacaoParticipanteData item,
      ) {
    final ids = [
      item.graduacaoNovaId,
      item.graduacaoAtualId,
      item.graduacaoId,
    ].where((id) => id.trim().isNotEmpty);

    for (final id in ids) {
      final direto = _graduacoesCache[id];
      if (direto != null) return direto;
    }

    final nomes = [
      item.graduacaoNova,
      item.graduacaoAtual,
      item.graduacaoTexto,
    ].where((nome) => nome.trim().isNotEmpty);

    for (final nome in nomes) {
      final direto = _graduacoesCache[nome];
      final upper = _graduacoesCache[nome.trim().toUpperCase()];
      final normalizado = _graduacoesCache[_graduacaoKey(nome)];

      if (direto != null) return direto;
      if (upper != null) return upper;
      if (normalizado != null) return normalizado;
    }

    return null;
  }

  String _nomeGraduacaoResolvido(_FinalizacaoParticipanteData item) {
    final map = _graduacaoMapDoParticipante(item);
    final nomeMap = map?['nome_graduacao']?.toString().trim();
    if (nomeMap != null && nomeMap.isNotEmpty) return nomeMap;

    if (item.graduacaoNova.trim().isNotEmpty) return item.graduacaoNova.trim();
    if (item.graduacaoAtual.trim().isNotEmpty) return item.graduacaoAtual.trim();
    if (item.graduacaoTexto.trim().isNotEmpty) return item.graduacaoTexto.trim();
    return 'SEM GRADUAÇÃO';
  }

  int _nivelGraduacaoResolvido(_FinalizacaoParticipanteData item) {
    final map = _graduacaoMapDoParticipante(item);
    return _parseInt(map?['nivel_graduacao'], 999999);
  }

  Color _cor1Graduacao(_FinalizacaoParticipanteData item) {
    final map = _graduacaoMapDoParticipante(item);
    return _colorFromHexSeguro(
      map?['hex_cor1']?.toString(),
      context.uai.textMuted,
    );
  }

  Color _cor2Graduacao(_FinalizacaoParticipanteData item) {
    final map = _graduacaoMapDoParticipante(item);
    return _colorFromHexSeguro(
      map?['hex_cor2']?.toString(),
      _cor1Graduacao(item),
    );
  }

  String? _getModifiedSvg(_FinalizacaoParticipanteData item) {
    final svgBase = _svgContent;
    if (svgBase == null || svgBase.isEmpty) return null;

    final graduacaoMap = _graduacaoMapDoParticipante(item);
    if (graduacaoMap == null) return null;

    final gradId = graduacaoMap['id']?.toString() ?? '';
    final nome = graduacaoMap['nome_graduacao']?.toString() ?? '';
    final cacheKey = 'svg_${gradId}_${_graduacaoKey(nome)}';

    if (_svgCache.containsKey(cacheKey)) return _svgCache[cacheKey];

    try {
      final document = xml.XmlDocument.parse(svgBase);

      Color colorFromHex(String? hexColor) {
        return _colorFromHexSeguro(hexColor, context.uai.textMuted);
      }

      void changeColor(String id, Color color) {
        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );

        if (element.name.local.isEmpty) return;

        final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
        final oldStyle = element.getAttribute('style') ?? '';

        if (oldStyle.contains('fill:')) {
          final newStyle = oldStyle.replaceAll(
            RegExp(r'fill:\s*#[0-9a-fA-F]{3,8}'),
            'fill:$hex',
          );
          element.setAttribute('style', newStyle);
        } else {
          element.setAttribute('style', 'fill:$hex;$oldStyle');
        }

        element.setAttribute('fill', hex);
      }

      changeColor('cor1', colorFromHex(graduacaoMap['hex_cor1']?.toString()));
      changeColor('cor2', colorFromHex(graduacaoMap['hex_cor2']?.toString()));
      changeColor(
        'corponta1',
        colorFromHex(graduacaoMap['hex_ponta1']?.toString()),
      );
      changeColor(
        'corponta2',
        colorFromHex(graduacaoMap['hex_ponta2']?.toString()),
      );

      final result = document.toXmlString();
      _svgCache[cacheKey] = result;
      return result;
    } catch (e) {
      debugPrint('⚠️ Erro ao montar corda.svg para $nome: $e');
      return null;
    }
  }

  List<_FinalizacaoParticipanteData> _mapearParticipantes(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final buscaNormalizada = _normalizeString(_busca);

    final lista = docs
        .map(_FinalizacaoParticipanteData.fromDoc)
        .where((item) => !item.finalizado)
        .where((item) {
      if (buscaNormalizada.isEmpty) return true;

      final alvo = _normalizeString([
        item.nome,
        item.graduacaoAtual,
        item.graduacaoNova,
        item.graduacaoTexto,
        item.turma,
        item.tamanhoCamisa,
      ].join(' '));

      return alvo.contains(buscaNormalizada);
    }).where((item) {
      final chamado = _chamados.contains(item.id);
      if (_filtroChamada == 'Chamados') return chamado;
      if (_filtroChamada == 'Não chamados') return !chamado;
      return true;
    }).toList();

    lista.sort((a, b) => a.nome.compareTo(b.nome));
    return lista;
  }

  List<_FinalizacaoParticipanteData> _ordenarParaVisualPrincipal(
      List<_FinalizacaoParticipanteData> participantes,
      ) {
    final lista = List<_FinalizacaoParticipanteData>.from(participantes);

    if (_ordenacaoPrincipal == 'graduacao') {
      lista.sort((a, b) {
        final nivelA = _nivelGraduacaoResolvido(a);
        final nivelB = _nivelGraduacaoResolvido(b);
        final byNivel = nivelA.compareTo(nivelB);
        if (byNivel != 0) return byNivel;

        final gradA = _nomeGraduacaoResolvido(a);
        final gradB = _nomeGraduacaoResolvido(b);
        final byGrad = gradA.compareTo(gradB);
        if (byGrad != 0) return byGrad;

        return a.nome.compareTo(b.nome);
      });
      return lista;
    }

    lista.sort((a, b) => a.nome.compareTo(b.nome));
    return lista;
  }

  int _contarFinalizados(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs
        .map(_FinalizacaoParticipanteData.fromDoc)
        .where((item) => item.finalizado)
        .length;
  }

  List<_GrupoGraduacaoFinalizacao> _agruparPorGraduacao(
      List<_FinalizacaoParticipanteData> participantes,
      ) {
    final grupos = <String, _GrupoGraduacaoFinalizacao>{};

    for (final item in participantes) {
      final titulo = _nomeGraduacaoResolvido(item);
      final key = _graduacaoKey(titulo);
      final cor1 = _cor1Graduacao(item);
      final cor2 = _cor2Graduacao(item);

      grupos.putIfAbsent(
        key,
            () => _GrupoGraduacaoFinalizacao(
          key: key,
          titulo: titulo,
          ordem: _nivelGraduacaoResolvido(item),
          referencia: item,
          alunos: [],
          color1: cor1,
          color2: cor2,
        ),
      );

      grupos[key]!.alunos.add(item);
    }

    final lista = grupos.values.toList();
    lista.sort((a, b) {
      final byNivel = a.ordem.compareTo(b.ordem);
      if (byNivel != 0) return byNivel;
      return a.titulo.compareTo(b.titulo);
    });

    for (final grupo in lista) {
      grupo.alunos.sort((a, b) => a.nome.compareTo(b.nome));
    }

    return lista;
  }

  Future<void> _garantirIndiceAlunos() {
    return _indexarAlunosFuture ??= _indexarTodosAlunos();
  }

  Future<void> _indexarTodosAlunos() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;

      try {
        snap = await _firestore
            .collection('alunos')
            .limit(2000)
            .get(const GetOptions(source: Source.cache));

        if (snap.docs.isEmpty) {
          snap = await _firestore
              .collection('alunos')
              .limit(2000)
              .get(const GetOptions(source: Source.server));
        }
      } catch (_) {
        snap = await _firestore
            .collection('alunos')
            .limit(2000)
            .get(const GetOptions(source: Source.server));
      }

      for (final doc in snap.docs) {
        final extra = _AlunoExtraEventoData.fromAlunoDoc(doc.data());
        _alunosExtraPorId[doc.id] = extra;

        final nomeKey = _normalizeString(extra.nome);
        if (nomeKey.isNotEmpty) {
          _alunosExtraPorNome[nomeKey] = extra;
        }
      }

      debugPrint(
        '✅ Índice de alunos carregado na finalização em massa: ${snap.docs.length}',
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao indexar alunos para fotos: $e');
    }
  }

  Future<_AlunoExtraEventoData> _buscarAlunoExtra(
      _FinalizacaoParticipanteData item,
      ) async {
    // Mesma ideia da tela de participantes:
    // 1) tenta direto pelo aluno_id no documento alunos;
    // 2) se não achou, tenta pelo índice local de alunos;
    // 3) por último, tenta pelo nome exato/normalizado.
    // Importante: não guardamos resultado vazio como cache definitivo,
    // porque no web/cache o primeiro frame pode vir antes da foto estar resolvida.
    final idKey = item.alunoId.trim();
    final nomeKey = _normalizeString(item.nome);
    final futureKey = idKey.isNotEmpty ? idKey : 'nome:$nomeKey';

    final cached = _alunoExtraCache[futureKey];
    if (cached != null && cached.fotoUrl.trim().isNotEmpty) {
      return cached;
    }

    if (idKey.isNotEmpty) {
      final cachedById = _alunosExtraPorId[idKey];
      if (cachedById != null && cachedById.fotoUrl.trim().isNotEmpty) {
        _alunoExtraCache[futureKey] = cachedById;
        return cachedById;
      }
    }

    if (nomeKey.isNotEmpty) {
      final cachedByName = _alunosExtraPorNome[nomeKey];
      if (cachedByName != null && cachedByName.fotoUrl.trim().isNotEmpty) {
        _alunoExtraCache[futureKey] = cachedByName;
        return cachedByName;
      }
    }

    try {
      Map<String, dynamic>? data;
      String? resolvedId;

      // Caminho principal: igual participantes_evento_screen.dart
      // FirebaseFirestore.instance.collection('alunos').doc(p.alunoId).get()
      if (idKey.isNotEmpty) {
        final doc = await _firestore.collection('alunos').doc(idKey).get();
        if (doc.exists) {
          data = doc.data() ?? <String, dynamic>{};
          resolvedId = doc.id;
        }
      }

      // Índice local de todos os alunos. Isso ajuda quando o aluno_id da
      // participação veio antigo, vazio ou com variação de campo.
      if (data == null) {
        await _garantirIndiceAlunos();

        if (idKey.isNotEmpty) {
          final porId = _alunosExtraPorId[idKey];
          if (porId != null) {
            if (porId.fotoUrl.trim().isNotEmpty) {
              _alunoExtraCache[futureKey] = porId;
            }
            return porId;
          }
        }

        if (nomeKey.isNotEmpty) {
          final porNome = _alunosExtraPorNome[nomeKey];
          if (porNome != null) {
            if (porNome.fotoUrl.trim().isNotEmpty) {
              _alunoExtraCache[futureKey] = porNome;
            }
            return porNome;
          }

          for (final entry in _alunosExtraPorNome.entries) {
            final key = entry.key;
            if (key == nomeKey || key.startsWith(nomeKey) || nomeKey.startsWith(key)) {
              if (entry.value.fotoUrl.trim().isNotEmpty) {
                _alunoExtraCache[futureKey] = entry.value;
              }
              return entry.value;
            }
          }
        }
      }

      // Fallback por query exata, só se o índice ainda não resolveu.
      if (data == null && item.nome.trim().isNotEmpty) {
        final nomeExato = item.nome.trim();
        final snap = await _firestore
            .collection('alunos')
            .where('nome', isEqualTo: nomeExato)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          data = snap.docs.first.data();
          resolvedId = snap.docs.first.id;
        }
      }

      if (data == null) {
        // Se a participação já trouxe uma foto direta válida, usa ao menos ela.
        final direta = item.fotoUrl?.trim() ?? '';
        if (direta.startsWith('http://') || direta.startsWith('https://')) {
          final extraDireto = _AlunoExtraEventoData(
            nome: item.nome,
            fotoUrl: direta,
            graduacaoAtual: item.graduacaoAtual,
            graduacaoAtualId: item.graduacaoAtualId,
          );
          _alunoExtraCache[futureKey] = extraDireto;
          return extraDireto;
        }
        return _AlunoExtraEventoData.empty();
      }

      final extra = _AlunoExtraEventoData.fromAlunoDoc(data);

      if (resolvedId != null && resolvedId.isNotEmpty) {
        _alunosExtraPorId[resolvedId] = extra;
      }

      final extraNomeKey = _normalizeString(extra.nome);
      if (extraNomeKey.isNotEmpty) {
        _alunosExtraPorNome[extraNomeKey] = extra;
      }

      if (extra.fotoUrl.trim().isNotEmpty) {
        _alunoExtraCache[futureKey] = extra;
      }

      return extra;
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar foto do aluno ${item.nome} ($futureKey): $e');
      return _AlunoExtraEventoData.empty();
    }
  }

  void _setStatePreservandoScroll(VoidCallback action) {
    if (!mounted) return;

    final offsetAntes = _scrollController.hasClients
        ? _scrollController.offset
        : null;

    setState(action);

    if (offsetAntes == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final max = _scrollController.position.maxScrollExtent;
      final alvo = offsetAntes.clamp(0.0, max).toDouble();

      if ((_scrollController.offset - alvo).abs() > 1) {
        _scrollController.jumpTo(alvo);
      }
    });
  }

  void _toggleChamado(_FinalizacaoParticipanteData item) {
    if (_processando) return;

    _setStatePreservandoScroll(() {
      if (_chamados.contains(item.id)) {
        _chamados.remove(item.id);
      } else {
        _chamados.add(item.id);
      }
    });
  }

  void _marcarTodosFiltrados(
      List<_FinalizacaoParticipanteData> participantes,
      bool chamado,
      ) {
    if (_processando || participantes.isEmpty) return;

    _setStatePreservandoScroll(() {
      for (final item in participantes) {
        if (chamado) {
          _chamados.add(item.id);
        } else {
          _chamados.remove(item.id);
        }
      }
    });
  }

  void _inverterFiltrados(List<_FinalizacaoParticipanteData> participantes) {
    if (_processando || participantes.isEmpty) return;

    _setStatePreservandoScroll(() {
      for (final item in participantes) {
        if (_chamados.contains(item.id)) {
          _chamados.remove(item.id);
        } else {
          _chamados.add(item.id);
        }
      }
    });
  }

  void _limparChamados() {
    if (_processando) return;
    _setStatePreservandoScroll(_chamados.clear);
  }

  Future<void> _abrirDialogoChamar(
      List<_FinalizacaoParticipanteData> participantes,
      ) async {
    if (_processando) return;

    final selecionados = participantes
        .where((item) => _chamados.contains(item.id))
        .toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    if (selecionados.isEmpty) {
      _mostrarSnack('Marque pelo menos um aluno para chamar.', context.uai.warning);
      return;
    }

    final confirmados = await showDialog<List<_FinalizacaoParticipanteData>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final chamadosDialog = List<_FinalizacaoParticipanteData>.from(selecionados);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final t = context.uai;
            final primary = _ensureVisible(t.primary, t.card);

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
                child: Material(
                  color: t.card,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 15, 8, 14),
                        decoration: BoxDecoration(gradient: t.primaryGradient),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.18),
                                ),
                              ),
                              child: Icon(
                                Icons.campaign_rounded,
                                color: _readableOn(t.primary),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chamar alunos no microfone',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _readableOn(t.primary),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${chamadosDialog.length} aluno(s) na chamada. Remova quem não apareceu.',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _readableOn(t.primary).withOpacity(0.80),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: Icon(
                                Icons.close_rounded,
                                color: _readableOn(t.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: chamadosDialog.isEmpty
                            ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_remove_alt_1_rounded,
                                color: t.textMuted,
                                size: 54,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum aluno na chamada',
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Feche esta caixa e marque novamente os alunos que serão chamados.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        )
                            : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(14),
                          itemCount: chamadosDialog.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = chamadosDialog[index];
                            final svg = _getModifiedSvg(item);
                            final cor = _ensureVisible(_cor1Graduacao(item), t.card);
                            final nomeGrad = _nomeGraduacaoResolvido(item);

                            return Container(
                              padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.055),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cor.withOpacity(0.16)),
                              ),
                              child: Row(
                                children: [
                                  _AvatarAlunoChamado(
                                    item: item,
                                    extraFuture: _buscarAlunoExtra(item),
                                    borderColor: cor,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.nome,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: t.textPrimary,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          nomeGrad,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: t.textSecondary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (svg != null) ...[
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 34,
                                      height: 42,
                                      child: SvgPicture.string(
                                        svg,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ],
                                  IconButton(
                                    tooltip: 'Remover da chamada',
                                    onPressed: () {
                                      setDialogState(() {
                                        chamadosDialog.removeAt(index);
                                      });
                                    },
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: t.error,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        decoration: BoxDecoration(
                          color: t.surface,
                          border: Border(top: BorderSide(color: t.border)),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 430;
                            final actions = [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('VOLTAR'),
                              ),
                              ElevatedButton.icon(
                                onPressed: chamadosDialog.isEmpty
                                    ? null
                                    : () => Navigator.pop(
                                  dialogContext,
                                  List<_FinalizacaoParticipanteData>.from(
                                    chamadosDialog,
                                  ),
                                ),
                                icon: const Icon(Icons.verified_rounded),
                                label: const Text('FINALIZAR DE VERDADE'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: _readableOn(primary),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ];

                            if (compact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  actions[1],
                                  const SizedBox(height: 8),
                                  actions[0],
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Confirme somente quem apareceu para receber a graduação.',
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                actions[0],
                                const SizedBox(width: 8),
                                actions[1],
                              ],
                            );
                          },
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

    if (confirmados == null || confirmados.isEmpty) return;
    await _finalizarDeVerdade(confirmados);
  }

  Future<void> _finalizarDeVerdade(
      List<_FinalizacaoParticipanteData> confirmados,
      ) async {
    if (_processando) return;

    if (!_podeFinalizar) {
      _mostrarSnack(
        'Você não tem permissão para finalizar participantes.',
        context.uai.error,
      );
      return;
    }

    setState(() {
      _processando = true;
      _processandoIds
        ..clear()
        ..addAll(confirmados.map((item) => item.id));
    });

    try {
      final batch = _firestore.batch();
      final agora = FieldValue.serverTimestamp();

      for (final item in confirmados) {
        final participacaoRef = _firestore
            .collection('participacoes_eventos_em_andamento')
            .doc(item.id);

        final historicoRef = _firestore
            .collection('participacoes_eventos')
            .doc(item.id);

        final andamentoSnap = await participacaoRef.get();
        final dadosOriginais = andamentoSnap.data() ?? <String, dynamic>{};

        if (!andamentoSnap.exists) {
          throw Exception(
            'Participação de ${item.nome} não encontrada em andamento.',
          );
        }

        final graduacaoHistorico = item.graduacaoNova.trim().isNotEmpty
            ? item.graduacaoNova.trim()
            : item.graduacaoLonga;

        final linkCertificadoAtual = item.linkCertificado.trim().isNotEmpty
            ? item.linkCertificado.trim()
            : (dadosOriginais['link_certificado']?.toString().trim() ?? '');

        final eventoIdFinal = item.eventoId.trim().isNotEmpty
            ? item.eventoId.trim()
            : widget.eventoId;

        final eventoNomeFinal = item.eventoNome.trim().isNotEmpty
            ? item.eventoNome.trim()
            : widget.eventoNome;

        // Mesmo conceito do ParticipacaoService.finalizarParticipacao:
        // copia todos os dados atuais para participacoes_eventos com o mesmo ID
        // e remove da coleção em andamento. Assim o histórico do aluno e as
        // telas de participações enxergam a participação como finalizada.
        final dadosHistorico = <String, dynamic>{
          ...dadosOriginais,
          'aluno_id': item.alunoId,
          'aluno_nome': item.nome,
          'evento_id': eventoIdFinal,
          'evento_nome': eventoNomeFinal,
          'data_evento': Timestamp.fromDate(item.dataEvento),
          'tipo_evento': item.tipoEvento.trim().isNotEmpty
              ? item.tipoEvento.trim()
              : 'EVENTO',
          'graduacao': graduacaoHistorico,
          'graduacao_anterior': item.graduacaoAtual.trim(),
          'graduacao_nova': item.graduacaoNova.trim(),
          'graduacao_nova_id': item.graduacaoNovaId.trim(),
          'graduacao_id': item.graduacaoNovaId.trim().isNotEmpty
              ? item.graduacaoNovaId.trim()
              : item.graduacaoId.trim(),
          'tamanho_camisa': item.tamanhoCamisa,
          'status': 'finalizado',
          'finalizado': true,
          'participacao_finalizada': true,
          'aguardando_finalizacao': false,
          'graduacao_final': item.graduacaoNova.trim().isNotEmpty
              ? item.graduacaoNova.trim()
              : null,
          'graduacao_final_id': item.graduacaoNovaId.trim().isNotEmpty
              ? item.graduacaoNovaId.trim()
              : null,
          'origem_finalizacao': 'finalizacao_massa_evento',
          'participacao_andamento_id': item.id,
          'valor_inscricao': item.valorInscricao,
          'valor_camisa': item.valorCamisa,
          'total_pago': item.totalPago,
          'atualizado_em': agora,
          'data_finalizacao': agora,
          'finalizado_em': agora,
        };

        if (linkCertificadoAtual.isNotEmpty) {
          dadosHistorico['link_certificado'] = linkCertificadoAtual;
        } else {
          dadosHistorico.remove('link_certificado');
        }

        batch.set(historicoRef, dadosHistorico, SetOptions(merge: true));

        // Remove da fila em andamento para ficar 100% igual ao fluxo individual.
        batch.delete(participacaoRef);

        // Mantém a referência resumida em eventos/{eventoId}/participacoes.
        if (eventoIdFinal.isNotEmpty) {
          batch.set(
            _firestore
                .collection('eventos')
                .doc(eventoIdFinal)
                .collection('participacoes')
                .doc(item.id),
            {
              'participacao_id': item.id,
              'aluno_id': item.alunoId,
              'aluno_nome': item.nome,
              'status': 'finalizado',
              'total_pago': item.totalPago,
              'valor_total': item.valorInscricao + item.valorCamisa,
              'tamanho_camisa': item.tamanhoCamisa,
              'modelagem_camisa':
              dadosOriginais['modelagem_camisa'] ?? 'NORMAL',
              'tipo_camisa': dadosOriginais['tipo_camisa'] ?? 'MANGA',
              'link_certificado': linkCertificadoAtual.isNotEmpty
                  ? linkCertificadoAtual
                  : dadosOriginais['link_certificado'],
              'finalizado_em': agora,
              'atualizado_em': agora,
            },
            SetOptions(merge: true),
          );
        }

        final novaGraduacaoNome = item.graduacaoNova.trim();
        final novaGraduacaoId = item.graduacaoNovaId.trim();

        if (item.alunoId.trim().isNotEmpty &&
            (novaGraduacaoNome.isNotEmpty || novaGraduacaoId.isNotEmpty)) {
          final alunoRef = _firestore.collection('alunos').doc(item.alunoId);
          final dadosAluno = <String, dynamic>{
            'atualizado_em': agora,
          };

          if (novaGraduacaoNome.isNotEmpty) {
            dadosAluno['graduacao_atual'] = novaGraduacaoNome;
            dadosAluno['graduacao_nome'] = novaGraduacaoNome;
          }

          if (novaGraduacaoId.isNotEmpty) {
            dadosAluno['graduacao_id'] = novaGraduacaoId;
            dadosAluno['graduacao_atual_id'] = novaGraduacaoId;
          }

          batch.set(alunoRef, dadosAluno, SetOptions(merge: true));
        }
      }

      await batch.commit();

      if (!mounted) return;
      setState(() {
        for (final item in confirmados) {
          _chamados.remove(item.id);
        }
        _processandoIds.clear();
        _processando = false;
      });

      _mostrarSnack(
        '✅ ${confirmados.length} aluno(s) finalizado(s) de verdade.',
        context.uai.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processandoIds.clear();
        _processando = false;
      });

      _mostrarSnack('Erro ao finalizar em massa: $e', context.uai.error);
    }
  }

  void _mostrarSnack(String mensagem, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final appBarBg = _appBarBg();
    final appBarFg = _appBarFg();

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Finalização em massa',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            Text(
              widget.eventoNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appBarFg.withOpacity(0.78),
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        actions: [
          IconButton(
            tooltip: _viewMode == _viewGraduacoes
                ? 'Trocar para visual da chamada'
                : 'Trocar para graduação',
            onPressed: _processando
                ? null
                : () {
              setState(() {
                _viewMode = _viewMode == _viewGraduacoes
                    ? _viewPrincipal
                    : _viewGraduacoes;
              });
            },
            icon: Icon(
              _viewMode == _viewGraduacoes
                  ? Icons.workspace_premium_rounded
                  : Icons.dashboard_customize_rounded,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ordenar visual principal',
            icon: Icon(
              _ordenacaoPrincipal == 'graduacao'
                  ? Icons.workspace_premium_rounded
                  : Icons.sort_by_alpha_rounded,
            ),
            enabled: !_processando,
            onSelected: (value) {
              setState(() => _ordenacaoPrincipal = value);
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: 'nome',
                checked: _ordenacaoPrincipal == 'nome',
                child: const Text('Ordem alfabética'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'graduacao',
                checked: _ordenacaoPrincipal == 'graduacao',
                child: const Text('Ordem por nível de corda'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Atualizar dados',
            onPressed: _isRefreshing || _processando ? null : _atualizarTudo,
            icon: _isRefreshing
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: appBarFg,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: _buildSearchField(appBarFg),
              ),
            ),
          ),
        ),
      ),
      body: _carregandoPermissao || _carregandoGraduacoes
          ? _buildLoading()
          : !_podeFinalizar
          ? _buildSemPermissao()
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('participacoes_eventos_em_andamento')
            .where('evento_id', isEqualTo: widget.eventoId)
            .orderBy('aluno_nome')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErro(snapshot.error.toString());
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoading();
          }

          final docs = snapshot.data?.docs ?? [];
          final participantes = _mapearParticipantes(docs);
          final totalFinalizados = _contarFinalizados(docs);

          _chamados.removeWhere(
                (id) => docs.every((doc) => doc.id != id),
          );

          return Stack(
            children: [
              Positioned.fill(
                child: _buildConteudo(
                  participantes: participantes,
                  docs: docs,
                  totalFinalizados: totalFinalizados,
                ),
              ),
              if (_chamados.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildChamarOverlay(participantes),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField(Color appBarFg) {
    final t = context.uai;
    final searchBg = appBarFg.withOpacity(0.13);
    final searchBorder = appBarFg.withOpacity(0.18);

    return TextField(
      controller: _buscaController,
      focusNode: _buscaFocus,
      onChanged: _onBuscaChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(
        color: appBarFg,
        fontWeight: FontWeight.w800,
      ),
      cursorColor: appBarFg,
      decoration: InputDecoration(
        hintText: 'Buscar por nome ou graduação...',
        hintStyle: TextStyle(color: appBarFg.withOpacity(0.72)),
        prefixIcon: Icon(Icons.search_rounded, color: appBarFg),
        suffixIcon: _busca.isNotEmpty
            ? IconButton(
          onPressed: () {
            _buscaController.clear();
            setState(() => _busca = '');
            _buscaFocus.requestFocus();
          },
          icon: Icon(Icons.close_rounded, color: appBarFg),
        )
            : null,
        filled: true,
        fillColor: searchBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
          borderSide: BorderSide(color: searchBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
          borderSide: BorderSide(color: searchBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
          borderSide: BorderSide(
            color: appBarFg.withOpacity(0.75),
            width: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildConteudo({
    required List<_FinalizacaoParticipanteData> participantes,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required int totalFinalizados,
  }) {
    final totalGeral = docs.length;
    final totalNaFila = docs.map(_FinalizacaoParticipanteData.fromDoc)
        .where((item) => !item.finalizado)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontal = width < 600 ? 10.0 : 18.0;
        final maxWidth = width >= 1600
            ? 1520.0
            : width >= 1200
            ? 1360.0
            : width >= 900
            ? 1180.0
            : double.infinity;

        return RefreshIndicator(
          onRefresh: _atualizarTudo,
          color: context.uai.primary,
          child: CustomScrollView(
            key: PageStorageKey<String>(
              'finalizacao_massa_evento_scroll_${widget.eventoId}_$_viewMode',
            ),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: _buildResumoAoVivo(
                        totalNaFila: totalNaFila,
                        totalFiltrado: participantes.length,
                        totalFinalizados: totalFinalizados,
                        totalGeral: totalGeral,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: _buildPainelControle(participantes),
                    ),
                  ),
                ),
              ),
              if (participantes.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildListaVazia(),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    10,
                    horizontal,
                    _chamados.isEmpty ? 22 : 118,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: _viewMode == _viewGraduacoes
                            ? _buildGraduacoesView(participantes)
                            : _buildVisualPrincipalView(participantes),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResumoAoVivo({
    required int totalNaFila,
    required int totalFiltrado,
    required int totalFinalizados,
    required int totalGeral,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final header = Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: primary.withOpacity(0.14)),
                ),
                child: Icon(Icons.campaign_rounded, color: primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _viewMode == _viewGraduacoes
                          ? 'Chamada por graduação'
                          : _ordenacaoPrincipal == 'graduacao'
                          ? 'Visual da chamada • por nível'
                          : 'Visual da chamada • alfabético',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Marque quem será chamado, toque em CHAMAR e finalize só quem apareceu.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final stats = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _resumoChip(
                Icons.people_alt_rounded,
                '$totalNaFila',
                'na fila',
                t.warning,
              ),
              _resumoChip(
                Icons.filter_alt_rounded,
                '$totalFiltrado',
                'filtrado',
                t.info,
              ),
              _resumoChip(
                Icons.campaign_rounded,
                '${_chamados.length}',
                'chamados',
                t.primary,
              ),
              _resumoChip(
                Icons.check_circle_rounded,
                '$totalFinalizados',
                'finalizados',
                t.success,
              ),
              _resumoChip(
                Icons.groups_rounded,
                '$totalGeral',
                'total',
                t.info,
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 10),
                stats,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              stats,
            ],
          );
        },
      ),
    );
  }

  Widget _resumoChip(IconData icon, String value, String label, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
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

  Widget _buildPainelControle(List<_FinalizacaoParticipanteData> participantes) {
    final t = context.uai;
    final todosChamados = participantes.isNotEmpty &&
        participantes.every((item) => _chamados.contains(item.id));

    return Container(
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(2, 3, 2, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final filtros = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFiltroChamadaChip('Todos', Icons.groups_rounded),
                const SizedBox(width: 8),
                _buildFiltroChamadaChip('Chamados', Icons.campaign_rounded),
                const SizedBox(width: 8),
                _buildFiltroChamadaChip(
                  'Não chamados',
                  Icons.person_search_rounded,
                ),
              ],
            ),
          );

          final actions = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment:
              compact ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _processando || participantes.isEmpty
                      ? null
                      : () => _marcarTodosFiltrados(
                    participantes,
                    !todosChamados,
                  ),
                  icon: Icon(
                    todosChamados
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                  ),
                  label: Text(todosChamados ? 'DESMARCAR FILTRO' : 'MARCAR FILTRO'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _processando || participantes.isEmpty
                      ? null
                      : () => _inverterFiltrados(participantes),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('INVERTER'),
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filtros,
                const SizedBox(height: 8),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: filtros),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFiltroChamadaChip(String label, IconData icon) {
    final t = context.uai;
    final selected = _filtroChamada == label;
    final primary = _ensureVisible(t.primary, t.surface);

    return ChoiceChip(
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: selected ? primary : t.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
      onSelected: (_) => setState(() => _filtroChamada = label),
      backgroundColor: t.card,
      selectedColor: primary.withOpacity(0.12),
      side: BorderSide(
        color: selected ? primary.withOpacity(0.34) : t.border,
      ),
      labelStyle: TextStyle(
        color: selected ? primary : t.textSecondary,
        fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
      ),
    );
  }

  Widget _buildGraduacoesView(List<_FinalizacaoParticipanteData> participantes) {
    final grupos = _agruparPorGraduacao(participantes);

    return Column(
      children: grupos.map(_buildGrupoGraduacaoCard).toList(),
    );
  }

  Widget _buildGrupoGraduacaoCard(_GrupoGraduacaoFinalizacao grupo) {
    final t = context.uai;
    final cor1 = _ensureVisible(grupo.color1, t.card);
    final cor2 = _ensureVisible(grupo.color2, t.card);
    final aberto = _gruposAbertos.contains(grupo.key);
    final chamadosGrupo =
        grupo.alunos.where((item) => _chamados.contains(item.id)).length;
    final todosChamados =
        grupo.alunos.isNotEmpty && chamadosGrupo == grupo.alunos.length;
    final svg = _getModifiedSvg(grupo.referencia);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: aberto ? Color.alphaBlend(cor1.withOpacity(0.03), t.card) : t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(
          color: aberto ? cor1.withOpacity(0.44) : cor1.withOpacity(0.20),
        ),
        boxShadow: t.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _setStatePreservandoScroll(() {
                  if (aberto) {
                    _gruposAbertos.remove(grupo.key);
                  } else {
                    _gruposAbertos.add(grupo.key);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 58,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cor1.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cor1.withOpacity(0.20)),
                      ),
                      child: svg == null
                          ? _buildCordaMiniatura(cor1, cor2)
                          : SvgPicture.string(svg, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grupo.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: grupo.alunos.isEmpty
                                  ? 0
                                  : ((chamadosGrupo / grupo.alunos.length)
                                  .clamp(0.0, 1.0)).toDouble(),
                              minHeight: 6,
                              backgroundColor: t.border.withOpacity(0.65),
                              valueColor: AlwaysStoppedAnimation<Color>(cor1),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            chamadosGrupo == 0
                                ? '${grupo.alunos.length} aluno${grupo.alunos.length == 1 ? '' : 's'} aguardando chamada'
                                : '$chamadosGrupo de ${grupo.alunos.length} marcado${chamadosGrupo == 1 ? '' : 's'} para chamar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: todosChamados
                          ? 'Desmarcar graduação'
                          : 'Marcar graduação',
                      onPressed: _processando
                          ? null
                          : () => _marcarTodosFiltrados(
                        grupo.alunos,
                        !todosChamados,
                      ),
                      icon: Icon(
                        todosChamados
                            ? Icons.remove_done_rounded
                            : Icons.done_all_rounded,
                        color: cor1,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: cor1.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cor1.withOpacity(0.16)),
                      ),
                      child: Text(
                        chamadosGrupo > 0
                            ? '$chamadosGrupo/${grupo.alunos.length}'
                            : '${grupo.alunos.length}',
                        style: TextStyle(
                          color: cor1,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: aberto ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: cor1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState:
            aberto ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: _buildGridChamados(grupo.alunos),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCordaMiniatura(Color cor1, Color cor2) {
    final t = context.uai;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Expanded(child: Container(color: cor1)),
          Expanded(child: Container(color: cor2)),
          if (cor1 == cor2)
            Container(width: 1, color: t.card.withOpacity(0.8)),
        ],
      ),
    );
  }

  Widget _buildGridChamados(List<_FinalizacaoParticipanteData> participantes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // O log mostrou BoxConstraints(w=-5.0, h=232.0). Isso acontecia quando
        // o Flutter media o conteúdo expandido com largura transitória muito
        // pequena e o cálculo de 2 colunas gerava largura negativa.
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        if (width <= 0) return const SizedBox.shrink();

        final isMobileGrid = width < 620;
        final spacing = isMobileGrid ? 8.0 : 10.0;
        final minCardWidth = isMobileGrid ? 136.0 : 168.0;

        int columns;
        if (width < 300) {
          columns = 1;
        } else if (width < 620) {
          // No celular, a chamada fica mais rápida em 2x2.
          // Mantém 1 coluna só em larguras realmente apertadas.
          columns = 2;
        } else if (width < 900) {
          columns = 3;
        } else if (width < 1180) {
          columns = 4;
        } else if (width < 1500) {
          columns = 5;
        } else {
          columns = 6;
        }

        while (columns > 1 &&
            ((width - spacing * (columns - 1)) / columns) < minCardWidth) {
          columns--;
        }

        final rawItemWidth = columns <= 1
            ? width
            : (width - spacing * (columns - 1)) / columns;
        final itemWidth = rawItemWidth < 1 ? 1.0 : rawItemWidth;
        final cardHeight = isMobileGrid && columns >= 2
            ? (itemWidth * 1.16).clamp(166.0, 194.0).toDouble()
            : itemWidth < 180
            ? 224.0
            : 232.0;
        final compactCard = isMobileGrid && columns >= 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: participantes.map((item) {
            final cor1 = _cor1Graduacao(item);
            final cor2 = _cor2Graduacao(item);
            final svg = _getModifiedSvg(item);

            return SizedBox(
              width: itemWidth,
              height: cardHeight,
              child: _FinalizacaoAlunoFotoCard(
                item: item,
                alunoExtraFuture: _buscarAlunoExtra(item),
                chamado: _chamados.contains(item.id),
                processando: _processandoIds.contains(item.id),
                cor1: cor1,
                cor2: cor2,
                svg: svg,
                onTap: () => _toggleChamado(item),
                readableOn: _readableOn,
                compact: compactCard,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildVisualPrincipalView(
      List<_FinalizacaoParticipanteData> participantes,
      ) {
    final ordenados = _ordenarParaVisualPrincipal(participantes);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        if (width <= 0) return const SizedBox.shrink();

        final columns = width >= 1500
            ? 3
            : width >= 980
            ? 2
            : 1;
        const spacing = 12.0;
        final rawItemWidth = columns <= 1
            ? width
            : (width - spacing * (columns - 1)) / columns;
        final itemWidth = rawItemWidth < 1 ? 1.0 : rawItemWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: ordenados.map((item) {
            final cor1 = _cor1Graduacao(item);
            final cor2 = _cor2Graduacao(item);
            final svg = _getModifiedSvg(item);

            return SizedBox(
              width: itemWidth,
              height: 112,
              child: _FinalizacaoAlunoHorizontalCard(
                item: item,
                alunoExtraFuture: _buscarAlunoExtra(item),
                chamado: _chamados.contains(item.id),
                processando: _processandoIds.contains(item.id),
                cor1: cor1,
                cor2: cor2,
                svg: svg,
                onTap: () => _toggleChamado(item),
                readableOn: _readableOn,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildChamarOverlay(
      List<_FinalizacaoParticipanteData> participantesFiltrados,
      ) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    final chamadosVisiveis = participantesFiltrados
        .where((item) => _chamados.contains(item.id))
        .length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: primary.withOpacity(0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 460;

                  final label = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: primary.withOpacity(0.14)),
                        ),
                        child: Icon(Icons.campaign_rounded, color: primary, size: 20),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          chamadosVisiveis == _chamados.length
                              ? '${_chamados.length} aluno(s) marcado(s)'
                              : '${_chamados.length} marcado(s) • $chamadosVisiveis neste filtro',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  );

                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _processando ? null : _limparChamados,
                        child: const Text('LIMPAR'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _processando
                            ? null
                            : () => _abrirDialogoChamar(participantesFiltrados),
                        icon: const Icon(Icons.campaign_rounded),
                        label: const Text('CHAMAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: _readableOn(primary),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        label,
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: label),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final t = context.uai;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            const SizedBox(height: 14),
            Text(
              'Carregando finalização do evento...',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemPermissao() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.warning.withOpacity(0.20)),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 58, color: t.warning),
              const SizedBox(height: 12),
              Text(
                'Sem permissão para finalizar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Peça para o administrador liberar a permissão “pode_concluir_participacao_evento”.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErro(String erro) {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.error.withOpacity(0.28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: t.error, size: 54),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar finalização',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                erro,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaVazia() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _busca.isEmpty && _filtroChamada == 'Todos'
                  ? Icons.verified_rounded
                  : Icons.search_off_rounded,
              size: 66,
              color: _busca.isEmpty && _filtroChamada == 'Todos'
                  ? t.success
                  : t.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              _busca.isEmpty && _filtroChamada == 'Todos'
                  ? 'Todos os alunos foram finalizados'
                  : 'Nenhum aluno encontrado neste filtro',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _busca.isEmpty && _filtroChamada == 'Todos'
                  ? 'A lista fica vazia quando todos já passaram pela finalização.'
                  : 'Limpe a busca ou altere o filtro para voltar para a lista geral.',
              textAlign: TextAlign.center,
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
}

class _FinalizacaoAlunoFotoCard extends StatelessWidget {
  final _FinalizacaoParticipanteData item;
  final Future<_AlunoExtraEventoData> alunoExtraFuture;
  final bool chamado;
  final bool processando;
  final Color cor1;
  final Color cor2;
  final String? svg;
  final VoidCallback onTap;
  final Color Function(Color background) readableOn;
  final bool compact;

  const _FinalizacaoAlunoFotoCard({
    required this.item,
    required this.alunoExtraFuture,
    required this.chamado,
    required this.processando,
    required this.cor1,
    required this.cor2,
    required this.svg,
    required this.onTap,
    required this.readableOn,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final accent = chamado ? t.primary : cor1;
    final cardRadius = compact ? 16.0 : 22.0;
    final clipRadius = compact ? 14.5 : 19.0;
    final bottomBarHeight = compact ? 22.0 : 32.0;
    final horizontalPadding = compact ? 7.0 : 9.0;
    final bottomPadding = compact ? 7.0 : 9.0;
    final nomeFont = compact ? 9.6 : 12.8;
    final nomeMaxLines = compact ? 2 : 2;
    final checkSize = chamado ? (compact ? 23.0 : 28.0) : (compact ? 12.0 : 14.0);
    final checkIconSize = compact ? 15.0 : 18.0;
    final actionSize = compact ? 24.0 : 29.0;
    final actionIconSize = compact ? 13.5 : 16.0;
    final svgWidth = compact ? 26.0 : 34.0;
    final svgHeight = compact ? 34.0 : 42.0;

    return FutureBuilder<_AlunoExtraEventoData>(
      future: alunoExtraFuture,
      builder: (context, snapshot) {
        final extra = snapshot.data ?? _AlunoExtraEventoData.empty();
        final fotoUrl = item.melhorFoto(extra);
        final nome = item.nome.trim().isEmpty ? extra.nome : item.nome;
        final primeiraLetra = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();

        return AnimatedScale(
          duration: const Duration(milliseconds: 130),
          scale: chamado ? 0.985 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(cardRadius),
              border: Border.all(
                color: accent.withOpacity(chamado ? 0.95 : 0.78),
                width: chamado ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(chamado ? 0.22 : 0.13),
                  blurRadius: chamado ? 14 : 9,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: processando ? null : onTap,
                borderRadius: BorderRadius.circular(cardRadius - 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(clipRadius),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Column(
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _FotoAlunoEvento(
                                    fotoUrl: fotoUrl,
                                    fallbackLetter: primeiraLetra,
                                  ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.center,
                                          colors: [
                                            Colors.black.withOpacity(0.74),
                                            Colors.black.withOpacity(0.24),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: horizontalPadding,
                                    right: horizontalPadding,
                                    bottom: bottomPadding,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          nome.toUpperCase(),
                                          maxLines: nomeMaxLines,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: nomeFont,
                                            fontWeight: FontWeight.w900,
                                            height: 1.02,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black87,
                                                blurRadius: 7,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Flexible(
                                              child: _GradChipMini(
                                                label: item.graduacaoCurta,
                                              ),
                                            ),
                                            if (item.tamanhoCamisa.isNotEmpty) ...[
                                              const SizedBox(width: 5),
                                              _CamisaChipMini(
                                                label: item.tamanhoCamisa,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: bottomBarHeight,
                              child: Row(
                                children: [
                                  Expanded(child: Container(color: cor2)),
                                  Expanded(child: Container(color: cor1)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 7,
                        left: 7,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: checkSize,
                          height: checkSize,
                          decoration: BoxDecoration(
                            color: chamado ? accent : t.card,
                            shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.22),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                          child: chamado
                              ? Icon(
                            Icons.check_rounded,
                            color: readableOn(accent),
                            size: checkIconSize,
                          )
                              : null,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: actionSize,
                          height: actionSize,
                          decoration: BoxDecoration(
                            color: t.warning,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.card, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.20),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.campaign_rounded,
                            color: readableOn(t.warning),
                            size: actionIconSize,
                          ),
                        ),
                      ),
                      if (svg != null)
                        Positioned(
                          right: compact ? 6 : 8,
                          bottom: bottomBarHeight + (compact ? 2 : 4),
                          child: SizedBox(
                            width: svgWidth,
                            height: svgHeight,
                            child: SvgPicture.string(
                              svg!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      if (processando)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.45),
                            alignment: Alignment.center,
                            child: CircularProgressIndicator(color: accent),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FinalizacaoAlunoHorizontalCard extends StatelessWidget {
  final _FinalizacaoParticipanteData item;
  final Future<_AlunoExtraEventoData> alunoExtraFuture;
  final bool chamado;
  final bool processando;
  final Color cor1;
  final Color cor2;
  final String? svg;
  final VoidCallback onTap;
  final Color Function(Color background) readableOn;

  const _FinalizacaoAlunoHorizontalCard({
    required this.item,
    required this.alunoExtraFuture,
    required this.chamado,
    required this.processando,
    required this.cor1,
    required this.cor2,
    required this.svg,
    required this.onTap,
    required this.readableOn,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final accent = chamado ? t.primary : cor1;

    return FutureBuilder<_AlunoExtraEventoData>(
      future: alunoExtraFuture,
      builder: (context, snapshot) {
        final extra = snapshot.data ?? _AlunoExtraEventoData.empty();
        final fotoUrl = item.melhorFoto(extra);
        final nome = item.nome.trim().isEmpty ? extra.nome : item.nome;
        final primeiraLetra = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withOpacity(chamado ? 0.80 : 0.22),
              width: chamado ? 2.4 : 1,
            ),
            boxShadow: t.softShadow,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: processando ? null : onTap,
              borderRadius: BorderRadius.circular(18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _FotoAlunoEvento(
                                  fotoUrl: fotoUrl,
                                  fallbackLetter: primeiraLetra,
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 8,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [cor2, cor1],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(11, 9, 8, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    nome.toUpperCase(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.2,
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    item.graduacaoLonga,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        chamado
                                            ? Icons.campaign_rounded
                                            : Icons.radio_button_unchecked_rounded,
                                        color: accent,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          chamado ? 'Chamado para finalizar' : 'Toque para marcar',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: accent,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (svg != null)
                            SizedBox(
                              width: 48,
                              child: Center(
                                child: SvgPicture.string(
                                  svg!,
                                  height: 56,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          const SizedBox(width: 7),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: chamado ? accent : cor1,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(999),
                          ),
                        ),
                        child: Icon(
                          chamado ? Icons.check_rounded : Icons.campaign_rounded,
                          color: readableOn(chamado ? accent : cor1),
                          size: 19,
                        ),
                      ),
                    ),
                    if (processando)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.40),
                          alignment: Alignment.center,
                          child: CircularProgressIndicator(color: accent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AvatarAlunoChamado extends StatelessWidget {
  final _FinalizacaoParticipanteData item;
  final Future<_AlunoExtraEventoData> extraFuture;
  final Color borderColor;

  const _AvatarAlunoChamado({
    required this.item,
    required this.extraFuture,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AlunoExtraEventoData>(
      future: extraFuture,
      builder: (context, snapshot) {
        final extra = snapshot.data ?? _AlunoExtraEventoData.empty();
        final foto = item.melhorFoto(extra);
        final nome = item.nome.trim().isEmpty ? extra.nome : item.nome;
        final letra = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();

        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2.2),
          ),
          child: ClipOval(
            child: _FotoAlunoEvento(fotoUrl: foto, fallbackLetter: letra),
          ),
        );
      },
    );
  }
}

class _FotoAlunoEvento extends StatefulWidget {
  final String fotoUrl;
  final String fallbackLetter;

  const _FotoAlunoEvento({
    required this.fotoUrl,
    required this.fallbackLetter,
  });

  @override
  State<_FotoAlunoEvento> createState() => _FotoAlunoEventoState();
}

class _FotoAlunoEventoState extends State<_FotoAlunoEvento> {
  Future<String?>? _resolvedFuture;
  String _lastRaw = '';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant _FotoAlunoEvento oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fotoUrl != widget.fotoUrl) {
      _prepare();
    }
  }

  void _prepare() {
    final raw = widget.fotoUrl.trim();
    _lastRaw = raw;

    if (raw.isEmpty || raw.startsWith('http://') || raw.startsWith('https://')) {
      _resolvedFuture = null;
      return;
    }

    _resolvedFuture = _resolverStorageUrl(raw);
  }

  Future<String?> _resolverStorageUrl(String raw) async {
    try {
      final value = raw.trim();
      if (value.isEmpty) return null;
      if (value.startsWith('http://') || value.startsWith('https://')) return value;

      if (value.startsWith('gs://')) {
        return FirebaseStorage.instance.refFromURL(value).getDownloadURL();
      }

      // Aceita caminho salvo no Firestore, por exemplo:
      // alunos/fotos/abc.jpg, fotos_alunos/abc.png, uploads/...
      var path = value;
      while (path.startsWith('/')) {
        path = path.substring(1);
      }

      if (path.isEmpty) return null;

      return FirebaseStorage.instance.ref(path).getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.fotoUrl.trim();

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return _network(context, raw);
    }

    final future = _resolvedFuture;
    if (future != null) {
      return FutureBuilder<String?>(
        future: future,
        builder: (context, snapshot) {
          final resolved = snapshot.data?.trim() ?? '';
          if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
            return _network(context, resolved);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              color: context.uai.cardAlt,
              alignment: Alignment.center,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.uai.primary,
                ),
              ),
            );
          }
          return _fallback(context);
        },
      );
    }

    return _fallback(context);
  }

  Widget _network(BuildContext context, String url) {
    return Image.network(
      url,
      key: ValueKey<String>(url),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _fallback(context);
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: context.uai.cardAlt,
          alignment: Alignment.center,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.uai.primary,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _fallback(context);
      },
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      color: context.uai.cardAlt,
      alignment: Alignment.center,
      child: Text(
        widget.fallbackLetter,
        style: TextStyle(
          color: context.uai.textMuted,
          fontSize: 42,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GradChipMini extends StatelessWidget {
  final String label;

  const _GradChipMini({required this.label});

  @override
  Widget build(BuildContext context) {
    final text = label.trim().isEmpty ? 'SEM GRADUAÇÃO' : label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF991B1B),
          fontWeight: FontWeight.w900,
          fontSize: 9.2,
        ),
      ),
    );
  }
}

class _CamisaChipMini extends StatelessWidget {
  final String label;

  const _CamisaChipMini({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_bag_rounded, size: 9, color: context.uai.warning),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: context.uai.warning,
              fontWeight: FontWeight.w900,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrupoGraduacaoFinalizacao {
  final String key;
  final String titulo;
  final int ordem;
  final _FinalizacaoParticipanteData referencia;
  final List<_FinalizacaoParticipanteData> alunos;
  final Color color1;
  final Color color2;

  _GrupoGraduacaoFinalizacao({
    required this.key,
    required this.titulo,
    required this.ordem,
    required this.referencia,
    required this.alunos,
    required this.color1,
    required this.color2,
  });
}

class _FinalizacaoParticipanteData {
  final String id;
  final String alunoId;
  final String nome;
  final String? fotoUrl;
  final DateTime dataEvento;
  final String tipoEvento;
  final String eventoId;
  final String eventoNome;
  final String linkCertificado;
  final double valorInscricao;
  final double valorCamisa;
  final double totalPago;
  final String graduacaoAtual;
  final String graduacaoNova;
  final String graduacaoTexto;
  final String graduacaoId;
  final String graduacaoAtualId;
  final String graduacaoNovaId;
  final String turma;
  final String tamanhoCamisa;
  final String statusPagamento;
  final bool estaQuitado;
  final bool aguardandoFinalizacao;
  final bool finalizado;
  final double saldoDevedor;

  const _FinalizacaoParticipanteData({
    required this.id,
    required this.alunoId,
    required this.nome,
    required this.fotoUrl,
    required this.dataEvento,
    required this.tipoEvento,
    required this.eventoId,
    required this.eventoNome,
    required this.linkCertificado,
    required this.valorInscricao,
    required this.valorCamisa,
    required this.totalPago,
    required this.graduacaoAtual,
    required this.graduacaoNova,
    required this.graduacaoTexto,
    required this.graduacaoId,
    required this.graduacaoAtualId,
    required this.graduacaoNovaId,
    required this.turma,
    required this.tamanhoCamisa,
    required this.statusPagamento,
    required this.estaQuitado,
    required this.aguardandoFinalizacao,
    required this.finalizado,
    required this.saldoDevedor,
  });

  String get primeiroNome {
    final partes = nome.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return 'ALUNO';
    return partes.first;
  }

  String get graduacaoLonga {
    if (graduacaoNova.trim().isNotEmpty) return graduacaoNova.trim();
    if (graduacaoAtual.trim().isNotEmpty) return graduacaoAtual.trim();
    if (graduacaoTexto.trim().isNotEmpty) return graduacaoTexto.trim();
    return 'SEM GRADUAÇÃO';
  }

  String get graduacaoCurta {
    final base = graduacaoLonga;
    if (base == 'SEM GRADUAÇÃO') return base;
    return base.split(RegExp(r'\s+')).take(2).join(' ');
  }

  String melhorFoto(_AlunoExtraEventoData extra) {
    // Não usamos mais a foto salva na participação como fallback automático.
    // Ela pode ser uma URL antiga do Storage e gerar 404 no console antes da
    // foto atual do aluno chegar pelo FutureBuilder. A fonte confiável é o
    // documento atual em "alunos".
    final extraFoto = extra.fotoUrl.trim();
    if (extraFoto.isNotEmpty && extraFoto.toLowerCase() != 'null') {
      return extraFoto;
    }

    return '';
  }

  static DateTime _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return DateTime.now();

    try {
      return DateTime.parse(text);
    } catch (_) {
      final partes = text.split('/');
      if (partes.length == 3) {
        try {
          return DateTime(
            int.parse(partes[2]),
            int.parse(partes[1]),
            int.parse(partes[0]),
          );
        } catch (_) {}
      }
    }

    return DateTime.now();
  }

  factory _FinalizacaoParticipanteData.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data();

    // Usa o MESMO model da tela de participantes como fonte principal.
    // Essa tela de participantes já carrega as fotos corretamente porque usa
    // ParticipacaoModel.fromFirestore -> p.alunoId -> coleção alunos.
    final p = ParticipacaoModel.fromFirestore(doc);
    final modelMap = p.toMap();

    final status = _text(data['status'] ?? modelMap['status']).toLowerCase();
    final statusPagamento = _text(
      data['status_pagamento'] ??
          data['statusPagamento'] ??
          modelMap['status_pagamento'] ??
          modelMap['statusPagamento'],
    );

    final valorTotal = _asDouble(
      data['valor_total'] ??
          data['valorTotal'] ??
          modelMap['valor_total'] ??
          modelMap['valorTotal'],
    );
    final totalPago = _asDouble(
      data['total_pago'] ??
          data['totalPago'] ??
          modelMap['total_pago'] ??
          modelMap['totalPago'],
    );
    final saldoCalculado = (valorTotal - totalPago).clamp(0, double.infinity);

    final estaQuitado = p.estaQuitado ||
        data['esta_quitado'] == true ||
        data['quitado'] == true ||
        statusPagamento.toLowerCase().contains('quit') ||
        (valorTotal > 0 && totalPago >= valorTotal);

    final finalizado = data['finalizado'] == true ||
        data['participacao_finalizada'] == true ||
        data['data_finalizacao'] != null ||
        data['finalizado_em'] != null ||
        status == 'finalizado' ||
        status == 'finalizada' ||
        status == 'concluido' ||
        status == 'concluído' ||
        status == 'concluida' ||
        status == 'concluída';

    final alunoIdModelo = _text(p.alunoId);
    final alunoNomeModelo = _text(p.alunoNome);
    final alunoIdRaw = _text(
      data['aluno_id'] ??
          data['alunoId'] ??
          data['id_aluno'] ??
          data['idAluno'] ??
          data['aluno_doc_id'] ??
          data['alunoDocId'] ??
          data['aluno_uid'] ??
          data['alunoUid'] ??
          data['student_id'] ??
          data['studentId'] ??
          data['member_id'] ??
          data['memberId'] ??
          modelMap['aluno_id'] ??
          modelMap['alunoId'] ??
          _nestedText(data['aluno'], ['id', 'uid', 'docId', 'doc_id']),
    );

    return _FinalizacaoParticipanteData(
      id: p.id ?? doc.id,
      alunoId: alunoIdModelo.isNotEmpty ? alunoIdModelo : alunoIdRaw,
      nome: alunoNomeModelo.isNotEmpty
          ? alunoNomeModelo
          : _text(
        data['aluno_nome'] ?? data['alunoNome'],
        fallback: _text(data['nome'], fallback: 'Aluno'),
      ),
      fotoUrl: _firstUrl([
        p.alunoFoto,
        data['aluno_foto'],
        data['alunoFoto'],
        modelMap['aluno_foto'],
        modelMap['alunoFoto'],
        data['foto_perfil_aluno'],
        data['fotoPerfilAluno'],
        data['foto_perfil'],
        data['fotoPerfil'],
        data['foto_profile'],
        data['profile_image'],
        data['profileImage'],
        data['foto'],
        data['foto_url'],
        data['fotoUrl'],
        data['url_foto'],
        data['urlFoto'],
        data['link_foto'],
        data['linkFoto'],
        data['foto_aluno'],
        data['fotoAluno'],
        data['foto_aluno_url'],
        data['fotoAlunoUrl'],
        data['imagem'],
        data['imageUrl'],
        data['photoUrl'],
        data['profilePhotoUrl'],
        data['avatar'],
        data['avatarUrl'],
        data['urlImagem'],
        data['imagem_url'],
      ]),
      dataEvento: _asDateTime(data['data_evento'] ?? modelMap['data_evento']),
      tipoEvento: _text(
        p.tipoEvento,
        fallback: _text(data['tipo_evento'] ?? data['tipoEvento'], fallback: 'EVENTO'),
      ),
      eventoId: _text(
        p.eventoId,
        fallback: _text(data['evento_id'] ?? data['eventoId']),
      ),
      eventoNome: _text(
        p.eventoNome,
        fallback: _text(data['evento_nome'] ?? data['eventoNome']),
      ),
      linkCertificado: _text(
        p.linkCertificado,
        fallback: _text(
          data['link_certificado'] ??
              data['linkCertificado'] ??
              data['certificado_url'] ??
              data['certificadoUrl'] ??
              data['url_certificado'] ??
              data['urlCertificado'],
        ),
      ),
      valorInscricao: _asDouble(
        data['valor_inscricao'] ?? data['valorInscricao'] ?? modelMap['valor_inscricao'],
      ),
      valorCamisa: _asDouble(
        data['valor_camisa'] ?? data['valorCamisa'] ?? modelMap['valor_camisa'],
      ),
      totalPago: totalPago,
      graduacaoAtual: _text(
        p.graduacao,
        fallback: _text(
          data['graduacao'],
          fallback: _text(
            data['graduacao_atual'],
            fallback: _text(data['graduacaoAtual'], fallback: 'SEM GRADUAÇÃO'),
          ),
        ),
      ),
      graduacaoNova: _text(
        p.graduacaoNova,
        fallback: _text(data['graduacao_nova'] ?? data['graduacaoNova']),
      ),
      graduacaoTexto: _text(
        data['graduacao_nome'] ?? data['graduacaoNome'],
        fallback: _text(data['graduacao'], fallback: _text(p.graduacao)),
      ),
      graduacaoId: _text(data['graduacao_id'] ?? data['graduacaoId']),
      graduacaoAtualId: _text(
        data['graduacao_atual_id'] ?? data['graduacaoAtualId'],
      ),
      graduacaoNovaId: _text(
        p.graduacaoNovaId,
        fallback: _text(data['graduacao_nova_id'] ?? data['graduacaoNovaId']),
      ),
      turma: _text(data['turma'] ?? modelMap['turma']),
      tamanhoCamisa: _text(
        p.tamanhoCamisa,
        fallback: _text(data['tamanho_camisa'] ?? data['tamanhoCamisa']),
      ).toUpperCase(),
      statusPagamento: statusPagamento,
      estaQuitado: estaQuitado,
      aguardandoFinalizacao: p.aguardandoFinalizacao ||
          data['aguardando_finalizacao'] == true ||
          data['aguardandoFinalizacao'] == true,
      finalizado: finalizado,
      saldoDevedor: p.saldoDevedor > 0
          ? p.saldoDevedor
          : saldoCalculado.toDouble(),
    );
  }

  static String? _firstUrl(List<dynamic> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  static String _nestedText(dynamic value, List<String> keys) {
    if (value is! Map) return '';
    for (final key in keys) {
      final text = _text(value[key]);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().replaceAll(',', '.').trim() ?? '';
    if (text.isEmpty) return 0;
    return double.tryParse(text) ?? 0;
  }
}

class _AlunoExtraEventoData {
  final String nome;
  final String fotoUrl;
  final String graduacaoAtual;
  final String graduacaoAtualId;

  const _AlunoExtraEventoData({
    required this.nome,
    required this.fotoUrl,
    required this.graduacaoAtual,
    required this.graduacaoAtualId,
  });

  factory _AlunoExtraEventoData.empty() {
    return const _AlunoExtraEventoData(
      nome: '',
      fotoUrl: '',
      graduacaoAtual: '',
      graduacaoAtualId: '',
    );
  }

  factory _AlunoExtraEventoData.fromAlunoDoc(Map<String, dynamic> data) {
    return _AlunoExtraEventoData(
      nome: _text(data['nome']),
      fotoUrl: _firstUrl([
        data['foto_perfil_aluno'],
        data['fotoPerfilAluno'],
        data['foto_perfil'],
        data['fotoPerfil'],
        data['foto_profile'],
        data['profile_image'],
        data['profileImage'],
        data['foto'],
        data['foto_url'],
        data['fotoUrl'],
        data['url_foto'],
        data['urlFoto'],
        data['link_foto'],
        data['linkFoto'],
        data['foto_aluno'],
        data['fotoAluno'],
        data['aluno_foto'],
        data['imagem'],
        data['imageUrl'],
        data['photoUrl'],
        data['profilePhotoUrl'],
        data['avatar'],
        data['avatarUrl'],
        data['urlImagem'],
        data['imagem_url'],
      ]),
      graduacaoAtual: _text(
        data['graduacao_atual'],
        fallback: _text(data['graduacao_nome'], fallback: _text(data['graduacao'])),
      ),
      graduacaoAtualId: _text(
        data['graduacao_id'],
        fallback: _text(data['graduacao_atual_id']),
      ),
    );
  }

  static String _firstUrl(List<dynamic> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        // Pode ser https, gs:// ou caminho interno do Firebase Storage.
        // A classe _FotoAlunoEvento resolve esses formatos.
        return text;
      }
    }
    return '';
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
  }
}
