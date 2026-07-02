import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventoModel {
  // ───────────────────── PADRÕES DE CAMISA ─────────────────────
  static const String modelagemNormal = 'NORMAL';
  static const String modelagemBabyLook = 'BABY_LOOK';

  static const String tipoManga = 'MANGA';
  static const String tipoMangaLonga = 'MANGA_LONGA';
  static const String tipoRegata = 'REGATA';

  static const List<String> tamanhosPadraoCamisa = [
    '1A',
    '2A',
    '4A',
    '6A',
    '8A',
    '10A',
    '12A',
    '14A',
    'PP',
    'P',
    'M',
    'G',
    'GG',
    'EGG',
  ];

  static const List<String> modelagensPadraoCamisa = [
    modelagemNormal,
    modelagemBabyLook,
  ];

  static const List<String> tiposPadraoCamisa = [
    tipoManga,
    tipoMangaLonga,
    tipoRegata,
  ];

  static const Map<String, double> valoresPadraoPorTipoCamisa = {
    tipoManga: 0.0,
    tipoMangaLonga: 0.0,
    tipoRegata: 0.0,
  };

  // 📅 DADOS BÁSICOS
  final String? id;
  final String nome;
  final String descricao;
  final String tipo;
  final DateTime data;
  final String horario;
  final String local;
  final String cidade;
  final List<String> organizadores;
  final String status;

  // 💰 CONFIGURAÇÕES DE TAXA
  final double valorInscricao;
  final bool permiteParcelamento;
  final int maxParcelas;
  final int descontoAVista;
  final DateTime? dataLimitePrimeiraParcela;

  // 👕 CONFIGURAÇÕES DE CAMISA
  final bool temCamisa;
  final double? valorCamisa;

  /// Valores de confecção/venda por tipo de camisa.
  ///
  /// Compatibilidade:
  /// - eventos antigos podem ter apenas `valorCamisa`;
  /// - se este mapa não existir, o sistema usa `valorCamisa` como valor padrão
  ///   para MANGA, MANGA_LONGA e REGATA;
  /// - se uma camisa antiga não tiver tipo, assume MANGA.
  final Map<String, double> valoresPorTipoCamisa;

  final List<String> tamanhosDisponiveis;
  final List<String> modelagensCamisaDisponiveis;
  final List<String> tiposCamisaDisponiveis;
  final bool camisaObrigatoria;

  // 🎯 REGRAS POR TIPO
  final bool alteraGraduacao;
  final bool geraCertificado;
  final String? tipoPublico;

  // 🔗 LINKS
  final String? linkBanner;
  final String? linkFotosVideos;
  final String? previaVideo;
  final String? linkPlaylist;

  // 🔥 CERTIFICADO
  final bool temCertificado;
  final String? modeloCertificadoId;
  final String? modeloCertificadoPath;
  final Map<String, dynamic>? configuracoesCertificado;

  // 🌐 PORTFÓLIO WEB
  final bool mostrarNoPortfolioWeb;

  // 📊 METADADOS
  final Timestamp? criadoEm;
  final Timestamp? atualizadoEm;

  EventoModel({
    this.id,
    required this.nome,
    required this.descricao,
    required this.tipo,
    required this.data,
    required this.horario,
    required this.local,
    required this.cidade,
    required this.organizadores,
    required this.status,
    required this.valorInscricao,
    required this.permiteParcelamento,
    required this.maxParcelas,
    required this.descontoAVista,
    this.dataLimitePrimeiraParcela,
    required this.temCamisa,
    this.valorCamisa,
    this.valoresPorTipoCamisa = valoresPadraoPorTipoCamisa,
    required this.tamanhosDisponiveis,
    this.modelagensCamisaDisponiveis = modelagensPadraoCamisa,
    this.tiposCamisaDisponiveis = tiposPadraoCamisa,
    required this.camisaObrigatoria,
    required this.alteraGraduacao,
    required this.geraCertificado,
    this.tipoPublico,
    this.linkBanner,
    this.linkFotosVideos,
    this.previaVideo,
    this.linkPlaylist,
    this.temCertificado = false,
    this.modeloCertificadoId,
    this.modeloCertificadoPath,
    this.configuracoesCertificado,
    required this.mostrarNoPortfolioWeb,
    this.criadoEm,
    this.atualizadoEm,
  });

  factory EventoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime dataEvento;
    if (data['data'] is Timestamp) {
      dataEvento = (data['data'] as Timestamp).toDate();
    } else if (data['data'] is String) {
      try {
        final partes = (data['data'] as String).split('/');
        dataEvento = DateTime(
          int.parse(partes[2]),
          int.parse(partes[1]),
          int.parse(partes[0]),
        );
      } catch (e) {
        dataEvento = DateTime.now();
        debugPrint('⚠️ Erro ao converter data do evento: $e');
      }
    } else {
      dataEvento = DateTime.now();
    }

    List<String> organizadoresList = [];
    if (data['organizadores'] != null) {
      if (data['organizadores'] is List) {
        organizadoresList = List<String>.from(data['organizadores']);
      } else if (data['organizadores'] is String) {
        final String orgString = data['organizadores'] as String;
        if (orgString.trim().isNotEmpty) {
          organizadoresList = orgString
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
    }

    final configCertificadoRaw =
        data['configuracoes_certificado'] ?? data['configuracoesCertificado'];

    final valorCamisaBase =
        (data['valorCamisa'] as num?)?.toDouble() ??
        (data['valor_camisa'] as num?)?.toDouble();

    return EventoModel(
      id: doc.id,
      nome: data['nome'] ?? '',
      descricao: data['descricao'] ?? '',
      tipo: data['tipo'] ?? data['tipo_evento'] ?? '',
      data: dataEvento,
      horario: data['horario'] ?? '',
      local: data['local'] ?? '',
      cidade: data['cidade'] ?? '',
      organizadores: organizadoresList,
      status: data['status'] ?? 'andamento',

      valorInscricao:
          (data['valorInscricao'] as num?)?.toDouble() ??
          (data['valor_inscricao'] as num?)?.toDouble() ??
          0,
      permiteParcelamento:
          data['permiteParcelamento'] ?? data['permite_parcelamento'] ?? false,
      maxParcelas:
          (data['maxParcelas'] as num?)?.toInt() ??
          (data['max_parcelas'] as num?)?.toInt() ??
          1,
      descontoAVista:
          (data['descontoAVista'] as num?)?.toInt() ??
          (data['desconto_a_vista'] as num?)?.toInt() ??
          0,
      dataLimitePrimeiraParcela:
          _timestampToDateTime(data['dataLimitePrimeiraParcela']) ??
          _timestampToDateTime(data['data_limite_primeira_parcela']),

      temCamisa: data['temCamisa'] ?? data['tem_camisa'] ?? false,
      valorCamisa: valorCamisaBase,
      valoresPorTipoCamisa: _normalizarValoresPorTipoCamisa(
        data['valoresPorTipoCamisa'] ??
            data['valores_por_tipo_camisa'] ??
            data['valoresTipoCamisa'] ??
            data['valores_tipo_camisa'],
        valorPadrao: valorCamisaBase,
      ),
      tamanhosDisponiveis: _normalizarListaTamanhos(
        data['tamanhosDisponiveis'] ?? data['tamanhos_disponiveis'],
      ),
      modelagensCamisaDisponiveis: _normalizarListaModelagens(
        data['modelagensCamisaDisponiveis'] ??
            data['modelagens_camisa_disponiveis'] ??
            data['modelagensDisponiveis'] ??
            data['modelagens_disponiveis'],
      ),
      tiposCamisaDisponiveis: _normalizarListaTiposCamisa(
        data['tiposCamisaDisponiveis'] ??
            data['tipos_camisa_disponiveis'] ??
            data['tiposDisponiveis'] ??
            data['tipos_disponiveis'],
      ),
      camisaObrigatoria:
          data['camisaObrigatoria'] ?? data['camisa_obrigatoria'] ?? false,

      alteraGraduacao:
          data['alteraGraduacao'] ?? data['altera_graduacao'] ?? false,
      geraCertificado:
          data['geraCertificado'] ?? data['gera_certificado'] ?? false,
      tipoPublico: data['tipoPublico'] ?? data['tipo_publico'],

      linkBanner: data['linkBanner'] ?? data['link_banner'],
      linkFotosVideos: data['linkFotosVideos'] ?? data['link_fotos_videos'],
      previaVideo: data['previaVideo'] ?? data['previa_video'],
      linkPlaylist: data['linkPlaylist'] ?? data['link_playlist'],

      temCertificado:
          data['tem_certificado'] ?? data['temCertificado'] ?? false,
      modeloCertificadoId:
          (data['modelo_certificado_id'] ??
                  data['modeloCertificadoId'] ??
                  ConfiguracoesCertificadoEvento.modeloAutomatico)
              ?.toString(),
      modeloCertificadoPath:
          data['modelo_certificado_path'] ?? data['modeloCertificadoPath'],
      configuracoesCertificado: configCertificadoRaw is Map
          ? Map<String, dynamic>.from(configCertificadoRaw)
          : null,

      mostrarNoPortfolioWeb:
          data['mostrarNoPortfolioWeb'] ??
          data['mostrar_no_portfolio_web'] ??
          false,

      criadoEm: data['criado_em'] as Timestamp?,
      atualizadoEm: data['atualizado_em'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nome': nome,
      'descricao': descricao,
      'tipo': tipo,
      'data': Timestamp.fromDate(data),
      'horario': horario,
      'local': local,
      'cidade': cidade,
      'organizadores': organizadores,
      'status': status,

      'valorInscricao': valorInscricao,
      'permiteParcelamento': permiteParcelamento,
      'maxParcelas': maxParcelas,
      'descontoAVista': descontoAVista,
      if (dataLimitePrimeiraParcela != null)
        'dataLimitePrimeiraParcela': Timestamp.fromDate(
          dataLimitePrimeiraParcela!,
        ),

      'temCamisa': temCamisa,
      if (valorCamisa != null) 'valorCamisa': valorCamisa,
      'valoresPorTipoCamisa': _normalizarValoresPorTipoCamisa(
        valoresPorTipoCamisa,
        valorPadrao: valorCamisa,
      ),
      'tamanhosDisponiveis': _normalizarListaTamanhos(tamanhosDisponiveis),
      'modelagensCamisaDisponiveis': _normalizarListaModelagens(
        modelagensCamisaDisponiveis,
      ),
      'tiposCamisaDisponiveis': _normalizarListaTiposCamisa(
        tiposCamisaDisponiveis,
      ),
      'camisaObrigatoria': camisaObrigatoria,

      'alteraGraduacao': alteraGraduacao,
      'geraCertificado': geraCertificado,
      if (tipoPublico != null) 'tipoPublico': tipoPublico,

      if (linkBanner != null) 'linkBanner': linkBanner,
      if (linkFotosVideos != null) 'linkFotosVideos': linkFotosVideos,
      if (previaVideo != null) 'previaVideo': previaVideo,
      if (linkPlaylist != null) 'linkPlaylist': linkPlaylist,

      'tem_certificado': temCertificado,
      'modelo_certificado_id':
          modeloCertificadoId ??
          ConfiguracoesCertificadoEvento.modeloAutomatico,
      'modelo_certificado_path': modeloCertificadoPath,
      'configuracoes_certificado': temCertificado
          ? configuracoesCertificadoAtualizada
          : null,

      'mostrarNoPortfolioWeb': mostrarNoPortfolioWeb,

      'atualizado_em': FieldValue.serverTimestamp(),
    };

    if (id == null) {
      map['criado_em'] = FieldValue.serverTimestamp();
    }

    return map;
  }

  EventoModel copyWith({
    String? id,
    String? nome,
    String? descricao,
    String? tipo,
    DateTime? data,
    String? horario,
    String? local,
    String? cidade,
    List<String>? organizadores,
    String? status,
    double? valorInscricao,
    bool? permiteParcelamento,
    int? maxParcelas,
    int? descontoAVista,
    DateTime? dataLimitePrimeiraParcela,
    bool? temCamisa,
    double? valorCamisa,
    Map<String, double>? valoresPorTipoCamisa,
    List<String>? tamanhosDisponiveis,
    List<String>? modelagensCamisaDisponiveis,
    List<String>? tiposCamisaDisponiveis,
    bool? camisaObrigatoria,
    bool? alteraGraduacao,
    bool? geraCertificado,
    String? tipoPublico,
    String? linkBanner,
    String? linkFotosVideos,
    String? previaVideo,
    String? linkPlaylist,
    bool? temCertificado,
    String? modeloCertificadoId,
    String? modeloCertificadoPath,
    Map<String, dynamic>? configuracoesCertificado,
    bool? mostrarNoPortfolioWeb,
    Timestamp? criadoEm,
    Timestamp? atualizadoEm,
  }) {
    return EventoModel(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      tipo: tipo ?? this.tipo,
      data: data ?? this.data,
      horario: horario ?? this.horario,
      local: local ?? this.local,
      cidade: cidade ?? this.cidade,
      organizadores: organizadores ?? this.organizadores,
      status: status ?? this.status,
      valorInscricao: valorInscricao ?? this.valorInscricao,
      permiteParcelamento: permiteParcelamento ?? this.permiteParcelamento,
      maxParcelas: maxParcelas ?? this.maxParcelas,
      descontoAVista: descontoAVista ?? this.descontoAVista,
      dataLimitePrimeiraParcela:
          dataLimitePrimeiraParcela ?? this.dataLimitePrimeiraParcela,
      temCamisa: temCamisa ?? this.temCamisa,
      valorCamisa: valorCamisa ?? this.valorCamisa,
      valoresPorTipoCamisa: _normalizarValoresPorTipoCamisa(
        valoresPorTipoCamisa ?? this.valoresPorTipoCamisa,
        valorPadrao: valorCamisa ?? this.valorCamisa,
      ),
      tamanhosDisponiveis: _normalizarListaTamanhos(
        tamanhosDisponiveis ?? this.tamanhosDisponiveis,
      ),
      modelagensCamisaDisponiveis: _normalizarListaModelagens(
        modelagensCamisaDisponiveis ?? this.modelagensCamisaDisponiveis,
      ),
      tiposCamisaDisponiveis: _normalizarListaTiposCamisa(
        tiposCamisaDisponiveis ?? this.tiposCamisaDisponiveis,
      ),
      camisaObrigatoria: camisaObrigatoria ?? this.camisaObrigatoria,
      alteraGraduacao: alteraGraduacao ?? this.alteraGraduacao,
      geraCertificado: geraCertificado ?? this.geraCertificado,
      tipoPublico: tipoPublico ?? this.tipoPublico,
      linkBanner: linkBanner ?? this.linkBanner,
      linkFotosVideos: linkFotosVideos ?? this.linkFotosVideos,
      previaVideo: previaVideo ?? this.previaVideo,
      linkPlaylist: linkPlaylist ?? this.linkPlaylist,
      temCertificado: temCertificado ?? this.temCertificado,
      modeloCertificadoId: modeloCertificadoId ?? this.modeloCertificadoId,
      modeloCertificadoPath:
          modeloCertificadoPath ?? this.modeloCertificadoPath,
      configuracoesCertificado:
          configuracoesCertificado ?? this.configuracoesCertificado,
      mostrarNoPortfolioWeb:
          mostrarNoPortfolioWeb ?? this.mostrarNoPortfolioWeb,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }

  static DateTime? _timestampToDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return fallback;

    return double.tryParse(text.replaceAll(',', '.')) ?? fallback;
  }

  static Map<String, double> _normalizarValoresPorTipoCamisa(
    dynamic value, {
    double? valorPadrao,
  }) {
    final fallback = valorPadrao ?? 0.0;

    final result = <String, double>{
      tipoManga: fallback,
      tipoMangaLonga: fallback,
      tipoRegata: fallback,
    };

    if (value is Map) {
      value.forEach((key, rawValue) {
        final tipo = _normalizarTipoCamisa(key);
        result[tipo] = _asDouble(rawValue, fallback: fallback);
      });
    }

    return result;
  }

  static List<String> _normalizarListaTamanhos(dynamic value) {
    final source = value is List ? value : const [];

    final result = <String>[];

    for (final item in source) {
      final text = item?.toString().trim().toUpperCase() ?? '';
      if (text.isEmpty) continue;

      final clean = text
          .replaceAll(' ', '')
          .replaceAll('ANOS', 'A')
          .replaceAll('ANO', 'A');

      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) {
      return List<String>.from(tamanhosPadraoCamisa);
    }

    result.sort(_compararTamanhosCamisa);
    return result;
  }

  static int _compararTamanhosCamisa(String a, String b) {
    final ordem = <String, int>{
      '1A': 1,
      '2A': 2,
      '4A': 4,
      '6A': 6,
      '8A': 8,
      '10A': 10,
      '12A': 12,
      '14A': 14,
      'PP': 100,
      'P': 101,
      'M': 102,
      'G': 103,
      'GG': 104,
      'EGG': 105,
      'XG': 106,
      'XXG': 107,
    };

    final ia = ordem[a] ?? 999;
    final ib = ordem[b] ?? 999;

    if (ia != ib) return ia.compareTo(ib);
    return a.compareTo(b);
  }

  static List<String> _normalizarListaModelagens(dynamic value) {
    final source = value is List ? value : const [];
    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarModelagemCamisa(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) return List<String>.from(modelagensPadraoCamisa);

    result.sort((a, b) {
      final ordem = {modelagemNormal: 0, modelagemBabyLook: 1};

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  static List<String> _normalizarListaTiposCamisa(dynamic value) {
    final source = value is List ? value : const [];
    final result = <String>[];

    for (final item in source) {
      final clean = _normalizarTipoCamisa(item);
      if (!result.contains(clean)) result.add(clean);
    }

    if (result.isEmpty) return List<String>.from(tiposPadraoCamisa);

    result.sort((a, b) {
      final ordem = {tipoManga: 0, tipoMangaLonga: 1, tipoRegata: 2};

      return (ordem[a] ?? 99).compareTo(ordem[b] ?? 99);
    });

    return result;
  }

  static String _normalizarModelagemCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'BABYLOOK' ||
        clean == 'BABY_LOOK' ||
        clean == 'BABY_LOOK_FEMININA' ||
        clean == 'FEMININA') {
      return modelagemBabyLook;
    }

    return modelagemNormal;
  }

  static String _normalizarTipoCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'MANGA_LONGA' ||
        clean == 'LONGA' ||
        clean == 'MANGA_COMPRIDA') {
      return tipoMangaLonga;
    }

    if (clean == 'REGATA') {
      return tipoRegata;
    }

    return tipoManga;
  }

  static String modelagemCamisaLabel(String value) {
    switch (_normalizarModelagemCamisa(value)) {
      case modelagemBabyLook:
        return 'Baby Look';
      case modelagemNormal:
      default:
        return 'Normal';
    }
  }

  static String tipoCamisaLabel(String value) {
    switch (_normalizarTipoCamisa(value)) {
      case tipoMangaLonga:
        return 'Manga Longa';
      case tipoRegata:
        return 'Regata';
      case tipoManga:
      default:
        return 'Manga';
    }
  }

  String get dataFormatada {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }

  String get localDataCertificado {
    final cidadeLimpa = cidade.trim().isEmpty ? local.trim() : cidade.trim();
    final cidadeFormatada = cidadeLimpa.toUpperCase();
    return '$cidadeFormatada, ${data.day.toString().padLeft(2, '0')} DE '
        '${_nomeMes(data.month).toUpperCase()} DE ${data.year}';
  }

  static String _nomeMes(int mes) {
    const meses = [
      '',
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];

    if (mes < 1 || mes > 12) return '';
    return meses[mes];
  }

  bool get isBatizado => tipo.toUpperCase().contains('BATIZADO');
  bool get isConfraternizacao =>
      tipo.toUpperCase().contains('CONFRATERNIZAÇÃO');
  bool get isForaCidade => tipo.toUpperCase().contains('OUTRA CIDADE');
  bool get isDestaque => tipo.toUpperCase().contains('DESTAQUE');
  bool get isCampeonato => tipo.toUpperCase().contains('CAMPEONATO');
  bool get isAulao => tipo.toUpperCase().contains('AULÃO');

  double valorCamisaPorTipo(String? tipoCamisa) {
    if (!temCamisa) return 0.0;

    final tipo = _normalizarTipoCamisa(tipoCamisa);
    final valores = _normalizarValoresPorTipoCamisa(
      valoresPorTipoCamisa,
      valorPadrao: valorCamisa,
    );

    return valores[tipo] ?? valorCamisa ?? 0.0;
  }

  double get valorCamisaManga => valorCamisaPorTipo(tipoManga);
  double get valorCamisaMangaLonga => valorCamisaPorTipo(tipoMangaLonga);
  double get valorCamisaRegata => valorCamisaPorTipo(tipoRegata);

  double getValorTotal({bool comCamisa = true, String? tipoCamisa}) {
    double total = valorInscricao;
    if (comCamisa && temCamisa) {
      total += valorCamisaPorTipo(tipoCamisa ?? tipoManga);
    }
    return total;
  }

  double getValorParcela({bool comCamisa = true, int numeroParcelas = 1}) {
    final total = getValorTotal(comCamisa: comCamisa);
    if (!permiteParcelamento || numeroParcelas == 1) {
      return total * (1 - descontoAVista / 100);
    }
    return total / numeroParcelas;
  }

  List<String> get tamanhosDisponiveisFormatados {
    if (!temCamisa) return [];
    return tamanhosDisponiveis;
  }

  bool tamanhoDisponivel(String tamanho) {
    return tamanhosDisponiveis.contains(tamanho.trim().toUpperCase());
  }

  bool modelagemCamisaDisponivel(String modelagem) {
    return modelagensCamisaDisponiveis.contains(
      _normalizarModelagemCamisa(modelagem),
    );
  }

  bool tipoCamisaDisponivel(String tipoCamisa) {
    return tiposCamisaDisponiveis.contains(_normalizarTipoCamisa(tipoCamisa));
  }

  Color get corDoTipo {
    if (isBatizado) return Colors.green;
    if (isConfraternizacao) return Colors.orange;
    if (isForaCidade) return Colors.blue;
    if (isDestaque) return Colors.purple;
    if (isCampeonato) return Colors.red;
    if (isAulao) return Colors.teal;
    return Colors.grey;
  }

  IconData get iconeDoTipo {
    if (isBatizado) return Icons.emoji_events;
    if (isConfraternizacao) return Icons.celebration;
    if (isForaCidade) return Icons.bus_alert;
    if (isDestaque) return Icons.star;
    if (isCampeonato) return Icons.sports_martial_arts;
    if (isAulao) return Icons.school;
    return Icons.event;
  }

  ConfiguracoesCertificadoEvento get configuracoesCertificadoEvento {
    return ConfiguracoesCertificadoEvento.fromMap(configuracoesCertificado);
  }

  Map<String, dynamic> get configuracoesCertificadoAtualizada {
    if (!temCertificado) return {};
    return configuracoesCertificadoEvento.toMap();
  }

  bool get temConfiguracaoCertificadoCompleta {
    if (!temCertificado) return false;
    return configuracoesCertificadoEvento.assinaturasValidas.isNotEmpty;
  }

  bool certificadoConfigurado(String tipoCertificado) {
    if (!temCertificado) return false;
    return configuracoesCertificadoEvento.ativo;
  }

  Map<String, dynamic>? getConfiguracaoCertificado(String tipoCertificado) {
    if (!temCertificado) return null;
    return configuracoesCertificadoEvento.toMap();
  }

  int get quantidadeCertificadosConfigurados {
    if (!temCertificado) return 0;
    return configuracoesCertificadoEvento.assinaturasValidas.length;
  }

  String? get caminhoCompletoCertificado {
    if (modeloCertificadoPath == null) return null;
    return 'assets/certificados/$modeloCertificadoPath';
  }

  Map<String, String> get configuracoesCertificadoPadrao {
    if (configuracoesCertificado == null) return {};

    try {
      return configuracoesCertificado!.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );
    } catch (_) {
      return {};
    }
  }

  bool certificadoValidoParaTipo(String tipoCertificado) {
    if (!temCertificado) return false;
    return configuracoesCertificadoEvento.ativo;
  }
}

@immutable
class ConfiguracoesCertificadoEvento {
  static const String modeloAutomatico = 'AUTO_POR_GRADUACAO';

  final bool ativo;
  final String modeloPadrao;
  final List<AssinaturaCertificadoEvento> assinaturas;
  final bool usarCidadeDoEvento;
  final bool usarDataDoEvento;

  /// Configuração visual dinâmica dos textos do certificado.
  ///
  /// Chaves principais:
  /// - nome
  /// - cpf
  /// - graduacao
  /// - frase
  /// - assinatura_nome
  /// - assinatura_apelido
  /// - local_data
  ///
  /// Essa estrutura é salva dentro de `configuracoes_certificado.textos`
  /// no Firestore. Se algum campo não existir, o sistema usa o padrão atual.
  final Map<String, CertificadoTextoCampoConfig> textos;

  const ConfiguracoesCertificadoEvento({
    required this.ativo,
    required this.modeloPadrao,
    required this.assinaturas,
    required this.usarCidadeDoEvento,
    required this.usarDataDoEvento,
    this.textos = CertificadoTextoCampoConfig.defaults,
  });

  factory ConfiguracoesCertificadoEvento.padrao() {
    return const ConfiguracoesCertificadoEvento(
      ativo: true,
      modeloPadrao: modeloAutomatico,
      usarCidadeDoEvento: true,
      usarDataDoEvento: true,
      textos: CertificadoTextoCampoConfig.defaults,
      assinaturas: [
        AssinaturaCertificadoEvento(
          nome: 'ALTAIR ALVES BARROSO',
          apelido: 'MESTRE GRILO',
        ),
        AssinaturaCertificadoEvento(
          nome: 'LAURO FELIPE ALMEIDA DIAS',
          apelido: 'CM. BARRÃOZINHO',
        ),
        AssinaturaCertificadoEvento(
          nome: 'WARLEY VINICIUS LIMA CRUZ',
          apelido: 'PROFESSOR SCORPION',
        ),
        AssinaturaCertificadoEvento(
          nome: 'JOÃO LUCAS SILVA RABELO',
          apelido: 'PROFESSOR TICO-TICO',
        ),
        AssinaturaCertificadoEvento(
          nome: 'JOÃO PAULO SILVA OLIVEIRA',
          apelido: 'INSTRUTOR BODE',
        ),
      ],
    );
  }

  factory ConfiguracoesCertificadoEvento.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return ConfiguracoesCertificadoEvento.padrao();
    }

    final rawAssinaturas = map['assinaturas'];

    List<AssinaturaCertificadoEvento> assinaturas = [];
    if (rawAssinaturas is List) {
      assinaturas = rawAssinaturas
          .whereType<Map>()
          .map(
            (item) => AssinaturaCertificadoEvento.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    }

    final rawTextos =
        map['textos'] ??
        map['config_textos'] ??
        map['configuracoes_texto'] ??
        map['texto_config'];

    return ConfiguracoesCertificadoEvento(
      ativo: map['ativo'] ?? map['usar_configuracao_personalizada'] ?? true,
      modeloPadrao: map['modelo_padrao']?.toString() ?? modeloAutomatico,
      usarCidadeDoEvento: map['usar_cidade_do_evento'] ?? true,
      usarDataDoEvento: map['usar_data_do_evento'] ?? true,
      assinaturas: assinaturas.isEmpty
          ? ConfiguracoesCertificadoEvento.padrao().assinaturas
          : assinaturas,
      textos: CertificadoTextoCampoConfig.mergeWithDefaults(rawTextos),
    );
  }

  ConfiguracoesCertificadoEvento copyWith({
    bool? ativo,
    String? modeloPadrao,
    List<AssinaturaCertificadoEvento>? assinaturas,
    bool? usarCidadeDoEvento,
    bool? usarDataDoEvento,
    Map<String, CertificadoTextoCampoConfig>? textos,
  }) {
    return ConfiguracoesCertificadoEvento(
      ativo: ativo ?? this.ativo,
      modeloPadrao: modeloPadrao ?? this.modeloPadrao,
      assinaturas: assinaturas ?? this.assinaturas,
      usarCidadeDoEvento: usarCidadeDoEvento ?? this.usarCidadeDoEvento,
      usarDataDoEvento: usarDataDoEvento ?? this.usarDataDoEvento,
      textos: textos ?? this.textos,
    );
  }

  List<AssinaturaCertificadoEvento> get assinaturasValidas {
    return assinaturas
        .where((item) => item.nome.trim().isNotEmpty)
        .take(5)
        .toList();
  }

  CertificadoTextoCampoConfig textoConfig(String campo) {
    return textos[campo] ??
        CertificadoTextoCampoConfig.defaults[campo] ??
        CertificadoTextoCampoConfig.padraoGenerico;
  }

  Map<String, dynamic> toMap() {
    return {
      'ativo': ativo,
      'modelo_padrao': modeloPadrao,
      'usar_cidade_do_evento': usarCidadeDoEvento,
      'usar_data_do_evento': usarDataDoEvento,
      'assinaturas': assinaturasValidas.map((e) => e.toMap()).toList(),
      'textos': textos.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}

@immutable
class CertificadoTextoCampoConfig {
  static const String campoNome = 'nome';
  static const String campoCpf = 'cpf';
  static const String campoGraduacao = 'graduacao';
  static const String campoFrase = 'frase';
  static const String campoAssinaturaNome = 'assinatura_nome';
  static const String campoAssinaturaApelido = 'assinatura_apelido';
  static const String campoLocalData = 'local_data';

  static const List<String> fontesDisponiveis = [
    'Arial',
    'ArialBold',
    'ArialItalic',
    'ArialBoldItalic',
    'ArialNarrow',
    'ArialNarrowBold',
    'ArialBlack',
    'ArialRounded',
    'EngraversGothicBT',
    'Square721BT',
    'Square721BTBold',
    'Square721CnBT',
    'Square721CnBTBold',
    'Autography',
    'PhotographSignature',
    'Bigtimes',
    'AngelinaMalika',
  ];

  static const List<String> alinhamentosDisponiveis = [
    'left',
    'center',
    'right',
  ];

  final String fonte;
  final double tamanho;
  final String corHex;
  final String alinhamento;
  final double lineHeight;

  /// Deslocamento vertical do texto dentro da caixa-guia, em milímetros.
  /// 0.0 é o padrão de fábrica. Valores negativos sobem, positivos descem.
  final double verticalOffsetMm;

  /// upper = MAIÚSCULAS
  /// lower = minúsculas
  /// title = Iniciais Maiúsculas
  /// none = mantém como veio
  final String textCase;
  final bool uppercase;
  final bool negrito;
  final bool autoAjustar;

  const CertificadoTextoCampoConfig({
    required this.fonte,
    required this.tamanho,
    required this.corHex,
    required this.alinhamento,
    required this.lineHeight,
    this.verticalOffsetMm = 0.0,
    this.textCase = 'upper',
    required this.uppercase,
    required this.negrito,
    required this.autoAjustar,
  });

  static const CertificadoTextoCampoConfig padraoGenerico =
      CertificadoTextoCampoConfig(
        fonte: 'Arial',
        tamanho: 15.0,
        corHex: '#1A0202',
        alinhamento: 'center',
        lineHeight: 1.0,
        uppercase: true,
        negrito: false,
        autoAjustar: true,
      );

  static const Map<String, CertificadoTextoCampoConfig> defaults = {
    campoNome: CertificadoTextoCampoConfig(
      fonte: 'Arial',
      tamanho: 20.0,
      corHex: '#1A0202',
      alinhamento: 'center',
      lineHeight: 1.0,
      uppercase: true,
      negrito: true,
      autoAjustar: true,
    ),
    campoCpf: CertificadoTextoCampoConfig(
      fonte: 'Arial',
      tamanho: 12.0,
      corHex: '#1A0202',
      alinhamento: 'left',
      lineHeight: 1.0,
      uppercase: true,
      negrito: true,
      autoAjustar: true,
    ),
    campoGraduacao: CertificadoTextoCampoConfig(
      fonte: 'Arial',
      tamanho: 16.0,
      corHex: '#1A0202',
      alinhamento: 'left',
      lineHeight: 1.0,
      uppercase: true,
      negrito: true,
      autoAjustar: true,
    ),
    campoFrase: CertificadoTextoCampoConfig(
      fonte: 'EngraversGothicBT',
      tamanho: 15.0,
      corHex: '#1A0202',
      alinhamento: 'center',
      lineHeight: 1.22,
      uppercase: true,
      negrito: false,
      autoAjustar: false,
    ),
    campoAssinaturaNome: CertificadoTextoCampoConfig(
      fonte: 'Arial',
      tamanho: 15.0,
      corHex: '#1A0202',
      alinhamento: 'center',
      lineHeight: 1.0,
      uppercase: true,
      negrito: false,
      autoAjustar: true,
    ),
    campoAssinaturaApelido: CertificadoTextoCampoConfig(
      fonte: 'Arial',
      tamanho: 11.5,
      corHex: '#1A0202',
      alinhamento: 'center',
      lineHeight: 1.0,
      uppercase: true,
      negrito: false,
      autoAjustar: true,
    ),
    campoLocalData: CertificadoTextoCampoConfig(
      fonte: 'Square721BTBold',
      tamanho: 10.5,
      corHex: '#1A0202',
      alinhamento: 'center',
      lineHeight: 1.0,
      uppercase: true,
      negrito: true,
      autoAjustar: true,
    ),
  };

  factory CertificadoTextoCampoConfig.fromMap(
    Map<String, dynamic>? map, {
    CertificadoTextoCampoConfig fallback = padraoGenerico,
  }) {
    if (map == null || map.isEmpty) return fallback;

    return CertificadoTextoCampoConfig(
      fonte: _asString(map['fonte'], fallback.fonte),
      tamanho: _normalizarTamanhoPt(
        _asDouble(map['tamanho'], fallback.tamanho),
      ),
      corHex: _normalizarHex(_asString(map['cor'], fallback.corHex)),
      alinhamento: _normalizarAlinhamento(
        _asString(map['alinhamento'], fallback.alinhamento),
      ),
      lineHeight: _asDouble(
        map['lineHeight'] ?? map['line_height'] ?? map['espacamento_linhas'],
        fallback.lineHeight,
      ),
      verticalOffsetMm: _asDouble(
        map['verticalOffsetMm'] ??
            map['vertical_offset_mm'] ??
            map['topOffsetMm'] ??
            map['offsetY'] ??
            map['yOffset'],
        fallback.verticalOffsetMm,
      ),
      textCase: _normalizarTextCase(
        _asString(
          map['textCase'] ??
              map['text_case'] ??
              map['caixaTexto'] ??
              map['caixa_texto'],
          fallback.textCase,
        ),
      ),
      uppercase: _asBool(map['uppercase'], fallback.uppercase),
      negrito: _asBool(map['negrito'] ?? map['bold'], fallback.negrito),
      autoAjustar: _asBool(
        map['autoAjustar'] ?? map['auto_ajustar'],
        fallback.autoAjustar,
      ),
    );
  }

  static Map<String, CertificadoTextoCampoConfig> mergeWithDefaults(
    dynamic raw,
  ) {
    final merged = Map<String, CertificadoTextoCampoConfig>.from(defaults);

    if (raw is Map) {
      final rawMap = Map<String, dynamic>.from(raw);

      for (final entry in rawMap.entries) {
        final key = entry.key.toString();
        final fallback = merged[key] ?? padraoGenerico;

        if (entry.value is Map) {
          merged[key] = CertificadoTextoCampoConfig.fromMap(
            Map<String, dynamic>.from(entry.value as Map),
            fallback: fallback,
          );
        }
      }
    }

    return merged;
  }

  CertificadoTextoCampoConfig copyWith({
    String? fonte,
    double? tamanho,
    String? corHex,
    String? alinhamento,
    double? lineHeight,
    double? verticalOffsetMm,
    String? textCase,
    bool? uppercase,
    bool? negrito,
    bool? autoAjustar,
  }) {
    return CertificadoTextoCampoConfig(
      fonte: fonte ?? this.fonte,
      tamanho: tamanho ?? this.tamanho,
      corHex: corHex ?? this.corHex,
      alinhamento: alinhamento ?? this.alinhamento,
      lineHeight: lineHeight ?? this.lineHeight,
      verticalOffsetMm: verticalOffsetMm ?? this.verticalOffsetMm,
      textCase: textCase ?? this.textCase,
      uppercase: uppercase ?? this.uppercase,
      negrito: negrito ?? this.negrito,
      autoAjustar: autoAjustar ?? this.autoAjustar,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fonte': fonte,
      'tamanho': tamanho,
      'cor': corHex,
      'alinhamento': alinhamento,
      'lineHeight': lineHeight,
      'verticalOffsetMm': verticalOffsetMm,
      'topOffsetMm': verticalOffsetMm,
      'textCase': textCase,
      'uppercase': uppercase,
      'negrito': negrito,
      'autoAjustar': autoAjustar,
    };
  }

  String aplicarCaixa(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';

    switch (textCase) {
      case 'lower':
        return clean.toLowerCase();
      case 'title':
        return _toTitleCase(clean);
      case 'none':
        return clean;
      case 'upper':
      default:
        // Mantém compatibilidade: se algum dado antigo vier com uppercase=false,
        // respeita o antigo como "original".
        return uppercase ? clean.toUpperCase() : clean;
    }
  }

  static String _toTitleCase(String value) {
    final lower = value.toLowerCase();

    return lower.replaceAllMapped(
      RegExp(r'(^|[\s\-/])([a-záàâãäéèêëíìîïóòôõöúùûüç])'),
      (match) {
        final prefix = match.group(1) ?? '';
        final letter = match.group(2) ?? '';
        return '$prefix${letter.toUpperCase()}';
      },
    );
  }

  static String _normalizarTextCase(String value) {
    final clean = value.trim().toLowerCase();

    if (clean == 'lower' ||
        clean == 'minusculo' ||
        clean == 'minúsculo' ||
        clean == 'minuscula' ||
        clean == 'minúscula') {
      return 'lower';
    }

    if (clean == 'title' ||
        clean == 'iniciais' ||
        clean == 'capitalizado' ||
        clean == 'capitalize') {
      return 'title';
    }

    if (clean == 'none' || clean == 'original' || clean == 'normal') {
      return 'none';
    }

    return 'upper';
  }

  static double _normalizarTamanhoPt(double value) {
    // Compatibilidade com a primeira versão do Certificado 2.0:
    // valores visuais antigos ficavam entre 3 e 8; agora o painel usa pt real.
    if (value > 0 && value < 9.0) return value * 3.0;
    return value;
  }

  static String _asString(dynamic value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static double _asDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();

    final text = value?.toString().replaceAll(',', '.').trim();
    if (text == null || text.isEmpty) return fallback;

    return double.tryParse(text) ?? fallback;
  }

  static bool _asBool(dynamic value, bool fallback) {
    if (value is bool) return value;

    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return fallback;

    if (text == 'true' || text == '1' || text == 'sim' || text == 'yes') {
      return true;
    }

    if (text == 'false' || text == '0' || text == 'nao' || text == 'não') {
      return false;
    }

    return fallback;
  }

  static String _normalizarHex(String value) {
    final clean = value.trim().toUpperCase();

    if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(clean)) return clean;

    final withoutHash = clean.replaceAll('#', '');
    if (RegExp(r'^[0-9A-F]{6}$').hasMatch(withoutHash)) {
      return '#$withoutHash';
    }

    return '#1A0202';
  }

  static String _normalizarAlinhamento(String value) {
    final clean = value.trim().toLowerCase();

    if (clean == 'left' || clean == 'esquerda' || clean == 'start') {
      return 'left';
    }

    if (clean == 'right' || clean == 'direita' || clean == 'end') {
      return 'right';
    }

    return 'center';
  }
}

@immutable
class AssinaturaCertificadoEvento {
  final String nome;
  final String apelido;

  const AssinaturaCertificadoEvento({
    required this.nome,
    required this.apelido,
  });

  factory AssinaturaCertificadoEvento.fromMap(Map<String, dynamic> map) {
    return AssinaturaCertificadoEvento(
      nome: map['nome']?.toString() ?? '',
      apelido:
          map['apelido']?.toString() ??
          map['titulo']?.toString() ??
          map['cargo']?.toString() ??
          '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': nome.trim().toUpperCase(),
      'apelido': apelido.trim().toUpperCase(),
    };
  }
}
