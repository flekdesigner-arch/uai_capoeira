import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class GraduacaoModel {
  final String id;
  final String nome;
  final int nivel;
  final String cor1;
  final String cor2;
  final String ponta1;
  final String ponta2;
  final String titulo;

  GraduacaoModel({
    required this.id,
    required this.nome,
    required this.nivel,
    required this.cor1,
    required this.cor2,
    required this.ponta1,
    required this.ponta2,
    required this.titulo,
  });

  factory GraduacaoModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return GraduacaoModel(
      id: doc.id,
      nome: data['nome_graduacao'] ?? '',
      nivel: data['nivel_graduacao'] ?? 0,
      cor1: data['hex_cor1'] ?? '#FFFFFF',
      cor2: data['hex_cor2'] ?? '#FFFFFF',
      ponta1: data['hex_ponta1'] ?? '#FFFFFF',
      ponta2: data['hex_ponta2'] ?? '#FFFFFF',
      titulo: data['titulo_graduacao'] ?? 'ALUNO',
    );
  }

  // Retorna as cores para o SVG
  Map<String, Color> get cores {
    return {
      'cor1': _hexToColor(cor1),
      'cor2': _hexToColor(cor2),
      'ponta1': _hexToColor(ponta1),
      'ponta2': _hexToColor(ponta2),
    };
  }

  static Color _hexToColor(String hex) {
    String hexClean = hex.replaceFirst('#', '');
    if (hexClean.length == 6) {
      return Color(int.parse('FF$hexClean', radix: 16));
    } else if (hexClean.length == 8) {
      return Color(int.parse(hexClean, radix: 16));
    }
    return Colors.grey;
  }

  // Cor principal para gráficos
  Color get corPrincipal => _hexToColor(cor1);

  // Nome resumido para exibição
  String get nomeResumido {
    if (nome.contains('-')) {
      return nome.split('-').last.trim();
    }
    return nome;
  }
}