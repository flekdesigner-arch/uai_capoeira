import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';

class EstudosRepository {
  static const String collectionPath = 'estudos';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  EstudosRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionPath);

  Stream<List<EstudoModel>> watchEstudosAdmin() {
    return _collection.snapshots().map((snapshot) {
      final estudos = snapshot.docs.map(EstudoModel.fromDoc).toList();
      estudos.sort(_comparePadrao);
      return estudos;
    });
  }

  Stream<List<EstudoModel>> watchEstudosPorCiclo(String cicloId) {
    return watchEstudosAdmin().map(
      (estudos) => estudos.where((e) => e.cicloId == cicloId).toList(),
    );
  }

  Stream<EstudosResumo> watchResumo() {
    return watchEstudosAdmin().map(EstudosResumo.fromEstudos);
  }

  Stream<List<EstudoModel>> watchEstudosVisiveisPorCiclo({
    required String cicloId,
    required bool mostrarEmBreve,
  }) {
    final statuses = mostrarEmBreve
        ? const [EstudoCicloStatus.publicado, EstudoCicloStatus.emBreve]
        : const [EstudoCicloStatus.publicado];

    return _collection
        .where('cicloId', isEqualTo: cicloId)
        .where('status', whereIn: statuses)
        .where('mostrarNaLinhaDoTempo', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final estudos = snapshot.docs
              .map(EstudoModel.fromDoc)
              .where(
                (estudo) => _estudoVisivelParaAluno(estudo, mostrarEmBreve),
              )
              .toList();
          estudos.sort(_comparePadrao);
          return estudos;
        });
  }

  Stream<List<EstudoModel>> watchEstudosPublicosPorCiclo(String cicloId) {
    return watchEstudosVisiveisPorCiclo(
      cicloId: cicloId,
      mostrarEmBreve: false,
    );
  }

  Stream<List<EstudoModel>> watchEstudosPublicadosVisiveis() {
    return _collection
        .where('status', isEqualTo: EstudoCicloStatus.publicado)
        .where('mostrarNaLinhaDoTempo', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final estudos = snapshot.docs
              .map(EstudoModel.fromDoc)
              .where((estudo) => estudo.mostrarNaLinhaDoTempo)
              .toList();
          estudos.sort(_comparePadrao);
          return estudos;
        });
  }

  bool _estudoVisivelParaAluno(EstudoModel estudo, bool mostrarEmBreve) {
    if (!estudo.mostrarNaLinhaDoTempo) return false;
    if (estudo.status == EstudoCicloStatus.publicado) return true;
    if (mostrarEmBreve && estudo.status == EstudoCicloStatus.emBreve) {
      return true;
    }
    return false;
  }

  Future<void> criarEstudo(EstudoModel estudo) async {
    final uid = _auth.currentUser?.uid ?? '';
    final data = estudo.copyWith(criadoPor: uid, atualizadoPor: uid).toMap();
    data['criadoEm'] = FieldValue.serverTimestamp();
    data['atualizadoEm'] = FieldValue.serverTimestamp();
    await _collection.add(data);
  }

  Future<void> atualizarEstudo(EstudoModel estudo) async {
    if (estudo.id.trim().isEmpty) {
      throw ArgumentError('Estudo sem id nao pode ser atualizado.');
    }
    final uid = _auth.currentUser?.uid ?? '';
    final data = estudo.copyWith(atualizadoPor: uid).toMap();
    data.remove('criadoEm');
    data.remove('criadoPor');
    data['atualizadoEm'] = FieldValue.serverTimestamp();
    await _collection.doc(estudo.id).set(data, SetOptions(merge: true));
  }

  Future<void> alterarStatus(String estudoId, String status) async {
    if (!EstudoCicloStatus.isValid(status)) {
      throw ArgumentError('Status de estudo invalido: $status');
    }
    final uid = _auth.currentUser?.uid ?? '';
    await _collection.doc(estudoId).set({
      'status': status,
      'atualizadoPor': uid,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> arquivarEstudo(String estudoId) {
    return alterarStatus(estudoId, EstudoCicloStatus.arquivado);
  }

  Future<void> duplicarEstudo(EstudoModel estudo) async {
    final uid = _auth.currentUser?.uid ?? '';
    final data = estudo
        .copyWith(
          id: '',
          titulo: 'Copia de ${estudo.titulo}',
          status: EstudoCicloStatus.rascunho,
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

  int _comparePadrao(EstudoModel a, EstudoModel b) {
    final ciclo = a.cicloTituloSnapshot.toLowerCase().compareTo(
      b.cicloTituloSnapshot.toLowerCase(),
    );
    if (ciclo != 0) return ciclo;
    final ordem = a.ordem.compareTo(b.ordem);
    if (ordem != 0) return ordem;
    return a.numero.compareTo(b.numero);
  }
}
