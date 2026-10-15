import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class DashboardEstatisticasScreen extends StatefulWidget {
  const DashboardEstatisticasScreen({super.key});

  @override
  State<DashboardEstatisticasScreen> createState() =>
      _DashboardEstatisticasScreenState();
}

class _DashboardEstatisticasScreenState
    extends State<DashboardEstatisticasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  final ScrollController _scrollController = ScrollController();

  // TRACKING PATCH 05:
  // O dashboard abre lendo apenas o cache agregado do Firebase.
  // Sessões brutas só são carregadas quando a aba "Sessões" é aberta.
  Map<String, dynamic> _cacheDashboard = {};
  DateTime? _cacheGeradoEm;
  bool _cacheExiste = false;
  bool _reconstruindoCache = false;
  bool _sessoesInicializadas = false;
  bool _carregandoSessoes = false;

  Map<String, dynamic> _dadosAgregados = {};
  List<Map<String, dynamic>> _acessosCarregados = [];

  int _totalAcessos = 0;
  int _visitasHoje = 0;
  int _visitasSemana = 0;
  int _visitasMes = 0;

  Map<String, int> _acessosPorHora = {};
  Map<String, int> _acessosPorDia = {};

  bool _carregandoInicial = true;
  bool _carregandoMais = false;
  bool _temMaisDados = true;

  String _filtroPeriodo = 'todos';
  int _abaDashboard = 0;

  DocumentSnapshot? _ultimoDocumento;
  final int _limitePorPagina = 30;

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
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

  Color _onPrimary() => _readableOn(context.uai.primary);

  Color _softOnCard(Color color) {
    final t = context.uai;
    return _ensureVisible(color, t.card);
  }

  Color _softFill(Color color, {Color? base}) {
    final t = context.uai;
    final bg = base ?? t.card;
    final accent = _ensureVisible(color, bg);
    return Color.alphaBlend(accent.withAlpha(26), bg);
  }

  Color _softBorder(Color color, {Color? base}) {
    final t = context.uai;
    final bg = base ?? t.card;
    final accent = _ensureVisible(color, bg);
    return accent.withAlpha(56);
  }

  @override
  void initState() {
    super.initState();
    _carregarTudo();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_abaDashboard != 3 || !_sessoesInicializadas) return;
    if (!_scrollController.hasClients) return;

    final posicao = _scrollController.position;
    if (posicao.pixels >= posicao.maxScrollExtent - 240) {
      _carregarMaisAcessos();
    }
  }

  Future<void> _carregarTudo() async {
    await _carregarCacheDashboard();
  }

  Future<void> _atualizarTudo() async {
    if (_reconstruindoCache) return;

    if (mounted) {
      setState(() => _reconstruindoCache = true);
    }

    try {
      final callable =
          _functions.httpsCallable('reconstruirCacheDashboardTracking');
      final result = await callable.call(<String, dynamic>{
        'origem': 'pull_to_refresh_dashboard',
      });

      final raw = result.data;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      if (data['success'] != true) {
        throw StateError(
          data['message']?.toString() ?? 'Falha ao reconstruir cache.',
        );
      }

      final cacheRaw = data['cache'];
      if (cacheRaw is Map) {
        _aplicarCacheDashboard(Map<String, dynamic>.from(cacheRaw));
      } else {
        await _carregarCacheDashboard();
      }

      // Se o administrador estiver olhando sessões, atualiza somente a
      // primeira página (30 docs) depois do rebuild.
      if (_abaDashboard == 3 && _sessoesInicializadas) {
        await _carregarPrimeiraPagina();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estatísticas reconstruídas • ${data['sessoesLidas'] ?? 0} sessões processadas',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _mostrarSnack(
        e.message ?? 'Não foi possível atualizar as estatísticas.',
        erro: true,
      );
    } catch (_) {
      if (!mounted) return;
      _mostrarSnack(
        'Não foi possível atualizar as estatísticas.',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => _reconstruindoCache = false);
    }
  }

  Future<void> _carregarCacheDashboard() async {
    if (mounted) setState(() => _carregandoInicial = true);

    try {
      final callable = _functions.httpsCallable('obterCacheDashboardTracking');
      final result = await callable.call();
      final raw = result.data;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      if (data['success'] == true && data['cache'] is Map) {
        _aplicarCacheDashboard(
          Map<String, dynamic>.from(data['cache'] as Map),
        );
      } else {
        // Primeiro uso depois do patch: mostra o painel leve e deixa o admin
        // puxar para baixo para gerar o primeiro cache.
        if (mounted) {
          setState(() {
            _cacheExiste = false;
            _cacheDashboard = {};
            _dadosAgregados = {};
            _totalAcessos = 0;
            _visitasHoje = 0;
            _visitasSemana = 0;
            _visitasMes = 0;
            _acessosPorHora = {};
            _acessosPorDia = {};
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cacheExiste = false);
      }
    } finally {
      if (mounted) setState(() => _carregandoInicial = false);
    }
  }

  Map<String, dynamic> _mapDinamico(dynamic value) {
    return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  }

  Map<String, int> _mapStringInt(dynamic value) {
    if (value is! Map) return <String, int>{};
    return value.map(
      (key, value) => MapEntry(
        key.toString(),
        value is num ? value.round() : int.tryParse(value.toString()) ?? 0,
      ),
    );
  }

  String get _chavePeriodoCache {
    return switch (_filtroPeriodo) {
      'hoje' => 'hoje',
      'semana' => 'semana',
      'mes' => 'mes',
      _ => 'todos',
    };
  }

  Map<String, dynamic> get _cachePeriodoAtual {
    final periodos = _mapDinamico(_cacheDashboard['periodos']);
    return _mapDinamico(periodos[_chavePeriodoCache]);
  }

  void _aplicarCacheDashboard(Map<String, dynamic> cache) {
    final periodos = _mapDinamico(cache['periodos']);
    final todos = _mapDinamico(periodos['todos']);
    final hoje = _mapDinamico(periodos['hoje']);
    final semana = _mapDinamico(periodos['semana']);
    final mes = _mapDinamico(periodos['mes']);

    DateTime? geradoEm;
    final iso = cache['gerado_em_iso']?.toString();
    if (iso != null && iso.isNotEmpty) {
      geradoEm = DateTime.tryParse(iso)?.toLocal();
    }

    final localizacaoLegacy = _mapDinamico(cache['localizacao_legacy']);

    if (!mounted) return;
    setState(() {
      _cacheDashboard = cache;
      _cacheExiste = true;
      _cacheGeradoEm = geradoEm;
      _dadosAgregados = _converterNotacaoPontoParaArvore(localizacaoLegacy);
      _totalAcessos = (todos['total_visitas'] as num?)?.round() ?? 0;
      _visitasHoje = (hoje['total_visitas'] as num?)?.round() ?? 0;
      _visitasSemana = (semana['total_visitas'] as num?)?.round() ?? 0;
      _visitasMes = (mes['total_visitas'] as num?)?.round() ?? 0;

      final atual = _mapDinamico(periodos[_chavePeriodoCache]);
      _acessosPorHora = _mapStringInt(atual['acessos_por_hora']);
      _acessosPorDia = _mapStringInt(atual['acessos_por_dia']);
    });
  }

  void _aplicarPeriodoCacheSelecionado() {
    if (!_cacheExiste) return;
    final atual = _cachePeriodoAtual;
    setState(() {
      _acessosPorHora = _mapStringInt(atual['acessos_por_hora']);
      _acessosPorDia = _mapStringInt(atual['acessos_por_dia']);
    });
  }

  String _textoAtualizacaoCache() {
    final data = _cacheGeradoEm;
    if (data == null) return 'Cache ainda não gerado';
    final diff = DateTime.now().difference(data);
    if (diff.inMinutes < 1) return 'Atualizado agora';
    if (diff.inMinutes < 60) return 'Atualizado há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Atualizado há ${diff.inHours} h';
    return 'Atualizado em ${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')} '
        '${data.hour.toString().padLeft(2, '0')}:'
        '${data.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _garantirSessoesCarregadas() async {
    if (_sessoesInicializadas || _carregandoSessoes) return;
    _sessoesInicializadas = true;
    await _carregarPrimeiraPagina();
  }

  Future<void> _carregarPrimeiraPagina() async {
    if (mounted) {
      setState(() {
        _carregandoSessoes = true;
        _acessosCarregados = [];
        _ultimoDocumento = null;
        _temMaisDados = true;
      });
    }

    try {
      final query = _firestore
          .collection('estatisticas_acessos')
          .orderBy('data_acesso', descending: true)
          .limit(_limitePorPagina);

      final snapshot = await query.get();

      final acessos = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (!mounted) return;

      setState(() {
        _acessosCarregados = acessos;
        _ultimoDocumento = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _temMaisDados = snapshot.docs.length == _limitePorPagina;
        _carregandoSessoes = false;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar primeira página: $e');
      if (mounted) setState(() => _carregandoSessoes = false);
    }
  }

  Future<void> _carregarMaisAcessos() async {
    if (_carregandoMais ||
        !_temMaisDados ||
        _ultimoDocumento == null) {
      return;
    }

    setState(() => _carregandoMais = true);

    try {
      final query = _firestore
          .collection('estatisticas_acessos')
          .orderBy('data_acesso', descending: true)
          .startAfterDocument(_ultimoDocumento!)
          .limit(_limitePorPagina);

      final snapshot = await query.get();

      final novosAcessos = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (!mounted) return;

      setState(() {
        _acessosCarregados.addAll(novosAcessos);
        _ultimoDocumento = snapshot.docs.isNotEmpty
            ? snapshot.docs.last
            : _ultimoDocumento;
        _temMaisDados = snapshot.docs.length == _limitePorPagina;
        _carregandoMais = false;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar mais acessos: $e');
      if (mounted) setState(() => _carregandoMais = false);
    }
  }

  void _recalcularEstatisticasCompletas() {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
    final inicioMes = DateTime(agora.year, agora.month, 1);

    int visitasHoje = 0;
    int visitasSemana = 0;
    int visitasMes = 0;

    final porHora = <String, int>{};
    final porDia = <String, int>{};

    for (final acesso in _acessosCarregados) {
      final timestamp = acesso['data_acesso'];
      final dataAcesso = timestamp is Timestamp ? timestamp.toDate() : null;

      if (dataAcesso == null) continue;

      if (dataAcesso.isAfter(hoje)) visitasHoje++;
      if (dataAcesso.isAfter(inicioSemana)) visitasSemana++;
      if (dataAcesso.isAfter(inicioMes)) visitasMes++;

      final horaKey = '${dataAcesso.hour.toString().padLeft(2, '0')}:00';
      porHora[horaKey] = (porHora[horaKey] ?? 0) + 1;

      final diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
      final diaKey = diasSemana[dataAcesso.weekday - 1];
      porDia[diaKey] = (porDia[diaKey] ?? 0) + 1;
    }

    if (!mounted) return;

    setState(() {
      _visitasHoje = visitasHoje;
      _visitasSemana = visitasSemana;
      _visitasMes = visitasMes;
      _acessosPorHora = porHora;
      _acessosPorDia = porDia;
    });
  }

  Map<String, dynamic> _converterNotacaoPontoParaArvore(
    Map<String, dynamic> dados,
  ) {
    final resultado = <String, dynamic>{};

    dados.forEach((chave, valor) {
      if (chave == 'total_visitas' || chave == 'ultima_atualizacao') {
        resultado[chave] = valor;
      } else if (chave.contains('.')) {
        final partes = chave.split('.');
        Map<String, dynamic> atual = resultado;

        for (int i = 0; i < partes.length - 1; i++) {
          final parte = partes[i];
          atual.putIfAbsent(parte, () => <String, dynamic>{});
          atual = atual[parte] as Map<String, dynamic>;
        }

        atual[partes.last] = valor;
      } else {
        resultado[chave] = valor;
      }
    });

    return resultado;
  }

  List<Map<String, dynamic>> _getAcessosFiltrados() {
    if (_filtroPeriodo == 'todos') return _acessosCarregados;

    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    final dataLimite = switch (_filtroPeriodo) {
      'hoje' => hoje,
      'semana' => hoje.subtract(Duration(days: hoje.weekday - 1)),
      'mes' => DateTime(agora.year, agora.month, 1),
      _ => DateTime(2000),
    };

    return _acessosCarregados.where((acesso) {
      final timestamp = acesso['data_acesso'];
      final dataAcesso = timestamp is Timestamp ? timestamp.toDate() : null;
      return dataAcesso != null && dataAcesso.isAfter(dataLimite);
    }).toList();
  }

  String _formatarDataHora(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';

    final date = timestamp.toDate();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatarHoraEvento(dynamic valor) {
    if (valor == null) return '--:--:--';

    try {
      DateTime? dateTime;

      if (valor is Timestamp) {
        dateTime = valor.toDate();
      } else {
        final texto = valor.toString();
        if (texto.trim().isNotEmpty) {
          dateTime = DateTime.parse(texto);
        }
      }

      if (dateTime == null) return '--:--:--';

      return '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}:'
          '${dateTime.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--:--';
    }
  }

  Future<void> _abrirGoogleMaps(double? latitude, double? longitude) async {
    if (latitude == null || longitude == null) {
      _mostrarSnack('Coordenadas não disponíveis para este acesso', erro: true);
      return;
    }

    final lat = latitude.toStringAsFixed(6);
    final lng = longitude.toStringAsFixed(6);

    final urls = <Uri>[
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
      Uri.parse('https://maps.google.com/?q=$lat,$lng'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];

    for (final uri in urls) {
      try {
        final abriu = await launchUrl(
          uri,
          mode: uri.scheme == 'geo'
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );

        if (abriu) return;
      } catch (e) {
        debugPrint('⚠️ Falha ao abrir mapa com $uri: $e');
      }
    }

    _mostrarSnack(
      'Não foi possível abrir o Google Maps neste dispositivo.',
      erro: true,
    );
  }

  void _mostrarSnack(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? context.uai.error : context.uai.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _contarEventos(List<Map<String, dynamic>> eventos, String tipo) {
    return eventos.where((e) => e['tipo']?.toString() == tipo).length;
  }

  Map<String, int> _resumoTiposEvento(List<Map<String, dynamic>> eventos) {
    return {
      'menus': _contarEventos(eventos, 'menu'),
      'botoes':
          _contarEventos(eventos, 'botao_social') +
          _contarEventos(eventos, 'clique'),
      'cards': _contarEventos(eventos, 'card'),
      'paginas': _contarEventos(eventos, 'pagina'),
      'telas': _contarEventos(eventos, 'tela'),
      'formularios': _contarEventos(eventos, 'formulario'),
      'etapas': _contarEventos(eventos, 'etapa_formulario'),
      'erros': _contarEventos(eventos, 'erro_formulario'),
      'conversoes': _contarEventos(eventos, 'conversao'),
      'funil': _contarEventos(eventos, 'funil_inscricao'),
      'campos': _contarEventos(eventos, 'campo_formulario'),
      'snapshots': _contarEventos(eventos, 'snapshot_formulario'),
      'rolagens': _contarEventos(eventos, 'rolagem'),
      'filtros': _contarEventos(eventos, 'filtro'),
      'itens': _contarEventos(eventos, 'item_visualizado'),
    };
  }

  int _contarCamposSuspeitos(List<Map<String, dynamic>> eventos) {
    var total = 0;

    for (final evento in eventos) {
      final metadata = evento['metadata'];
      if (metadata is! Map) continue;

      if (metadata['suspeito'] == true) total++;

      final camposSuspeitos = metadata['campos_suspeitos'];
      if (camposSuspeitos is List) total += camposSuspeitos.length;
    }

    return total;
  }

  int _somarDuracaoEventos(List<Map<String, dynamic>> eventos, String tipo) {
    var total = 0;

    for (final evento in eventos) {
      if (evento['tipo']?.toString() != tipo) continue;
      final metadata = evento['metadata'];
      if (metadata is! Map) continue;
      final valor =
          metadata['duracao_segundos'] ?? metadata['duracao_etapa_segundos'];
      if (valor is int) total += valor;
      if (valor is double) total += valor.round();
    }

    return total;
  }

  String _formatarDuracao(int segundos) {
    if (segundos <= 0) return '0s';
    if (segundos < 60) return '${segundos}s';

    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    if (minutos < 60) {
      return resto == 0 ? '${minutos}min' : '${minutos}min ${resto}s';
    }

    final horas = minutos ~/ 60;
    final minutosRestantes = minutos % 60;
    return '${horas}h ${minutosRestantes}min';
  }

  bool _eventoEhSuspeito(Map<String, dynamic> evento) {
    final metadataRaw = evento['metadata'];
    if (metadataRaw is! Map) return false;
    final metadata = Map<String, dynamic>.from(metadataRaw);

    if (metadata['suspeito'] == true ||
        metadata['tem_conteudo_suspeito'] == true) {
      return true;
    }

    final campos = metadata['campos_suspeitos'];
    return campos is List && campos.isNotEmpty;
  }

  String _descricaoEvento(Map<String, dynamic> evento) {
    final tipo = evento['tipo']?.toString() ?? 'evento';
    final metadataRaw = evento['metadata'];
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : <String, dynamic>{};

    switch (tipo) {
      case 'etapa_formulario':
        return '${metadata['acao'] ?? 'etapa'} • ${metadata['formulario'] ?? ''}';
      case 'erro_formulario':
        final erros = metadata['erros'];
        if (erros is List && erros.isNotEmpty) return erros.take(2).join(' | ');
        return 'Erro de formulário';
      case 'campo_formulario':
        final valor = metadata['valor']?.toString() ?? '';
        return valor.isEmpty ? 'Campo vazio' : 'Digitou: $valor';
      case 'snapshot_formulario':
        final suspeitos = metadata['campos_suspeitos'];
        if (suspeitos is List && suspeitos.isNotEmpty) {
          return '⚠ Atenção: campos suspeitos — ${suspeitos.join(', ')}';
        }
        return 'Snapshot de ${metadata['total_campos'] ?? 0} campos';
      case 'conversao':
        return 'Conversão registrada';
      case 'funil_inscricao':
        final etapa = metadata['etapa_nome']?.toString();
        final acao = metadata['acao']?.toString() ?? evento['origem']?.toString() ?? '';
        return [acao, if (etapa != null && etapa.isNotEmpty) etapa]
            .where((e) => e.trim().isNotEmpty)
            .join(' • ');
      case 'rolagem':
        return 'Rolagem até ${metadata['percentual'] ?? evento['nome']}';
      case 'filtro':
        return 'Filtro ${metadata['filtro'] ?? evento['nome']}: ${metadata['valor'] ?? ''}';
      case 'item_visualizado':
        return '${metadata['item_tipo'] ?? 'item'} visualizado';
      case 'tela':
        return '${metadata['acao'] ?? ''}${metadata['duracao_segundos'] != null ? ' • ${_formatarDuracao((metadata['duracao_segundos'] as num).round())}' : ''}';
      default:
        return '${evento['tipo'] ?? ''} • Origem: ${evento['origem'] ?? 'N/A'}';
    }
  }

  bool _eventoTecnicoRuido(Map<String, dynamic> evento) {
    final tipo = evento['tipo']?.toString() ?? '';
    final metadata = _metadataEvento(evento);

    if (tipo == 'campo_formulario') return !_eventoEhSuspeito(evento);
    if (tipo == 'snapshot_formulario') return !_eventoEhSuspeito(evento);

    if (tipo == 'formulario') {
      final acao = metadata['acao']?.toString() ?? evento['origem']?.toString() ?? '';
      const importantes = {
        'abandonou_inscricao',
        'tentou_enviar_inscricao',
        'cancelou_saida_inscricao',
      };
      return !importantes.contains(acao);
    }

    return false;
  }

  List<Map<String, dynamic>> _eventosTimelinePrincipal(
    List<Map<String, dynamic>> eventos,
  ) {
    return eventos.where((e) => !_eventoTecnicoRuido(e)).toList(growable: false);
  }

  bool _eventoEhInscricao(Map<String, dynamic> evento) {
    final tipo = evento['tipo']?.toString() ?? '';
    final nome = evento['nome']?.toString() ?? '';
    final pagina = evento['pagina_origem']?.toString() ?? '';
    final metadata = _metadataEvento(evento);
    return tipo == 'funil_inscricao' ||
        nome.contains('inscricao_publica') ||
        pagina.contains('inscricao_publica') ||
        metadata['formulario']?.toString() == 'inscricao_publica';
  }

  bool _sessaoVisualizouInscricao(List<Map<String, dynamic>> eventos) {
    return eventos.any((e) {
      final tipo = e['tipo']?.toString();
      final nome = e['nome']?.toString();
      return (tipo == 'pagina' || tipo == 'tela') && nome == 'inscricao_publica' ||
          e['tipo']?.toString() == 'funil_inscricao';
    });
  }

  bool _sessaoTemMarco(
    List<Map<String, dynamic>> eventos,
    String marco, {
    String? fallbackTipo,
    String? fallbackNome,
  }) {
    if (eventos.any((e) =>
        e['tipo']?.toString() == 'funil_inscricao' &&
        e['nome']?.toString() == marco)) {
      return true;
    }
    if (fallbackTipo != null) {
      return eventos.any((e) =>
          e['tipo']?.toString() == fallbackTipo &&
          (fallbackNome == null || e['nome']?.toString() == fallbackNome));
    }
    return false;
  }

  Map<String, dynamic> _metricasFunilInscricao() {
    if (_cacheExiste) {
      final funil = _mapDinamico(_cachePeriodoAtual['funil_inscricao']);
      return {
        'visualizou': (funil['visualizou'] as num?)?.round() ?? 0,
        'iniciou': (funil['iniciou'] as num?)?.round() ?? 0,
        'revisao': (funil['revisao'] as num?)?.round() ?? 0,
        'envio': (funil['envio'] as num?)?.round() ?? 0,
        'concluiu': (funil['concluiu'] as num?)?.round() ?? 0,
        'abandonou': (funil['abandonou'] as num?)?.round() ?? 0,
        'erros': (funil['erros'] as num?)?.round() ?? 0,
        'conversao': (funil['conversao'] as num?)?.toDouble() ?? 0.0,
        'media_tempo': (funil['media_tempo'] as num?)?.round() ?? 0,
        'etapas': _mapStringInt(funil['etapas']),
        'maior_abandono': funil['maior_abandono'],
        'maior_abandono_qtd':
            (funil['maior_abandono_qtd'] as num?)?.round() ?? 0,
      };
    }

    var visualizou = 0;
    var iniciou = 0;
    var revisao = 0;
    var envio = 0;
    var concluiu = 0;
    var abandonou = 0;
    var erros = 0;
    var somaTempo = 0;
    var tempos = 0;
    final etapas = <String, int>{};
    final abandonosEtapa = <String, int>{};

    for (final acesso in _getAcessosFiltrados()) {
      final eventos = _eventosDoDocumento(acesso);
      if (!_sessaoVisualizouInscricao(eventos)) continue;
      visualizou++;

      final temInicio = _sessaoTemMarco(eventos, 'inicio_formulario') ||
          eventos.any((e) => e['tipo']?.toString() == 'etapa_formulario');
      if (temInicio) iniciou++;

      final etapasSessao = <String>{};
      for (final evento in eventos) {
        final metadata = _metadataEvento(evento);
        if (evento['tipo']?.toString() == 'etapa_formulario' &&
            metadata['acao']?.toString() == 'entrou') {
          final etapa = metadata['nome_etapa']?.toString() ?? evento['nome']?.toString();
          if (etapa != null && etapa.isNotEmpty) etapasSessao.add(etapa);
        }
        if (evento['tipo']?.toString() == 'funil_inscricao' &&
            evento['nome']?.toString() == 'etapa_visualizada') {
          final etapa = metadata['etapa_nome']?.toString();
          if (etapa != null && etapa.isNotEmpty) etapasSessao.add(etapa);
        }
      }
      for (final etapa in etapasSessao) {
        etapas[etapa] = (etapas[etapa] ?? 0) + 1;
      }

      if (etapasSessao.contains('revisao')) revisao++;

      final temEnvio = _sessaoTemMarco(eventos, 'envio_iniciado') ||
          eventos.any((e) {
            if (e['tipo']?.toString() != 'formulario') return false;
            final m = _metadataEvento(e);
            return m['acao']?.toString() == 'tentou_enviar_inscricao';
          });
      if (temEnvio) envio++;

      final temConclusao = _sessaoTemMarco(
            eventos,
            'concluiu_inscricao',
            fallbackTipo: 'conversao',
            fallbackNome: 'inscricao_publica_enviada',
          );
      if (temConclusao) {
        concluiu++;
        for (final e in eventos.reversed) {
          if (e['tipo']?.toString() == 'conversao' &&
              e['nome']?.toString() == 'inscricao_publica_enviada') {
            final m = _metadataEvento(e);
            final t = m['tempo_total_inscricao_segundos'];
            if (t is num) {
              somaTempo += t.round();
              tempos++;
            }
            break;
          }
        }
      }

      final abandono = eventos.cast<Map<String, dynamic>?>().firstWhere(
        (e) {
          if (e == null) return false;
          if (e['tipo']?.toString() == 'funil_inscricao' &&
              e['nome']?.toString() == 'abandono') {
            return true;
          }
          if (e['tipo']?.toString() == 'formulario') {
            return _metadataEvento(e)['acao']?.toString() == 'abandonou_inscricao';
          }
          return false;
        },
        orElse: () => null,
      );
      if (abandono != null && !temConclusao) {
        abandonou++;
        final m = _metadataEvento(abandono);
        final etapa = (m['etapa_nome'] ?? m['nome_etapa_atual'])?.toString();
        if (etapa != null && etapa.isNotEmpty) {
          abandonosEtapa[etapa] = (abandonosEtapa[etapa] ?? 0) + 1;
        }
      }

      erros += eventos.where((e) => e['tipo']?.toString() == 'erro_formulario').length;
    }

    final conversao = visualizou == 0 ? 0.0 : (concluiu / visualizou) * 100;
    final mediaTempo = tempos == 0 ? 0 : (somaTempo / tempos).round();
    String? maiorAbandono;
    var maiorAbandonoQtd = 0;
    for (final entry in abandonosEtapa.entries) {
      if (entry.value > maiorAbandonoQtd) {
        maiorAbandono = entry.key;
        maiorAbandonoQtd = entry.value;
      }
    }

    return {
      'visualizou': visualizou,
      'iniciou': iniciou,
      'revisao': revisao,
      'envio': envio,
      'concluiu': concluiu,
      'abandonou': abandonou,
      'erros': erros,
      'conversao': conversao,
      'media_tempo': mediaTempo,
      'etapas': etapas,
      'maior_abandono': maiorAbandono,
      'maior_abandono_qtd': maiorAbandonoQtd,
    };
  }

  Map<String, Map<String, num>> _metricasPaginas() {
    if (_cacheExiste) {
      final raw = _cachePeriodoAtual['paginas'];
      if (raw is Map) {
        final out = <String, Map<String, num>>{};
        raw.forEach((key, value) {
          final item = _mapDinamico(value);
          out[key.toString()] = <String, num>{
            'sessoes': (item['sessoes'] as num?) ?? 0,
            'duracao': (item['duracao'] as num?) ?? 0,
          };
        });
        return out;
      }
    }

    final resultado = <String, Map<String, num>>{};

    for (final acesso in _getAcessosFiltrados()) {
      final eventos = _eventosDoDocumento(acesso);
      final paginasSessao = <String>{};
      final duracoes = <String, int>{};

      for (final evento in eventos) {
        final tipo = evento['tipo']?.toString();
        final nome = evento['nome']?.toString().trim() ?? '';
        if (nome.isEmpty) continue;

        if (tipo == 'pagina') paginasSessao.add(nome);
        if (tipo == 'tela') {
          final m = _metadataEvento(evento);
          if (m['acao']?.toString() == 'entrou') paginasSessao.add(nome);
          final d = m['duracao_segundos'];
          if (d is num && d > 0) {
            duracoes[nome] = (duracoes[nome] ?? 0) + d.round();
          }
        }
      }

      for (final pagina in paginasSessao) {
        final atual = resultado.putIfAbsent(
          pagina,
          () => <String, num>{'sessoes': 0, 'duracao': 0},
        );
        atual['sessoes'] = (atual['sessoes'] ?? 0) + 1;
        atual['duracao'] = (atual['duracao'] ?? 0) + (duracoes[pagina] ?? 0);
      }
    }
    return resultado;
  }

  void _mostrarRastroDocumento(Map<String, dynamic> documento) {
    final eventosMap = _eventosDoDocumento(documento);

    final totalEventos = eventosMap.length;
    final resumoTipos = _resumoTiposEvento(eventosMap);
    final camposSuspeitos = _contarCamposSuspeitos(eventosMap);

    final latitude = _toDouble(documento['latitude']);
    final longitude = _toDouble(documento['longitude']);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        backgroundColor: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = MediaQuery.of(context).size.width;
            final compact = width < 520;

            return Container(
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              decoration: BoxDecoration(
                color: context.uai.surface,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(46),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildRastroHeader(documento, compact),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(compact ? 12 : 16),
                      children: [
                        _buildResumoEventos(
                          totalEventos: totalEventos,
                          resumoTipos: resumoTipos,
                          camposSuspeitos: camposSuspeitos,
                          compact: compact,
                        ),
                        const SizedBox(height: 10),
                        _buildInteligenciaFluxo(eventosMap, compact),
                        if (_eventoLoginAreaAluno(eventosMap) != null) ...[
                          const SizedBox(height: 10),
                          _buildAreaAlunoRastroCard(
                            _eventoLoginAreaAluno(eventosMap)!,
                          ),
                        ],
                        if (latitude != null && longitude != null) ...[
                          const SizedBox(height: 10),
                          _buildMapaCard(latitude, longitude),
                        ],
                        const SizedBox(height: 10),
                        _buildDispositivoCard(documento),
                        const SizedBox(height: 14),
                        _buildTimeline(_eventosTimelinePrincipal(eventosMap), compact),
                        const SizedBox(height: 14),
                        _buildInfoAcesso(documento, latitude, longitude),
                      ],
                    ),
                  ),
                  _buildRastroBottomBar(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _eventosDoDocumento(
    Map<String, dynamic> documento,
  ) {
    final eventosRaw = documento['eventos'];
    if (eventosRaw is! List) return <Map<String, dynamic>>[];

    return eventosRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic>? _eventoLoginAreaAluno(
    List<Map<String, dynamic>> eventos,
  ) {
    for (final evento in eventos.reversed) {
      final tipo = evento['tipo']?.toString();
      final nome = evento['nome']?.toString();
      if ((tipo == 'area_aluno' && nome == 'login_aluno_sucesso') ||
          (tipo == 'conversao' && nome == 'area_aluno_login_sucesso')) {
        return evento;
      }
    }
    return null;
  }

  Map<String, dynamic> _metadataEvento(Map<String, dynamic>? evento) {
    if (evento == null) return <String, dynamic>{};
    return _mapFromDynamic(evento['metadata']);
  }

  String _textoValor(dynamic value, [String fallback = 'N/A']) {
    final texto = value?.toString().trim() ?? '';
    if (texto.isEmpty || texto == 'null') return fallback;
    return texto;
  }

  String _capitalizar(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _textoDispositivo(Map<String, dynamic> documento) {
    final dispositivo = _mapFromDynamic(documento['dispositivo']);
    return _textoDispositivoMapa(dispositivo);
  }

  String _textoDispositivoMapa(Map<String, dynamic> dispositivo) {
    final tipo = dispositivo['tipo_dispositivo']?.toString().trim();
    final plataforma =
        dispositivo['tipo_plataforma']?.toString().trim() ??
        dispositivo['plataforma_flutter']?.toString().trim();
    final sistema = dispositivo['sistema_operacional_aproximado']
        ?.toString()
        .trim();
    final marca = dispositivo['celular_marca_aproximada']?.toString().trim();
    final modelo = dispositivo['celular_modelo_aproximado']?.toString().trim();

    if ((tipo == null || tipo.isEmpty) &&
        (plataforma == null || plataforma.isEmpty)) {
      return 'Dispositivo não informado';
    }

    final partes = <String>[
      if (tipo != null &&
          tipo.isNotEmpty &&
          sistema != null &&
          sistema.isNotEmpty)
        '${_capitalizar(tipo)} $sistema'
      else ...[
        if (tipo != null && tipo.isNotEmpty) _capitalizar(tipo),
        if (plataforma != null && plataforma.isNotEmpty) plataforma,
      ],
      if (marca != null &&
          marca.isNotEmpty &&
          marca != 'desconhecido' &&
          marca != 'nao_aplicavel')
        [
          marca,
          if (modelo != null &&
              modelo.isNotEmpty &&
              modelo != 'nao_disponivel_pelo_navegador')
            modelo,
        ].join(' '),
    ];

    return partes.join(' / ');
  }

  String _tamanhoTelaDispositivo(Map<String, dynamic> documento) {
    final dispositivo = _mapFromDynamic(documento['dispositivo']);

    final largura = dispositivo['largura_tela'];
    final altura = dispositivo['altura_tela'];

    if (largura == null || altura == null) return 'Tela não informada';

    final orientacao = dispositivo['orientacao']?.toString();
    final sufixo = orientacao == null || orientacao.isEmpty
        ? ''
        : ' / $orientacao';

    return '${largura}x$altura$sufixo';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 520;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text(
          'Dashboard de Visitas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: compact,
        elevation: 0,
        actions: [
          IconButton(
            icon: _reconstruindoCache
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Reconstruir cache das estatísticas',
            onPressed: _reconstruindoCache ? null : _atualizarTudo,
          ),
        ],
      ),
      body: _carregandoInicial
          ? _buildLoadingInicial()
          : RefreshIndicator(
              color: context.uai.primary,
              onRefresh: _atualizarTudo,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 20,
                        compact ? 12 : 18,
                        compact ? 12 : 20,
                        24,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeroDashboard(compact),
                              const SizedBox(height: 12),
                              _buildDashboardTabs(),
                              const SizedBox(height: 10),
                              _buildCacheStatus(compact),
                              const SizedBox(height: 14),
                              if (_abaDashboard == 0) ...[
                                _buildCardsRapidos(),
                                const SizedBox(height: 14),
                                _buildGraficosSection(compact),
                                const SizedBox(height: 14),
                                _buildTopCidadesEstados(),
                              ] else if (_abaDashboard == 1) ...[
                                _buildPaginasV2(),
                              ] else if (_abaDashboard == 2) ...[
                                _buildInscricoesV2(),
                              ] else ...[
                                _buildFiltroPeriodo(),
                                const SizedBox(height: 10),
                                if (_carregandoSessoes &&
                                    _acessosCarregados.isEmpty)
                                  _buildLoadingSessoes()
                                else
                                  _buildListaAcessos(),
                                if (_carregandoMais) _buildLoadingIndicator(),
                                if (!_temMaisDados && _acessosCarregados.isNotEmpty)
                                  _buildFimLista(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCacheStatus(bool compact) {
    final cor = _cacheExiste ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _cardDecoration(
        radius: 16,
        borderColor: _softBorder(cor),
      ),
      child: Row(
        children: [
          Icon(
            _cacheExiste ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
            size: 18,
            color: _softOnCard(cor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _cacheExiste
                  ? '${_textoAtualizacaoCache()} • painel servido pelo cache'
                  : 'Cache ainda não gerado • puxe para baixo para construir',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: compact ? 10.8 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_reconstruindoCache) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingSessoes() {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        children: [
          CircularProgressIndicator(color: context.uai.primary),
          const SizedBox(height: 10),
          Text(
            'Carregando as 30 sessões mais recentes...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.uai.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingInicial() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(radius: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            const SizedBox(height: 14),
            Text(
              'Carregando estatísticas...',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTabs() {
    final itens = const [
      (Icons.dashboard_rounded, 'Visão geral'),
      (Icons.web_rounded, 'Páginas'),
      (Icons.how_to_reg_rounded, 'Inscrições'),
      (Icons.history_rounded, 'Sessões'),
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: _cardDecoration(radius: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 720;
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(itens.length, (index) {
              final selecionado = _abaDashboard == index;
              final item = itens[index];
              return SizedBox(
                width: compacto ? (constraints.maxWidth - 6) / 2 : null,
                child: Material(
                  color: selecionado
                      ? _softFill(context.uai.primary)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    onTap: () {
                      setState(() => _abaDashboard = index);
                      if (index == 3) {
                        unawaited(_garantirSessoesCarregadas());
                      }
                    },
                    borderRadius: BorderRadius.circular(15),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      child: Row(
                        mainAxisSize: compacto ? MainAxisSize.max : MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.$1,
                            size: 18,
                            color: selecionado
                                ? _softOnCard(context.uai.primary)
                                : context.uai.textSecondary,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              item.$2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selecionado
                                    ? _softOnCard(context.uai.primary)
                                    : context.uai.textSecondary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildMetricV2({
    required String titulo,
    required String valor,
    required IconData icone,
    required Color cor,
    String? subtitulo,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 20, borderColor: _softBorder(cor)),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _softFill(cor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icone, color: _softOnCard(cor), size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 20,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  titulo,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.uai.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        final colunas = largura >= 980 ? 4 : largura >= 620 ? 2 : 1;
        final larguraCard = (largura - ((colunas - 1) * 10)) / colunas;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((card) => SizedBox(width: larguraCard, child: card))
              .toList(),
        );
      },
    );
  }

  Widget _buildPaginasV2() {
    final metricas = _metricasPaginas();
    final entries = metricas.entries.toList()
      ..sort((a, b) => (b.value['sessoes'] ?? 0).compareTo(a.value['sessoes'] ?? 0));

    if (entries.isEmpty) {
      return _buildEmptyV2(
        Icons.web_asset_off_rounded,
        'Ainda não há navegação de páginas suficiente neste período.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFiltroPeriodo(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: _cardDecoration(radius: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                icon: Icons.web_stories_rounded,
                title: 'Páginas do site',
                color: Colors.purple,
                trailing: '${entries.length} páginas',
              ),
              const SizedBox(height: 12),
              ...entries.map((entry) {
                final sessoes = (entry.value['sessoes'] ?? 0).round();
                final duracao = (entry.value['duracao'] ?? 0).round();
                final media = sessoes == 0 ? 0 : duracao ~/ sessoes;
                final max = (entries.first.value['sessoes'] ?? 1).toDouble();
                final progresso = max <= 0 ? 0.0 : (sessoes / max).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _capitalizar(entry.key.replaceAll('_', ' ')),
                              style: TextStyle(
                                color: context.uai.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            '$sessoes sessões',
                            style: TextStyle(
                              color: context.uai.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (media > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '• ${_formatarDuracao(media)} méd.',
                              style: TextStyle(
                                color: context.uai.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progresso,
                          minHeight: 7,
                          backgroundColor: context.uai.border.withAlpha(89),
                          color: _softOnCard(Colors.purple),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInscricoesV2() {
    final f = _metricasFunilInscricao();
    final visualizou = f['visualizou'] as int;
    final iniciou = f['iniciou'] as int;
    final revisao = f['revisao'] as int;
    final envio = f['envio'] as int;
    final concluiu = f['concluiu'] as int;
    final abandonou = f['abandonou'] as int;
    final erros = f['erros'] as int;
    final conversao = f['conversao'] as double;
    final mediaTempo = f['media_tempo'] as int;
    final etapas = Map<String, int>.from(f['etapas'] as Map);
    final maiorAbandono = f['maior_abandono']?.toString();
    final maiorAbandonoQtd = f['maior_abandono_qtd'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFiltroPeriodo(),
        const SizedBox(height: 12),
        _buildMetricGrid([
          _buildMetricV2(
            titulo: 'Visualizaram inscrição',
            valor: '$visualizou',
            icone: Icons.visibility_rounded,
            cor: Colors.blue,
          ),
          _buildMetricV2(
            titulo: 'Concluíram',
            valor: '$concluiu',
            icone: Icons.verified_rounded,
            cor: Colors.green,
          ),
          _buildMetricV2(
            titulo: 'Conversão',
            valor: '${conversao.toStringAsFixed(1)}%',
            icone: Icons.trending_up_rounded,
            cor: Colors.teal,
          ),
          _buildMetricV2(
            titulo: 'Tempo médio',
            valor: _formatarDuracao(mediaTempo),
            icone: Icons.timer_rounded,
            cor: Colors.orange,
            subtitulo: 'das inscrições concluídas',
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: _cardDecoration(radius: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                icon: Icons.filter_alt_rounded,
                title: 'Funil da aula experimental',
                color: Colors.teal,
                trailing: '$visualizou sessões',
              ),
              const SizedBox(height: 14),
              _buildFunnelLine('Visualizou', visualizou, visualizou, Colors.blue),
              _buildFunnelLine('Iniciou', iniciou, visualizou, Colors.indigo),
              _buildFunnelLine('Chegou à revisão', revisao, visualizou, Colors.purple),
              _buildFunnelLine('Tentou enviar', envio, visualizou, Colors.orange),
              _buildFunnelLine('Concluiu', concluiu, visualizou, Colors.green),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildMetricGrid([
          _buildMetricV2(
            titulo: 'Abandonos',
            valor: '$abandonou',
            icone: Icons.exit_to_app_rounded,
            cor: Colors.deepOrange,
            subtitulo: maiorAbandono == null
                ? 'sem etapa dominante'
                : 'mais comum: ${maiorAbandono.replaceAll('_', ' ')} ($maiorAbandonoQtd)',
          ),
          _buildMetricV2(
            titulo: 'Erros de formulário',
            valor: '$erros',
            icone: Icons.warning_amber_rounded,
            cor: Colors.red,
          ),
        ]),
        if (etapas.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: _cardDecoration(radius: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  icon: Icons.stairs_rounded,
                  title: 'Alcance por etapa',
                  color: Colors.purple,
                ),
                const SizedBox(height: 12),
                ..._ordemEtapasInscricao.map((etapa) {
                  final valor = etapas[etapa] ?? 0;
                  return _buildFunnelLine(
                    _tituloEtapa(etapa),
                    valor,
                    visualizou,
                    Colors.purple,
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static const List<String> _ordemEtapasInscricao = [
    'boas_vindas',
    'foto_aluno',
    'dados_aluno',
    'acesso_email',
    'contatos',
    'endereco',
    'documento',
    'revisao',
  ];

  String _tituloEtapa(String etapa) {
    const titulos = {
      'boas_vindas': 'Boas-vindas',
      'foto_aluno': 'Foto do aluno',
      'dados_aluno': 'Dados do aluno',
      'acesso_email': 'Acesso/e-mail',
      'contatos': 'Contatos',
      'endereco': 'Endereço',
      'documento': 'Documento',
      'revisao': 'Revisão',
    };
    return titulos[etapa] ?? _capitalizar(etapa.replaceAll('_', ' '));
  }

  Widget _buildFunnelLine(
    String titulo,
    int valor,
    int total,
    Color cor,
  ) {
    final progresso = total <= 0 ? 0.0 : (valor / total).clamp(0.0, 1.0);
    final percentual = total <= 0 ? 0.0 : (valor / total) * 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                '$valor • ${percentual.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: context.uai.textSecondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 8,
              backgroundColor: context.uai.border.withAlpha(89),
              color: _softOnCard(cor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyV2(IconData icon, String texto) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: context.uai.textMuted),
          const SizedBox(height: 10),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.uai.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroDashboard(bool compact) {
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.uai.primaryGradient.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withAlpha(36),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 650;

          final icon = Container(
            width: compact ? 58 : 68,
            height: compact ? 58 : 68,
            decoration: BoxDecoration(
              color: _onPrimary().withAlpha(36),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _onPrimary().withAlpha(41)),
            ),
            child: Icon(
              Icons.query_stats_rounded,
              color: _onPrimary(),
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                'Estatísticas do Site',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: _onPrimary(),
                  fontSize: compact ? 25 : 34,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Acompanhe acessos, localização, cliques e comportamento dos visitantes.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: _onPrimary().withAlpha(209),
                  fontSize: compact ? 12.8 : 15,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildWhiteChip(
                    Icons.people_alt_rounded,
                    '$_totalAcessos visitas',
                  ),
                  _buildWhiteChip(
                    Icons.cloud_done_rounded,
                    _cacheExiste ? _textoAtualizacaoCache() : 'cache pendente',
                  ),
                  _buildWhiteChip(Icons.location_on_rounded, 'Mapa integrado'),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(children: [icon, const SizedBox(height: 12), text]);
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _onPrimary().withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _onPrimary().withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _onPrimary(), size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: _onPrimary(),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardsRapidos() {
    final cards = [
      _MetricCard('Total', _totalAcessos.toString(), Icons.people, Colors.red),
      _MetricCard('Hoje', _visitasHoje.toString(), Icons.today, Colors.orange),
      _MetricCard(
        'Semana',
        _visitasSemana.toString(),
        Icons.calendar_view_week,
        Colors.green,
      ),
      _MetricCard(
        'Mês',
        _visitasMes.toString(),
        Icons.calendar_month,
        Colors.blue,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 700 ? 2 : 4;
        const spacing = 10.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: itemWidth,
              child: _buildCardRapidoItem(card),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCardRapidoItem(_MetricCard card) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(13),
      decoration: _cardDecoration(
        radius: 22,
        borderColor: card.color.withAlpha(26),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: card.color.withAlpha(23),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(card.icon, color: card.color, size: 21),
          ),
          const SizedBox(height: 18),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.uai.textPrimary,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.title,
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraficosSection(bool compact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        final hora = _buildGraficoHoras(compact);
        final dia = _buildGraficoDiasSemana(compact);

        if (hora is SizedBox && dia is SizedBox) return const SizedBox.shrink();

        if (!wide) {
          return Column(
            children: [
              hora,
              if (hora is! SizedBox && dia is! SizedBox)
                const SizedBox(height: 14),
              dia,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: hora),
            const SizedBox(width: 14),
            Expanded(child: dia),
          ],
        );
      },
    );
  }

  Widget _buildGraficoHoras(bool compact) {
    if (_acessosPorHora.isEmpty) return const SizedBox.shrink();

    final horasOrdenadas = _acessosPorHora.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxY =
        horasOrdenadas
            .map((e) => e.value)
            .reduce((a, b) => a > b ? a : b)
            .toDouble() +
        1;
    final intervaloY = maxY <= 5 ? 1.0 : (maxY / 5).ceilToDouble();

    return _chartCard(
      title: 'Acessos por hora',
      icon: Icons.schedule_rounded,
      color: Colors.purple,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final hora = horasOrdenadas[group.x].key;
                final valor = horasOrdenadas[group.x].value;
                return BarTooltipItem(
                  '$hora\n$valor acesso${valor != 1 ? 's' : ''}',
                  const TextStyle(color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < horasOrdenadas.length) {
                    if (compact && index % 3 != 0) return const SizedBox.shrink();
                    final label = horasOrdenadas[index].key;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        compact ? label.substring(0, 2) : label,
                        style: TextStyle(fontSize: compact ? 8 : 9),
                      ),
                    );
                  }

                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: intervaloY,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  if (value % 1 == 0) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    );
                  }

                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: intervaloY,
          ),
          borderData: FlBorderData(show: false),
          barGroups: horasOrdenadas.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.value.toDouble(),
                  color: Colors.purple.shade300,
                  width: compact ? 8 : 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGraficoDiasSemana(bool compact) {
    if (_acessosPorDia.isEmpty) return const SizedBox.shrink();

    final diasOrdem = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];
    final dadosOrdenados = diasOrdem
        .map((dia) => MapEntry(dia, _acessosPorDia[dia] ?? 0))
        .toList();
    final maxY =
        dadosOrdenados
            .map((e) => e.value)
            .reduce((a, b) => a > b ? a : b)
            .toDouble() +
        1;
    final intervaloY = maxY <= 5 ? 1.0 : (maxY / 5).ceilToDouble();

    return _chartCard(
      title: 'Acessos por dia',
      icon: Icons.calendar_today_rounded,
      color: Colors.teal,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final dia = dadosOrdenados[group.x].key;
                final valor = dadosOrdenados[group.x].value;
                return BarTooltipItem(
                  '$dia\n$valor acesso${valor != 1 ? 's' : ''}',
                  const TextStyle(color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < dadosOrdenados.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dadosOrdenados[index].key,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }

                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: intervaloY,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  if (value % 1 == 0) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    );
                  }

                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: intervaloY,
          ),
          borderData: FlBorderData(show: false),
          barGroups: dadosOrdenados.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.value.toDouble(),
                  color: Colors.teal.shade300,
                  width: compact ? 12 : 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required IconData icon,
    required MaterialColor color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: icon, title: title, color: color),
          const SizedBox(height: 16),
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 520 ? 210 : 176,
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildTopCidadesEstados() {
    Map<String, dynamic> paises = {};

    if (_dadosAgregados['paises'] != null) {
      paises = Map<String, dynamic>.from(_dadosAgregados['paises'] as Map);
    }

    final cidades = <String, int>{};
    final estados = <String, int>{};

    for (final pais in paises.values) {
      final paisMap = pais is Map
          ? Map<String, dynamic>.from(pais)
          : <String, dynamic>{};
      final estadosDoPaisRaw = paisMap['estados'];

      if (estadosDoPaisRaw is! Map) continue;

      final estadosDoPais = Map<String, dynamic>.from(estadosDoPaisRaw);

      for (final estadoEntry in estadosDoPais.entries) {
        final estadoNome = estadoEntry.key;
        final estadoData = estadoEntry.value is Map
            ? Map<String, dynamic>.from(estadoEntry.value as Map)
            : <String, dynamic>{};

        estados[estadoNome] = (estadoData['total'] ?? 0) as int;

        final cidadesDoEstadoRaw = estadoData['cidades'];
        if (cidadesDoEstadoRaw is! Map) continue;

        final cidadesDoEstado = Map<String, dynamic>.from(cidadesDoEstadoRaw);

        for (final cidadeEntry in cidadesDoEstado.entries) {
          final cidadeData = cidadeEntry.value is Map
              ? Map<String, dynamic>.from(cidadeEntry.value as Map)
              : <String, dynamic>{};

          cidades[cidadeEntry.key] = (cidadeData['total'] ?? 0) as int;
        }
      }
    }

    final topCidades = cidades.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEstados = estados.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.emoji_events_rounded,
            title: 'Top locais',
            color: Colors.orange,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;

              if (!wide) {
                return Column(
                  children: [
                    _buildSecaoTop(
                      'Cidades',
                      Icons.location_city,
                      Colors.orange,
                      topCidades.take(5).toList(),
                    ),
                    const SizedBox(height: 14),
                    _buildSecaoTop(
                      'Estados',
                      Icons.map_rounded,
                      Colors.blue,
                      topEstados.take(5).toList(),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildSecaoTop(
                      'Cidades',
                      Icons.location_city,
                      Colors.orange,
                      topCidades.take(5).toList(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildSecaoTop(
                      'Estados',
                      Icons.map_rounded,
                      Colors.blue,
                      topEstados.take(5).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoTop(
    String titulo,
    IconData icone,
    MaterialColor cor,
    List<MapEntry<String, int>> items,
  ) {
    final t = context.uai;
    final accent = _ensureVisible(cor, t.card);

    if (items.isEmpty) {
      return _emptyMiniCard('Nenhum dado de $titulo ainda');
    }

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(20), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withAlpha(46)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withAlpha(36), t.card),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: accent.withAlpha(41)),
                ),
                child: Icon(icone, size: 17, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12.2,
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(accent.withAlpha(31), t.card),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: accent.withAlpha(46)),
                    ),
                    child: Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroPeriodo() {
    final filtros = [
      ('Todos', 'todos'),
      ('Hoje', 'hoje'),
      ('Semana', 'semana'),
      ('Mês', 'mes'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(radius: 20),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, color: context.uai.primary),
          const SizedBox(width: 8),
          Text(
            'Filtrar',
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filtros.map((filtro) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _buildChipFiltro(filtro.$1, filtro.$2),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipFiltro(String label, String valor) {
    final selecionado = _filtroPeriodo == valor;

    return ChoiceChip(
      label: Text(label),
      selected: selecionado,
      onSelected: (_) {
        setState(() => _filtroPeriodo = valor);
        _aplicarPeriodoCacheSelecionado();
      },
      backgroundColor: context.uai.background,
      selectedColor: context.uai.primary,
      labelStyle: TextStyle(
        color: selecionado ? _onPrimary() : context.uai.textPrimary,
        fontWeight: selecionado ? FontWeight.w900 : FontWeight.w700,
        fontSize: 12,
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: selecionado ? context.uai.primary : context.uai.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    );
  }

  Widget _buildListaAcessos() {
    final acessosFiltrados = _getAcessosFiltrados();

    if (acessosFiltrados.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: _cardDecoration(radius: 24),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 54,
                color: context.uai.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                'Nenhum acesso neste período',
                style: TextStyle(
                  color: context.uai.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.history_rounded,
            title: 'Acessos recentes',
            color: Colors.green,
            trailing: '${acessosFiltrados.length} de $_totalAcessos',
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: acessosFiltrados.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: context.uai.cardAlt),
            itemBuilder: (context, index) =>
                _buildAcessoItem(acessosFiltrados[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildAcessoItem(Map<String, dynamic> acesso) {
    final timestamp = acesso['data_acesso'];
    final dataAcesso = timestamp is Timestamp
        ? timestamp.toDate()
        : DateTime.now();

    final dataFormatada =
        '${dataAcesso.day.toString().padLeft(2, '0')}/${dataAcesso.month.toString().padLeft(2, '0')}';
    final horaFormatada =
        '${dataAcesso.hour.toString().padLeft(2, '0')}:${dataAcesso.minute.toString().padLeft(2, '0')}';

    final ip = acesso['ip']?.toString() ?? 'N/A';
    final ipCurto = ip.contains('.')
        ? ip.substring(0, ip.lastIndexOf('.'))
        : ip;

    final eventosLista = _eventosDoDocumento(acesso);
    final temEventos = eventosLista.isNotEmpty;
    final temConversao = eventosLista.any((e) => e['tipo'] == 'conversao');
    final temErro = eventosLista.any((e) => e['tipo'] == 'erro_formulario');
    final suspeitos = _contarCamposSuspeitos(eventosLista);
    final eventoLogin = _eventoLoginAreaAluno(eventosLista);
    final metadataLogin = _metadataEvento(eventoLogin);
    final alunoLogin = _textoValor(metadataLogin['aluno_nome'], '');
    final possivelTrocaAluno = metadataLogin['possivel_troca_aluno'] == true;

    final cidade = acesso['cidade']?.toString().trim();
    final estado = acesso['estado']?.toString().trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _mostrarRastroDocumento(acesso),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.person_pin_circle_rounded,
                  color: _readableOn(Colors.green),
                  size: 23,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cidade?.isNotEmpty == true ? cidade : 'Desconhecida'}'
                      '${estado?.isNotEmpty == true ? ', $estado' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: context.uai.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$dataFormatada às $horaFormatada',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.uai.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _textoDispositivo(acesso),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.uai.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (alunoLogin.isNotEmpty || possivelTrocaAluno) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (alunoLogin.isNotEmpty)
                            _buildInfoChip('Aluno', alunoLogin),
                          if (possivelTrocaAluno)
                            _buildAlertaAcessoChip(
                              'Mesmo aparelho em outro aluno',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _softFill(temEventos ? Colors.blue : Colors.green),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: _softBorder(temEventos ? Colors.blue : Colors.green),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: temEventos
                      ? [
                          Icon(
                            Icons.timeline_rounded,
                            size: 13,
                            color: _softOnCard(Colors.blue),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            suspeitos > 0
                                ? 'Suspeito'
                                : temConversao
                                ? 'Conversão'
                                : temErro
                                ? 'Erro'
                                : '${eventosLista.length} eventos',
                            style: TextStyle(
                              fontSize: 10,
                              color: _softOnCard(Colors.blue),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ]
                      : [
                          Text(
                            ipCurto,
                            style: TextStyle(
                              fontSize: 10,
                              color: _softOnCard(Colors.green),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: context.uai.primary),
            const SizedBox(height: 8),
            Text(
              'Carregando mais acessos...',
              style: TextStyle(color: context.uai.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFimLista() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_rounded, color: _softOnCard(Colors.green)),
            const SizedBox(height: 8),
            Text(
              'Todos os $_totalAcessos acessos carregados',
              style: TextStyle(fontSize: 12, color: context.uai.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRastroHeader(Map<String, dynamic> documento, bool compact) {
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade900, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _onPrimary().withAlpha(36),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _onPrimary().withAlpha(41)),
            ),
            child: Icon(
              Icons.timeline_rounded,
              color: _readableOn(Colors.blue.shade900),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rastro do acesso',
                  style: TextStyle(
                    color: _readableOn(Colors.blue.shade900),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'IP: ${documento['ip'] ?? 'N/A'} • ${documento['cidade'] ?? 'N/A'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _readableOn(Colors.blue.shade900).withAlpha(199),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoEventos({
    required int totalEventos,
    required Map<String, int> resumoTipos,
    required int camposSuspeitos,
    required bool compact,
  }) {
    final items = [
      _ResumoDialog(
        'Total',
        totalEventos.toString(),
        Icons.touch_app_rounded,
        Colors.blue,
      ),
      _ResumoDialog(
        'Telas',
        (resumoTipos['telas'] ?? 0).toString(),
        Icons.web_rounded,
        Colors.indigo,
      ),
      _ResumoDialog(
        'Cliques',
        (resumoTipos['botoes'] ?? 0).toString(),
        Icons.ads_click_rounded,
        Colors.orange,
      ),
      _ResumoDialog(
        'Etapas',
        (resumoTipos['etapas'] ?? 0).toString(),
        Icons.stairs_rounded,
        Colors.purple,
      ),
      _ResumoDialog(
        'Campos',
        (resumoTipos['campos'] ?? 0).toString(),
        Icons.edit_note_rounded,
        Colors.teal,
      ),
      _ResumoDialog(
        'Erros',
        (resumoTipos['erros'] ?? 0).toString(),
        Icons.warning_rounded,
        Colors.red,
      ),
      _ResumoDialog(
        'Conversões',
        (resumoTipos['conversoes'] ?? 0).toString(),
        Icons.verified_rounded,
        Colors.green,
      ),
      if (camposSuspeitos > 0)
        _ResumoDialog(
          'Suspeitos',
          camposSuspeitos.toString(),
          Icons.report_rounded,
          Colors.deepOrange,
        ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return SizedBox(
          width: compact ? 98 : 128,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: _cardDecoration(
              radius: 18,
              borderColor: item.color.withAlpha(31),
            ),
            child: Column(
              children: [
                Icon(item.icon, color: item.color, size: 21),
                const SizedBox(height: 5),
                Text(
                  item.value,
                  style: TextStyle(
                    color: item.color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInteligenciaFluxo(
    List<Map<String, dynamic>> eventosMap,
    bool compact,
  ) {
    final resumo = _resumoTiposEvento(eventosMap);
    final duracaoTelas = _somarDuracaoEventos(eventosMap, 'tela');
    final duracaoEtapas = _somarDuracaoEventos(eventosMap, 'etapa_formulario');
    final suspeitos = _contarCamposSuspeitos(eventosMap);
    final conversoes = resumo['conversoes'] ?? 0;
    final erros = resumo['erros'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(
        radius: 22,
        borderColor: _softBorder(
          suspeitos > 0 ? Colors.deepOrange : Colors.green,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: suspeitos > 0
                ? Icons.report_rounded
                : Icons.auto_graph_rounded,
            title: 'Leitura inteligente do fluxo',
            color: suspeitos > 0 ? Colors.deepOrange : Colors.green,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip('Tempo em telas', _formatarDuracao(duracaoTelas)),
              _buildInfoChip(
                'Tempo em etapas',
                _formatarDuracao(duracaoEtapas),
              ),
              _buildInfoChip('Erros', erros),
              _buildInfoChip('Conversões', conversoes),
              _buildInfoChip('Campos suspeitos', suspeitos),
            ],
          ),
          if (suspeitos > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _softFill(Colors.deepOrange),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _softBorder(Colors.deepOrange)),
              ),
              child: Text(
                'Atenção: esta sessão possui texto suspeito/zoeira em campos digitados ou snapshots.',
                style: TextStyle(
                  color: _softOnCard(Colors.deepOrange),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAreaAlunoRastroCard(Map<String, dynamic> evento) {
    final metadata = _metadataEvento(evento);
    final dispositivo = _mapFromDynamic(metadata['dispositivo']);
    final possivelTroca = metadata['possivel_troca_aluno'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(
        radius: 22,
        borderColor: _softBorder(
          possivelTroca ? Colors.deepOrange : Colors.green,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.school_rounded,
            title: 'Área do Aluno',
            color: possivelTroca ? Colors.deepOrange : Colors.green,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip(
                'Aluno logado',
                _textoValor(metadata['aluno_nome']),
              ),
              _buildInfoChip('Turma', _textoValor(metadata['turma'])),
              _buildInfoChip('Academia', _textoValor(metadata['academia'])),
              _buildInfoChip(
                'Horário',
                _formatarHoraEvento(evento['data_hora'] ?? evento['timestamp']),
              ),
              if (dispositivo.isNotEmpty)
                _buildInfoChip(
                  'Dispositivo',
                  _textoDispositivoMapa(dispositivo),
                ),
              if (dispositivo['navegador_nome'] != null)
                _buildInfoChip(
                  'Navegador',
                  [
                    dispositivo['navegador_nome'],
                    if (_textoValor(
                      dispositivo['navegador_versao'],
                      '',
                    ).isNotEmpty)
                      dispositivo['navegador_versao'],
                  ].join(' '),
                ),
              if (dispositivo['sistema_operacional_aproximado'] != null)
                _buildInfoChip(
                  'Sistema',
                  dispositivo['sistema_operacional_aproximado'],
                ),
              if (dispositivo['celular_marca_aproximada'] != null)
                _buildInfoChip(
                  'Marca/modelo',
                  [
                    dispositivo['celular_marca_aproximada'],
                    dispositivo['celular_modelo_aproximado'],
                  ].where((e) => _textoValor(e, '').isNotEmpty).join(' '),
                ),
              if (dispositivo['largura_tela'] != null &&
                  dispositivo['altura_tela'] != null)
                _buildInfoChip(
                  'Tela',
                  '${dispositivo['largura_tela']}x${dispositivo['altura_tela']}',
                ),
              if (dispositivo['idioma'] != null)
                _buildInfoChip('Idioma', dispositivo['idioma']),
              if (dispositivo['timezone'] != null)
                _buildInfoChip('Fuso', dispositivo['timezone']),
            ],
          ),
          if (possivelTroca) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _softFill(Colors.deepOrange),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _softBorder(Colors.deepOrange)),
              ),
              child: Text(
                'Mesmo aparelho usado em outro aluno anteriormente.',
                style: TextStyle(
                  color: _softOnCard(Colors.deepOrange),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapaCard(double latitude, double longitude) {
    return Material(
      color: _softFill(Colors.blue),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _abrirGoogleMaps(latitude, longitude),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _softBorder(Colors.blue)),
          ),
          child: Row(
            children: [
              Icon(Icons.map_rounded, color: _softOnCard(Colors.blue)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Abrir localização no Google Maps',
                  style: TextStyle(
                    color: _softOnCard(Colors.blue),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                color: Colors.blue.shade800,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline(List<Map<String, dynamic>> eventosMap, bool compact) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.route_rounded,
            title: 'Linha do tempo',
            color: Colors.blue,
            trailing: '${eventosMap.length} eventos',
          ),
          const SizedBox(height: 10),
          if (eventosMap.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: Text(
                  'Nenhum evento registrado nesta sessão',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
              ),
            )
          else
            ...List.generate(eventosMap.length, (index) {
              final evento = eventosMap[index];
              return _buildEventoLinha(evento, index, compact);
            }),
        ],
      ),
    );
  }

  Widget _buildEventoLinha(
    Map<String, dynamic> evento,
    int index,
    bool compact,
  ) {
    final tipo = evento['tipo']?.toString() ?? 'evento';
    final nome = evento['nome']?.toString() ?? 'Evento';
    final hora = _formatarHoraEvento(
      evento['data_hora'] ?? evento['timestamp'],
    );
    final suspeito = _eventoEhSuspeito(evento);

    final (iconeBase, corBase) = switch (tipo) {
      'menu' => (Icons.menu_rounded, Colors.green),
      'botao_social' => (Icons.share_rounded, Colors.blue),
      'clique' => (Icons.ads_click_rounded, Colors.orange),
      'card' => (Icons.grid_view_rounded, Colors.orange),
      'pagina' => (Icons.web_rounded, Colors.purple),
      'tela' => (Icons.desktop_windows_rounded, Colors.indigo),
      'formulario' => (Icons.dynamic_form_rounded, Colors.teal),
      'etapa_formulario' => (Icons.stairs_rounded, Colors.purple),
      'erro_formulario' => (Icons.warning_rounded, Colors.red),
      'conversao' => (Icons.verified_rounded, Colors.green),
      'funil_inscricao' => (Icons.filter_alt_rounded, Colors.teal),
      'campo_formulario' => (Icons.edit_note_rounded, Colors.blue),
      'snapshot_formulario' => (Icons.fact_check_rounded, Colors.cyan),
      'rolagem' => (Icons.swap_vert_rounded, Colors.brown),
      'filtro' => (Icons.filter_alt_rounded, Colors.deepPurple),
      'item_visualizado' => (Icons.visibility_rounded, Colors.pink),
      _ => (Icons.touch_app_rounded, Colors.grey),
    };
    final icone = suspeito ? Icons.warning_amber_rounded : iconeBase;
    final cor = suspeito ? Colors.amber.shade800 : corBase;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _softFill(cor),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _softBorder(cor)),
                ),
                child: Icon(icone, color: _softOnCard(cor), size: 18),
              ),
              if (index != 9999)
                Container(width: 2, height: 24, color: context.uai.border),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: context.uai.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: suspeito ? _softBorder(cor) : context.uai.border,
                  width: suspeito ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (suspeito) ...[
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: _softOnCard(cor),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                nome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.uai.textPrimary,
                                  fontSize: compact ? 12.2 : 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _descricaoEvento(evento),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.uai.textSecondary,
                            fontSize: 10.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hora,
                    style: TextStyle(
                      color: context.uai.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDispositivoCard(Map<String, dynamic> documento) {
    final dispositivo = _mapFromDynamic(documento['dispositivo']);
    final userAgent = documento['user_agent']?.toString().trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.devices_rounded,
            title: 'Dispositivo de acesso',
            color: Colors.deepPurple,
          ),
          const SizedBox(height: 10),
          if (dispositivo.isEmpty && (userAgent == null || userAgent.isEmpty))
            _emptyMiniCard('Nenhum dado de dispositivo registrado neste acesso')
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip('Dispositivo', _textoDispositivo(documento)),
                _buildInfoChip('Tela', _tamanhoTelaDispositivo(documento)),
                if (dispositivo['navegador_nome'] != null)
                  _buildInfoChip(
                    'Navegador',
                    [
                      dispositivo['navegador_nome'],
                      if (_textoValor(
                        dispositivo['navegador_versao'],
                        '',
                      ).isNotEmpty)
                        dispositivo['navegador_versao'],
                    ].join(' '),
                  ),
                if (dispositivo['sistema_operacional_aproximado'] != null)
                  _buildInfoChip(
                    'Sistema',
                    dispositivo['sistema_operacional_aproximado'],
                  ),
                if (dispositivo['celular_marca_aproximada'] != null)
                  _buildInfoChip(
                    'Celular',
                    [
                      dispositivo['celular_marca_aproximada'],
                      dispositivo['celular_modelo_aproximado'],
                    ].where((e) => _textoValor(e, '').isNotEmpty).join(' '),
                  ),
                if (dispositivo['idioma'] != null)
                  _buildInfoChip('Idioma', dispositivo['idioma']),
                if (dispositivo['timezone'] != null)
                  _buildInfoChip('Fuso', dispositivo['timezone']),
                if (dispositivo['tema_sistema'] != null)
                  _buildInfoChip('Tema', dispositivo['tema_sistema']),
                if (dispositivo['pixel_ratio'] != null)
                  _buildInfoChip('Pixel ratio', dispositivo['pixel_ratio']),
                if (dispositivo['tela'] != null)
                  _buildInfoChip('Tela origem', dispositivo['tela']),
                if (dispositivo['origem'] != null)
                  _buildInfoChip('Origem', dispositivo['origem']),
              ],
            ),
            if (userAgent != null && userAgent.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: context.uai.cardAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.uai.border),
                ),
                child: Text(
                  'User agent: $userAgent',
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 10.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoAcesso(
    Map<String, dynamic> documento,
    double? latitude,
    double? longitude,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.info_rounded,
            title: 'Informações do acesso',
            color: Colors.grey,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip('ISP', documento['isp'] ?? 'N/A'),
              _buildInfoChip(
                'Data/Hora',
                _formatarDataHora(documento['data_acesso'] as Timestamp?),
              ),
              _buildInfoChip(
                'Total Eventos',
                (documento['total_eventos'] ?? 0).toString(),
              ),
              if (latitude != null && longitude != null)
                _buildInfoChip(
                  'Coordenadas',
                  '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRastroBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: context.uai.surface,
          border: Border(top: BorderSide(color: context.uai.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_rounded),
            label: const Text('FECHAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.primary,
              foregroundColor: _onPrimary(),
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, dynamic valor) {
    final texto = valor?.toString() ?? 'N/A';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.uai.cardAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: context.uai.border),
      ),
      child: Text(
        '$label: $texto',
        style: TextStyle(
          fontSize: 11,
          color: context.uai.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAlertaAcessoChip(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _softFill(Colors.deepOrange),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _softBorder(Colors.deepOrange)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          color: _softOnCard(Colors.deepOrange),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required MaterialColor color,
    String? trailing,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withAlpha(31), t.cardAlt),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: accent.withAlpha(41)),
          ),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: t.border),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyMiniCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.uai.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.uai.border),
      ),
      child: Text(text, style: TextStyle(color: context.uai.textSecondary)),
    );
  }

  BoxDecoration _cardDecoration({double radius = 18, Color? borderColor}) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.softShadow,
    );
  }
}

class _MetricCard {
  final String title;
  final String value;
  final IconData icon;
  final MaterialColor color;

  const _MetricCard(this.title, this.value, this.icon, this.color);
}

class _ResumoDialog {
  final String label;
  final String value;
  final IconData icon;
  final MaterialColor color;

  const _ResumoDialog(this.label, this.value, this.icon, this.color);
}
