import 'package:cloud_firestore/cloud_firestore.dart';

class RastreioSiteService {
  static final RastreioSiteService _instance = RastreioSiteService._internal();

  factory RastreioSiteService() => _instance;

  RastreioSiteService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _documentoAcessoId;
  DateTime? _inicioSessao;
  DateTime? _inicioTelaAtual;
  String? _telaAtual;

  int _contadorEventos = 0;
  bool _sessaoFinalizada = false;

  final Map<String, DateTime> _marcadoresTempo = {};

  String? get documentoAcessoId => _documentoAcessoId;

  void iniciarSessaoComDocumento(String documentoId) {
    _documentoAcessoId = documentoId;
    _inicioSessao = DateTime.now();
    _inicioTelaAtual = null;
    _telaAtual = null;
    _contadorEventos = 0;
    _sessaoFinalizada = false;
    _marcadoresTempo.clear();

    print('✅ Sessão iniciada para documento: $documentoId');
  }

  Map<String, dynamic> _metadadosBase(Map<String, dynamic>? metadata) {
    final agora = DateTime.now();
    final duracaoSessao = _inicioSessao == null
        ? 0
        : agora.difference(_inicioSessao!).inSeconds;

    return {
      'sessao_duracao_segundos': duracaoSessao,
      'evento_ordem': _contadorEventos,
      if (_telaAtual != null) 'tela_atual': _telaAtual,
      ...?metadata,
    };
  }

  Future<void> registrarEvento({
    required String tipo,
    required String nome,
    String? origem,
    String? paginaOrigem,
    Map<String, dynamic>? metadata,
  }) async {
    if (_documentoAcessoId == null) {
      print('⚠️ Nenhum documento de acesso ativo. Ignorando evento: $tipo | $nome');
      return;
    }

    if (_sessaoFinalizada) {
      print('⚠️ Sessão já finalizada. Ignorando evento: $tipo | $nome');
      return;
    }

    _contadorEventos++;

    try {
      final agora = DateTime.now();
      final evento = {
        'tipo': tipo,
        'nome': nome,
        'origem': origem,
        'pagina_origem': paginaOrigem,
        'timestamp': agora.millisecondsSinceEpoch,
        'data_hora': agora.toIso8601String(),
        'metadata': _metadadosBase(metadata),
      };

      await _firestore
          .collection('estatisticas_acessos')
          .doc(_documentoAcessoId!)
          .update({
        'eventos': FieldValue.arrayUnion([evento]),
        'ultima_atividade': FieldValue.serverTimestamp(),
        'total_eventos': FieldValue.increment(1),
        'ultimo_evento_tipo': tipo,
        'ultimo_evento_nome': nome,
        'ultimo_evento_origem': origem,
      });

      print('✅ Evento registrado: $tipo | $nome | $origem');
    } catch (e) {
      print('❌ Erro ao registrar evento: $e');
      if (e is FirebaseException) {
        print('   Código: ${e.code}');
        print('   Mensagem: ${e.message}');
      }
    }
  }

  Future<void> registrarPaginaVista(String pagina, String? origem) async {
    await registrarEvento(
      tipo: 'pagina',
      nome: pagina,
      origem: origem,
      metadata: {
        'tempo_carregamento': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> iniciarTela(
      String tela, {
        String? origem,
        Map<String, dynamic>? metadata,
      }) async {
    final nomeTela = tela.trim();
    if (nomeTela.isEmpty) return;

    if (_telaAtual != null && _inicioTelaAtual != null && _telaAtual != nomeTela) {
      await finalizarTela(destino: nomeTela);
    }

    _telaAtual = nomeTela;
    _inicioTelaAtual = DateTime.now();
    marcarTempo('tela_$nomeTela');

    await registrarEvento(
      tipo: 'tela',
      nome: nomeTela,
      origem: origem ?? 'entrada',
      paginaOrigem: origem,
      metadata: {
        'acao': 'entrou',
        ...?metadata,
      },
    );
  }

  Future<void> finalizarTela({
    String? tela,
    String? origem,
    String? destino,
    Map<String, dynamic>? metadata,
  }) async {
    final nomeTela = tela ?? _telaAtual;
    if (nomeTela == null || nomeTela.trim().isEmpty || _inicioTelaAtual == null) {
      return;
    }

    final duracao = DateTime.now().difference(_inicioTelaAtual!).inSeconds;

    await registrarEvento(
      tipo: 'tela',
      nome: nomeTela,
      origem: origem ?? 'saida',
      metadata: {
        'acao': 'saiu',
        'destino': destino,
        'duracao_segundos': duracao,
        ...?metadata,
      },
    );

    if (_telaAtual == nomeTela) {
      _telaAtual = null;
      _inicioTelaAtual = null;
    }
  }

  void marcarTempo(String chave) {
    _marcadoresTempo[chave] = DateTime.now();
  }

  int? segundosDesdeMarcador(String chave) {
    final inicio = _marcadoresTempo[chave];
    if (inicio == null) return null;
    return DateTime.now().difference(inicio).inSeconds;
  }

  Future<void> registrarTempoMarcador({
    String? chave,
    String? nome,
    String? tipo,
    String? origem,
    Map<String, dynamic>? metadata,
    bool limparMarcador = false,
  }) async {
    final marcador = chave ?? nome;
    if (marcador == null || marcador.trim().isEmpty) return;

    final segundos = segundosDesdeMarcador(marcador);

    await registrarEvento(
      tipo: tipo ?? 'tempo',
      nome: nome ?? marcador,
      origem: origem,
      metadata: {
        if (segundos != null) 'duracao_segundos': segundos,
        'marcador': marcador,
        ...?metadata,
      },
    );

    if (limparMarcador) _marcadoresTempo.remove(marcador);
  }

  Future<void> registrarClique({
    required String nome,
    String? origem,
    String? paginaOrigem,
    Map<String, dynamic>? metadata,
  }) async {
    await registrarEvento(
      tipo: 'clique',
      nome: nome,
      origem: origem,
      paginaOrigem: paginaOrigem,
      metadata: metadata,
    );
  }

  Future<void> registrarAcaoFormulario({
    required String formulario,
    required String acao,
    String? origem,
    String? etapa,
    Map<String, dynamic>? metadata,
  }) async {
    await registrarEvento(
      tipo: 'formulario',
      nome: formulario,
      origem: origem ?? acao,
      paginaOrigem: etapa,
      metadata: {
        'formulario': formulario,
        'acao': acao,
        if (etapa != null) 'etapa': etapa,
        ...?metadata,
      },
    );
  }

  Future<void> registrarEtapaFormulario({
    required String formulario,
    dynamic etapa,
    String? nomeEtapa,
    required String acao,
    String? origem,
    int? numeroEtapa,
    int? totalEtapas,
    Map<String, dynamic>? metadata,
  }) async {
    final etapaValor = etapa ?? numeroEtapa;
    final etapaNome = nomeEtapa ?? etapaValor?.toString() ?? 'etapa';

    await registrarEvento(
      tipo: 'etapa_formulario',
      nome: etapaNome,
      origem: origem ?? acao,
      paginaOrigem: formulario,
      metadata: {
        'formulario': formulario,
        'etapa': etapaValor,
        'nome_etapa': etapaNome,
        'acao': acao,
        if (numeroEtapa != null) 'numero_etapa': numeroEtapa,
        if (totalEtapas != null) 'total_etapas': totalEtapas,
        ...?metadata,
      },
    );
  }

  Future<void> registrarErroFormulario({
    required String formulario,
    String? local,
    List<String>? erros,
    String? erro,
    String? etapa,
    String? origem,
    Map<String, dynamic>? metadata,
  }) async {
    final listaErros = erros ?? (erro == null ? <String>[] : <String>[erro]);
    final localFinal = local ?? etapa ?? 'formulario';

    await registrarEvento(
      tipo: 'erro_formulario',
      nome: localFinal,
      origem: origem ?? 'erro',
      paginaOrigem: formulario,
      metadata: {
        'formulario': formulario,
        'local': localFinal,
        if (etapa != null) 'etapa': etapa,
        'erros': listaErros,
        'total_erros': listaErros.length,
        ...?metadata,
      },
    );
  }

  Future<void> registrarConversao({
    required String nome,
    String? origem,
    dynamic valor,
    Map<String, dynamic>? metadata,
  }) async {
    await registrarEvento(
      tipo: 'conversao',
      nome: nome,
      origem: origem,
      metadata: {
        if (valor != null) 'valor': valor,
        ...?metadata,
      },
    );
  }

  Future<void> registrarCampoFormulario({
    required String formulario,
    required String campo,
    required dynamic valor,
    String? origem,
    String? etapa,
    String? paginaOrigem,
    bool sensivel = false,
    Map<String, dynamic>? metadata,
  }) async {
    final valorTexto = valor?.toString() ?? '';
    final valorSeguro = sensivel ? _mascararValorSensivel(valorTexto) : valorTexto;

    await registrarEvento(
      tipo: 'campo_formulario',
      nome: campo,
      origem: origem ?? formulario,
      paginaOrigem: paginaOrigem ?? etapa,
      metadata: {
        'formulario': formulario,
        'campo': campo,
        'valor': valorSeguro,
        'sensivel': sensivel,
        'tamanho': valorTexto.length,
        'vazio': valorTexto.trim().isEmpty,
        'suspeito': _textoSuspeito(valorTexto),
        'categoria_suspeita': _categoriaTextoSuspeito(valorTexto),
        if (etapa != null) 'etapa': etapa,
        ...?metadata,
      },
    );
  }

  Future<void> registrarSnapshotFormulario({
    required String formulario,
    required String momento,
    required Map<String, dynamic> campos,
    String? origem,
    String? etapa,
    String? paginaOrigem,
    List<String> camposSensiveis = const [],
    Map<String, dynamic>? metadata,
  }) async {
    final camposTratados = <String, dynamic>{};
    final camposSuspeitos = <String>[];

    campos.forEach((campo, valor) {
      final valorTexto = valor?.toString() ?? '';
      final sensivel = camposSensiveis.contains(campo);

      camposTratados[campo] = {
        'valor': sensivel ? _mascararValorSensivel(valorTexto) : valorTexto,
        'sensivel': sensivel,
        'tamanho': valorTexto.length,
        'vazio': valorTexto.trim().isEmpty,
        'suspeito': _textoSuspeito(valorTexto),
        'categoria_suspeita': _categoriaTextoSuspeito(valorTexto),
      };

      if (_textoSuspeito(valorTexto)) {
        camposSuspeitos.add(campo);
      }
    });

    await registrarEvento(
      tipo: 'snapshot_formulario',
      nome: momento,
      origem: origem ?? formulario,
      paginaOrigem: paginaOrigem ?? etapa,
      metadata: {
        'formulario': formulario,
        'momento': momento,
        'campos': camposTratados,
        'total_campos': camposTratados.length,
        'campos_suspeitos': camposSuspeitos,
        'tem_conteudo_suspeito': camposSuspeitos.isNotEmpty,
        if (etapa != null) 'etapa': etapa,
        ...?metadata,
      },
    );
  }

  Future<void> registrarItemVisualizado({
    required String tela,
    required String itemTipo,
    required String itemNome,
    String? itemId,
    String? origem,
    Map<String, dynamic>? metadata,
  }) async {
    await registrarEvento(
      tipo: 'item_visualizado',
      nome: itemNome,
      origem: origem ?? tela,
      paginaOrigem: tela,
      metadata: {
        'tela': tela,
        'item_tipo': itemTipo,
        'item_nome': itemNome,
        if (itemId != null) 'item_id': itemId,
        ...?metadata,
      },
    );
  }

  Future<void> registrarFiltro({
    required String tela,
    required String filtro,
    required dynamic valor,
    String? origem,
    Map<String, dynamic>? metadata,
  }) async {
    await registrarEvento(
      tipo: 'filtro',
      nome: filtro,
      origem: origem ?? tela,
      paginaOrigem: tela,
      metadata: {
        'tela': tela,
        'filtro': filtro,
        'valor': valor,
        ...?metadata,
      },
    );
  }

  Future<void> registrarBuscaOuFiltroResultado({
    required String tela,
    required String nome,
    required int total,
    String? origem,
    Map<String, dynamic>? metadata,
  }) async {
    await registrarEvento(
      tipo: 'resultado',
      nome: nome,
      origem: origem ?? tela,
      paginaOrigem: tela,
      metadata: {
        'tela': tela,
        'total': total,
        ...?metadata,
      },
    );
  }

  Future<void> registrarRolagem({
    required String tela,
    required int percentual,
    String? origem,
    Map<String, dynamic>? metadata,
  }) async {
    await registrarEvento(
      tipo: 'rolagem',
      nome: '$percentual%',
      origem: origem ?? tela,
      paginaOrigem: tela,
      metadata: {
        'tela': tela,
        'percentual': percentual,
        ...?metadata,
      },
    );
  }

  Future<void> finalizarSessao() async {
    if (_documentoAcessoId != null && _inicioSessao != null) {
      final duracao = DateTime.now().difference(_inicioSessao!).inSeconds;
      try {
        await _firestore
            .collection('estatisticas_acessos')
            .doc(_documentoAcessoId)
            .update({
          'fim_sessao': FieldValue.serverTimestamp(),
          'duracao_segundos': duracao,
        });
        _sessaoFinalizada = true;
        print('✅ Sessão finalizada. Duração: ${duracao}s');
      } catch (e) {
        print('❌ Erro ao finalizar sessão: $e');
      }
    }
  }

  Future<Map<String, dynamic>> buscarRastroSessao(String documentoId) async {
    try {
      final doc = await _firestore
          .collection('estatisticas_acessos')
          .doc(documentoId)
          .get();

      if (!doc.exists) {
        return {'erro': 'Documento não encontrado'};
      }

      final data = doc.data()!;
      final eventosRaw = data['eventos'] as List? ?? [];
      final List<Map<String, dynamic>> eventosMap = eventosRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return {
        'sessao': {
          'id': documentoId,
          'ip': data['ip'],
          'cidade': data['cidade'],
          'estado': data['estado'],
          'pais': data['pais'],
          'latitude': data['latitude'],
          'longitude': data['longitude'],
          'isp': data['isp'],
          'inicio_sessao': (data['data_acesso'] as Timestamp?)?.toDate(),
          'fim_sessao': (data['fim_sessao'] as Timestamp?)?.toDate(),
          'total_eventos': data['total_eventos'] ?? 0,
          'user_agent': data['user_agent'] ?? 'Desconhecido',
        },
        'eventos': eventosMap,
        'resumo': _gerarResumoEventos(eventosMap),
      };
    } catch (e) {
      print('❌ Erro ao buscar rastro: $e');
      return {'erro': e.toString()};
    }
  }

  Map<String, dynamic> _gerarResumoEventos(List<Map<String, dynamic>> eventos) {
    int countTipo(String tipo) => eventos.where((e) => e['tipo'] == tipo).length;

    final eventosSuspeitos = eventos.where((e) {
      final metadata = Map<String, dynamic>.from(e['metadata'] as Map? ?? {});
      return metadata['suspeito'] == true ||
          metadata['tem_conteudo_suspeito'] == true;
    }).length;

    return {
      'total_eventos': eventos.length,
      'menus_clicados': countTipo('menu'),
      'botoes_clicados': countTipo('botao_social') + countTipo('clique'),
      'cards_clicados': countTipo('card'),
      'paginas_vistas': countTipo('pagina'),
      'telas': countTipo('tela'),
      'formularios': countTipo('formulario'),
      'etapas_formulario': countTipo('etapa_formulario'),
      'erros_formulario': countTipo('erro_formulario'),
      'conversoes': countTipo('conversao'),
      'campos_digitados': countTipo('campo_formulario'),
      'snapshots_formulario': countTipo('snapshot_formulario'),
      'rolagens': countTipo('rolagem'),
      'filtros': countTipo('filtro'),
      'itens_visualizados': countTipo('item_visualizado'),
      'eventos_suspeitos': eventosSuspeitos,
    };
  }

  String _mascararValorSensivel(String valor) {
    final somenteDigitos = valor.replaceAll(RegExp(r'[^0-9]'), '');

    if (somenteDigitos.isEmpty) return '';

    if (somenteDigitos.length <= 4) {
      return '*' * somenteDigitos.length;
    }

    final inicio = somenteDigitos.substring(0, 2);
    final fim = somenteDigitos.substring(somenteDigitos.length - 2);

    return '$inicio${'*' * (somenteDigitos.length - 4)}$fim';
  }

  bool _textoSuspeito(String texto) {
    return _categoriaTextoSuspeito(texto) != null;
  }

  String? _categoriaTextoSuspeito(String texto) {
    final normalizado = texto.toLowerCase().trim().normalizeSemAcentos();

    if (normalizado.isEmpty) return null;

    final baixoCalao = [
      'pau',
      'buceta',
      'bct',
      'cu',
      'bunda',
      'pinto',
      'rola',
      'caralho',
      'porra',
      'merda',
      'fuder',
      'foda',
      'fdp',
      'vtnc',
      'vai tomar no cu',
    ];

    for (final termo in baixoCalao) {
      if (normalizado.contains(termo)) {
        return 'baixo_calao';
      }
    }

    final testeZoeira = [
      'teste',
      'asdf',
      'qwerty',
      'kkkk',
      'hahaha',
      'lalala',
      'abc123',
      '123456',
    ];

    for (final termo in testeZoeira) {
      if (normalizado.contains(termo)) {
        return 'possivel_teste_ou_zoeira';
      }
    }

    return null;
  }
}

extension _RastreioStringNormalize on String {
  String normalizeSemAcentos() {
    const comAcento = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
    const semAcento = 'aaaaaeeeeiiiiooooouuuucn';

    var resultado = this;
    for (var i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(comAcento[i], semAcento[i]);
    }

    return resultado;
  }
}
