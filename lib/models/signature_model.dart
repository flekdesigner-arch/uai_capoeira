class Signature {
  final String id;
  final String inscricaoId;
  final String imageUrl;
  final DateTime dataHora;
  final String nomeResponsavel;
  final String nomeAluno;

  Signature({
    required this.id,
    required this.inscricaoId,
    required this.imageUrl,
    required this.dataHora,
    required this.nomeResponsavel,
    required this.nomeAluno,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inscricao_id': inscricaoId,
      'image_url': imageUrl,
      'data_hora': dataHora.toIso8601String(),
      'nome_responsavel': nomeResponsavel,
      'nome_aluno': nomeAluno,
    };
  }

  factory Signature.fromJson(Map<String, dynamic> json) {
    return Signature(
      id: json['id'],
      inscricaoId: json['inscricao_id'],
      imageUrl: json['image_url'],
      dataHora: DateTime.parse(json['data_hora']),
      nomeResponsavel: json['nome_responsavel'],
      nomeAluno: json['nome_aluno'],
    );
  }
}