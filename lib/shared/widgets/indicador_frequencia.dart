// lib/shared/widgets/indicador_frequencia.dart
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/chamadas/models/frequencia_model.dart';
import 'package:uai_capoeira/modules/chamadas/services/frequencia_service.dart';

class IndicadorFrequencia extends StatelessWidget {
  final FrequenciaModel frequencia;
  final bool mostrarTexto;
  final double tamanho;
  final bool premium;

  const IndicadorFrequencia({
    super.key,
    required this.frequencia,
    this.mostrarTexto = false,
    this.tamanho = 12,
    this.premium = true,
  });

  factory IndicadorFrequencia.fromAlunoData(
      Map<String, dynamic> alunoData, {
        bool mostrarTexto = false,
        double tamanho = 12,
        bool premium = true,
      }) {
    final service = FrequenciaService();
    final frequencia = service.calcularFrequencia(alunoData);
    return IndicadorFrequencia(
      frequencia: frequencia,
      mostrarTexto: mostrarTexto,
      tamanho: tamanho,
      premium: premium,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final color = frequencia.corIndicador;

    if (!premium) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(color),
          if (mostrarTexto) ...[
            const SizedBox(width: 6),
            Text(
              frequencia.statusTexto,
              style: TextStyle(
                fontSize: tamanho * 0.9,
                color: t.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }

    if (!mostrarTexto) {
      return Tooltip(
        message: '${frequencia.nivel} • ${frequencia.statusTexto}',
        child: _dot(color),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (tamanho * 0.70).clamp(8.0, 12.0),
        vertical: (tamanho * 0.42).clamp(5.0, 8.0),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              frequencia.statusTexto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: (tamanho * 0.86).clamp(10.5, 13.0),
                color: t.textSecondary,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.34),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
