// widgets/indicador_frequencia.dart
import 'package:flutter/material.dart';
import '../models/frequencia_model.dart';
import '../services/frequencia_service.dart';

class IndicadorFrequencia extends StatelessWidget {
  final FrequenciaModel frequencia;
  final bool mostrarTexto;
  final double tamanho;

  const IndicadorFrequencia({
    super.key,
    required this.frequencia,
    this.mostrarTexto = false,
    this.tamanho = 12,
  });

  factory IndicadorFrequencia.fromAlunoData(
      Map<String, dynamic> alunoData, {
        bool mostrarTexto = false,
        double tamanho = 12,
      }) {
    final service = FrequenciaService();
    final frequencia = service.calcularFrequencia(alunoData);
    return IndicadorFrequencia(
      frequencia: frequencia,
      mostrarTexto: mostrarTexto,
      tamanho: tamanho,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: tamanho,
          height: tamanho,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: frequencia.corIndicador,
            boxShadow: [
              BoxShadow(
                color: frequencia.corIndicador.withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        if (mostrarTexto) ...[
          const SizedBox(width: 6),
          Text(
            frequencia.statusTexto,
            style: TextStyle(
              fontSize: tamanho * 0.9,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}