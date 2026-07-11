class AlternativaAvaliacaoEstudoModel {
  final String id;
  final String texto;
  final String label;
  final String letra;
  final int ordem;
  final String valor;

  const AlternativaAvaliacaoEstudoModel({
    required this.id,
    required this.texto,
    required this.label,
    required this.letra,
    required this.ordem,
    required this.valor,
  });

  factory AlternativaAvaliacaoEstudoModel.fromMap(Map<String, dynamic> data) {
    return AlternativaAvaliacaoEstudoModel(
      id: _text(data['id']),
      texto: _text(data['texto']),
      label: _text(data['label']),
      letra: _text(data['letra']),
      ordem: _intValue(data['ordem'], fallback: 0),
      valor: _text(data['valor']),
    );
  }

  String get displayLabel {
    if (letra.isNotEmpty) return letra.toUpperCase();
    if (label.isNotEmpty) return label;
    if (valor.isNotEmpty) return valor;
    return id.toUpperCase();
  }
}

class PerguntaAvaliacaoEstudoModel {
  final String perguntaId;
  final String estudoId;
  final String cicloId;
  final String enunciado;
  final String tipo;
  final List<AlternativaAvaliacaoEstudoModel> alternativasPublicas;
  final String dificuldade;
  final int peso;
  final int ordem;
  final List<String> tags;
  final bool obrigatoria;
  final bool podeAparecerEmAvaliacao;

  const PerguntaAvaliacaoEstudoModel({
    required this.perguntaId,
    required this.estudoId,
    required this.cicloId,
    required this.enunciado,
    required this.tipo,
    required this.alternativasPublicas,
    required this.dificuldade,
    required this.peso,
    required this.ordem,
    required this.tags,
    required this.obrigatoria,
    required this.podeAparecerEmAvaliacao,
  });

  factory PerguntaAvaliacaoEstudoModel.fromMap(Map<String, dynamic> data) {
    final alternativasRaw = data['alternativasPublicas'];
    final alternativas = alternativasRaw is Iterable
        ? alternativasRaw
              .whereType<Map>()
              .map(
                (item) => AlternativaAvaliacaoEstudoModel.fromMap(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => item.id.isNotEmpty)
              .toList()
        : <AlternativaAvaliacaoEstudoModel>[];
    alternativas.sort((a, b) => a.ordem.compareTo(b.ordem));

    return PerguntaAvaliacaoEstudoModel(
      perguntaId: _text(data['perguntaId']),
      estudoId: _text(data['estudoId']),
      cicloId: _text(data['cicloId']),
      enunciado: _text(data['enunciado']),
      tipo: _text(data['tipo'], fallback: 'multipla_escolha'),
      alternativasPublicas: alternativas,
      dificuldade: _text(data['dificuldade']),
      peso: _intValue(data['peso'], fallback: 1),
      ordem: _intValue(data['ordem'], fallback: 0),
      tags: _stringList(data['tags']),
      obrigatoria: _boolValue(data['obrigatoria'], fallback: true),
      podeAparecerEmAvaliacao: _boolValue(
        data['podeAparecerEmAvaliacao'],
        fallback: true,
      ),
    );
  }

  bool get isSelecaoUnica =>
      tipo == 'multipla_escolha' || tipo == 'verdadeiro_falso';
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

bool _boolValue(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return fallback;
}

List<String> _stringList(dynamic value) {
  if (value is! Iterable) return const [];
  return value
      .map((item) => _text(item))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
