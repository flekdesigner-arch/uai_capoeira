import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';

class EstudosCiclosRepository {
  static const String collectionPath = 'estudos_ciclos';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  EstudosCiclosRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionPath);

  Stream<List<EstudoCicloModel>> watchCiclosAdmin() {
    return _collection.snapshots().map((snapshot) {
      final ciclos = snapshot.docs.map(EstudoCicloModel.fromDoc).toList();
      ciclos.sort(_compareCiclosPadrao);
      return ciclos;
    });
  }

  Stream<EstudosCiclosResumo> watchResumo() {
    return watchCiclosAdmin().map(EstudosCiclosResumo.fromCiclos);
  }

  Stream<List<EstudoCicloModel>> watchCiclosVisiveisParaAluno({
    required bool mostrarEmBreve,
  }) {
    final statuses = mostrarEmBreve
        ? const [EstudoCicloStatus.publicado, EstudoCicloStatus.emBreve]
        : const [EstudoCicloStatus.publicado];

    return _collection
        .where('status', whereIn: statuses)
        .where('mostrarNaLinhaDoTempo', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final ciclos = snapshot.docs
              .map(EstudoCicloModel.fromDoc)
              .where((ciclo) => _cicloVisivelParaAluno(ciclo, mostrarEmBreve))
              .toList();
          ciclos.sort(_compareCiclosPadrao);
          return ciclos;
        });
  }

  Stream<List<EstudoCicloModel>> watchCiclosPublicosParaAluno() {
    return watchCiclosVisiveisParaAluno(mostrarEmBreve: false);
  }

  bool _cicloVisivelParaAluno(EstudoCicloModel ciclo, bool mostrarEmBreve) {
    if (!ciclo.mostrarNaLinhaDoTempo) return false;
    if (ciclo.status == EstudoCicloStatus.publicado) return true;
    if (mostrarEmBreve && ciclo.status == EstudoCicloStatus.emBreve) {
      return true;
    }
    return false;
  }

  Future<void> criarCiclo(EstudoCicloModel ciclo) async {
    final uid = _auth.currentUser?.uid ?? '';
    final data = ciclo.copyWith(criadoPor: uid, atualizadoPor: uid).toMap();

    data['criadoEm'] = FieldValue.serverTimestamp();
    data['atualizadoEm'] = FieldValue.serverTimestamp();

    await _collection.add(data);
  }

  Future<void> atualizarCiclo(EstudoCicloModel ciclo) async {
    if (ciclo.id.trim().isEmpty) {
      throw ArgumentError('Ciclo sem id nao pode ser atualizado.');
    }

    final uid = _auth.currentUser?.uid ?? '';
    final data = ciclo.copyWith(atualizadoPor: uid).toMap();
    data.remove('criadoEm');
    data.remove('criadoPor');
    data['atualizadoEm'] = FieldValue.serverTimestamp();

    await _collection.doc(ciclo.id).set(data, SetOptions(merge: true));
  }

  Future<void> alterarStatus(String cicloId, String status) async {
    if (!EstudoCicloStatus.isValid(status)) {
      throw ArgumentError('Status de ciclo invalido: $status');
    }

    final uid = _auth.currentUser?.uid ?? '';
    await _collection.doc(cicloId).set({
      'status': status,
      'atualizadoPor': uid,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> arquivarCiclo(String cicloId) {
    return alterarStatus(cicloId, EstudoCicloStatus.arquivado);
  }

  Future<void> duplicarCiclo(EstudoCicloModel ciclo) async {
    final uid = _auth.currentUser?.uid ?? '';
    final data = ciclo
        .copyWith(
          id: '',
          titulo: 'Copia de ${ciclo.titulo}',
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

  Future<void> atualizarOrdem(EstudoCicloModel ciclo, int novaOrdem) async {
    final uid = _auth.currentUser?.uid ?? '';
    await _collection.doc(ciclo.id).set({
      'ordem': novaOrdem < 1 ? 1 : novaOrdem,
      'atualizadoPor': uid,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> criarCiclosPadrao() async {
    final uid = _auth.currentUser?.uid ?? '';
    final batch = _firestore.batch();
    final titulos = <String>[
      'Antes da Capoeira',
      'Africa, diaspora e Brasil',
      'Primeiros registros da capoeira',
      'Perseguicao e resistencia',
      'Berimbau e musicalidade',
      'Mestre Bimba e Capoeira Regional',
      'Mestre Pastinha e Capoeira Angola',
      'Angola, Regional e Contemporanea',
      'Fundamentos da roda',
      'Capoeira como patrimonio cultural',
    ];

    for (var i = 0; i < titulos.length; i++) {
      final numero = i + 1;
      final ref = _collection.doc();
      batch.set(ref, {
        'numero': numero,
        'titulo': titulos[i],
        'subtitulo': '',
        'descricao': '',
        'periodoHistorico': '',
        'capaUrl': '',
        'ordem': numero,
        'status': EstudoCicloStatus.rascunho,
        'mostrarNaLinhaDoTempo': true,
        'mostrarComoEmBreve': false,
        'criadoPor': uid,
        'atualizadoPor': uid,
        'criadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  int _compareCiclosPadrao(EstudoCicloModel a, EstudoCicloModel b) {
    final ordem = a.ordem.compareTo(b.ordem);
    if (ordem != 0) return ordem;
    final numero = a.numero.compareTo(b.numero);
    if (numero != 0) return numero;
    return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
  }
}
