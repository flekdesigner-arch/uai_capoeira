import 'package:cloud_firestore/cloud_firestore.dart';

class GabaritoEstudoModel {
  final String id;
  final String perguntaId;
  final String estudoId;
  final String cicloId;
  final String tipoPergunta;
  final String? alternativaCorretaId;
  final List<String> alternativasCorretasIds;
  final String? respostaEsperadaTexto;
  final String? justificativaCorreta;
  final int peso;
  final bool ativo;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final String? criadoPor;
  final String? atualizadoPor;

  const GabaritoEstudoModel({
    required this.id,
    required this.perguntaId,
    required this.estudoId,
    required this.cicloId,
    required this.tipoPergunta,
    this.alternativaCorretaId,
    this.alternativasCorretasIds = const [],
    this.respostaEsperadaTexto,
    this.justificativaCorreta,
    this.peso = 1,
    this.ativo = true,
    this.criadoEm,
    this.atualizadoEm,
    this.criadoPor,
    this.atualizadoPor,
  });

  factory GabaritoEstudoModel.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return GabaritoEstudoModel(
      id: doc.id,
      perguntaId: (data['perguntaId'] ?? doc.id).toString(),
      estudoId: (data['estudoId'] ?? '').toString(),
      cicloId: (data['cicloId'] ?? '').toString(),
      tipoPergunta: (data['tipoPergunta'] ?? '').toString(),
      alternativaCorretaId: data['alternativaCorretaId']?.toString(),
      alternativasCorretasIds: _stringList(data['alternativasCorretasIds']),
      respostaEsperadaTexto: data['respostaEsperadaTexto']?.toString(),
      justificativaCorreta: data['justificativaCorreta']?.toString(),
      peso: _intValue(data['peso'], fallback: 1),
      ativo: data['ativo'] == true,
      criadoEm: _dateTime(data['criadoEm']),
      atualizadoEm: _dateTime(data['atualizadoEm']),
      criadoPor: data['criadoPor']?.toString(),
      atualizadoPor: data['atualizadoPor']?.toString(),
    );
  }

  Map<String, dynamic> toMap({
    bool includeCreateFields = false,
    String? usuarioId,
  }) {
    final now = FieldValue.serverTimestamp();

    return {
      'perguntaId': perguntaId,
      'estudoId': estudoId,
      'cicloId': cicloId,
      'tipoPergunta': tipoPergunta,
      'alternativaCorretaId': alternativaCorretaId,
      'alternativasCorretasIds': alternativasCorretasIds,
      'respostaEsperadaTexto': respostaEsperadaTexto,
      'justificativaCorreta': justificativaCorreta,
      'peso': peso,
      'ativo': ativo,
      'atualizadoEm': now,
      'atualizadoPor': usuarioId,
      if (includeCreateFields) ...{
        'criadoEm': now,
        'criadoPor': usuarioId,
      },
    };
  }

  GabaritoEstudoModel copyWith({
    String? id,
    String? perguntaId,
    String? estudoId,
    String? cicloId,
    String? tipoPergunta,
    String? alternativaCorretaId,
    List<String>? alternativasCorretasIds,
    String? respostaEsperadaTexto,
    String? justificativaCorreta,
    int? peso,
    bool? ativo,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
    String? criadoPor,
    String? atualizadoPor,
  }) {
    return GabaritoEstudoModel(
      id: id ?? this.id,
      perguntaId: perguntaId ?? this.perguntaId,
      estudoId: estudoId ?? this.estudoId,
      cicloId: cicloId ?? this.cicloId,
      tipoPergunta: tipoPergunta ?? this.tipoPergunta,
      alternativaCorretaId: alternativaCorretaId ?? this.alternativaCorretaId,
      alternativasCorretasIds:
          alternativasCorretasIds ?? this.alternativasCorretasIds,
      respostaEsperadaTexto:
          respostaEsperadaTexto ?? this.respostaEsperadaTexto,
      justificativaCorreta:
          justificativaCorreta ?? this.justificativaCorreta,
      peso: peso ?? this.peso,
      ativo: ativo ?? this.ativo,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      criadoPor: criadoPor ?? this.criadoPor,
      atualizadoPor: atualizadoPor ?? this.atualizadoPor,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  static int _intValue(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static DateTime? _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}