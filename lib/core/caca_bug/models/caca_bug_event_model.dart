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
      tipo: tipo,
      acao: acao,
      descricao: _limit(descricao, 800),
      tela: tela,
      arquivo: arquivo,
      rota: rota,
      status: status,
      dados: sanitizeMap(dados ?? const {}),
      erro: erro == null ? null : sanitizeMap(erro, stackLimit: 4000),
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
    int stackLimit = 1200,
  }) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value == null) return;
      final normalizedKey = key.toString();
      final lower = normalizedKey.toLowerCase();
      if (lower.contains('senha') ||
          lower.contains('password') ||
          lower.contains('token') ||
          lower.contains('cpf') ||
          lower.contains('documento') ||
          lower.contains('telefone')) {
        return;
      }
      out[normalizedKey] = _sanitizeValue(value, stackLimit: stackLimit);
    });
    return out;
  }

  static dynamic _sanitizeValue(dynamic value, {required int stackLimit}) {
    if (value == null || value is num || value is bool) return value;
    if (value is DateTime) return value.toIso8601String();
    if (value is Timestamp) return value;
    if (value is String) return _limit(value, stackLimit);
    if (value is List) {
      return value
          .take(30)
          .map((e) => _sanitizeValue(e, stackLimit: 300))
          .toList();
    }
    if (value is Map) {
      return sanitizeMap(Map<String, dynamic>.from(value), stackLimit: 300);
    }
    return _limit(value.toString(), 500);
  }

  static String _limit(String value, int max) {
    if (value.length <= max) return value;
    return value.substring(0, max);
  }
}
