import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudos_config_model.dart';

class EstudosConfigService {
  static const String collectionPath = 'estudos_config';
  static const String globalDocId = 'global';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  EstudosConfigService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection(collectionPath).doc(globalDocId);

  Stream<EstudosConfigModel> watchConfig() {
    return _doc.snapshots().map((snapshot) {
      if (!snapshot.exists) return EstudosConfigModel.defaults();
      return EstudosConfigModel.fromMap(snapshot.data());
    });
  }

  Future<EstudosConfigModel> buscarConfigGlobal({
    bool criarSeNaoExistir = false,
  }) async {
    final snapshot = await _doc.get();

    if (snapshot.exists) {
      return EstudosConfigModel.fromMap(snapshot.data());
    }

    final defaults = EstudosConfigModel.defaults();
    if (criarSeNaoExistir) {
      await salvarConfigGlobal(defaults);
    }

    return defaults;
  }

  Future<void> salvarConfigGlobal(EstudosConfigModel config) async {
    final uid = _auth.currentUser?.uid ?? '';
    final data = config.copyWith(updatedBy: uid).toMap(
          includeServerTimestamp: true,
        );

    // A config editorial deve ser alterada somente por administradores.
    // A garantia definitiva precisa ficar nas regras do Firestore.
    await _doc.set(data, SetOptions(merge: true));
  }

  Future<bool> moduloDisponivelParaAluno() async {
    final config = await buscarConfigGlobal();
    return config.ativo && config.mostrarCardAreaAluno;
  }
}
