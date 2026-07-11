import 'package:cloud_firestore/cloud_firestore.dart';

class EstudosConfigModel {
  final bool ativo;
  final bool mostrarCardAreaAluno;
  final bool mostrarEmBreve;
  final DateTime? updatedAt;
  final String updatedBy;

  const EstudosConfigModel({
    required this.ativo,
    required this.mostrarCardAreaAluno,
    required this.mostrarEmBreve,
    this.updatedAt,
    this.updatedBy = '',
  });

  factory EstudosConfigModel.defaults() {
    return const EstudosConfigModel(
      ativo: false,
      mostrarCardAreaAluno: false,
      mostrarEmBreve: true,
    );
  }

  factory EstudosConfigModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return EstudosConfigModel.defaults();

    return EstudosConfigModel(
      ativo: data['ativo'] == true,
      mostrarCardAreaAluno: data['mostrarCardAreaAluno'] == true,
      mostrarEmBreve: data['mostrarEmBreve'] is bool
          ? data['mostrarEmBreve'] == true
          : true,
      updatedAt: _dateFromValue(data['updatedAt']),
      updatedBy: data['updatedBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap({bool includeServerTimestamp = false}) {
    return {
      'ativo': ativo,
      'mostrarCardAreaAluno': mostrarCardAreaAluno,
      'mostrarEmBreve': mostrarEmBreve,
      'updatedBy': updatedBy,
      if (includeServerTimestamp)
        'updatedAt': FieldValue.serverTimestamp()
      else if (updatedAt != null)
        'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  EstudosConfigModel copyWith({
    bool? ativo,
    bool? mostrarCardAreaAluno,
    bool? mostrarEmBreve,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return EstudosConfigModel(
      ativo: ativo ?? this.ativo,
      mostrarCardAreaAluno:
          mostrarCardAreaAluno ?? this.mostrarCardAreaAluno,
      mostrarEmBreve: mostrarEmBreve ?? this.mostrarEmBreve,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  static DateTime? _dateFromValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
