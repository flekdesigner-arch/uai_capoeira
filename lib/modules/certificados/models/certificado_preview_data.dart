import 'package:flutter/material.dart';

import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';

class CertificadoPreviewData {
  final String alunoNome;
  final String? cpf;
  final String sexo;
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
    this.sexo = '',
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

  bool get sexoFeminino {
    final s = sexo.trim().toUpperCase();
    return s == 'FEMININO' ||
        s == 'F' ||
        s == 'MULHER' ||
        s == 'MENINA' ||
        s == 'ALUNA';
  }

  bool get sexoMasculino {
    final s = sexo.trim().toUpperCase();
    return s == 'MASCULINO' ||
        s == 'M' ||
        s == 'HOMEM' ||
        s == 'MENINO' ||
        s == 'ALUNO';
  }

  String get sexoNormalizado {
    if (sexoFeminino) return 'FEMININO';
    if (sexoMasculino) return 'MASCULINO';
    return sexo.trim().toUpperCase();
  }

  String fraseFinal({
    required CertificadoTemplateTipo tipo,
    String tituloGraduacao = 'PROFESSOR',
    String corda = 'PROFESSOR - MARROM',
  }) {
    final titulo = _tituloDinamico(tituloGraduacao);

    // Quando a frase usa os tokens novos, eles já resolvem masculino/feminino.
    // Então NÃO podemos rodar a adaptação antiga por cima, senão:
    // PORTADORA vira PORTADORAA e MONITORA vira MONITORAA/MONITORAAA.
    final usaTokensDeGenero = _usaTokensDeGenero(frase);

    var finalText = frase
        .replaceAll('{nome}', alunoNome)
        .replaceAll('{cpf}', cpfFormatado)
        .replaceAll('{corda}', corda)
        .replaceAll('{titulo_graduacao}', titulo)
        .replaceAll('{titulo}', titulo)
        .replaceAll(
          '{portador_cpf}',
          sexoFeminino ? 'PORTADORA DO CPF' : 'PORTADOR DO CPF',
        )
        .replaceAll('{portador}', sexoFeminino ? 'PORTADORA' : 'PORTADOR')
        .replaceAll(
          '{reconhecido}',
          sexoFeminino ? 'RECONHECIDA' : 'RECONHECIDO',
        )
        .replaceAll('{apto}', sexoFeminino ? 'APTA' : 'APTO')
        .replaceAll('{aprovado}', sexoFeminino ? 'APROVADA' : 'APROVADO')
        .replaceAll('{aluno}', sexoFeminino ? 'ALUNA' : 'ALUNO')
        .replaceAll('{o_a}', sexoFeminino ? 'A' : 'O')
        .replaceAll('{do_da}', sexoFeminino ? 'DA' : 'DO')
        .replaceAll('{ao_a}', sexoFeminino ? 'À' : 'AO');

    if (!usaTokensDeGenero) {
      finalText = _adaptarFraseAntigaPorSexo(finalText);
    }

    return finalText;
  }

  bool _usaTokensDeGenero(String value) {
    final lower = value.toLowerCase();

    return lower.contains('{portador') ||
        lower.contains('{reconhecido}') ||
        lower.contains('{apto}') ||
        lower.contains('{aprovado}') ||
        lower.contains('{aluno}') ||
        lower.contains('{o_a}') ||
        lower.contains('{do_da}') ||
        lower.contains('{ao_a}') ||
        lower.contains('{titulo_graduacao}') ||
        lower.contains('{titulo}');
  }

  String _tituloDinamico(String tituloGraduacao) {
    final titulo = tituloGraduacao.trim().toUpperCase();
    if (titulo.isEmpty) return sexoFeminino ? 'ALUNA' : 'ALUNO';

    if (!sexoFeminino) return titulo;

    final mapa = <String, String>{
      'ALUNO': 'ALUNA',
      'MONITOR': 'MONITORA',
      'INSTRUTOR': 'INSTRUTORA',
      'PROFESSOR': 'PROFESSORA',
      'CONTRA-MESTRE': 'CONTRA-MESTRA',
      'CONTRA MESTRE': 'CONTRA MESTRA',
      'MESTRE': 'MESTRA',
      'FORMADO': 'FORMADA',
      'GRADUADO': 'GRADUADA',
    };

    if (mapa.containsKey(titulo)) return mapa[titulo]!;

    var out = titulo;

    // Casos compostos como "PROFESSOR - MARROM" ou "INSTRUTOR ROXO".
    mapa.forEach((masc, fem) {
      out = out.replaceAll(RegExp('\\b$masc\\b'), fem);
    });

    return out;
  }

  String _adaptarFraseAntigaPorSexo(String text) {
    if (!sexoFeminino) return text;

    var out = text;

    final frases = <String, String>{
      'RECONHECIDO COMO APTO E APROVADO': 'RECONHECIDA COMO APTA E APROVADA',
      'RECONHECIDO(A) COMO APTO(A) E APROVADO(A)':
          'RECONHECIDA COMO APTA E APROVADA',
      'PORTADOR DO CPF': 'PORTADORA DO CPF',
      'PORTADOR(A) DO CPF': 'PORTADORA DO CPF',
      'O(A) ALUNO(A)': 'A ALUNA',
      'DO(A) ALUNO(A)': 'DA ALUNA',
      'RECONHECIDO(A)': 'RECONHECIDA',
      'APTO(A)': 'APTA',
      'APROVADO(A)': 'APROVADA',
      'ALUNO(A)': 'ALUNA',
    };

    frases.forEach((from, to) {
      out = out.replaceAll(from, to);
    });

    final palavras = <String, String>{
      'PORTADOR': 'PORTADORA',
      'RECONHECIDO': 'RECONHECIDA',
      'APROVADO': 'APROVADA',
      'APTO': 'APTA',
      'MONITOR': 'MONITORA',
      'INSTRUTOR': 'INSTRUTORA',
      'PROFESSOR': 'PROFESSORA',
      'CONTRA-MESTRE': 'CONTRA-MESTRA',
      'CONTRA MESTRE': 'CONTRA MESTRA',
      'MESTRE': 'MESTRA',
    };

    palavras.forEach((from, to) {
      out = out.replaceAll(
        RegExp('(?<![A-ZÀ-Ú])' + RegExp.escape(from) + '(?![A-ZÀ-Ú])'),
        to,
      );
    });

    return out;
  }

  static CertificadoPreviewData exemplo(CertificadoTemplateTipo tipo) {
    switch (tipo) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return const CertificadoPreviewData(
          alunoNome: 'MATEUS HENRIQUE OLIVEIRA SANTOS',
          sexo: 'MASCULINO',
          graduacaoNova: '2° ADULTO - CINZA',
          frase:
              'CERTIFICAMOS QUE O(A) ALUNO(A) ACIMA ESTÁ APTO(A) E APROVADO(A) PARA RECEBER A GRADUAÇÃO EM CAPOEIRA, POR DEMONSTRAR INTERESSE NA ARTE E CULTURA BRASILEIRA, SENDO RECONHECIDO(A) PELOS MESTRES, CONTRAMESTRES, PROFESSORES E FORMADOS DO GRUPO.',
          localData: 'BOCAIUVA - MG, 20 DE JUNHO DE 2026',
          assinaturas: [
            CertificadoAssinaturaData(
              nome: 'JOÃO LUCAS SILVA RABELO',
              apelido: 'TICO-TICO',
            ),
            CertificadoAssinaturaData(
              nome: 'MESTRE NAVARRO',
              apelido: 'MESTRE',
            ),
            CertificadoAssinaturaData(
              nome: 'ASSOCIAÇÃO UAI CAPOEIRA',
              apelido: 'ORGANIZAÇÃO',
            ),
            CertificadoAssinaturaData(
              nome: 'CONVIDADO ESPECIAL',
              apelido: 'FORMADO',
            ),
            CertificadoAssinaturaData(
              nome: 'COORDENAÇÃO DO EVENTO',
              apelido: 'UAI CAPOEIRA',
            ),
          ],
        );

      case CertificadoTemplateTipo.certificadoComCpf:
        return const CertificadoPreviewData(
          alunoNome: 'MARIA ELISA OLIVEIRA SANTOS',
          cpf: '13408182647',
          sexo: 'FEMININO',
          graduacaoNova: 'INSTRUTORA - ROXA',
          frase:
              'CERTIFICAMOS QUE, {nome}, {portador_cpf}, {cpf}, CONCLUIU COM ÊXITO O CURSO DE CAPOEIRA, DEMONSTRANDO PLENO DOMÍNIO E HABILIDADE NESSA ARTE. COMO RESULTADO DE SEU DESEMPENHO EXCEPCIONAL, É {reconhecido} COMO {apto} E {aprovado} PARA EXERCER A FUNÇÃO DE PROFISSIONAL NESSA ÁREA, OSTENTANDO O TÍTULO DE {titulo_graduacao}, SENDO ATRIBUÍDA A CORDA {corda} EM SUA GRADUAÇÃO.',
          localData: 'BOCAIUVA - MG, 20 DE JUNHO DE 2026',
          assinaturas: [
            CertificadoAssinaturaData(
              nome: 'JOÃO LUCAS SILVA RABELO',
              apelido: 'TICO-TICO',
            ),
            CertificadoAssinaturaData(
              nome: 'MESTRE NAVARRO',
              apelido: 'MESTRE',
            ),
            CertificadoAssinaturaData(
              nome: 'ASSOCIAÇÃO UAI CAPOEIRA',
              apelido: 'ORGANIZAÇÃO',
            ),
            CertificadoAssinaturaData(
              nome: 'CONVIDADO ESPECIAL',
              apelido: 'FORMADO',
            ),
            CertificadoAssinaturaData(
              nome: 'COORDENAÇÃO DO EVENTO',
              apelido: 'UAI CAPOEIRA',
            ),
          ],
        );

      case CertificadoTemplateTipo.diploma:
        return const CertificadoPreviewData(
          alunoNome: 'JOÃO LUCAS SILVA RABELO',
          cpf: '13408182647',
          sexo: 'MASCULINO',
          graduacaoNova: 'PROFESSOR - MARROM',
          frase:
              'CERTIFICAMOS QUE, {nome}, {portador_cpf}, {cpf}, CONCLUIU COM ÊXITO O CURSO DE CAPOEIRA, DEMONSTRANDO PLENO DOMÍNIO E HABILIDADE NESSA ARTE. COMO RESULTADO DE SEU DESEMPENHO EXCEPCIONAL, É {reconhecido} COMO {apto} E {aprovado} PARA EXERCER A FUNÇÃO DE PROFISSIONAL NESSA ÁREA, OSTENTANDO O TÍTULO DE {titulo_graduacao}, SENDO ATRIBUÍDA A CORDA {corda} EM SUA GRADUAÇÃO.',
          localData: 'BOCAIUVA - MG, 20 DE JUNHO DE 2026',
          assinaturas: [
            CertificadoAssinaturaData(
              nome: 'JOÃO LUCAS SILVA RABELO',
              apelido: 'TICO-TICO',
            ),
            CertificadoAssinaturaData(
              nome: 'MESTRE NAVARRO',
              apelido: 'MESTRE',
            ),
            CertificadoAssinaturaData(
              nome: 'ASSOCIAÇÃO UAI CAPOEIRA',
              apelido: 'ORGANIZAÇÃO',
            ),
            CertificadoAssinaturaData(
              nome: 'CONVIDADO ESPECIAL',
              apelido: 'FORMADO',
            ),
            CertificadoAssinaturaData(
              nome: 'COORDENAÇÃO DO EVENTO',
              apelido: 'UAI CAPOEIRA',
            ),
          ],
        );
    }
  }
}

@immutable
class CertificadoAssinaturaData {
  final String nome;
  final String apelido;

  const CertificadoAssinaturaData({required this.nome, required this.apelido});
}
