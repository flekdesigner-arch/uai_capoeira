class CategoriaModel {
  final String id;
  final String nome;
  final int idadeMin;
  final int idadeMax;
  final String sexo;
  final double taxa;
  final int vagas;
  final bool ativo;

  CategoriaModel({
    required this.id,
    required this.nome,
    required this.idadeMin,
    required this.idadeMax,
    required this.sexo,
    required this.taxa,
    required this.vagas,
    required this.ativo,
  });

  factory CategoriaModel.fromFirestore(Map<String, dynamic> data, {String? id}) {
    return CategoriaModel(
      id: id ?? data['id'] ?? '',
      nome: data['nome'] ?? '',
      idadeMin: data['idade_min'] ?? 0,
      idadeMax: data['idade_max'] ?? 0,
      sexo: data['sexo'] ?? 'MISTO',
      taxa: (data['taxa'] ?? 0.0).toDouble(),
      vagas: data['vagas'] ?? 0,
      ativo: data['ativo'] ?? true,
    );
  }

  bool isCompativel(int idade, String? sexo) {
    final sexoCompativel = this.sexo == 'MISTO' || this.sexo == sexo;
    return idade >= idadeMin && idade <= idadeMax && sexoCompativel;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'nome': nome,
      'idade_min': idadeMin,
      'idade_max': idadeMax,
      'sexo': sexo,
      'taxa': taxa,
      'vagas': vagas,
      'ativo': ativo,
    };
  }
}