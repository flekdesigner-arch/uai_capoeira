import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CampeonatoModel {
  final String id;
  final String nome;
  final DateTime data;
  final String horario;
  final String local;
  final String cidade;
  final double taxaInscricao;
  final int vagasDisponiveis;
  final List<CategoriaCampeonato> categorias;
  final bool ativo;
  final String? linkBanner;
  final String? regulamento;
  final List<String> organizadores;
  final String status; // 'ativo', 'andamento', 'finalizado'

  CampeonatoModel({
    required this.id,
    required this.nome,
    required this.data,
    required this.horario,
    required this.local,
    required this.cidade,
    required this.taxaInscricao,
    required this.vagasDisponiveis,
    required this.categorias,
    required this.ativo,
    this.linkBanner,
    this.regulamento,
    required this.organizadores,
    required this.status,
  });

  // Data formatada
  String get dataFormatada {
    return DateFormat('dd/MM/yyyy').format(data);
  }

  // Factory method para criar a partir do Firestore
  factory CampeonatoModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Converter categorias
    List<CategoriaCampeonato> categorias = [];
    if (data['categorias'] != null) {
      categorias = (data['categorias'] as List)
          .map((cat) => CategoriaCampeonato.fromMap(cat))
          .toList();
    }

    return CampeonatoModel(
      id: doc.id,
      nome: data['nome_campeonato'] ?? data['nome'] ?? '',
      data: (data['data_evento'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horario: data['horario_evento'] ?? '',
      local: data['local_evento'] ?? '',
      cidade: data['cidade'] ?? '',
      taxaInscricao: (data['taxa_inscricao'] ?? 0.0).toDouble(),
      vagasDisponiveis: data['vagas_disponiveis'] ?? 0,
      categorias: categorias,
      ativo: data['campeonato_ativo'] ?? false,
      linkBanner: data['link_banner'],
      regulamento: data['texto_regulamento'],
      organizadores: List<String>.from(data['organizadores'] ?? []),
      status: data['status'] ?? 'ativo',
    );
  }

  // Método para converter para Map (para salvar)
  Map<String, dynamic> toMap() {
    return {
      'nome_campeonato': nome,
      'data_evento': Timestamp.fromDate(data),
      'horario_evento': horario,
      'local_evento': local,
      'cidade': cidade,
      'taxa_inscricao': taxaInscricao,
      'vagas_disponiveis': vagasDisponiveis,
      'categorias': categorias.map((cat) => cat.toMap()).toList(),
      'campeonato_ativo': ativo,
      'link_banner': linkBanner,
      'texto_regulamento': regulamento,
      'organizadores': organizadores,
      'status': status,
    };
  }
}

class CategoriaCampeonato {
  final String id;
  final String nome;
  final int idadeMin;
  final int idadeMax;
  final String sexo; // 'MASCULINO', 'FEMININO', 'MISTO'
  final double taxa;

  CategoriaCampeonato({
    required this.id,
    required this.nome,
    required this.idadeMin,
    required this.idadeMax,
    required this.sexo,
    required this.taxa,
  });

  factory CategoriaCampeonato.fromMap(Map<String, dynamic> map) {
    return CategoriaCampeonato(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      idadeMin: map['idade_min'] ?? 0,
      idadeMax: map['idade_max'] ?? 0,
      sexo: map['sexo'] ?? 'MISTO',
      taxa: (map['taxa'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'idade_min': idadeMin,
      'idade_max': idadeMax,
      'sexo': sexo,
      'taxa': taxa,
    };
  }
}

// 👇 A CLASSE InscricaoCampeonatoModel FOI REMOVIDA DAQUI!
// Agora ela está em 'inscricao_campeonato_model.dart'