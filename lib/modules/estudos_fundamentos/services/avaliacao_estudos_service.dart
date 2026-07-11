import 'package:cloud_functions/cloud_functions.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/pergunta_avaliacao_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/resultado_tentativa_estudo_model.dart';

class PerguntasEstudoAvaliacaoResult {
  final bool success;
  final String alunoId;
  final String estudoId;
  final String cicloId;
  final int totalPerguntas;
  final List<PerguntaAvaliacaoEstudoModel> perguntas;

  const PerguntasEstudoAvaliacaoResult({
    required this.success,
    required this.alunoId,
    required this.estudoId,
    required this.cicloId,
    required this.totalPerguntas,
    required this.perguntas,
  });

  factory PerguntasEstudoAvaliacaoResult.fromMap(Map<String, dynamic> data) {
    final perguntasRaw = data['perguntas'];
    final perguntas = perguntasRaw is Iterable
        ? perguntasRaw
              .whereType<Map>()
              .map(
                (item) => PerguntaAvaliacaoEstudoModel.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((pergunta) => pergunta.perguntaId.isNotEmpty)
              .toList()
        : <PerguntaAvaliacaoEstudoModel>[];
    perguntas.sort((a, b) => a.ordem.compareTo(b.ordem));

    return PerguntasEstudoAvaliacaoResult(
      success: data['success'] == true,
      alunoId: _text(data['alunoId']),
      estudoId: _text(data['estudoId']),
      cicloId: _text(data['cicloId']),
      totalPerguntas: _intValue(
        data['totalPerguntas'],
        fallback: perguntas.length,
      ),
      perguntas: perguntas,
    );
  }
}

class AvaliacaoEstudosService {
  final FirebaseFunctions _functions;

  AvaliacaoEstudosService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  Future<PerguntasEstudoAvaliacaoResult> buscarPerguntasEstudo({
    required String alunoId,
    required String estudoId,
  }) async {
    final result = await _functions.httpsCallable('buscarPerguntasEstudo').call(
      {'alunoId': alunoId, 'estudoId': estudoId},
    );
    final data = Map<String, dynamic>.from(result.data as Map);
    return PerguntasEstudoAvaliacaoResult.fromMap(data);
  }

  Future<ResultadoTentativaEstudoModel> finalizarTentativaEstudo({
    required String alunoId,
    required String estudoId,
    required String clientAttemptId,
    required List<Map<String, dynamic>> respostas,
  }) async {
    final result = await _functions
        .httpsCallable('finalizarTentativaEstudo')
        .call({
          'alunoId': alunoId,
          'estudoId': estudoId,
          'clientAttemptId': clientAttemptId,
          'respostas': respostas,
        });
    final data = Map<String, dynamic>.from(result.data as Map);
    return ResultadoTentativaEstudoModel.fromMap(data);
  }
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

int _intValue(dynamic value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}
