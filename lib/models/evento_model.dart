import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventoModel {
  // 📅 DADOS BÁSICOS
  final String? id;
  final String nome;
  final String descricao;  // 👈 ADICIONE ESTA LINHA!
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

  // 🌐 NOVO - PORTFÓLIO WEB
  final bool mostrarNoPortfolioWeb;

  // 📊 METADADOS
  final Timestamp? criadoEm;
  final Timestamp? atualizadoEm;

  EventoModel({
    this.id,
    required this.nome,
    required this.descricao,  // 👈 ADICIONE AQUI TAMBÉM!
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

  // 🔥 Construtor para criar a partir do Firestore
  factory EventoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // 🔥 TRATAMENTO DA DATA
    DateTime dataEvento;
    if (data['data'] is Timestamp) {
      dataEvento = (data['data'] as Timestamp).toDate();
    } else if (data['data'] is String) {
      try {
        final partes = data['data'].split('/');
        dataEvento = DateTime(
          int.parse(partes[2]),
          int.parse(partes[1]),
          int.parse(partes[0]),
        );
      } catch (e) {
        dataEvento = DateTime.now();
        print('⚠️ Erro ao converter data: $e');
      }
    } else {
      dataEvento = DateTime.now();
    }

    // 🔥 TRATAMENTO DOS ORGANIZADORES
    List<String> organizadoresList = [];
    if (data['organizadores'] != null) {
      if (data['organizadores'] is List) {
        organizadoresList = List<String>.from(data['organizadores']);
      } else if (data['organizadores'] is String) {
        final String orgString = data['organizadores'] as String;
        if (orgString.isNotEmpty) {
          organizadoresList = orgString
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
    }

    return EventoModel(
      id: doc.id,
      nome: data['nome'] ?? '',
      descricao: data['descricao'] ?? '',  // 👈 ADICIONE AQUI!
      tipo: data['tipo'] ?? data['tipo_evento'] ?? '',
      data: dataEvento,
      horario: data['horario'] ?? '',
      local: data['local'] ?? '',
      cidade: data['cidade'] ?? '',
      organizadores: organizadoresList,
      status: data['status'] ?? 'andamento',

      // Taxas
      valorInscricao: (data['valorInscricao'] as num?)?.toDouble() ?? 0,
      permiteParcelamento: data['permiteParcelamento'] ?? false,
      maxParcelas: data['maxParcelas'] ?? 1,
      descontoAVista: data['descontoAVista'] ?? 0,
      dataLimitePrimeiraParcela: data['dataLimitePrimeiraParcela'] != null
          ? (data['dataLimitePrimeiraParcela'] as Timestamp).toDate()
          : null,

      // Camisa
      temCamisa: data['temCamisa'] ?? false,
      valorCamisa: (data['valorCamisa'] as num?)?.toDouble(),
      tamanhosDisponiveis: List<String>.from(data['tamanhosDisponiveis'] ?? []),
      camisaObrigatoria: data['camisaObrigatoria'] ?? false,

      // Regras
      alteraGraduacao: data['alteraGraduacao'] ?? false,
      geraCertificado: data['geraCertificado'] ?? false,
      tipoPublico: data['tipoPublico'],

      // Links
      linkBanner: data['linkBanner'] ?? data['link_banner'],
      linkFotosVideos: data['linkFotosVideos'] ?? data['link_fotos_videos'],
      previaVideo: data['previaVideo'] ?? data['previa_video'],
      linkPlaylist: data['linkPlaylist'] ?? data['link_playlist'],

      // Certificado
      temCertificado: data['tem_certificado'] ?? false,
      modeloCertificadoId: data['modelo_certificado_id'],
      modeloCertificadoPath: data['modelo_certificado_path'],
      configuracoesCertificado: data['configuracoes_certificado'] != null
          ? Map<String, dynamic>.from(data['configuracoes_certificado'])
          : null,

      // 🌐 PORTFÓLIO WEB
      mostrarNoPortfolioWeb: data['mostrarNoPortfolioWeb'] ?? false,

      // Metadados
      criadoEm: data['criado_em'] as Timestamp?,
      atualizadoEm: data['atualizado_em'] as Timestamp?,
    );
  }

  // 🔥 Converter para Map (para salvar no Firestore)
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nome': nome,
      'descricao': descricao,  // 👈 ADICIONE AQUI!
      'tipo': tipo,
      'data': Timestamp.fromDate(data),
      'horario': horario,
      'local': local,
      'cidade': cidade,
      'organizadores': organizadores,
      'status': status,

      // Taxas
      'valorInscricao': valorInscricao,
      'permiteParcelamento': permiteParcelamento,
      'maxParcelas': maxParcelas,
      'descontoAVista': descontoAVista,
      if (dataLimitePrimeiraParcela != null)
        'dataLimitePrimeiraParcela': Timestamp.fromDate(dataLimitePrimeiraParcela!),

      // Camisa
      'temCamisa': temCamisa,
      if (valorCamisa != null) 'valorCamisa': valorCamisa,
      'tamanhosDisponiveis': tamanhosDisponiveis,
      'camisaObrigatoria': camisaObrigatoria,

      // Regras
      'alteraGraduacao': alteraGraduacao,
      'geraCertificado': geraCertificado,
      if (tipoPublico != null) 'tipoPublico': tipoPublico,

      // Links
      if (linkBanner != null) 'linkBanner': linkBanner,
      if (linkFotosVideos != null) 'linkFotosVideos': linkFotosVideos,
      if (previaVideo != null) 'previaVideo': previaVideo,
      if (linkPlaylist != null) 'linkPlaylist': linkPlaylist,

      // Certificado
      'tem_certificado': temCertificado,
      'modelo_certificado_id': modeloCertificadoId,
      'modelo_certificado_path': modeloCertificadoPath,
      if (configuracoesCertificado != null)
        'configuracoes_certificado': configuracoesCertificado,

      // 🌐 PORTFÓLIO WEB
      'mostrarNoPortfolioWeb': mostrarNoPortfolioWeb,

      // Metadados
      'atualizado_em': FieldValue.serverTimestamp(),
    };

    if (id == null) {
      map['criado_em'] = FieldValue.serverTimestamp();
    }

    return map;
  }

  // 🔥 Métodos auxiliares
  String get dataFormatada {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }

  bool get isBatizado => tipo.contains('BATIZADO');
  bool get isConfraternizacao => tipo.contains('CONFRATERNIZAÇÃO');
  bool get isForaCidade => tipo.contains('OUTRA CIDADE');
  bool get isDestaque => tipo.contains('DESTAQUE');

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
    return Colors.grey;
  }

  IconData get iconeDoTipo {
    if (isBatizado) return Icons.emoji_events;
    if (isConfraternizacao) return Icons.celebration;
    if (isForaCidade) return Icons.bus_alert;
    if (isDestaque) return Icons.star;
    return Icons.event;
  }

  // 🔥 MÉTODOS AUXILIARES PARA CERTIFICADO
  bool get temConfiguracaoCertificadoCompleta {
    if (!temCertificado) return false;
    return configuracoesCertificado != null && configuracoesCertificado!.isNotEmpty;
  }

  bool certificadoConfigurado(String tipo) {
    if (!temCertificado || configuracoesCertificado == null) return false;

    switch (tipo) {
      case 'CERTIFICADO':
        return configuracoesCertificado!.containsKey('certificado_padrao');
      case 'CERTIFICADOCOMCPF':
        return configuracoesCertificado!.containsKey('certificado_com_cpf');
      case 'DIPLOMA':
        return configuracoesCertificado!.containsKey('diploma');
      default:
        return false;
    }
  }

  Map<String, dynamic>? getConfiguracaoCertificado(String tipo) {
    if (!temCertificado || configuracoesCertificado == null) return null;

    switch (tipo) {
      case 'CERTIFICADO':
        return configuracoesCertificado!['certificado_padrao'];
      case 'CERTIFICADOCOMCPF':
        return configuracoesCertificado!['certificado_com_cpf'];
      case 'DIPLOMA':
        return configuracoesCertificado!['diploma'];
      default:
        return null;
    }
  }

  int get quantidadeCertificadosConfigurados {
    if (!temCertificado || configuracoesCertificado == null) return 0;

    int count = 0;
    if (configuracoesCertificado!.containsKey('certificado_padrao')) count++;
    if (configuracoesCertificado!.containsKey('certificado_com_cpf')) count++;
    if (configuracoesCertificado!.containsKey('diploma')) count++;
    return count;
  }

  String? get caminhoCompletoCertificado {
    if (modeloCertificadoPath == null) return null;
    return 'assets/images/certificados/${modeloCertificadoPath}';
  }

  // 🔥 Método de compatibilidade
  Map<String, String> get configuracoesCertificadoPadrao {
    if (configuracoesCertificado == null) return {};

    try {
      return Map<String, String>.from(configuracoesCertificado!);
    } catch (e) {
      return {};
    }
  }

  bool certificadoValidoParaTipo(String tipoCertificado) {
    if (!temCertificado) return false;
    return certificadoConfigurado(tipoCertificado);
  }
}