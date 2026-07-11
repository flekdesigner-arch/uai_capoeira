import 'package:cloud_firestore/cloud_firestore.dart';

class PerguntaEstudoTipo {
  static const String multiplaEscolha = 'multipla_escolha';
  static const String verdadeiroFalso = 'verdadeiro_falso';

  static const List<String> values = [multiplaEscolha, verdadeiroFalso];

  static bool isValid(String value) => values.contains(value);

  static String label(String value) {
    switch (value) {
      case verdadeiroFalso:
        return 'Verdadeiro/falso';
      case multiplaEscolha:
      default:
        return 'Multipla escolha';
    }
  }
}

class PerguntaEstudoDificuldade {
  static const String facil = 'facil';
  static const String media = 'media';
  static const String dificil = 'dificil';

  static const List<String> values = [facil, media, dificil];

  static bool isValid(String value) => values.contains(value);

  static String label(String value) {
    switch (value) {
      case media:
        return 'Media';
      case dificil:
        return 'Dificil';
      case facil:
      default:
        return 'Facil';
    }
  }
}

class PerguntaEstudoStatus {
  static const String rascunho = 'rascunho';
  static const String ativa = 'ativa';
  static const String inativa = 'inativa';
  static const String arquivada = 'arquivada';

  static const List<String> values = [rascunho, ativa, inativa, arquivada];

  static bool isValid(String value) => values.contains(value);

  static String label(String value) {
    switch (value) {
      case ativa:
        return 'Ativa';
      case inativa:
        return 'Inativa';
      case arquivada:
        return 'Arquivada';
      case rascunho:
      default:
        return 'Rascunho';
    }
  }
}

class AlternativaPerguntaModel {
  final String id;
  final String texto;
  final int ordem;

  const AlternativaPerguntaModel({
    required this.id,
    required this.texto,
    required this.ordem,
  });

  factory AlternativaPerguntaModel.empty(int index) {
    return AlternativaPerguntaModel(
      id: String.fromCharCode(97 + index),
      texto: '',
      ordem: index + 1,
    );
  }

  factory AlternativaPerguntaModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return AlternativaPerguntaModel(
      id: _text(map['id']),
      texto: _text(map['texto']),
      ordem: _intValue(map['ordem'], fallback: 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id.trim(), 'texto': texto.trim(), 'ordem': ordem};
  }

  AlternativaPerguntaModel copyWith({String? id, String? texto, int? ordem}) {
    return AlternativaPerguntaModel(
      id: id ?? this.id,
      texto: texto ?? this.texto,
      ordem: ordem ?? this.ordem,
    );
  }

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
}

class PerguntaEstudoModel {
  final String id;
  final String cicloId;
  final String cicloTituloSnapshot;
  final String estudoId;
  final String estudoTituloSnapshot;
  final int estudoNumeroSnapshot;
  final String enunciado;
  final String tipo;
  final List<AlternativaPerguntaModel> alternativasPublicas;
  final String dificuldade;
  final int peso;
  final int ordem;
  final String status;
  final List<String> tags;
  final bool podeAparecerEmAvaliacao;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;
  final String criadoPor;
  final String atualizadoPor;

  const PerguntaEstudoModel({
    required this.id,
    required this.cicloId,
    required this.cicloTituloSnapshot,
    required this.estudoId,
    required this.estudoTituloSnapshot,
    required this.estudoNumeroSnapshot,
    required this.enunciado,
    required this.tipo,
    required this.alternativasPublicas,
    required this.dificuldade,
    required this.peso,
    required this.ordem,
    required this.status,
    required this.tags,
    required this.podeAparecerEmAvaliacao,
    this.criadoEm,
    this.atualizadoEm,
    required this.criadoPor,
    required this.atualizadoPor,
  });

  factory PerguntaEstudoModel.empty() {
    return PerguntaEstudoModel(
      id: '',
      cicloId: '',
      cicloTituloSnapshot: '',
      estudoId: '',
      estudoTituloSnapshot: '',
      estudoNumeroSnapshot: 0,
      enunciado: '',
      tipo: PerguntaEstudoTipo.multiplaEscolha,
      alternativasPublicas: List.generate(4, AlternativaPerguntaModel.empty),
      dificuldade: PerguntaEstudoDificuldade.facil,
      peso: 1,
      ordem: 1,
      status: PerguntaEstudoStatus.rascunho,
      tags: const [],
      podeAparecerEmAvaliacao: false,
      criadoPor: '',
      atualizadoPor: '',
    );
  }

  factory PerguntaEstudoModel.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return PerguntaEstudoModel.fromMap(doc.id, doc.data());
  }

  factory PerguntaEstudoModel.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final tipo = _text(
      map['tipo'],
      fallback: PerguntaEstudoTipo.multiplaEscolha,
    );
    final dificuldade = _text(
      map['dificuldade'],
      fallback: PerguntaEstudoDificuldade.facil,
    );
    final status = _text(
      map['status'],
      fallback: PerguntaEstudoStatus.rascunho,
    );
    final alternativasRaw = map['alternativasPublicas'];
    final alternativas = alternativasRaw is Iterable
        ? alternativasRaw
              .whereType<Map>()
              .map(
                (item) => AlternativaPerguntaModel.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : <AlternativaPerguntaModel>[];
    alternativas.sort((a, b) => a.ordem.compareTo(b.ordem));

    return PerguntaEstudoModel(
      id: id,
      cicloId: _text(map['cicloId']),
      cicloTituloSnapshot: _text(map['cicloTituloSnapshot']),
      estudoId: _text(map['estudoId']),
      estudoTituloSnapshot: _text(map['estudoTituloSnapshot']),
      estudoNumeroSnapshot: _intValue(map['estudoNumeroSnapshot'], fallback: 0),
      enunciado: _text(map['enunciado']),
      tipo: PerguntaEstudoTipo.isValid(tipo)
          ? tipo
          : PerguntaEstudoTipo.multiplaEscolha,
      alternativasPublicas: alternativas,
      dificuldade: PerguntaEstudoDificuldade.isValid(dificuldade)
          ? dificuldade
          : PerguntaEstudoDificuldade.facil,
      peso: _intValue(map['peso'], fallback: 1),
      ordem: _intValue(map['ordem'], fallback: 1),
      status: PerguntaEstudoStatus.isValid(status)
          ? status
          : PerguntaEstudoStatus.rascunho,
      tags: _stringList(map['tags']),
      podeAparecerEmAvaliacao: _boolValue(map['podeAparecerEmAvaliacao']),
      criadoEm: _dateValue(map['criadoEm']),
      atualizadoEm: _dateValue(map['atualizadoEm']),
      criadoPor: _text(map['criadoPor']),
      atualizadoPor: _text(map['atualizadoPor']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cicloId': cicloId,
      'cicloTituloSnapshot': cicloTituloSnapshot,
      'estudoId': estudoId,
      'estudoTituloSnapshot': estudoTituloSnapshot,
      'estudoNumeroSnapshot': estudoNumeroSnapshot,
      'enunciado': enunciado.trim(),
      'tipo': tipo,
      'alternativasPublicas': alternativasPublicas
          .map((a) => a.toMap())
          .toList(),
      'dificuldade': dificuldade,
      'peso': peso,
      'ordem': ordem,
      'status': status,
      'tags': tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      'podeAparecerEmAvaliacao': podeAparecerEmAvaliacao,
      'criadoPor': criadoPor,
      'atualizadoPor': atualizadoPor,
      if (criadoEm != null) 'criadoEm': Timestamp.fromDate(criadoEm!),
      if (atualizadoEm != null)
        'atualizadoEm': Timestamp.fromDate(atualizadoEm!),
    };
  }

  PerguntaEstudoModel copyWith({
    String? id,
    String? cicloId,
    String? cicloTituloSnapshot,
    String? estudoId,
    String? estudoTituloSnapshot,
    int? estudoNumeroSnapshot,
    String? enunciado,
    String? tipo,
    List<AlternativaPerguntaModel>? alternativasPublicas,
    String? dificuldade,
    int? peso,
    int? ordem,
    String? status,
    List<String>? tags,
    bool? podeAparecerEmAvaliacao,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
    String? criadoPor,
    String? atualizadoPor,
  }) {
    return PerguntaEstudoModel(
      id: id ?? this.id,
      cicloId: cicloId ?? this.cicloId,
      cicloTituloSnapshot: cicloTituloSnapshot ?? this.cicloTituloSnapshot,
      estudoId: estudoId ?? this.estudoId,
      estudoTituloSnapshot: estudoTituloSnapshot ?? this.estudoTituloSnapshot,
      estudoNumeroSnapshot: estudoNumeroSnapshot ?? this.estudoNumeroSnapshot,
      enunciado: enunciado ?? this.enunciado,
      tipo: tipo ?? this.tipo,
      alternativasPublicas: alternativasPublicas ?? this.alternativasPublicas,
      dificuldade: dificuldade ?? this.dificuldade,
      peso: peso ?? this.peso,
      ordem: ordem ?? this.ordem,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      podeAparecerEmAvaliacao:
          podeAparecerEmAvaliacao ?? this.podeAparecerEmAvaliacao,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      criadoPor: criadoPor ?? this.criadoPor,
      atualizadoPor: atualizadoPor ?? this.atualizadoPor,
    );
  }

  static List<String> parseTags(String value) {
    return value
        .replaceAll(',', '\n')
        .split(RegExp(r'\r?\n'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
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
      return ['true', 'sim', '1'].contains(value.trim().toLowerCase());
    }
    return fallback;
  }

  static int _intValue(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) return parseTags(value);
    return const [];
  }

  static DateTime? _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class PerguntasResumo {
  final int total;
  final int ativas;
  final int rascunhos;
  final int inativas;
  final int arquivadas;

  const PerguntasResumo({
    required this.total,
    required this.ativas,
    required this.rascunhos,
    required this.inativas,
    required this.arquivadas,
  });

  factory PerguntasResumo.fromPerguntas(List<PerguntaEstudoModel> perguntas) {
    return PerguntasResumo(
      total: perguntas.length,
      ativas: perguntas
          .where((p) => p.status == PerguntaEstudoStatus.ativa)
          .length,
      rascunhos: perguntas
          .where((p) => p.status == PerguntaEstudoStatus.rascunho)
          .length,
      inativas: perguntas
          .where((p) => p.status == PerguntaEstudoStatus.inativa)
          .length,
      arquivadas: perguntas
          .where((p) => p.status == PerguntaEstudoStatus.arquivada)
          .length,
    );
  }
}
