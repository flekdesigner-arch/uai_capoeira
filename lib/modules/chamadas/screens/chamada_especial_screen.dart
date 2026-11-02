import 'package:flutter/material.dart';
import 'package:uai_capoeira/modules/chamadas/screens/chamada_turma_screen.dart';

class ChamadaEspecialScreen extends StatelessWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;
  final String usuarioId;
  final DateTime dataSelecionada;

  const ChamadaEspecialScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
    required this.usuarioId,
    required this.dataSelecionada,
  });

  @override
  Widget build(BuildContext context) {
    return ChamadaTurmaScreen(
      turmaId: turmaId,
      turmaNome: turmaNome,
      academiaId: academiaId,
      academiaNome: academiaNome,
      usuarioId: usuarioId,
      dataSelecionadaEspecial: dataSelecionada,
    );
  }
}
