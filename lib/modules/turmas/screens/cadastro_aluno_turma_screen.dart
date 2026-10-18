import 'package:flutter/material.dart';
import 'package:uai_capoeira/modules/alunos/screens/editar_aluno_screen.dart';

/// Ponte de compatibilidade: todas as rotas legadas de cadastro da turma e
/// aprovação de inscrição utilizam o formulário oficial de alunos.
/// Preserve este widget enquanto houver importações antigas no projeto.
class CadastroAlunoTurmaScreen extends StatelessWidget {
  final String? alunoId;
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;
  final Map<String, dynamic>? dadosIniciais;

  const CadastroAlunoTurmaScreen({
    super.key,
    this.alunoId,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
    this.dadosIniciais,
  });

  @override
  Widget build(BuildContext context) => EditarAlunoScreen(
    alunoId: alunoId,
    turmaIdInicial: turmaId,
    turmaNomeInicial: turmaNome,
    academiaIdInicial: academiaId,
    academiaNomeInicial: academiaNome,
    dadosInscricao: alunoId == null ? dadosIniciais : null,
  );
}
