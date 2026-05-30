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
      assinaturas: config.assinaturasValidas,
    );
  }

  bool get podeGerarCertificados {
    return eventoId.trim().isNotEmpty &&
        temCertificado &&
        geraCertificado &&
        configuracoes.ativo &&
        assinaturas.isNotEmpty;
  }

  bool get usaModeloAutomatico {
    return modeloPadrao == ConfiguracoesCertificadoEvento.modeloAutomatico;
  }

  String get statusResumo {
    if (!temCertificado) return 'Certificados desativados';
    if (!geraCertificado) return 'Evento não marcado para gerar certificados';
    if (!configuracoes.ativo) return 'Configuração de certificado desativada';
    if (assinaturas.isEmpty) return 'Nenhuma assinatura configurada';
    return 'Pronto para gerar certificados';
  }

  String get modeloPadraoLabel {
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
