// models/frequencia_model.dart
import 'package:flutter/material.dart';

class FrequenciaModel {
  final int diasSemTreinar;
  final Color corIndicador;
  final String nivel; // "ALTA", "MÉDIA", "BAIXA", "TURISTA", "INATIVO(A)"
  final DateTime? ultimaPresenca;
  final String statusTexto;

  FrequenciaModel({
    required this.diasSemTreinar,
    required this.corIndicador,
    required this.nivel,
    this.ultimaPresenca,
    required this.statusTexto,
  });

  factory FrequenciaModel.vazia() {
    return FrequenciaModel(
      diasSemTreinar: 999,
      corIndicador: Colors.grey,
      nivel: "SEM DADOS",
      statusTexto: "Nunca presente",
    );
  }

  factory FrequenciaModel.calcular(DateTime? ultimoDiaPresente) {
    if (ultimoDiaPresente == null) {
      return FrequenciaModel(
        diasSemTreinar: 999,
        corIndicador: Colors.red,
        nivel: "INATIVO(A)",
        ultimaPresenca: null,
        statusTexto: "Nunca presente",
      );
    }

    final agora = DateTime.now();
    final diferenca = agora.difference(ultimoDiaPresente);
    final dias = diferenca.inDays;

    Color cor;
    String nivel;
    String statusTexto;

    // 🔥 SUA REGRA DE NEGÓCIO:
    // ≤ 4 dias → 🔵 ALTA
    // ≤ 7 dias → 🟢 MÉDIA
    // ≤ 14 dias → 🟡 BAIXA
    // ≤ 35 dias → 🟠 TURISTA
    // > 35 dias → 🔴 INATIVO(A)

    if (dias <= 4) {
      cor = Colors.blue;      // 🔵 Azul
      nivel = "ALTA";
      statusTexto = "Treinou há $dias ${dias == 1 ? 'dia' : 'dias'}";
    } else if (dias <= 7) {
      cor = Colors.green;     // 🟢 Verde
      nivel = "MÉDIA";
      statusTexto = "Treinou há $dias dias";
    } else if (dias <= 14) {
      cor = Colors.amber;     // 🟡 Amarelo
      nivel = "BAIXA";
      statusTexto = "Treinou há $dias dias";
    } else if (dias <= 35) {
      cor = Colors.orange;    // 🟠 Laranja
      nivel = "TURISTA";
      statusTexto = "Treinou há $dias dias";
    } else {
      cor = Colors.red;       // 🔴 Vermelho
      nivel = "INATIVO(A)";
      statusTexto = "Treinou há $dias dias";
    }

    return FrequenciaModel(
      diasSemTreinar: dias,
      corIndicador: cor,
      nivel: nivel,
      ultimaPresenca: ultimoDiaPresente,
      statusTexto: statusTexto,
    );
  }
}