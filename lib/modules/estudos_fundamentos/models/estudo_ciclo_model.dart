import 'package:cloud_firestore/cloud_firestore.dart';

class EstudoCicloStatus {
  static const String rascunho = 'rascunho';
  static const String publicado = 'publicado';
  static const String emBreve = 'em_breve';
  static const String oculto = 'oculto';
  static const String arquivado = 'arquivado';

  static const List<String> values = [
    rascunho,
    publicado,
    emBreve,
    oculto,
    arquivado,
  ];

  static String label(String status) {
    switch (status) {
      case publicado:
        return 'Publicado';
      case emBreve:
        return 'Em breve';
      case oculto:
        return 'Oculto';
      case arquivado:
        return 'Arquivado';
      case rascunho:
      default:
        return 'Rascunho';
    }
  }

  static bool isValid(String status) => values.contains(status);
}

class EstudoCicloModel {
  final String id;
  final int numero;
  final String titulo;
  final String subtitulo;
  final String descricao;
  final String periodoHistorico;
  final String capaUrl;
  final String capaStoragePath;
  final int ordem;
  final String status;
  final bool mostrarNaLinhaDoTempo;
  final bool mostrarComoEmBreve;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final String criadoPor;
  final String atualizadoPor;

  const EstudoCicloModel({
    required this.id,
    required this.numero,
    required this.titulo,
    required this.subtitulo,
    required this.descricao,
    required this.periodoHistorico,
    required this.capaUrl,
    required this.capaStoragePath,
    required this.ordem,
    required this.status,
    required this.mostrarNaLinhaDoTempo,
    required this.mostrarComoEmBreve,
    this.criadoEm,
    this.atualizadoEm,
    required this.criadoPor,
    required this.atualizadoPor,
  });

  factory EstudoCicloModel.empty() {
    return const EstudoCicloModel(
      id: '',
      numero: 1,
      titulo: '',
      subtitulo: '',
      descricao: '',
      periodoHistorico: '',
      capaUrl: '',
      capaStoragePath: '',
      ordem: 1,
      status: EstudoCicloStatus.rascunho,
      mostrarNaLinhaDoTempo: true,
      mostrarComoEmBreve: false,
      criadoPor: '',
      atualizadoPor: '',
    );
  }

  factory EstudoCicloModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return EstudoCicloModel.fromMap(doc.id, doc.data());
  }

  factory EstudoCicloModel.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final status = _text(map['status'], fallback: EstudoCicloStatus.rascunho);

    return EstudoCicloModel(
      id: id,
      numero: _intValue(map['numero'], fallback: 0),
      titulo: _text(map['titulo']),
      subtitulo: _text(map['subtitulo']),
      descricao: _text(map['descricao']),
      periodoHistorico: _text(map['periodoHistorico']),
      capaUrl: _text(map['capaUrl']),
      capaStoragePath: _text(map['capaStoragePath']),
      ordem: _intValue(map['ordem'], fallback: 0),
      status: EstudoCicloStatus.isValid(status)
          ? status
          : EstudoCicloStatus.rascunho,
      mostrarNaLinhaDoTempo: _boolValue(
        map['mostrarNaLinhaDoTempo'],
        fallback: true,
      ),
      mostrarComoEmBreve: _boolValue(map['mostrarComoEmBreve']),
      criadoEm: _dateValue(map['criadoEm']),
      atualizadoEm: _dateValue(map['atualizadoEm']),
      criadoPor: _text(map['criadoPor']),
      atualizadoPor: _text(map['atualizadoPor']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'numero': numero,
      'titulo': titulo.trim(),
      'subtitulo': subtitulo.trim(),
      'descricao': descricao.trim(),
      'periodoHistorico': periodoHistorico.trim(),
      'capaUrl': capaUrl.trim(),
      'capaStoragePath': capaStoragePath.trim(),
      'ordem': ordem,
      'status': status,
      'mostrarNaLinhaDoTempo': mostrarNaLinhaDoTempo,
      'mostrarComoEmBreve': mostrarComoEmBreve,
      'criadoPor': criadoPor,
      'atualizadoPor': atualizadoPor,
      if (criadoEm != null) 'criadoEm': Timestamp.fromDate(criadoEm!),
      if (atualizadoEm != null)
        'atualizadoEm': Timestamp.fromDate(atualizadoEm!),
    };
  }

  EstudoCicloModel copyWith({
    String? id,
    int? numero,
    String? titulo,
    String? subtitulo,
    String? descricao,
    String? periodoHistorico,
    String? capaUrl,
    String? capaStoragePath,
    int? ordem,
    String? status,
    bool? mostrarNaLinhaDoTempo,
    bool? mostrarComoEmBreve,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
    String? criadoPor,
    String? atualizadoPor,
  }) {
    return EstudoCicloModel(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      titulo: titulo ?? this.titulo,
      subtitulo: subtitulo ?? this.subtitulo,
      descricao: descricao ?? this.descricao,
      periodoHistorico: periodoHistorico ?? this.periodoHistorico,
      capaUrl: capaUrl ?? this.capaUrl,
      capaStoragePath: capaStoragePath ?? this.capaStoragePath,
      ordem: ordem ?? this.ordem,
      status: status ?? this.status,
      mostrarNaLinhaDoTempo:
          mostrarNaLinhaDoTempo ?? this.mostrarNaLinhaDoTempo,
      mostrarComoEmBreve: mostrarComoEmBreve ?? this.mostrarComoEmBreve,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      criadoPor: criadoPor ?? this.criadoPor,
      atualizadoPor: atualizadoPor ?? this.atualizadoPor,
    );
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  static bool _boolValue(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'sim' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == 'nao' || normalized == '0') {
        return false;
      }
    }
    return fallback;
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

class EstudosCiclosResumo {
  final int total;
  final int publicados;
  final int rascunhos;
  final int emBreve;
  final int ocultos;
  final int arquivados;

  const EstudosCiclosResumo({
    required this.total,
    required this.publicados,
    required this.rascunhos,
    required this.emBreve,
    required this.ocultos,
    required this.arquivados,
  });

  factory EstudosCiclosResumo.fromCiclos(List<EstudoCicloModel> ciclos) {
    return EstudosCiclosResumo(
      total: ciclos.length,
      publicados: ciclos
          .where((ciclo) => ciclo.status == EstudoCicloStatus.publicado)
          .length,
      rascunhos: ciclos
          .where((ciclo) => ciclo.status == EstudoCicloStatus.rascunho)
          .length,
      emBreve: ciclos
          .where((ciclo) => ciclo.status == EstudoCicloStatus.emBreve)
          .length,
      ocultos: ciclos
          .where((ciclo) => ciclo.status == EstudoCicloStatus.oculto)
          .length,
      arquivados: ciclos
          .where((ciclo) => ciclo.status == EstudoCicloStatus.arquivado)
          .length,
    );
  }
}
