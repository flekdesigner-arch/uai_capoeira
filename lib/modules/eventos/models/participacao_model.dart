import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ParticipacaoModel {
  // ───────────────────── DADOS BÁSICOS ─────────────────────
  final String? id;
  final String alunoId;
  final String alunoNome;
  final String? alunoFoto;
  final String eventoId;
  final String eventoNome;
  final DateTime dataEvento;
  final String tipoEvento;
  final String? graduacao;
  final String? graduacaoId;
  final String? tamanhoCamisa;
  final String? linkCertificado;
  final bool presente;
  final String status; // 'pendente', 'quitado', 'finalizado'
  final Timestamp? criadoEm;
  final Timestamp? atualizadoEm;

  // ───────────────────── BATIZADO / GRADUAÇÃO ─────────────────────
  final String? graduacaoNova;
  final String? graduacaoNovaId;

  // ───────────────────── CAMISA ─────────────────────
  final bool camisaEntregue;

  /// Modelagem da camisa.
  ///
  /// Valores esperados:
  /// - NORMAL
  /// - BABY_LOOK
  ///
  /// Regra de compatibilidade:
  /// Participações antigas sem esse campo serão tratadas como NORMAL.
  final String modelagemCamisa;

  /// Tipo da camisa.
  ///
  /// Valores esperados:
  /// - MANGA
  /// - MANGA_LONGA
  /// - REGATA
  ///
  /// Regra de compatibilidade:
  /// Participações antigas sem esse campo serão tratadas como MANGA.
  final String tipoCamisa;

  // ───────────────────── FINANCEIRO ─────────────────────
  final double valorInscricao;
  final double valorCamisa;
  final double totalPago;

  // ───────────────────── CONSTANTES ─────────────────────
  static const String modelagemNormal = 'NORMAL';
  static const String modelagemBabyLook = 'BABY_LOOK';

  static const String tipoManga = 'MANGA';
  static const String tipoMangaLonga = 'MANGA_LONGA';
  static const String tipoRegata = 'REGATA';

  ParticipacaoModel({
    this.id,
    required this.alunoId,
    required this.alunoNome,
    this.alunoFoto,
    required this.eventoId,
    required this.eventoNome,
    required this.dataEvento,
    required this.tipoEvento,
    this.graduacao,
    this.graduacaoId,
    this.tamanhoCamisa,
    this.linkCertificado,
    this.presente = false,
    this.status = 'pendente',
    this.criadoEm,
    this.atualizadoEm,
    this.graduacaoNova,
    this.graduacaoNovaId,
    this.camisaEntregue = false,
    this.modelagemCamisa = modelagemNormal,
    this.tipoCamisa = tipoManga,
    this.valorInscricao = 0,
    this.valorCamisa = 0,
    this.totalPago = 0,
  });

  // ───────────────────── GETTERS FINANCEIROS ─────────────────────

  double get valorTotal => valorInscricao + valorCamisa;

  bool get estaQuitado => totalPago >= valorTotal;

  double get saldoDevedor => valorTotal - totalPago;

  int get parcelas {
    // TODO: Implementar lógica real de parcelas baseada no evento, se necessário.
    return 1;
  }

  // ───────────────────── GETTERS DE DATA / STATUS ─────────────────────

  String get dataFormatada {
    final DateFormat formatter = DateFormat('dd/MM/yyyy');
    return formatter.format(dataEvento);
  }

  bool get isBatizado => tipoEvento.toUpperCase().contains('BATIZADO');

  bool get aguardandoFinalizacao =>
      isBatizado && status == 'pendente' && graduacaoNova != null;

  bool get estaFinalizado => status == 'finalizado';

  Color get corStatus {
    switch (status) {
      case 'finalizado':
        return Colors.green;
      case 'quitado':
        return Colors.blue;
      case 'pendente':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String get textoStatus {
    switch (status) {
      case 'finalizado':
        return '✅ FINALIZADO';
      case 'quitado':
        return '💰 QUITADO';
      case 'pendente':
        return '⏳ PENDENTE';
      default:
        return status.toUpperCase();
    }
  }

  // ───────────────────── GETTERS DE CAMISA ─────────────────────

  bool get temCamisaSelecionada =>
      tamanhoCamisa != null && tamanhoCamisa!.trim().isNotEmpty;

  bool get isBabyLook => modelagemCamisa == modelagemBabyLook;

  bool get isMangaLonga => tipoCamisa == tipoMangaLonga;

  bool get isRegata => tipoCamisa == tipoRegata;

  String get modelagemCamisaLabel {
    switch (modelagemCamisa) {
      case modelagemBabyLook:
        return 'Baby Look';
      case modelagemNormal:
      default:
        return 'Normal';
    }
  }

  String get tipoCamisaLabel {
    switch (tipoCamisa) {
      case tipoMangaLonga:
        return 'Manga Longa';
      case tipoRegata:
        return 'Regata';
      case tipoManga:
      default:
        return 'Manga';
    }
  }

  String get descricaoCamisa {
    final tamanho = tamanhoCamisa?.trim();

    if (tamanho == null || tamanho.isEmpty) {
      return 'Sem camisa';
    }

    return '$modelagemCamisaLabel • $tipoCamisaLabel • $tamanho';
  }

  // ───────────────────── SERIALIZAÇÃO ─────────────────────

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'aluno_id': alunoId,
      'aluno_nome': alunoNome,
      'aluno_foto': alunoFoto,
      'evento_id': eventoId,
      'evento_nome': eventoNome,
      'data_evento': Timestamp.fromDate(dataEvento),
      'tipo_evento': tipoEvento,
      'graduacao': graduacao,
      'graduacao_id': graduacaoId,
      'tamanho_camisa': tamanhoCamisa,
      'modelagem_camisa': _normalizarModelagem(modelagemCamisa),
      'tipo_camisa': _normalizarTipoCamisa(tipoCamisa),
      'link_certificado': linkCertificado,
      'presente': presente,
      'status': status,
      'criado_em': criadoEm ?? FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
      'camisa_entregue': camisaEntregue,
      'valor_inscricao': valorInscricao,
      'valor_camisa': valorCamisa,
      'total_pago': totalPago,
    };

    if (graduacaoNova != null) {
      map['graduacao_nova'] = graduacaoNova;
    }

    if (graduacaoNovaId != null) {
      map['graduacao_nova_id'] = graduacaoNovaId;
    }

    return map;
  }

  factory ParticipacaoModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return ParticipacaoModel.fromMap(doc.id, data);
  }

  factory ParticipacaoModel.fromMap(String id, Map<String, dynamic> map) {
    final dataEvento = _converterDataEvento(map['data_evento']);

    return ParticipacaoModel(
      id: id,
      alunoId: _asString(map['aluno_id']),
      alunoNome: _asString(map['aluno_nome']),
      alunoFoto: _nullableString(map['aluno_foto']),
      eventoId: _asString(map['evento_id']),
      eventoNome: _asString(map['evento_nome']),
      dataEvento: dataEvento,
      tipoEvento: _asString(map['tipo_evento'], fallback: 'EVENTO'),
      graduacao: _nullableString(map['graduacao']),
      graduacaoId: _nullableString(map['graduacao_id']),
      tamanhoCamisa: _nullableString(
        map['tamanho_camisa'] ?? map['tamanhoCamisa'],
      ),
      modelagemCamisa: _normalizarModelagem(
        map['modelagem_camisa'] ??
            map['modelagemCamisa'] ??
            map['modelagem'] ??
            modelagemNormal,
      ),
      tipoCamisa: _normalizarTipoCamisa(
        map['tipo_camisa'] ??
            map['tipoCamisa'] ??
            map['tipo'] ??
            tipoManga,
      ),
      linkCertificado: _nullableString(
        map['link_certificado'] ??
            map['linkCertificado'] ??
            map['certificado_url'] ??
            map['certificadoUrl'] ??
            map['url_certificado'] ??
            map['urlCertificado'],
      ),
      presente: map['presente'] == true,
      status: _asString(map['status'], fallback: 'pendente'),
      criadoEm: map['criado_em'] is Timestamp ? map['criado_em'] as Timestamp : null,
      atualizadoEm: map['atualizado_em'] is Timestamp
          ? map['atualizado_em'] as Timestamp
          : null,
      graduacaoNova: _nullableString(map['graduacao_nova']),
      graduacaoNovaId: _nullableString(map['graduacao_nova_id']),
      camisaEntregue: map['camisa_entregue'] == true,
      valorInscricao: _asDouble(map['valor_inscricao']),
      valorCamisa: _asDouble(map['valor_camisa']),
      totalPago: _asDouble(map['total_pago']),
    );
  }

  ParticipacaoModel copyWith({
    String? id,
    String? alunoId,
    String? alunoNome,
    String? alunoFoto,
    String? eventoId,
    String? eventoNome,
    DateTime? dataEvento,
    String? tipoEvento,
    String? graduacao,
    String? graduacaoId,
    String? tamanhoCamisa,
    String? modelagemCamisa,
    String? tipoCamisa,
    String? linkCertificado,
    bool? presente,
    String? status,
    Timestamp? criadoEm,
    Timestamp? atualizadoEm,
    String? graduacaoNova,
    String? graduacaoNovaId,
    bool? camisaEntregue,
    double? valorInscricao,
    double? valorCamisa,
    double? totalPago,
  }) {
    return ParticipacaoModel(
      id: id ?? this.id,
      alunoId: alunoId ?? this.alunoId,
      alunoNome: alunoNome ?? this.alunoNome,
      alunoFoto: alunoFoto ?? this.alunoFoto,
      eventoId: eventoId ?? this.eventoId,
      eventoNome: eventoNome ?? this.eventoNome,
      dataEvento: dataEvento ?? this.dataEvento,
      tipoEvento: tipoEvento ?? this.tipoEvento,
      graduacao: graduacao ?? this.graduacao,
      graduacaoId: graduacaoId ?? this.graduacaoId,
      tamanhoCamisa: tamanhoCamisa ?? this.tamanhoCamisa,
      modelagemCamisa: _normalizarModelagem(
        modelagemCamisa ?? this.modelagemCamisa,
      ),
      tipoCamisa: _normalizarTipoCamisa(
        tipoCamisa ?? this.tipoCamisa,
      ),
      linkCertificado: linkCertificado ?? this.linkCertificado,
      presente: presente ?? this.presente,
      status: status ?? this.status,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      graduacaoNova: graduacaoNova ?? this.graduacaoNova,
      graduacaoNovaId: graduacaoNovaId ?? this.graduacaoNovaId,
      camisaEntregue: camisaEntregue ?? this.camisaEntregue,
      valorInscricao: valorInscricao ?? this.valorInscricao,
      valorCamisa: valorCamisa ?? this.valorCamisa,
      totalPago: totalPago ?? this.totalPago,
    );
  }

  // ───────────────────── HELPERS ─────────────────────

  static DateTime _converterDataEvento(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        try {
          final partes = value.split('/');
          if (partes.length == 3) {
            return DateTime(
              int.parse(partes[2]),
              int.parse(partes[1]),
              int.parse(partes[0]),
            );
          }
        } catch (_) {
          return DateTime.now();
        }
      }
    }

    return DateTime.now();
  }

  static String _asString(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 0;

    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  static String _normalizarModelagem(dynamic value) {
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

  @override
  String toString() {
    return 'ParticipacaoModel('
        'id: $id, '
        'aluno: $alunoNome, '
        'evento: $eventoNome, '
        'status: $status, '
        'camisa: $descricaoCamisa, '
        'valor: R\$ ${valorTotal.toStringAsFixed(2)}'
        ')';
  }
}