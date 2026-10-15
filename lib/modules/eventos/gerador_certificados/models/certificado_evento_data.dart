import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

@immutable
class CertificadoEventoData {
  final String eventoId;
  final String eventoNome;
  final String tipoEvento;
  final DateTime dataEvento;
  final String horario;
  final String local;
  final String cidade;
  final String localData;
  final bool temCertificado;
  final bool geraCertificado;
  final String modeloPadrao;
  final ConfiguracoesCertificadoEvento configuracoes;
  final List<AssinaturaCertificadoEvento> assinaturas;

  const CertificadoEventoData({
    required this.eventoId,
    required this.eventoNome,
    required this.tipoEvento,
    required this.dataEvento,
    required this.horario,
    required this.local,
    required this.cidade,
    required this.localData,
    required this.temCertificado,
    required this.geraCertificado,
    required this.modeloPadrao,
    required this.configuracoes,
    required this.assinaturas,
  });

  factory CertificadoEventoData.fromEvento(EventoModel evento) {
    final config = evento.configuracoesCertificadoEvento;

    return CertificadoEventoData(
      eventoId: evento.id ?? '',
      eventoNome: evento.nome,
      tipoEvento: evento.tipo,
      dataEvento: evento.data,
      horario: evento.horario,
      local: evento.local,
      cidade: evento.cidade,
      localData: evento.localDataCertificado,
      temCertificado: evento.temCertificado,
      geraCertificado: evento.geraCertificado,
      modeloPadrao: config.modeloPadrao,
      configuracoes: config,
      // Renderização precisa dos 5 slots, inclusive lacunas.
      assinaturas: config.assinaturasPorSlot,
    );
  }

  int get quantidadeAssinaturasValidas =>
      assinaturas.where((item) => item.preenchida).length;

  bool get temAssinaturaValida => quantidadeAssinaturasValidas > 0;

  bool get exigeAssinaturas {
    final studio = configuracoes.studio;
    return studio.blocoAtivo('assinatura_nome') ||
        studio.blocoAtivo('assinatura_apelido');
  }

  bool get exigePdfIndividual => tipoEvento.toUpperCase().contains('DESTAQUE') &&
      configuracoes.studio.ehGraduacao;

  bool get podeGerarCertificados {
    return eventoId.trim().isNotEmpty &&
        temCertificado &&
        geraCertificado &&
        configuracoes.ativo &&
        (exigePdfIndividual || !exigeAssinaturas || temAssinaturaValida);
  }

  bool get usaModeloAutomatico {
    return configuracoes.studio.ehGraduacao &&
        modeloPadrao == ConfiguracoesCertificadoEvento.modeloAutomatico;
  }

  String get finalidadeCertificado => configuracoes.studio.finalidade;
  String get finalidadeCertificadoLabel => configuracoes.studio.finalidadeLabel;

  /// Slot semântico estável da emissão oficial.
  /// Permite mais de um certificado oficial para a mesma participação/evento.
  String get emissaoCertificadoKey {
    String slug(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    final finalidade = slug(finalidadeCertificado);
    final base = finalidade.isEmpty ? 'certificado' : finalidade;
    if (base != 'livre' && base != 'personalizado') return base;

    final template = slug(configuracoes.studio.templateId ?? '');
    return template.isEmpty ? '${base}_padrao' : '${base}_$template';
  }

  String get statusResumo {
    if (exigePdfIndividual) return 'PDF individual por participante';
    if (!temCertificado) return 'Certificados desativados';
    if (!geraCertificado) return 'Evento não marcado para gerar certificados';
    if (!configuracoes.ativo) return 'Configuração de certificado desativada';
    if (exigeAssinaturas && !temAssinaturaValida) {
      return 'Template exige assinatura, mas nenhuma foi configurada';
    }
    return 'Pronto para gerar certificados';
  }

  String get modeloPadraoLabel {
    if (exigePdfIndividual) return 'PDF individual por participante';
    if (!configuracoes.studio.ehGraduacao) {
      return configuracoes.studio.finalidadeLabel;
    }
    switch (modeloPadrao) {
      case 'CERTIFICADO':
        return 'Certificado simples';
      case 'CERTIFICADOCOMCPF':
        return 'Certificado com CPF';
      case 'DIPLOMA':
        return 'Diploma';
      case ConfiguracoesCertificadoEvento.modeloAutomatico:
      default:
        return 'Automático pela graduação';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'evento_id': eventoId,
      'evento_nome': eventoNome,
      'tipo_evento': tipoEvento,
      'data_evento': dataEvento.toIso8601String(),
      'horario': horario,
      'local': local,
      'cidade': cidade,
      'local_data': localData,
      'tem_certificado': temCertificado,
      'gera_certificado': geraCertificado,
      'modelo_padrao': modeloPadrao,
      'modelo_padrao_label': modeloPadraoLabel,
      'finalidade_certificado': finalidadeCertificado,
      'finalidade_certificado_label': finalidadeCertificadoLabel,
      'pode_gerar_certificados': podeGerarCertificados,
      'status_resumo': statusResumo,
      'assinaturas': assinaturas.map((e) => e.toMap()).toList(),
      'configuracoes': configuracoes.toMap(),
    };
  }

  CertificadoEventoData copyWith({
    String? eventoId,
    String? eventoNome,
    String? tipoEvento,
    DateTime? dataEvento,
    String? horario,
    String? local,
    String? cidade,
    String? localData,
    bool? temCertificado,
    bool? geraCertificado,
    String? modeloPadrao,
    ConfiguracoesCertificadoEvento? configuracoes,
    List<AssinaturaCertificadoEvento>? assinaturas,
  }) {
    return CertificadoEventoData(
      eventoId: eventoId ?? this.eventoId,
      eventoNome: eventoNome ?? this.eventoNome,
      tipoEvento: tipoEvento ?? this.tipoEvento,
      dataEvento: dataEvento ?? this.dataEvento,
      horario: horario ?? this.horario,
      local: local ?? this.local,
      cidade: cidade ?? this.cidade,
      localData: localData ?? this.localData,
      temCertificado: temCertificado ?? this.temCertificado,
      geraCertificado: geraCertificado ?? this.geraCertificado,
      modeloPadrao: modeloPadrao ?? this.modeloPadrao,
      configuracoes: configuracoes ?? this.configuracoes,
      assinaturas: assinaturas ?? this.assinaturas,
    );
  }
}
