import 'package:cloud_firestore/cloud_firestore.dart';

class ProgressoEstudoStatus {
  static const String iniciado = 'iniciado';
  static const String concluido = 'concluido';

  static const List<String> values = [iniciado, concluido];

  static bool isValid(String status) => values.contains(status);
}

class ProgressoEstudoModel {
  final String alunoId;
  final String googleUid;
  final String estudoId;
  final String cicloId;
  final String status;
  final DateTime? iniciadoEm;
  final DateTime? concluidoEm;
  final DateTime? atualizadoEm;
  final DateTime? ultimaVisualizacaoEm;
  final int percentualLeitura;
  final String origem;

  const ProgressoEstudoModel({
    required this.alunoId,
    required this.googleUid,
    required this.estudoId,
    required this.cicloId,
    required this.status,
    this.iniciadoEm,
    this.concluidoEm,
    this.atualizadoEm,
    this.ultimaVisualizacaoEm,
    required this.percentualLeitura,
    required this.origem,
  });

  factory ProgressoEstudoModel.empty({
    required String alunoId,
    required String estudoId,
    required String cicloId,
    String googleUid = '',
  }) {
    return ProgressoEstudoModel(
      alunoId: alunoId,
      googleUid: googleUid,
      estudoId: estudoId,
      cicloId: cicloId,
      status: ProgressoEstudoStatus.iniciado,
      percentualLeitura: 0,
      origem: 'area_aluno',
    );
  }

  factory ProgressoEstudoModel.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ProgressoEstudoModel.fromMap(doc.data(), fallbackEstudoId: doc.id);
  }

  factory ProgressoEstudoModel.fromMap(
    Map<String, dynamic>? data, {
    String fallbackEstudoId = '',
  }) {
    final map = data ?? const <String, dynamic>{};
    final status = _text(
      map['status'],
      fallback: ProgressoEstudoStatus.iniciado,
    );
    return ProgressoEstudoModel(
      alunoId: _text(map['alunoId']),
      googleUid: _text(map['googleUid']),
      estudoId: _text(map['estudoId'], fallback: fallbackEstudoId),
      cicloId: _text(map['cicloId']),
      status: ProgressoEstudoStatus.isValid(status)
          ? status
          : ProgressoEstudoStatus.iniciado,
      iniciadoEm: _dateValue(map['iniciadoEm']),
      concluidoEm: _dateValue(map['concluidoEm']),
      atualizadoEm: _dateValue(map['atualizadoEm']),
      ultimaVisualizacaoEm: _dateValue(map['ultimaVisualizacaoEm']),
      percentualLeitura: _intValue(map['percentualLeitura'], fallback: 0),
      origem: _text(map['origem'], fallback: 'area_aluno'),
    );
  }

  bool get concluido => status == ProgressoEstudoStatus.concluido;
  bool get iniciado => status == ProgressoEstudoStatus.iniciado || concluido;

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  static int _intValue(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class EstudosProgressoResumo {
  final int total;
  final int iniciados;
  final int concluidos;

  const EstudosProgressoResumo({
    required this.total,
    required this.iniciados,
    required this.concluidos,
  });

  int get percentual => total <= 0 ? 0 : ((concluidos / total) * 100).round();

  String get statusLabel {
    if (total <= 0 || iniciados == 0) return 'Nao iniciado';
    if (concluidos >= total) return 'Concluido';
    return 'Em andamento';
  }
}
