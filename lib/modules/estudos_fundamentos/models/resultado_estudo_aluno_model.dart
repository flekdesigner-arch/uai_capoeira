import 'package:cloud_firestore/cloud_firestore.dart';

class ResultadoEstudoAlunoModel {
  final String estudoId;
  final String cicloId;
  final double? nota;
  final bool aprovado;
  final int acertos;
  final int total;
  final DateTime? atualizadoEm;

  const ResultadoEstudoAlunoModel({
    required this.estudoId,
    required this.cicloId,
    required this.nota,
    required this.aprovado,
    required this.acertos,
    required this.total,
    this.atualizadoEm,
  });

  factory ResultadoEstudoAlunoModel.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ResultadoEstudoAlunoModel(
      estudoId: _text(data['estudoId'], fallback: doc.id),
      cicloId: _text(data['cicloId']),
      nota: _percentualValue(
        data['melhorPercentual'] ??
            data['ultimoPercentual'] ??
            data['percentual'] ??
            data['melhorNota'] ??
            data['nota'] ??
            data['score'],
      ),
      aprovado: _boolValue(data['aprovado']),
      acertos: _intValue(data['acertos']),
      total: _intValue(data['totalQuestoes'] ?? data['total']),
      atualizadoEm: _dateValue(
        data['updatedAt'] ??
            data['atualizadoEm'] ??
            data['concluidoEm'] ??
            data['criadoEm'],
      ),
    );
  }

  String get notaFormatada {
    final value = nota;
    if (value == null) return '--';
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

double? _doubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

double? _percentualValue(dynamic value) {
  final parsed = _doubleOrNull(value);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  if (parsed > 0 && parsed <= 1) return parsed * 100;
  return parsed;
}

bool _boolValue(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return [
      'true',
      'sim',
      '1',
      'aprovado',
    ].contains(value.trim().toLowerCase());
  }
  return false;
}

DateTime? _dateValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
