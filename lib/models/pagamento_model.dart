import 'package:cloud_firestore/cloud_firestore.dart';

class PagamentoModel {
  final String id;
  final double valor;
  final String formaPagamento;
  final DateTime dataPagamento;
  final String? observacoes;
  final String registroPor;
  final String registroPorNome;
  final int? parcela;
  final String? anexo;
  final String status; // 'confirmado', 'pendente'

  PagamentoModel({
    required this.id,
    required this.valor,
    required this.formaPagamento,
    required this.dataPagamento,
    this.observacoes,
    required this.registroPor,
    required this.registroPorNome,
    this.parcela,
    this.anexo,
    this.status = 'confirmado',
  });

  Map<String, dynamic> toMap() {
    return {
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'data_pagamento': Timestamp.fromDate(dataPagamento),
      'observacoes': observacoes,
      'registro_por': registroPor,
      'registro_por_nome': registroPorNome,
      'parcela': parcela,
      'anexo': anexo,
      'status': status,
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  factory PagamentoModel.fromMap(String id, Map<String, dynamic> map) {
    return PagamentoModel(
      id: id,
      valor: (map['valor'] ?? 0).toDouble(),
      formaPagamento: map['forma_pagamento'] ?? '',
      dataPagamento: (map['data_pagamento'] as Timestamp).toDate(),
      observacoes: map['observacoes'],
      registroPor: map['registro_por'] ?? '',
      registroPorNome: map['registro_por_nome'] ?? '',
      parcela: map['parcela'],
      anexo: map['anexo'],
      status: map['status'] ?? 'confirmado',
    );
  }
}