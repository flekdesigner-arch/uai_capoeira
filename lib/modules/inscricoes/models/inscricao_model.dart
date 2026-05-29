import 'package:cloud_firestore/cloud_firestore.dart';  // 👈 FALTANDO!

class InscricaoModel {
  final String? id;
  final String nome;
  final String apelido;
  final String dataNascimento;
  final int idade;
  final String sexo;
  final String cpf;
  final String contatoAluno;
  final String endereco;
  final String cidade;
  final String grupo;
  final String professorNome;
  final String professorContato;
  final bool isGrupoUai;
  final String? graduacaoId;
  final String? graduacaoNome;
  final String? categoriaId;
  final String? categoriaNome;
  final bool autorizacao;
  final String termoAutorizacao;
  final String regulamento;
  final String status;
  final DateTime? dataInscricao;
  final bool isMaiorIdade;
  final bool assinaturaRecolhida;
  final String? assinaturaUrl;
  final String nomeCampeonato;
  final String dataEvento;
  final bool taxaPaga;
  final double taxaInscricao;
  final String? fotoUrl;
  final String? comprovanteUrl;

  InscricaoModel({
    this.id,
    required this.nome,
    required this.apelido,
    required this.dataNascimento,
    required this.idade,
    required this.sexo,
    required this.cpf,
    required this.contatoAluno,
    required this.endereco,
    required this.cidade,
    required this.grupo,
    required this.professorNome,
    required this.professorContato,
    required this.isGrupoUai,
    this.graduacaoId,
    this.graduacaoNome,
    this.categoriaId,
    this.categoriaNome,
    required this.autorizacao,
    required this.termoAutorizacao,
    required this.regulamento,
    required this.status,
    this.dataInscricao,
    required this.isMaiorIdade,
    required this.assinaturaRecolhida,
    this.assinaturaUrl,
    required this.nomeCampeonato,
    required this.dataEvento,
    required this.taxaPaga,
    required this.taxaInscricao,
    this.fotoUrl,
    this.comprovanteUrl,
  });

  factory InscricaoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return InscricaoModel(
      id: doc.id,
      nome: data['nome'] ?? '',
      apelido: data['apelido'] ?? '',
      dataNascimento: data['data_nascimento'] ?? '',
      idade: data['idade'] ?? 0,
      sexo: data['sexo'] ?? '',
      cpf: data['cpf'] ?? '',
      contatoAluno: data['contato_aluno'] ?? '',
      endereco: data['endereco'] ?? '',
      cidade: data['cidade'] ?? '',
      grupo: data['grupo'] ?? '',
      professorNome: data['professor_nome'] ?? '',
      professorContato: data['professor_contato'] ?? '',
      isGrupoUai: data['is_grupo_uai'] ?? false,
      graduacaoId: data['graduacao_id'],
      graduacaoNome: data['graduacao_nome'],
      categoriaId: data['categoria_id'],
      categoriaNome: data['categoria_nome'],
      autorizacao: data['autorizacao'] ?? false,
      termoAutorizacao: data['termo_autorizacao'] ?? '',
      regulamento: data['regulamento'] ?? '',
      status: data['status'] ?? 'pendente',
      dataInscricao: data['data_inscricao'] != null
          ? (data['data_inscricao'] as Timestamp).toDate()
          : null,
      isMaiorIdade: data['is_maior_idade'] ?? false,
      assinaturaRecolhida: data['assinatura_recolhida'] ?? false,
      assinaturaUrl: data['assinatura_url'],
      nomeCampeonato: data['nome_campeonato'] ?? '',
      dataEvento: data['data_evento'] ?? '',
      taxaPaga: data['taxa_paga'] ?? false,
      taxaInscricao: (data['taxa_inscricao'] ?? 0.0).toDouble(),
      fotoUrl: data['foto_url'],
      comprovanteUrl: data['comprovante_url'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nome': nome,
      'apelido': apelido,
      'data_nascimento': dataNascimento,
      'idade': idade,
      'sexo': sexo,
      'cpf': cpf.replaceAll(RegExp(r'[^0-9]'), ''),
      'contato_aluno': contatoAluno.replaceAll(RegExp(r'[^0-9]'), ''),
      'endereco': endereco,
      'cidade': cidade,
      'grupo': grupo,
      'professor_nome': professorNome,
      'professor_contato': professorContato.replaceAll(RegExp(r'[^0-9]'), ''),
      'is_grupo_uai': isGrupoUai,
      if (graduacaoId != null) 'graduacao_id': graduacaoId,
      if (graduacaoNome != null) 'graduacao_nome': graduacaoNome,
      if (categoriaId != null) 'categoria_id': categoriaId,
      if (categoriaNome != null) 'categoria_nome': categoriaNome,
      'autorizacao': autorizacao,
      'termo_autorizacao': termoAutorizacao,
      'regulamento': regulamento,
      'status': status,
      'is_maior_idade': isMaiorIdade,
      'assinatura_recolhida': assinaturaRecolhida,
      if (assinaturaUrl != null) 'assinatura_url': assinaturaUrl,
      'nome_campeonato': nomeCampeonato,
      'data_evento': dataEvento,
      'taxa_paga': taxaPaga,
      'taxa_inscricao': taxaInscricao,
      if (fotoUrl != null) 'foto_url': fotoUrl,
      if (comprovanteUrl != null) 'comprovante_url': comprovanteUrl,
      'data_inscricao': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}