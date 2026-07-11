class ResultadoTentativaEstudoModel {
  final bool success;
  final String tentativaId;
  final String estudoId;
  final String cicloId;
  final int totalQuestoes;
  final int totalObjetivas;
  final int totalDiscursivas;
  final int totalRespondidas;
  final int acertos;
  final num percentual;
  final bool aprovado;
  final String status;
  final bool possuiPendenciaManual;
  final num criterioAprovacaoPercentual;
  final bool idempotente;

  const ResultadoTentativaEstudoModel({
    required this.success,
    required this.tentativaId,
    required this.estudoId,
    required this.cicloId,
    required this.totalQuestoes,
    required this.totalObjetivas,
    required this.totalDiscursivas,
    required this.totalRespondidas,
    required this.acertos,
    required this.percentual,
    required this.aprovado,
    required this.status,
    required this.possuiPendenciaManual,
    required this.criterioAprovacaoPercentual,
    required this.idempotente,
  });

  factory ResultadoTentativaEstudoModel.fromMap(Map<String, dynamic> data) {
    return ResultadoTentativaEstudoModel(
      success: data['success'] == true,
      tentativaId: _text(data['tentativaId']),
      estudoId: _text(data['estudoId']),
      cicloId: _text(data['cicloId']),
      totalQuestoes: _intValue(data['totalQuestoes']),
      totalObjetivas: _intValue(data['totalObjetivas']),
      totalDiscursivas: _intValue(data['totalDiscursivas']),
      totalRespondidas: _intValue(data['totalRespondidas']),
      acertos: _intValue(data['acertos']),
      percentual: _numValue(data['percentual']),
      aprovado: data['aprovado'] == true,
      status: _text(data['status']),
      possuiPendenciaManual: data['possuiPendenciaManual'] == true,
      criterioAprovacaoPercentual: _numValue(
        data['criterioAprovacaoPercentual'],
        fallback: 70,
      ),
      idempotente: data['idempotente'] == true,
    );
  }

  String get percentualFormatado {
    if (percentual % 1 == 0) return percentual.toInt().toString();
    return percentual.toStringAsFixed(1);
  }
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

num _numValue(dynamic value, {num fallback = 0}) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim()) ?? fallback;
  return fallback;
}
