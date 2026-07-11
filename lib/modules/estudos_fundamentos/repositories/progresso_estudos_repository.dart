import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/progresso_estudo_model.dart';

class ProgressoEstudosRepository {
  static const String collectionPath = 'alunos_estudos_progresso';
  static const String estudosSubcollection = 'estudos';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ProgressoEstudosRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _estudosRef(String alunoId) {
    return _firestore
        .collection(collectionPath)
        .doc(alunoId)
        .collection(estudosSubcollection);
  }

  DocumentReference<Map<String, dynamic>> _progressoRef({
    required String alunoId,
    required String estudoId,
  }) {
    return _estudosRef(alunoId).doc(estudoId);
  }

  Stream<List<ProgressoEstudoModel>> watchProgressoAluno(String alunoId) {
    if (alunoId.trim().isEmpty) {
      return Stream.value(const <ProgressoEstudoModel>[]);
    }
    return _estudosRef(alunoId).snapshots().map((snapshot) {
      final progressos = snapshot.docs
          .map(ProgressoEstudoModel.fromDoc)
          .toList();
      progressos.sort((a, b) {
        final ad =
            a.atualizadoEm ??
            a.ultimaVisualizacaoEm ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            b.atualizadoEm ??
            b.ultimaVisualizacaoEm ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return progressos;
    });
  }

  Stream<ProgressoEstudoModel?> watchProgressoEstudo({
    required String alunoId,
    required String estudoId,
  }) {
    if (alunoId.trim().isEmpty || estudoId.trim().isEmpty) {
      return Stream.value(null);
    }
    return _progressoRef(alunoId: alunoId, estudoId: estudoId).snapshots().map(
      (snapshot) =>
          snapshot.exists ? ProgressoEstudoModel.fromDoc(snapshot) : null,
    );
  }

  Future<void> iniciarEstudo({
    required String alunoId,
    required String estudoId,
    required String cicloId,
    String origem = 'area_aluno',
  }) async {
    if (alunoId.trim().isEmpty || estudoId.trim().isEmpty) {
      throw ArgumentError('Aluno e estudo sao obrigatorios para progresso.');
    }
    final googleUid = _auth.currentUser?.uid ?? '';
    final ref = _progressoRef(alunoId: alunoId, estudoId: estudoId);
    final snapshot = await ref.get();
    final data = <String, dynamic>{
      'alunoId': alunoId,
      'googleUid': googleUid,
      'estudoId': estudoId,
      'cicloId': cicloId,
      'origem': origem,
      'ultimaVisualizacaoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    };

    if (!snapshot.exists) {
      data.addAll({
        'status': ProgressoEstudoStatus.iniciado,
        'percentualLeitura': 1,
        'iniciadoEm': FieldValue.serverTimestamp(),
      });
    } else {
      final atual = ProgressoEstudoModel.fromDoc(snapshot);
      if (!atual.concluido) {
        data['status'] = ProgressoEstudoStatus.iniciado;
        data['percentualLeitura'] = atual.percentualLeitura <= 0
            ? 1
            : atual.percentualLeitura;
        if (atual.iniciadoEm == null) {
          data['iniciadoEm'] = FieldValue.serverTimestamp();
        }
      }
    }

    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> marcarConcluido({
    required String alunoId,
    required String estudoId,
    required String cicloId,
    String origem = 'area_aluno',
  }) async {
    if (alunoId.trim().isEmpty || estudoId.trim().isEmpty) {
      throw ArgumentError('Aluno e estudo sao obrigatorios para progresso.');
    }
    final googleUid = _auth.currentUser?.uid ?? '';
    final ref = _progressoRef(alunoId: alunoId, estudoId: estudoId);
    final snapshot = await ref.get();
    final atual = snapshot.exists
        ? ProgressoEstudoModel.fromDoc(snapshot)
        : null;
    final data = <String, dynamic>{
      'alunoId': alunoId,
      'googleUid': googleUid,
      'estudoId': estudoId,
      'cicloId': cicloId,
      'status': ProgressoEstudoStatus.concluido,
      'percentualLeitura': 100,
      'origem': origem,
      'concluidoEm': FieldValue.serverTimestamp(),
      'ultimaVisualizacaoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    };
    if (atual?.iniciadoEm == null) {
      data['iniciadoEm'] = FieldValue.serverTimestamp();
    }
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> reabrirLeitura({
    required String alunoId,
    required String estudoId,
    required String cicloId,
    String origem = 'area_aluno',
  }) async {
    if (alunoId.trim().isEmpty || estudoId.trim().isEmpty) {
      throw ArgumentError('Aluno e estudo sao obrigatorios para progresso.');
    }
    final googleUid = _auth.currentUser?.uid ?? '';
    await _progressoRef(alunoId: alunoId, estudoId: estudoId).set({
      'alunoId': alunoId,
      'googleUid': googleUid,
      'estudoId': estudoId,
      'cicloId': cicloId,
      'status': ProgressoEstudoStatus.iniciado,
      'percentualLeitura': 1,
      'origem': origem,
      'concluidoEm': null,
      'ultimaVisualizacaoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  EstudosProgressoResumo calcularResumo({
    required Iterable<String> estudosObrigatoriosIds,
    required Iterable<ProgressoEstudoModel> progressos,
  }) {
    final ids = estudosObrigatoriosIds
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    final porEstudo = {for (final p in progressos) p.estudoId: p};
    var iniciados = 0;
    var concluidos = 0;
    for (final id in ids) {
      final progresso = porEstudo[id];
      if (progresso == null) continue;
      if (progresso.iniciado) iniciados++;
      if (progresso.concluido) concluidos++;
    }
    return EstudosProgressoResumo(
      total: ids.length,
      iniciados: iniciados,
      concluidos: concluidos,
    );
  }
}
