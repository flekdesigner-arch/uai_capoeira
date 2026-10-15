import 'package:cloud_firestore/cloud_firestore.dart';

class CacaBugEventModel {
  final String id;
  final String tipo;
  final String acao;
  final String descricao;
  final String tela;
  final String arquivo;
  final String rota;
  final String status;
  final Map<String, dynamic> dados;
  final Map<String, dynamic>? erro;
  final DateTime criadoEm;
  final int ordem;

  const CacaBugEventModel({
    required this.id,
    required this.tipo,
    required this.acao,
    required this.descricao,
    required this.tela,
    required this.arquivo,
    required this.rota,
    required this.status,
    required this.dados,
    required this.erro,
    required this.criadoEm,
    required this.ordem,
  });

  factory CacaBugEventModel.create({
    required String id,
    required String tipo,
    required String acao,
    required String descricao,
    required String tela,
    required String arquivo,
    required String rota,
    required String status,
    Map<String, dynamic>? dados,
    Map<String, dynamic>? erro,
    required int ordem,
  }) {
    return CacaBugEventModel(
      id: id,
      tipo: _safeShort(tipo, 40),
      acao: _safeShort(acao, 80),
      descricao: sanitizeText(descricao, max: 800),
      tela: _safeShort(tela, 120),
      arquivo: _safeShort(arquivo, 220),
      rota: _safeShort(rota, 180),
      status: _safeShort(status, 40),
      dados: sanitizeMap(dados ?? const {}),
      erro: erro == null ? null : sanitizeMap(erro, stackLimit: 1200),
      criadoEm: DateTime.now(),
      ordem: ordem,
    );
  }

  factory CacaBugEventModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime toDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return CacaBugEventModel(
      id: id,
      tipo: map['tipo']?.toString() ?? 'sistema',
      acao: map['acao']?.toString() ?? '',
      descricao: map['descricao']?.toString() ?? '',
      tela: map['tela']?.toString() ?? '',
      arquivo: map['arquivo']?.toString() ?? '',
      rota: map['rota']?.toString() ?? '',
      status: map['status']?.toString() ?? 'info',
      dados: Map<String, dynamic>.from(map['dados'] as Map? ?? const {}),
      erro: map['erro'] is Map
          ? Map<String, dynamic>.from(map['erro'] as Map)
          : null,
      criadoEm: toDate(map['criadoEm']),
      ordem: map['ordem'] is num ? (map['ordem'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo,
      'acao': acao,
      'descricao': descricao,
      'tela': tela,
      'arquivo': arquivo,
      'rota': rota,
      'status': status,
      'dados': dados,
      'erro': erro,
      'criadoEm': Timestamp.fromDate(criadoEm),
      'ordem': ordem,
    };
  }

  CacaBugEventModel copyWith({
    String? id,
    String? tipo,
    String? acao,
    String? descricao,
    String? tela,
    String? arquivo,
    String? rota,
    String? status,
    Map<String, dynamic>? dados,
    Map<String, dynamic>? erro,
    DateTime? criadoEm,
    int? ordem,
  }) {
    return CacaBugEventModel(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      acao: acao ?? this.acao,
      descricao: descricao ?? this.descricao,
      tela: tela ?? this.tela,
      arquivo: arquivo ?? this.arquivo,
      rota: rota ?? this.rota,
      status: status ?? this.status,
      dados: dados ?? this.dados,
      erro: erro ?? this.erro,
      criadoEm: criadoEm ?? this.criadoEm,
      ordem: ordem ?? this.ordem,
    );
  }

  static Map<String, dynamic> sanitizeMap(
    Map<String, dynamic> input, {
    int stackLimit = 700,
  }) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value == null) return;
      final normalizedKey = key.toString();
      final lower = normalizedKey.toLowerCase();
      if (_isSensitiveKey(lower)) return;
      out[_safeShort(normalizedKey, 80)] = _sanitizeValue(
        value,
        stackLimit: stackLimit,
      );
    });
    return out;
  }

  static bool _isSensitiveKey(String lower) {
    if (lower == 'temcontato' || lower == 'destinotipo' || lower == 'canal') {
      return false;
    }
    return lower.contains('senha') ||
        lower.contains('password') ||
        lower.contains('token') ||
        lower.contains('cpf') ||
        lower.contains('documento') ||
        lower.contains('telefone') ||
        lower.contains('whatsapp') ||
        lower.contains('contato') ||
        lower.contains('email') ||
        lower.contains('endereco') ||
        lower.contains('endereço') ||
        lower.contains('nascimento') ||
        lower.contains('responsavel') ||
        lower.contains('mensagem') ||
        lower.contains('url') ||
        lower.contains('link');
  }

  static dynamic _sanitizeValue(dynamic value, {required int stackLimit}) {
    if (value == null || value is num || value is bool) return value;
    if (value is DateTime) return value.toIso8601String();
    if (value is Timestamp) return value;
    if (value is String) return sanitizeText(value, max: stackLimit);
    if (value is List) {
      return value
          .take(20)
          .map((e) => _sanitizeValue(e, stackLimit: 220))
          .toList();
    }
    if (value is Map) {
      return sanitizeMap(Map<String, dynamic>.from(value), stackLimit: 220);
    }
    return sanitizeText(value.toString(), max: 420);
  }

  static String sanitizeText(String value, {required int max}) {
    var text = value
        .replaceAll(RegExp(r'https?:\/\/\S+'), '[url_redigida]')
        .replaceAll(RegExp(r'wa\.me\/\S+'), '[whatsapp_redigido]')
        .replaceAll(RegExp(r'api\.whatsapp\.com\/\S+'), '[whatsapp_redigido]')
        .replaceAll(RegExp(r'tel:\S+'), '[telefone_redigido]')
        .replaceAll(RegExp(r'\+?\d[\d\s\-\(\)]{7,}\d'), '[numero_redigido]')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  static String _safeShort(String value, int max) {
    final text = value.trim();
    if (text.length <= max) return text;
    return text.substring(0, max);
  }
}
