import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/resultado_estudo_aluno_model.dart';

class ResultadosEstudosRepository {
  final FirebaseFirestore _firestore;

  ResultadosEstudosRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<ResultadoEstudoAlunoModel>> watchResultadosAluno(String alunoId) {
    if (alunoId.trim().isEmpty) {
      return Stream.value(const <ResultadoEstudoAlunoModel>[]);
    }
    return _firestore
        .collection('alunos_estudos_resultados')
        .doc(alunoId)
        .collection('estudos')
        .snapshots()
        .map((snapshot) {
          final resultados = snapshot.docs
              .map(ResultadoEstudoAlunoModel.fromDoc)
              .where((resultado) => resultado.estudoId.isNotEmpty)
              .toList();
          resultados.sort((a, b) {
            final ad = a.atualizadoEm;
            final bd = b.atualizadoEm;
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });
          return resultados;
        });
  }
}
