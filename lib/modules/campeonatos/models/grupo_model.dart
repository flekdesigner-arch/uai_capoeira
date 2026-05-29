class GrupoModel {
  final String id;
  final String nome;
  final String contato;
  final String observacoes;
  final bool ativo;

  GrupoModel({
    required this.id,
    required this.nome,
    this.contato = '',
    this.observacoes = '',
    required this.ativo,
  });

  factory GrupoModel.fromFirestore(Map<String, dynamic> data, String documentId) {
    return GrupoModel(
      id: documentId,
      nome: data['nome']?.toString().trim().toUpperCase() ?? '',
      contato: data['contato']?.toString().trim() ?? '',
      observacoes: data['observacoes']?.toString().trim() ?? '',
      ativo: data['ativo'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nome': nome,
      'contato': contato,
      'observacoes': observacoes,
      'ativo': ativo,
    };
  }
}