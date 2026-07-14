import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/pergunta_estudo_model.dart';

class PerguntasEstudosRepository {
  static const String collectionPath = 'estudos_perguntas';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  PerguntasEstudosRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionPath);

  Stream<List<PerguntaEstudoModel>> watchPerguntasAdmin() {
    return _collection.snapshots().map((snapshot) {
      final perguntas = snapshot.docs.map(PerguntaEstudoModel.fromDoc).toList();
      perguntas.sort(_comparePadrao);
      return perguntas;
    });
  }

  Stream<List<PerguntaEstudoModel>> watchPerguntasPorCiclo(String cicloId) {
    return _collection.where('cicloId', isEqualTo: cicloId).snapshots().map((
      snapshot,
    ) {
      final perguntas = snapshot.docs.map(PerguntaEstudoModel.fromDoc).toList();
      perguntas.sort(_comparePadrao);
      return perguntas;
    });
  }

  Stream<List<PerguntaEstudoModel>> watchPerguntasPorEstudo(String estudoId) {
    return _collection.where('estudoId', isEqualTo: estudoId).snapshots().map((
      snapshot,
    ) {
      final perguntas = snapshot.docs.map(PerguntaEstudoModel.fromDoc).toList();
      perguntas.sort(_comparePadrao);
      return perguntas;
    });
  }

  Stream<PerguntasResumo> watchResumo() {
    return watchPerguntasAdmin().map(PerguntasResumo.fromPerguntas);
  }

  Future<void> criarPergunta(PerguntaEstudoModel pergunta) async {
    final uid = _auth.currentUser?.uid ?? '';
    final data = pergunta.copyWith(criadoPor: uid, atualizadoPor: uid).toMap();
    data['criadoEm'] = FieldValue.serverTimestamp();
    data['atualizadoEm'] = FieldValue.serverTimestamp();
    await _collection.add(data);
  }

  Future<void> atualizarPergunta(PerguntaEstudoModel pergunta) async {
    if (pergunta.id.trim().isEmpty) {
      throw ArgumentError('Pergunta sem id nao pode ser atualizada.');
    }
    final uid = _auth.currentUser?.uid ?? '';
    final data = pergunta.copyWith(atualizadoPor: uid).toMap();
    data.remove('criadoEm');
    data.remove('criadoPor');
    data['atualizadoEm'] = FieldValue.serverTimestamp();
    await _collection.doc(pergunta.id).set(data, SetOptions(merge: true));
  }

  Future<void> alterarStatus(String perguntaId, String status) async {
    if (!PerguntaEstudoStatus.isValid(status)) {
      throw ArgumentError('Status de pergunta invalido: $status');
    }
    await _collection
        .doc(perguntaId)
        .set(_statusUpdateData(status), SetOptions(merge: true));
  }

  Future<void> alterarStatusEmLote(
    Iterable<String> perguntaIds,
    String status,
  ) async {
    if (!PerguntaEstudoStatus.isValid(status)) {
      throw ArgumentError('Status de pergunta invalido: $status');
    }
    final ids = perguntaIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;

    final batch = _firestore.batch();
    final data = _statusUpdateData(status);
    for (final id in ids) {
      batch.set(_collection.doc(id), data, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Map<String, dynamic> _statusUpdateData(String status) {
    final uid = _auth.currentUser?.uid ?? '';
    return {
      'status': status,
      'atualizadoPor': uid,
      'atualizadoEm': FieldValue.serverTimestamp(),
    };
  }

  Future<void> arquivarPergunta(String perguntaId) {
    return alterarStatus(perguntaId, PerguntaEstudoStatus.arquivada);
  }

  Future<void> duplicarPergunta(PerguntaEstudoModel pergunta) async {
    final uid = _auth.currentUser?.uid ?? '';
    final data = pergunta
        .copyWith(
          id: '',
          enunciado: 'Copia de ${pergunta.enunciado}',
          status: PerguntaEstudoStatus.rascunho,
          podeAparecerEmAvaliacao: false,
          criadoPor: uid,
          atualizadoPor: uid,
        )
        .toMap();
    data.remove('criadoEm');
    data.remove('atualizadoEm');
    data['criadoEm'] = FieldValue.serverTimestamp();
    data['atualizadoEm'] = FieldValue.serverTimestamp();
    await _collection.add(data);
  }

  int _comparePadrao(PerguntaEstudoModel a, PerguntaEstudoModel b) {
    final ciclo = a.cicloTituloSnapshot.toLowerCase().compareTo(
      b.cicloTituloSnapshot.toLowerCase(),
    );
    if (ciclo != 0) return ciclo;
    final estudoNumero = a.estudoNumeroSnapshot.compareTo(
      b.estudoNumeroSnapshot,
    );
    if (estudoNumero != 0) return estudoNumero;
    final ordem = a.ordem.compareTo(b.ordem);
    if (ordem != 0) return ordem;
    return a.enunciado.toLowerCase().compareTo(b.enunciado.toLowerCase());
  }
}
