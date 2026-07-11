import 'package:cloud_functions/cloud_functions.dart';

class ExclusaoEstudosResumo {
  final bool success;
  final String tipo;
  final String id;
  final int ciclosApagados;
  final int estudosApagados;
  final int perguntasApagadas;
  final int gabaritosApagados;
  final int tentativasApagadas;
  final int resultadosApagados;
  final int progressosApagados;

  const ExclusaoEstudosResumo({
    required this.success,
    required this.tipo,
    required this.id,
    required this.ciclosApagados,
    required this.estudosApagados,
    required this.perguntasApagadas,
    required this.gabaritosApagados,
    required this.tentativasApagadas,
    required this.resultadosApagados,
    required this.progressosApagados,
  });

  factory ExclusaoEstudosResumo.fromMap(Map<String, dynamic> data) {
    return ExclusaoEstudosResumo(
      success: data['success'] == true,
      tipo: _text(data['tipo']),
      id: _text(data['id']),
      ciclosApagados: _intValue(data['ciclosApagados']),
      estudosApagados: _intValue(data['estudosApagados']),
      perguntasApagadas: _intValue(data['perguntasApagadas']),
      gabaritosApagados: _intValue(data['gabaritosApagados']),
      tentativasApagadas: _intValue(data['tentativasApagadas']),
      resultadosApagados: _intValue(data['resultadosApagados']),
      progressosApagados: _intValue(data['progressosApagados']),
    );
  }

  String get textoResumo {
    final partes = <String>[];
    if (ciclosApagados > 0) partes.add('$ciclosApagados ciclo(s)');
    if (estudosApagados > 0) partes.add('$estudosApagados estudo(s)');
    if (perguntasApagadas > 0) partes.add('$perguntasApagadas pergunta(s)');
    if (gabaritosApagados > 0) partes.add('$gabaritosApagados gabarito(s)');
    if (tentativasApagadas > 0) partes.add('$tentativasApagadas tentativa(s)');
    if (resultadosApagados > 0) partes.add('$resultadosApagados resultado(s)');
    if (progressosApagados > 0) partes.add('$progressosApagados progresso(s)');
    return partes.isEmpty ? 'Nenhum documento apagado.' : partes.join(', ');
  }
}

class ExclusaoEstudosAdminService {
  final FirebaseFunctions _functions;

  ExclusaoEstudosAdminService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  Future<ExclusaoEstudosResumo> excluir({
    required String tipo,
    required String id,
  }) async {
    final result = await _functions
        .httpsCallable('excluirConteudoEstudosFundamentos')
        .call({'tipo': tipo, 'id': id, 'confirmar': true});
    final data = Map<String, dynamic>.from(result.data as Map);
    return ExclusaoEstudosResumo.fromMap(data);
  }
}

String _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return '';
  return text;
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}
