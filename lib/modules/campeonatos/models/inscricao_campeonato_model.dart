import 'package:cloud_firestore/cloud_firestore.dart';

class InscricaoCampeonatoModel {
  final String id; // 👈 AGORA É OBRIGATÓRIO (NÃO PODE SER NULL)!
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
  final Map<String, dynamic>? categoriaDados;
  final String? eventoId;
  final DateTime? timestamp;

  InscricaoCampeonatoModel({
    required this.id, // 👈 AGORA É REQUIRED!
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
    this.categoriaDados,
    this.eventoId,
    this.timestamp,
  });

  factory InscricaoCampeonatoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return InscricaoCampeonatoModel(
      id: doc.id, // 👈 O FIRESTORE SEMPRE TEM ID!
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
      categoriaDados: data['categoria_dados'] as Map<String, dynamic>?,
      eventoId: data['evento_id'],
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    final Map<String, dynamic> data = {
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
      'autorizacao': autorizacao,
      'termo_autorizacao': termoAutorizacao,
      'regulamento': regulamento,
      'status': status,
      'is_maior_idade': isMaiorIdade,
      'assinatura_recolhida': assinaturaRecolhida,
      'nome_campeonato': nomeCampeonato,
      'data_evento': dataEvento,
      'taxa_paga': taxaPaga,
      'taxa_inscricao': taxaInscricao,
      'data_inscricao': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    // Campos opcionais
    if (graduacaoId != null) data['graduacao_id'] = graduacaoId;
    if (graduacaoNome != null) data['graduacao_nome'] = graduacaoNome;
    if (categoriaId != null) data['categoria_id'] = categoriaId;
    if (categoriaNome != null) data['categoria_nome'] = categoriaNome;
    if (assinaturaUrl != null) data['assinatura_url'] = assinaturaUrl;
    if (fotoUrl != null) data['foto_url'] = fotoUrl;
    if (comprovanteUrl != null) data['comprovante_url'] = comprovanteUrl;
    if (categoriaDados != null) data['categoria_dados'] = categoriaDados;
    if (eventoId != null) data['evento_id'] = eventoId;

    return data;
  }

  // Método de cópia com modificações
  InscricaoCampeonatoModel copyWith({
    String? id,
    String? nome,
    String? apelido,
    String? dataNascimento,
    int? idade,
    String? sexo,
    String? cpf,
    String? contatoAluno,
    String? endereco,
    String? cidade,
    String? grupo,
    String? professorNome,
    String? professorContato,
    bool? isGrupoUai,
    String? graduacaoId,
    String? graduacaoNome,
    String? categoriaId,
    String? categoriaNome,
    bool? autorizacao,
    String? termoAutorizacao,
    String? regulamento,
    String? status,
    DateTime? dataInscricao,
    bool? isMaiorIdade,
    bool? assinaturaRecolhida,
    String? assinaturaUrl,
    String? nomeCampeonato,
    String? dataEvento,
    bool? taxaPaga,
    double? taxaInscricao,
    String? fotoUrl,
    String? comprovanteUrl,
    Map<String, dynamic>? categoriaDados,
    String? eventoId,
    DateTime? timestamp,
  }) {
    return InscricaoCampeonatoModel(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      apelido: apelido ?? this.apelido,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      idade: idade ?? this.idade,
      sexo: sexo ?? this.sexo,
      cpf: cpf ?? this.cpf,
      contatoAluno: contatoAluno ?? this.contatoAluno,
      endereco: endereco ?? this.endereco,
      cidade: cidade ?? this.cidade,
      grupo: grupo ?? this.grupo,
      professorNome: professorNome ?? this.professorNome,
      professorContato: professorContato ?? this.professorContato,
      isGrupoUai: isGrupoUai ?? this.isGrupoUai,
      graduacaoId: graduacaoId ?? this.graduacaoId,
      graduacaoNome: graduacaoNome ?? this.graduacaoNome,
      categoriaId: categoriaId ?? this.categoriaId,
      categoriaNome: categoriaNome ?? this.categoriaNome,
      autorizacao: autorizacao ?? this.autorizacao,
      termoAutorizacao: termoAutorizacao ?? this.termoAutorizacao,
      regulamento: regulamento ?? this.regulamento,
      status: status ?? this.status,
      dataInscricao: dataInscricao ?? this.dataInscricao,
      isMaiorIdade: isMaiorIdade ?? this.isMaiorIdade,
      assinaturaRecolhida: assinaturaRecolhida ?? this.assinaturaRecolhida,
      assinaturaUrl: assinaturaUrl ?? this.assinaturaUrl,
      nomeCampeonato: nomeCampeonato ?? this.nomeCampeonato,
      dataEvento: dataEvento ?? this.dataEvento,
      taxaPaga: taxaPaga ?? this.taxaPaga,
      taxaInscricao: taxaInscricao ?? this.taxaInscricao,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      comprovanteUrl: comprovanteUrl ?? this.comprovanteUrl,
      categoriaDados: categoriaDados ?? this.categoriaDados,
      eventoId: eventoId ?? this.eventoId,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  // Getters úteis
  String get cpfFormatado {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0,3)}.${cpf.substring(3,6)}.${cpf.substring(6,9)}-${cpf.substring(9)}';
  }

  String get telefoneFormatado {
    if (contatoAluno.length != 11) return contatoAluno;
    return '(${contatoAluno.substring(0,2)}) ${contatoAluno.substring(2,7)}-${contatoAluno.substring(7)}';
  }

  bool get precisaPagar => !taxaPaga && status != 'cancelado';

  bool get podeConfirmar => status == 'pendente';

  bool get podeCancelar => status == 'pendente' || status == 'confirmado';
}