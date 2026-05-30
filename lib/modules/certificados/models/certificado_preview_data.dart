import 'package:flutter/material.dart';

import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';

class CertificadoPreviewData {
  final String alunoNome;
  final String? cpf;
  final String graduacaoNova;
  final String frase;
  final String localData;
  final List<CertificadoAssinaturaData> assinaturas;

  const CertificadoPreviewData({
    required this.alunoNome,
    required this.graduacaoNova,
    required this.frase,
    required this.localData,
    this.cpf,
    this.assinaturas = const [],
  });

  String get cpfFormatado {
    final raw = cpf?.trim() ?? '';
    if (raw.isEmpty) return '';

    final onlyNumbers = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (onlyNumbers.length != 11) return raw;

    return '${onlyNumbers.substring(0, 3)}.'
        '${onlyNumbers.substring(3, 6)}.'
        '${onlyNumbers.substring(6, 9)}-'
        '${onlyNumbers.substring(9)}';
  }

  String fraseFinal({
    required CertificadoTemplateTipo tipo,
    String tituloGraduacao = 'PROFESSOR',
    String corda = 'PROFESSOR - MARROM',
  }) {
    return frase
        .replaceAll('{nome}', alunoNome)
        .replaceAll('{cpf}', cpfFormatado)
        .replaceAll('{titulo_graduacao}', tituloGraduacao)
        .replaceAll('{corda}', corda);
  }

  static CertificadoPreviewData exemplo(CertificadoTemplateTipo tipo) {
    switch (tipo) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return const CertificadoPreviewData(
          alunoNome: 'MATEUS HENRIQUE OLIVEIRA SANTOS',
          graduacaoNova: '2° ADULTO - CINZA',
          frase:
          'CERTIFICAMOS QUE O(A) ALUNO(A) ACIMA ESTÁ APTO(A) E APROVADO(A) PARA RECEBER A GRADUAÇÃO EM CAPOEIRA, POR DEMONSTRAR INTERESSE NA ARTE E CULTURA BRASILEIRA, SENDO RECONHECIDO(A) PELOS MESTRES, CONTRAMESTRES, PROFESSORES E FORMADOS DO GRUPO.',
          localData: 'BOCAIUVA - MG, 20 DE JUNHO DE 2026',
          assinaturas: [
            CertificadoAssinaturaData(nome: 'JOÃO LUCAS SILVA RABELO', apelido: 'TICO-TICO'),
            CertificadoAssinaturaData(nome: 'MESTRE NAVARRO', apelido: 'MESTRE'),
            CertificadoAssinaturaData(nome: 'ASSOCIAÇÃO UAI CAPOEIRA', apelido: 'ORGANIZAÇÃO'),
            CertificadoAssinaturaData(nome: 'CONVIDADO ESPECIAL', apelido: 'FORMADO'),
            CertificadoAssinaturaData(nome: 'COORDENAÇÃO DO EVENTO', apelido: 'UAI CAPOEIRA'),
          ],
        );

      case CertificadoTemplateTipo.certificadoComCpf:
        return const CertificadoPreviewData(
          alunoNome: 'MARIA ELISA OLIVEIRA SANTOS',
          cpf: '13408182647',
          graduacaoNova: 'INSTRUTOR - ROXO',
          frase:
          'CERTIFICAMOS QUE, {nome}, PORTADOR DO CPF, {cpf}, CONCLUIU COM ÊXITO O CURSO DE CAPOEIRA, DEMONSTRANDO PLENO DOMÍNIO E HABILIDADE NESSA ARTE. COMO RESULTADO DE SEU DESEMPENHO EXCEPCIONAL, É RECONHECIDO COMO APTO E APROVADO PARA EXERCER A FUNÇÃO DE PROFISSIONAL NESSA ÁREA, OSTENTANDO O TÍTULO DE {titulo_graduacao}, SENDO ATRIBUÍDA A CORDA {corda} EM SUA GRADUAÇÃO.',
          localData: 'BOCAIUVA - MG, 20 DE JUNHO DE 2026',
          assinaturas: [
            CertificadoAssinaturaData(nome: 'JOÃO LUCAS SILVA RABELO', apelido: 'TICO-TICO'),
            CertificadoAssinaturaData(nome: 'MESTRE NAVARRO', apelido: 'MESTRE'),
            CertificadoAssinaturaData(nome: 'ASSOCIAÇÃO UAI CAPOEIRA', apelido: 'ORGANIZAÇÃO'),
            CertificadoAssinaturaData(nome: 'CONVIDADO ESPECIAL', apelido: 'FORMADO'),
            CertificadoAssinaturaData(nome: 'COORDENAÇÃO DO EVENTO', apelido: 'UAI CAPOEIRA'),
          ],
        );

      case CertificadoTemplateTipo.diploma:
        return const CertificadoPreviewData(
          alunoNome: 'JOÃO LUCAS SILVA RABELO',
          cpf: '13408182647',
          graduacaoNova: 'PROFESSOR - MARROM',
          frase:
          'CERTIFICAMOS QUE, {nome}, PORTADOR DO CPF, {cpf}, CONCLUIU COM ÊXITO O CURSO DE CAPOEIRA, DEMONSTRANDO PLENO DOMÍNIO E HABILIDADE NESSA ARTE. COMO RESULTADO DE SEU DESEMPENHO EXCEPCIONAL, É RECONHECIDO COMO APTO E APROVADO PARA EXERCER A FUNÇÃO DE PROFISSIONAL NESSA ÁREA, OSTENTANDO O TÍTULO DE {titulo_graduacao}, SENDO ATRIBUÍDA A CORDA {corda} EM SUA GRADUAÇÃO.',
          localData: 'BOCAIUVA - MG, 20 DE JUNHO DE 2026',
          assinaturas: [
            CertificadoAssinaturaData(nome: 'JOÃO LUCAS SILVA RABELO', apelido: 'TICO-TICO'),
            CertificadoAssinaturaData(nome: 'MESTRE NAVARRO', apelido: 'MESTRE'),
            CertificadoAssinaturaData(nome: 'ASSOCIAÇÃO UAI CAPOEIRA', apelido: 'ORGANIZAÇÃO'),
            CertificadoAssinaturaData(nome: 'CONVIDADO ESPECIAL', apelido: 'FORMADO'),
            CertificadoAssinaturaData(nome: 'COORDENAÇÃO DO EVENTO', apelido: 'UAI CAPOEIRA'),
          ],
        );
    }
  }
}

@immutable
class CertificadoAssinaturaData {
  final String nome;
  final String apelido;

  const CertificadoAssinaturaData({
    required this.nome,
    required this.apelido,
  });
}
