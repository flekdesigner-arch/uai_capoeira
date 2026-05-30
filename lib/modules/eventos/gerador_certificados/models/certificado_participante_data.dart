import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

@immutable
class CertificadoParticipanteData {
  final String participacaoId;
  final String eventoId;
  final String alunoId;
  final String alunoNome;
  final String cpf;
  final String alunoFoto;
  final String eventoNome;
  final String tipoEvento;
  final String graduacaoAtual;
  final String graduacaoAtualId;
  final String graduacaoNova;
  final String graduacaoNovaId;
  final String tituloGraduacao;
  final String corda;
  final String frase;
  final String certificadoOuDiploma;
  final String cor1;
  final String cor2;
  final String ponta1;
  final String ponta2;
  final bool presente;
  final bool aguardandoFinalizacao;
  final String statusPagamento;
  final String? linkCertificado;
  final DateTime? certificadoAtualizadoEm;

  // Controle do novo módulo.
  final bool certificadoGerado;
  final String certificadoStatus;
  final bool certificadoImpresso;
  final DateTime? certificadoImpressoEm;
  final int? certificadoLoteImpressao;
  final String? certificadoArquivoLote;
  final String? certificadoLoteId;
  final bool certificadoIncluidoZip;
  final String? certificadoPacoteGraficaId;
  final String? certificadoPacoteGraficaNome;
  final String? certificadoStoragePath;
  final String? certificadoTipoArquivo;

  const CertificadoParticipanteData({
    required this.participacaoId,
    required this.eventoId,
    required this.alunoId,
    required this.alunoNome,
    required this.cpf,
    required this.alunoFoto,
    required this.eventoNome,
    required this.tipoEvento,
    required this.graduacaoAtual,
    required this.graduacaoAtualId,
    required this.graduacaoNova,
    required this.graduacaoNovaId,
    required this.tituloGraduacao,
    required this.corda,
    required this.frase,
    required this.certificadoOuDiploma,
    required this.cor1,
    required this.cor2,
    required this.ponta1,
    required this.ponta2,
    required this.presente,
    required this.aguardandoFinalizacao,
    required this.statusPagamento,
    this.linkCertificado,
    this.certificadoAtualizadoEm,
    this.certificadoGerado = false,
    this.certificadoStatus = 'pendente',
    this.certificadoImpresso = false,
    this.certificadoImpressoEm,
    this.certificadoLoteImpressao,
    this.certificadoArquivoLote,
    this.certificadoLoteId,
    this.certificadoIncluidoZip = false,
    this.certificadoPacoteGraficaId,
    this.certificadoPacoteGraficaNome,
    this.certificadoStoragePath,
    this.certificadoTipoArquivo,
  });

  factory CertificadoParticipanteData.fromMaps({
    required String participacaoId,
    required Map<String, dynamic> participacao,
    required Map<String, dynamic>? aluno,
    required Map<String, dynamic>? graduacao,
  }) {
    final alunoId = _asString(participacao['aluno_id']);
    final alunoNome = _firstNotEmpty([
      participacao['aluno_nome'],
      aluno?['nome'],
      aluno?['aluno_nome'],
      aluno?['nome_aluno'],
    ]);

    final cpf = _firstNotEmpty([
      participacao['cpf'],
      participacao['aluno_cpf'],
      aluno?['cpf'],
      aluno?['documento'],
    ]);

    final graduacaoNovaId = _firstNotEmpty([
      participacao['graduacao_nova_id'],
      participacao['nova_graduacao_id'],
      aluno?['graduacao_atual_id'],
    ]);

    final graduacaoNova = _firstNotEmpty([
      participacao['graduacao_nova'],
      participacao['nova_graduacao'],
      graduacao?['nome_graduacao'],
      graduacao?['descricaoCompleta'],
    ]);

    final certificadoTipo = _firstNotEmpty([
      graduacao?['certificado_ou_diploma'],
      'CERTIFICADO',
    ]).toUpperCase();

    return CertificadoParticipanteData(
      participacaoId: participacaoId,
      eventoId: _asString(participacao['evento_id']),
      alunoId: alunoId,
      alunoNome: alunoNome,
      cpf: cpf,
      alunoFoto: _firstNotEmpty([
        participacao['aluno_foto'],
        aluno?['foto'],
        aluno?['foto_url'],
        aluno?['link_foto'],
      ]),
      eventoNome: _asString(participacao['evento_nome']),
      tipoEvento: _asString(participacao['tipo_evento']),
      graduacaoAtual: _asString(participacao['graduacao']),
      graduacaoAtualId: _asString(participacao['graduacao_id']),
      graduacaoNova: graduacaoNova,
      graduacaoNovaId: graduacaoNovaId,
      tituloGraduacao: _firstNotEmpty([
        graduacao?['titulo_graduacao'],
        'ALUNO',
      ]),
      corda: _firstNotEmpty([
        graduacao?['corda'],
        graduacaoNova,
      ]),
      frase: _firstNotEmpty([
        graduacao?['frase'],
        'CERTIFICAMOS QUE O(A) ALUNO(A) ACIMA ESTÁ APTO(A) E APROVADO(A) PARA RECEBER A GRADUAÇÃO EM CAPOEIRA.',
      ]),
      certificadoOuDiploma: certificadoTipo,
      cor1: _firstNotEmpty([graduacao?['hex_cor1'], '#FFFFFF']),
      cor2: _firstNotEmpty([graduacao?['hex_cor2'], '#FFFFFF']),
      ponta1: _firstNotEmpty([
        graduacao?['hex_ponta1'],
        graduacao?['hex_cor1'],
        '#FFFFFF',
      ]),
      ponta2: _firstNotEmpty([
        graduacao?['hex_ponta2'],
        graduacao?['hex_cor2'],
        '#FFFFFF',
      ]),
      presente: participacao['presente'] == true,
      aguardandoFinalizacao: participacao['aguardando_finalizacao'] == true,
      statusPagamento: _asString(participacao['status']),
      linkCertificado: _nullableString(participacao['link_certificado']),
      certificadoAtualizadoEm:
      _asDate(participacao['certificado_atualizado_em']),
      certificadoGerado: participacao['certificado_gerado'] == true ||
          _asString(participacao['link_certificado']).isNotEmpty,
      certificadoStatus:
      _firstNotEmpty([participacao['certificado_status'], 'pendente']),
      certificadoImpresso: participacao['certificado_impresso'] == true,
      certificadoImpressoEm: _asDate(participacao['certificado_impresso_em']),
      certificadoLoteImpressao:
      _asInt(participacao['certificado_lote_impressao']),
      certificadoArquivoLote:
      _nullableString(participacao['certificado_arquivo_lote']),
      certificadoLoteId: _nullableString(participacao['certificado_lote_id']),
      certificadoIncluidoZip:
      participacao['certificado_incluido_zip'] == true,
      certificadoPacoteGraficaId:
      _nullableString(participacao['certificado_pacote_grafica_id']),
      certificadoPacoteGraficaNome:
      _nullableString(participacao['certificado_pacote_grafica_nome']),
      certificadoStoragePath:
      _nullableString(participacao['certificado_storage_path']),
      certificadoTipoArquivo:
      _nullableString(participacao['certificado_tipo_arquivo']),
    );
  }

  bool get temCpf => cpf.trim().isNotEmpty;

  bool get temCertificadoGerado {
    return certificadoGerado ||
        (linkCertificado != null && linkCertificado!.trim().isNotEmpty);
  }

  bool get estaQuitado => statusPagamento.toLowerCase().trim() == 'quitado';

  bool get temGraduacaoNova {
    return graduacaoNovaId.trim().isNotEmpty && graduacaoNovaId != '0';
  }

  bool get estaProntoParaGerar {
    return alunoNome.trim().isNotEmpty && temGraduacaoNova;
  }

  CertificadoTemplateTipo tipoTemplate(CertificadoEventoData evento) {
    final forcar = evento.modeloPadrao.toUpperCase();

    switch (forcar) {
      case 'CERTIFICADO':
        return CertificadoTemplateTipo.certificadoSemCpf;
      case 'CERTIFICADOCOMCPF':
        return CertificadoTemplateTipo.certificadoComCpf;
      case 'DIPLOMA':
        return CertificadoTemplateTipo.diploma;
    }

    switch (certificadoOuDiploma.toUpperCase()) {
      case 'CERTIFICADOCOMCPF':
        return CertificadoTemplateTipo.certificadoComCpf;
      case 'DIPLOMA':
        return CertificadoTemplateTipo.diploma;
      case 'CERTIFICADO':
      default:
        return CertificadoTemplateTipo.certificadoSemCpf;
    }
  }

  CertificadoPreviewData toPreviewData(CertificadoEventoData evento) {
    return CertificadoPreviewData(
      alunoNome: alunoNome,
      cpf: cpf,
      graduacaoNova: graduacaoNova,
      frase: frase,
      localData: evento.localData,
      assinaturas: evento.assinaturas
          .map(
            (assinatura) => CertificadoAssinaturaData(
          nome: assinatura.nome,
          apelido: assinatura.apelido,
        ),
      )
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participacao_id': participacaoId,
      'evento_id': eventoId,
      'aluno_id': alunoId,
      'aluno_nome': alunoNome,
      'cpf': cpf,
      'evento_nome': eventoNome,
      'tipo_evento': tipoEvento,
      'graduacao_atual': graduacaoAtual,
      'graduacao_atual_id': graduacaoAtualId,
      'graduacao_nova': graduacaoNova,
      'graduacao_nova_id': graduacaoNovaId,
      'titulo_graduacao': tituloGraduacao,
      'corda': corda,
      'certificado_ou_diploma': certificadoOuDiploma,
      'cor1': cor1,
      'cor2': cor2,
      'ponta1': ponta1,
      'ponta2': ponta2,
      'presente': presente,
      'aguardando_finalizacao': aguardandoFinalizacao,
      'status_pagamento': statusPagamento,
      'link_certificado': linkCertificado,
      'certificado_gerado': certificadoGerado,
      'certificado_status': certificadoStatus,
      'certificado_impresso': certificadoImpresso,
      'certificado_lote_impressao': certificadoLoteImpressao,
      'certificado_arquivo_lote': certificadoArquivoLote,
      'certificado_incluido_zip': certificadoIncluidoZip,
      'tem_certificado_gerado': temCertificadoGerado,
      'esta_quitado': estaQuitado,
    };
  }

  CertificadoParticipanteData copyWith({
    String? participacaoId,
    String? eventoId,
    String? alunoId,
    String? alunoNome,
    String? cpf,
    String? alunoFoto,
    String? eventoNome,
    String? tipoEvento,
    String? graduacaoAtual,
    String? graduacaoAtualId,
    String? graduacaoNova,
    String? graduacaoNovaId,
    String? tituloGraduacao,
    String? corda,
    String? frase,
    String? certificadoOuDiploma,
    String? cor1,
    String? cor2,
    String? ponta1,
    String? ponta2,
    bool? presente,
    bool? aguardandoFinalizacao,
    String? statusPagamento,
    String? linkCertificado,
    DateTime? certificadoAtualizadoEm,
    bool? certificadoGerado,
    String? certificadoStatus,
    bool? certificadoImpresso,
    DateTime? certificadoImpressoEm,
    int? certificadoLoteImpressao,
    String? certificadoArquivoLote,
    String? certificadoLoteId,
    bool? certificadoIncluidoZip,
    String? certificadoPacoteGraficaId,
    String? certificadoPacoteGraficaNome,
    String? certificadoStoragePath,
    String? certificadoTipoArquivo,
  }) {
    return CertificadoParticipanteData(
      participacaoId: participacaoId ?? this.participacaoId,
      eventoId: eventoId ?? this.eventoId,
      alunoId: alunoId ?? this.alunoId,
      alunoNome: alunoNome ?? this.alunoNome,
      cpf: cpf ?? this.cpf,
      alunoFoto: alunoFoto ?? this.alunoFoto,
      eventoNome: eventoNome ?? this.eventoNome,
      tipoEvento: tipoEvento ?? this.tipoEvento,
      graduacaoAtual: graduacaoAtual ?? this.graduacaoAtual,
      graduacaoAtualId: graduacaoAtualId ?? this.graduacaoAtualId,
      graduacaoNova: graduacaoNova ?? this.graduacaoNova,
      graduacaoNovaId: graduacaoNovaId ?? this.graduacaoNovaId,
      tituloGraduacao: tituloGraduacao ?? this.tituloGraduacao,
      corda: corda ?? this.corda,
      frase: frase ?? this.frase,
      certificadoOuDiploma: certificadoOuDiploma ?? this.certificadoOuDiploma,
      cor1: cor1 ?? this.cor1,
      cor2: cor2 ?? this.cor2,
      ponta1: ponta1 ?? this.ponta1,
      ponta2: ponta2 ?? this.ponta2,
      presente: presente ?? this.presente,
      aguardandoFinalizacao:
      aguardandoFinalizacao ?? this.aguardandoFinalizacao,
      statusPagamento: statusPagamento ?? this.statusPagamento,
      linkCertificado: linkCertificado ?? this.linkCertificado,
      certificadoAtualizadoEm:
      certificadoAtualizadoEm ?? this.certificadoAtualizadoEm,
      certificadoGerado: certificadoGerado ?? this.certificadoGerado,
      certificadoStatus: certificadoStatus ?? this.certificadoStatus,
      certificadoImpresso: certificadoImpresso ?? this.certificadoImpresso,
      certificadoImpressoEm:
      certificadoImpressoEm ?? this.certificadoImpressoEm,
      certificadoLoteImpressao:
      certificadoLoteImpressao ?? this.certificadoLoteImpressao,
      certificadoArquivoLote:
      certificadoArquivoLote ?? this.certificadoArquivoLote,
      certificadoLoteId: certificadoLoteId ?? this.certificadoLoteId,
      certificadoIncluidoZip:
      certificadoIncluidoZip ?? this.certificadoIncluidoZip,
      certificadoPacoteGraficaId:
      certificadoPacoteGraficaId ?? this.certificadoPacoteGraficaId,
      certificadoPacoteGraficaNome:
      certificadoPacoteGraficaNome ?? this.certificadoPacoteGraficaNome,
      certificadoStoragePath:
      certificadoStoragePath ?? this.certificadoStoragePath,
      certificadoTipoArquivo:
      certificadoTipoArquivo ?? this.certificadoTipoArquivo,
    );
  }

  static String _asString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  static String? _nullableString(dynamic value) {
    final text = _asString(value);
    if (text.isEmpty) return null;
    return text;
  }

  static String _firstNotEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = _asString(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();

    try {
      final dynamicTimestamp = value;
      final toDate = dynamicTimestamp.toDate;
      if (toDate is Function) {
        return toDate();
      }
    } catch (_) {}

    return null;
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
