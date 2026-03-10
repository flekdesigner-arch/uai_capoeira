import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // Para Colors
import 'package:intl/intl.dart'; // Para DateFormat

class ParticipacaoModel {
  final String? id;
  final String alunoId;
  final String alunoNome;
  final String? alunoFoto;
  final String eventoId;
  final String eventoNome;
  final DateTime dataEvento;
  final String tipoEvento;
  final String? graduacao;
  final String? graduacaoId;
  final String? tamanhoCamisa;
  final String? linkCertificado;
  final bool presente;
  final String status; // 'pendente', 'quitado', 'finalizado'
  final Timestamp? criadoEm;
  final Timestamp? atualizadoEm;

  // Campos específicos para batizado
  final String? graduacaoNova;
  final String? graduacaoNovaId;

  // 🔥 NOVOS CAMPOS FINANCEIROS
  final bool camisaEntregue;
  final double valorInscricao;
  final double valorCamisa;
  final double totalPago;

  // 🔥 Getter para valor total
  double get valorTotal => valorInscricao + valorCamisa;

  ParticipacaoModel({
    this.id,
    required this.alunoId,
    required this.alunoNome,
    this.alunoFoto,
    required this.eventoId,
    required this.eventoNome,
    required this.dataEvento,
    required this.tipoEvento,
    this.graduacao,
    this.graduacaoId,
    this.tamanhoCamisa,
    this.linkCertificado,
    this.presente = false,
    this.status = 'pendente',
    this.criadoEm,
    this.atualizadoEm,
    this.graduacaoNova,
    this.graduacaoNovaId,
    // 🔥 NOVOS CAMPOS COM VALORES PADRÃO
    this.camisaEntregue = false,
    this.valorInscricao = 0,
    this.valorCamisa = 0,
    this.totalPago = 0,
  });

  /// Getter para data formatada
  String get dataFormatada {
    final DateFormat formatter = DateFormat('dd/MM/yyyy');
    return formatter.format(dataEvento);
  }

  /// Verifica se é batizado
  bool get isBatizado => tipoEvento.toUpperCase().contains('BATIZADO');

  /// Verifica se está aguardando finalização (batizado)
  bool get aguardandoFinalizacao => isBatizado && status == 'pendente' && graduacaoNova != null;

  /// Verifica se já foi finalizado
  bool get estaFinalizado => status == 'finalizado';

  /// 🔥 Verifica se está quitado
  bool get estaQuitado => totalPago >= valorTotal;

  /// 🔥 Saldo devedor
  double get saldoDevedor => valorTotal - totalPago;

  /// 🔥 Número de parcelas (baseado em regra de negócio - pode ser ajustado)
  int get parcelas {
    // TODO: Implementar lógica real de parcelas baseada no evento
    return 1;
  }

  /// Cor baseada no status
  Color get corStatus {
    switch (status) {
      case 'finalizado':
        return Colors.green;
      case 'quitado':
        return Colors.blue;
      case 'pendente':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Texto do status
  String get textoStatus {
    switch (status) {
      case 'finalizado':
        return '✅ FINALIZADO';
      case 'quitado':
        return '💰 QUITADO';
      case 'pendente':
        return '⏳ PENDENTE';
      default:
        return status.toUpperCase();
    }
  }

  /// Converte para Map para salvar no Firestore
  Map<String, dynamic> toMap() {
    final map = {
      'aluno_id': alunoId,
      'aluno_nome': alunoNome,
      'aluno_foto': alunoFoto,
      'evento_id': eventoId,
      'evento_nome': eventoNome,
      'data_evento': Timestamp.fromDate(dataEvento),
      'tipo_evento': tipoEvento,
      'graduacao': graduacao,
      'graduacao_id': graduacaoId,
      'tamanho_camisa': tamanhoCamisa,
      'link_certificado': linkCertificado,
      'presente': presente,
      'status': status,
      'criado_em': criadoEm ?? FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
      // 🔥 NOVOS CAMPOS
      'camisa_entregue': camisaEntregue,
      'valor_inscricao': valorInscricao,
      'valor_camisa': valorCamisa,
      'total_pago': totalPago,
    };

    // Adiciona campos de batizado se existirem
    if (graduacaoNova != null) {
      map['graduacao_nova'] = graduacaoNova;
    }
    if (graduacaoNovaId != null) {
      map['graduacao_nova_id'] = graduacaoNovaId;
    }

    return map;
  }

  /// Cria uma instância a partir do Firestore
  factory ParticipacaoModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data()!;

    // Trata a data que pode vir como Timestamp ou String
    DateTime dataEvento;
    if (data['data_evento'] is Timestamp) {
      dataEvento = (data['data_evento'] as Timestamp).toDate();
    } else if (data['data_evento'] is String) {
      dataEvento = DateTime.parse(data['data_evento'] as String);
    } else {
      dataEvento = DateTime.now();
    }

    return ParticipacaoModel(
      id: doc.id,
      alunoId: data['aluno_id'] ?? '',
      alunoNome: data['aluno_nome'] ?? '',
      alunoFoto: data['aluno_foto'] as String?,
      eventoId: data['evento_id'] ?? '',
      eventoNome: data['evento_nome'] ?? '',
      dataEvento: dataEvento,
      tipoEvento: data['tipo_evento'] ?? 'EVENTO',
      graduacao: data['graduacao'] as String?,
      graduacaoId: data['graduacao_id'] as String?,
      tamanhoCamisa: data['tamanho_camisa'] as String?,
      linkCertificado: data['link_certificado'] as String?,
      presente: data['presente'] ?? false,
      status: data['status'] ?? 'pendente',
      criadoEm: data['criado_em'] as Timestamp?,
      atualizadoEm: data['atualizado_em'] as Timestamp?,
      graduacaoNova: data['graduacao_nova'] as String?,
      graduacaoNovaId: data['graduacao_nova_id'] as String?,
      // 🔥 NOVOS CAMPOS
      camisaEntregue: data['camisa_entregue'] ?? false,
      valorInscricao: (data['valor_inscricao'] ?? 0).toDouble(),
      valorCamisa: (data['valor_camisa'] ?? 0).toDouble(),
      totalPago: (data['total_pago'] ?? 0).toDouble(),
    );
  }

  /// Cria uma instância a partir de um Map (para compatibilidade)
  factory ParticipacaoModel.fromMap(String id, Map<String, dynamic> map) {
    // Trata a data que pode vir como Timestamp ou String
    DateTime dataEvento;
    if (map['data_evento'] is Timestamp) {
      dataEvento = (map['data_evento'] as Timestamp).toDate();
    } else if (map['data_evento'] is String) {
      dataEvento = DateTime.parse(map['data_evento'] as String);
    } else {
      dataEvento = DateTime.now();
    }

    return ParticipacaoModel(
      id: id,
      alunoId: map['aluno_id'] ?? '',
      alunoNome: map['aluno_nome'] ?? '',
      alunoFoto: map['aluno_foto'] as String?,
      eventoId: map['evento_id'] ?? '',
      eventoNome: map['evento_nome'] ?? '',
      dataEvento: dataEvento,
      tipoEvento: map['tipo_evento'] ?? 'EVENTO',
      graduacao: map['graduacao'] as String?,
      graduacaoId: map['graduacao_id'] as String?,
      tamanhoCamisa: map['tamanho_camisa'] as String?,
      linkCertificado: map['link_certificado'] as String?,
      presente: map['presente'] ?? false,
      status: map['status'] ?? 'pendente',
      criadoEm: map['criado_em'] as Timestamp?,
      atualizadoEm: map['atualizado_em'] as Timestamp?,
      graduacaoNova: map['graduacao_nova'] as String?,
      graduacaoNovaId: map['graduacao_nova_id'] as String?,
      camisaEntregue: map['camisa_entregue'] ?? false,
      valorInscricao: (map['valor_inscricao'] ?? 0).toDouble(),
      valorCamisa: (map['valor_camisa'] ?? 0).toDouble(),
      totalPago: (map['total_pago'] ?? 0).toDouble(),
    );
  }

  /// Cria uma cópia com campos alterados
  ParticipacaoModel copyWith({
    String? id,
    String? alunoId,
    String? alunoNome,
    String? alunoFoto,
    String? eventoId,
    String? eventoNome,
    DateTime? dataEvento,
    String? tipoEvento,
    String? graduacao,
    String? graduacaoId,
    String? tamanhoCamisa,
    String? linkCertificado,
    bool? presente,
    String? status,
    Timestamp? criadoEm,
    Timestamp? atualizadoEm,
    String? graduacaoNova,
    String? graduacaoNovaId,
    bool? camisaEntregue,
    double? valorInscricao,
    double? valorCamisa,
    double? totalPago,
  }) {
    return ParticipacaoModel(
      id: id ?? this.id,
      alunoId: alunoId ?? this.alunoId,
      alunoNome: alunoNome ?? this.alunoNome,
      alunoFoto: alunoFoto ?? this.alunoFoto,
      eventoId: eventoId ?? this.eventoId,
      eventoNome: eventoNome ?? this.eventoNome,
      dataEvento: dataEvento ?? this.dataEvento,
      tipoEvento: tipoEvento ?? this.tipoEvento,
      graduacao: graduacao ?? this.graduacao,
      graduacaoId: graduacaoId ?? this.graduacaoId,
      tamanhoCamisa: tamanhoCamisa ?? this.tamanhoCamisa,
      linkCertificado: linkCertificado ?? this.linkCertificado,
      presente: presente ?? this.presente,
      status: status ?? this.status,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      graduacaoNova: graduacaoNova ?? this.graduacaoNova,
      graduacaoNovaId: graduacaoNovaId ?? this.graduacaoNovaId,
      camisaEntregue: camisaEntregue ?? this.camisaEntregue,
      valorInscricao: valorInscricao ?? this.valorInscricao,
      valorCamisa: valorCamisa ?? this.valorCamisa,
      totalPago: totalPago ?? this.totalPago,
    );
  }

  /// Método para debug
  @override
  String toString() {
    return 'ParticipacaoModel(id: $id, aluno: $alunoNome, evento: $eventoNome, status: $status, valor: R\$ ${valorTotal.toStringAsFixed(2)})';
  }
}