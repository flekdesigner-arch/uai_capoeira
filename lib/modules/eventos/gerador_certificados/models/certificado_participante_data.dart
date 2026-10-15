import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';

@immutable
class CertificadoParticipanteData {
  bool get pdfImportado => (certificadoStoragePath ?? '').contains('/importados/');

  final String participacaoId;
  final String eventoId;
  final String alunoId;
  final String alunoNome;
  final String cpf;
  final String sexo;
  final String alunoFoto;
  final String academiaId;
  final String academiaNome;
  final String turmaId;
  final String turmaNome;
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

  // Identidade oficial V2 / autenticidade pública.
  final String? certificadoEmissaoV2Id;
  final String? certificadoCodigoPublico;
  final String? certificadoCodigo;
  final String? certificadoUrlAutenticidade;
  final String? certificadoEmissaoV2Status;
  final String? certificadoEmissaoV2Key;
  final Map<String, Map<String, dynamic>> certificadoEmissoesV2;

  const CertificadoParticipanteData({
    required this.participacaoId,
    required this.eventoId,
    required this.alunoId,
    required this.alunoNome,
    required this.cpf,
    this.sexo = '',
    required this.alunoFoto,
    this.academiaId = '',
    this.academiaNome = '',
    this.turmaId = '',
    this.turmaNome = '',
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
    this.certificadoEmissaoV2Id,
    this.certificadoCodigoPublico,
    this.certificadoCodigo,
    this.certificadoUrlAutenticidade,
    this.certificadoEmissaoV2Status,
    this.certificadoEmissaoV2Key,
    this.certificadoEmissoesV2 = const {},
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

    final sexo = _normalizarSexo(
      _firstNotEmpty([
        participacao['sexo'],
        participacao['aluno_sexo'],
        participacao['sexo_aluno'],
        aluno?['sexo'],
        aluno?['genero'],
        aluno?['gênero'],
      ]),
    );

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
      sexo: sexo,
      alunoFoto: _firstNotEmpty([
        participacao['aluno_foto'],
        aluno?['foto'],
        aluno?['foto_url'],
        aluno?['link_foto'],
      ]),
      academiaId: _firstNotEmpty([
        participacao['academia_id'],
        aluno?['academia_id'],
      ]),
      academiaNome: _firstNotEmpty([
        participacao['academia_nome'],
        participacao['academia'],
        aluno?['academia_nome'],
        aluno?['academia'],
      ]),
      turmaId: _firstNotEmpty([
        participacao['turma_id'],
        aluno?['turma_id'],
      ]),
      turmaNome: _firstNotEmpty([
        participacao['turma_nome'],
        participacao['turma'],
        aluno?['turma_nome'],
        aluno?['turma'],
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
      corda: _firstNotEmpty([graduacao?['corda'], graduacaoNova]),
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
      certificadoAtualizadoEm: _asDate(
        participacao['certificado_atualizado_em'],
      ),
      certificadoGerado:
          participacao['certificado_gerado'] == true ||
          _asString(participacao['link_certificado']).isNotEmpty,
      certificadoStatus: _firstNotEmpty([
        participacao['certificado_status'],
        'pendente',
      ]),
      certificadoImpresso: participacao['certificado_impresso'] == true,
      certificadoImpressoEm: _asDate(participacao['certificado_impresso_em']),
      certificadoLoteImpressao: _asInt(
        participacao['certificado_lote_impressao'],
      ),
      certificadoArquivoLote: _nullableString(
        participacao['certificado_arquivo_lote'],
      ),
      certificadoLoteId: _nullableString(participacao['certificado_lote_id']),
      certificadoIncluidoZip: participacao['certificado_incluido_zip'] == true,
      certificadoPacoteGraficaId: _nullableString(
        participacao['certificado_pacote_grafica_id'],
      ),
      certificadoPacoteGraficaNome: _nullableString(
        participacao['certificado_pacote_grafica_nome'],
      ),
      certificadoStoragePath: _nullableString(
        participacao['certificado_storage_path'],
      ),
      certificadoTipoArquivo: _nullableString(
        participacao['certificado_tipo_arquivo'],
      ),
      certificadoEmissaoV2Id: _nullableString(
        participacao['certificado_emissao_v2_id'],
      ),
      certificadoCodigoPublico: _nullableString(
        participacao['certificado_codigo_publico'],
      ),
      certificadoCodigo: _nullableString(
        participacao['certificado_codigo'],
      ),
      certificadoUrlAutenticidade: _nullableString(
        participacao['certificado_url_autenticidade'],
      ),
      certificadoEmissaoV2Status: _nullableString(
        participacao['certificado_emissao_v2_status'],
      ),
      certificadoEmissaoV2Key: _nullableString(
        participacao['certificado_emissao_v2_key'],
      ),
      certificadoEmissoesV2: _mapEmissoesV2(
        participacao['certificado_emissoes_v2'],
      ),
    );
  }

  bool get temCpf => cpf.trim().isNotEmpty;

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

  String get statusEmissaoV2Normalizado =>
      (certificadoEmissaoV2Status ?? '').trim().toLowerCase();

  Map<String, dynamic>? emissaoV2ParaEvento(CertificadoEventoData evento) {
    final key = evento.emissaoCertificadoKey;
    final registro = certificadoEmissoesV2[key];
    if (registro != null) return registro;

    // Compatibilidade com emissões anteriores ao Patch 3.
    final keyAtual = (certificadoEmissaoV2Key ?? '').trim();
    final compativelLegado = keyAtual.isEmpty && key == 'graduacao';
    if (keyAtual == key || compativelLegado) {
      return {
        'id': certificadoEmissaoV2Id,
        'key': keyAtual.isEmpty ? key : keyAtual,
        'codigo_publico': certificadoCodigoPublico,
        'codigo': certificadoCodigo,
        'url_autenticidade': certificadoUrlAutenticidade,
        'status': certificadoEmissaoV2Status,
      };
    }
    return null;
  }

  bool temEmissaoOficialV2NoEvento(CertificadoEventoData evento) {
    final registro = emissaoV2ParaEvento(evento);
    if (registro == null) return false;
    final id = (registro['id'] ?? '').toString().trim();
    final codigo = (registro['codigo_publico'] ?? '').toString().trim();
    final url = (registro['url_autenticidade'] ?? '').toString().trim();
    if (id.isEmpty || codigo.isEmpty || url.isEmpty) return false;
    final status = (registro['status'] ?? '').toString().trim().toLowerCase();
    return status == 'valido' || status.isEmpty;
  }

  String codigoValidacaoNoEvento(CertificadoEventoData evento) {
    final registro = emissaoV2ParaEvento(evento);
    if (registro == null) return '';
    final humano = (registro['codigo'] ?? '').toString().trim();
    if (humano.isNotEmpty) return humano;
    return (registro['codigo_publico'] ?? '').toString().trim();
  }

  String urlAutenticidadeNoEvento(CertificadoEventoData evento) {
    return (emissaoV2ParaEvento(evento)?['url_autenticidade'] ?? '')
        .toString()
        .trim();
  }

  String statusEmissaoV2NoEvento(CertificadoEventoData evento) {
    return (emissaoV2ParaEvento(evento)?['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  bool get temIdentidadeV2Completa {
    return (certificadoEmissaoV2Id?.trim().isNotEmpty ?? false) &&
        (certificadoCodigoPublico?.trim().isNotEmpty ?? false) &&
        (certificadoUrlAutenticidade?.trim().isNotEmpty ?? false);
  }

  bool get temEmissaoOficialV2 {
    if (!temIdentidadeV2Completa) return false;

    final status = statusEmissaoV2Normalizado;
    if (status == 'valido') return true;

    // Retrocompatibilidade: emissões válidas criadas antes do Patch 2 não
    // possuíam certificado_emissao_v2_status na participação.
    return status.isEmpty;
  }

  bool get emissaoV2EmAndamento => const {
        'preparando',
        'gerando',
        'publicando',
      }.contains(statusEmissaoV2Normalizado);

  bool get emissaoV2ComErro => statusEmissaoV2Normalizado == 'erro';

  String get codigoValidacaoExibicao {
    final humano = certificadoCodigo?.trim() ?? '';
    if (humano.isNotEmpty) return humano;
    return certificadoCodigoPublico?.trim() ?? '';
  }

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

  /// Validação contextual para o Studio NASA.
  ///
  /// Mantém [estaProntoParaGerar] intacto para compatibilidade com fluxos
  /// legados, mas permite templates genéricos (homenagem, aluno destaque,
  /// participação etc.) que não usam graduação.
  bool estaProntoParaGerarNoEvento(CertificadoEventoData evento) {
    if (alunoNome.trim().isEmpty) return false;

    final studio = evento.configuracoes.studio;
    final exigeGraduacao = studio.ehGraduacao || studio.blocoAtivo('graduacao');
    if (exigeGraduacao && !temGraduacaoNova) return false;

    final modeloForcaCpf = studio.ehGraduacao &&
        evento.modeloPadrao.toUpperCase() == 'CERTIFICADOCOMCPF';
    if (modeloForcaCpf && cpf.trim().isEmpty) return false;

    return true;
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
      sexo: sexoNormalizado,
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
      'academia_id': academiaId,
      'academia_nome': academiaNome,
      'turma_id': turmaId,
      'turma_nome': turmaNome,
      'cpf': cpf,
      'sexo': sexoNormalizado,
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
      'certificado_emissao_v2_key': certificadoEmissaoV2Key,
      'certificado_emissoes_v2': certificadoEmissoesV2,
    };
  }

  CertificadoParticipanteData copyWith({
    String? participacaoId,
    String? eventoId,
    String? alunoId,
    String? alunoNome,
    String? cpf,
    String? sexo,
    String? alunoFoto,
    String? academiaId,
    String? academiaNome,
    String? turmaId,
    String? turmaNome,
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
    String? certificadoEmissaoV2Id,
    String? certificadoCodigoPublico,
    String? certificadoCodigo,
    String? certificadoUrlAutenticidade,
    String? certificadoEmissaoV2Key,
    Map<String, Map<String, dynamic>>? certificadoEmissoesV2,
  }) {
    return CertificadoParticipanteData(
      participacaoId: participacaoId ?? this.participacaoId,
      eventoId: eventoId ?? this.eventoId,
      alunoId: alunoId ?? this.alunoId,
      alunoNome: alunoNome ?? this.alunoNome,
      cpf: cpf ?? this.cpf,
      sexo: sexo ?? this.sexo,
      alunoFoto: alunoFoto ?? this.alunoFoto,
      academiaId: academiaId ?? this.academiaId,
      academiaNome: academiaNome ?? this.academiaNome,
      turmaId: turmaId ?? this.turmaId,
      turmaNome: turmaNome ?? this.turmaNome,
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
      certificadoEmissaoV2Id:
          certificadoEmissaoV2Id ?? this.certificadoEmissaoV2Id,
      certificadoCodigoPublico:
          certificadoCodigoPublico ?? this.certificadoCodigoPublico,
      certificadoCodigo: certificadoCodigo ?? this.certificadoCodigo,
      certificadoUrlAutenticidade:
          certificadoUrlAutenticidade ?? this.certificadoUrlAutenticidade,
      certificadoEmissaoV2Status: certificadoEmissaoV2Status,
      certificadoEmissaoV2Key:
          certificadoEmissaoV2Key ?? this.certificadoEmissaoV2Key,
      certificadoEmissoesV2:
          certificadoEmissoesV2 ?? this.certificadoEmissoesV2,
    );
  }

  static Map<String, Map<String, dynamic>> _mapEmissoesV2(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, Map<String, dynamic>>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      final value = entry.value;
      if (key.isEmpty || value is! Map) continue;
      result[key] = Map<String, dynamic>.from(value);
    }
    return result;
  }

  static String _normalizarSexo(String value) {
    final clean = value.trim().toUpperCase();

    if (clean.isEmpty) return '';

    if (clean == 'F' ||
        clean == 'FEMININO' ||
        clean == 'MULHER' ||
        clean == 'MENINA' ||
        clean == 'ALUNA') {
      return 'FEMININO';
    }

    if (clean == 'M' ||
        clean == 'MASCULINO' ||
        clean == 'HOMEM' ||
        clean == 'MENINO' ||
        clean == 'ALUNO') {
      return 'MASCULINO';
    }

    return clean;
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
