import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventoModel {
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
  final List<String> tamanhosDisponiveis;
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
    required this.tamanhosDisponiveis,
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

      valorInscricao: (data['valorInscricao'] as num?)?.toDouble() ??
          (data['valor_inscricao'] as num?)?.toDouble() ??
          0,
      permiteParcelamento: data['permiteParcelamento'] ??
          data['permite_parcelamento'] ??
          false,
      maxParcelas: (data['maxParcelas'] as num?)?.toInt() ??
          (data['max_parcelas'] as num?)?.toInt() ??
          1,
      descontoAVista: (data['descontoAVista'] as num?)?.toInt() ??
          (data['desconto_a_vista'] as num?)?.toInt() ??
          0,
      dataLimitePrimeiraParcela:
      _timestampToDateTime(data['dataLimitePrimeiraParcela']) ??
          _timestampToDateTime(data['data_limite_primeira_parcela']),

      temCamisa: data['temCamisa'] ?? data['tem_camisa'] ?? false,
      valorCamisa: (data['valorCamisa'] as num?)?.toDouble() ??
          (data['valor_camisa'] as num?)?.toDouble(),
      tamanhosDisponiveis: List<String>.from(
        data['tamanhosDisponiveis'] ?? data['tamanhos_disponiveis'] ?? [],
      ),
      camisaObrigatoria:
      data['camisaObrigatoria'] ?? data['camisa_obrigatoria'] ?? false,

      alteraGraduacao: data['alteraGraduacao'] ??
          data['altera_graduacao'] ??
          false,
      geraCertificado: data['geraCertificado'] ??
          data['gera_certificado'] ??
          false,
      tipoPublico: data['tipoPublico'] ?? data['tipo_publico'],

      linkBanner: data['linkBanner'] ?? data['link_banner'],
      linkFotosVideos: data['linkFotosVideos'] ?? data['link_fotos_videos'],
      previaVideo: data['previaVideo'] ?? data['previa_video'],
      linkPlaylist: data['linkPlaylist'] ?? data['link_playlist'],

      temCertificado:
      data['tem_certificado'] ?? data['temCertificado'] ?? false,
      modeloCertificadoId: (data['modelo_certificado_id'] ??
          data['modeloCertificadoId'] ??
          ConfiguracoesCertificadoEvento.modeloAutomatico)
          ?.toString(),
      modeloCertificadoPath:
      data['modelo_certificado_path'] ?? data['modeloCertificadoPath'],
      configuracoesCertificado: configCertificadoRaw is Map
          ? Map<String, dynamic>.from(configCertificadoRaw)
          : null,

      mostrarNoPortfolioWeb:
      data['mostrarNoPortfolioWeb'] ?? data['mostrar_no_portfolio_web'] ?? false,

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
        'dataLimitePrimeiraParcela':
        Timestamp.fromDate(dataLimitePrimeiraParcela!),

      'temCamisa': temCamisa,
      if (valorCamisa != null) 'valorCamisa': valorCamisa,
      'tamanhosDisponiveis': tamanhosDisponiveis,
      'camisaObrigatoria': camisaObrigatoria,

      'alteraGraduacao': alteraGraduacao,
      'geraCertificado': geraCertificado,
      if (tipoPublico != null) 'tipoPublico': tipoPublico,

      if (linkBanner != null) 'linkBanner': linkBanner,
      if (linkFotosVideos != null) 'linkFotosVideos': linkFotosVideos,
      if (previaVideo != null) 'previaVideo': previaVideo,
      if (linkPlaylist != null) 'linkPlaylist': linkPlaylist,

      'tem_certificado': temCertificado,
      'modelo_certificado_id': modeloCertificadoId ??
          ConfiguracoesCertificadoEvento.modeloAutomatico,
      'modelo_certificado_path': modeloCertificadoPath,
      'configuracoes_certificado':
      temCertificado ? configuracoesCertificadoAtualizada : null,

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
    List<String>? tamanhosDisponiveis,
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
      tamanhosDisponiveis: tamanhosDisponiveis ?? this.tamanhosDisponiveis,
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

  double getValorTotal({bool comCamisa = true}) {
    double total = valorInscricao;
    if (comCamisa && temCamisa && valorCamisa != null) {
      total += valorCamisa!;
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
    return tamanhosDisponiveis.contains(tamanho);
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

  const ConfiguracoesCertificadoEvento({
    required this.ativo,
    required this.modeloPadrao,
    required this.assinaturas,
    required this.usarCidadeDoEvento,
    required this.usarDataDoEvento,
  });

  factory ConfiguracoesCertificadoEvento.padrao() {
    return const ConfiguracoesCertificadoEvento(
      ativo: true,
      modeloPadrao: modeloAutomatico,
      usarCidadeDoEvento: true,
      usarDataDoEvento: true,
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

    return ConfiguracoesCertificadoEvento(
      ativo: map['ativo'] ?? map['usar_configuracao_personalizada'] ?? true,
      modeloPadrao: map['modelo_padrao']?.toString() ?? modeloAutomatico,
      usarCidadeDoEvento: map['usar_cidade_do_evento'] ?? true,
      usarDataDoEvento: map['usar_data_do_evento'] ?? true,
      assinaturas: assinaturas.isEmpty
          ? ConfiguracoesCertificadoEvento.padrao().assinaturas
          : assinaturas,
    );
  }

  ConfiguracoesCertificadoEvento copyWith({
    bool? ativo,
    String? modeloPadrao,
    List<AssinaturaCertificadoEvento>? assinaturas,
    bool? usarCidadeDoEvento,
    bool? usarDataDoEvento,
  }) {
    return ConfiguracoesCertificadoEvento(
      ativo: ativo ?? this.ativo,
      modeloPadrao: modeloPadrao ?? this.modeloPadrao,
      assinaturas: assinaturas ?? this.assinaturas,
      usarCidadeDoEvento: usarCidadeDoEvento ?? this.usarCidadeDoEvento,
      usarDataDoEvento: usarDataDoEvento ?? this.usarDataDoEvento,
    );
  }

  List<AssinaturaCertificadoEvento> get assinaturasValidas {
    return assinaturas
        .where((item) => item.nome.trim().isNotEmpty)
        .take(5)
        .toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'ativo': ativo,
      'modelo_padrao': modeloPadrao,
      'usar_cidade_do_evento': usarCidadeDoEvento,
      'usar_data_do_evento': usarDataDoEvento,
      'assinaturas': assinaturasValidas.map((e) => e.toMap()).toList(),
    };
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
      apelido: map['apelido']?.toString() ??
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
