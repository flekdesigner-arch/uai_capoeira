import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/gabarito_estudo_model.dart';

class GabaritosEstudosRepository {
  GabaritosEstudosRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('estudos_gabaritos');

  Stream<GabaritoEstudoModel?> watchGabaritoPorPergunta(String perguntaId) {
    final id = perguntaId.trim();
    if (id.isEmpty) return Stream.value(null);

    return _collection.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return GabaritoEstudoModel.fromDoc(doc);
    });
  }

  Future<GabaritoEstudoModel?> buscarGabaritoPorPergunta(
    String perguntaId,
  ) async {
    final id = perguntaId.trim();
    if (id.isEmpty) return null;

    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;

    return GabaritoEstudoModel.fromDoc(doc);
  }

  Future<void> salvarGabarito(GabaritoEstudoModel gabarito) async {
    _validarGabarito(gabarito);

    final perguntaId = gabarito.perguntaId.trim();
    final docRef = _collection.doc(perguntaId);
    final docAtual = await docRef.get();

    await docRef.set(
      gabarito.copyWith(id: perguntaId).toMap(
            includeCreateFields: !docAtual.exists,
            usuarioId: _auth.currentUser?.uid,
          ),
      SetOptions(merge: true),
    );
  }

  Future<void> ativarOuDesativarGabarito({
    required String perguntaId,
    required bool ativo,
  }) async {
    final id = perguntaId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Pergunta invalida para alterar gabarito.');
    }

    await _collection.doc(id).set(
      {
        'ativo': ativo,
        'atualizadoEm': FieldValue.serverTimestamp(),
        'atualizadoPor': _auth.currentUser?.uid,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> excluirGabarito(String perguntaId) async {
    final id = perguntaId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Pergunta invalida para excluir gabarito.');
    }

    await _collection.doc(id).delete();
  }

  void _validarGabarito(GabaritoEstudoModel gabarito) {
    if (gabarito.perguntaId.trim().isEmpty) {
      throw ArgumentError('Pergunta obrigatoria para salvar gabarito.');
    }

    if (gabarito.estudoId.trim().isEmpty) {
      throw ArgumentError('Estudo obrigatorio para salvar gabarito.');
    }

    if (gabarito.cicloId.trim().isEmpty) {
      throw ArgumentError('Ciclo obrigatorio para salvar gabarito.');
    }

    if (gabarito.tipoPergunta.trim().isEmpty) {
      throw ArgumentError('Tipo da pergunta obrigatorio para salvar gabarito.');
    }

    if (gabarito.peso <= 0) {
      throw ArgumentError('Peso do gabarito deve ser maior que zero.');
    }

    final temAlternativaUnica =
        gabarito.alternativaCorretaId?.trim().isNotEmpty == true;

    final temAlternativasMultiplas =
        gabarito.alternativasCorretasIds.isNotEmpty;

    final temRespostaTexto =
        gabarito.respostaEsperadaTexto?.trim().isNotEmpty == true;

    final temAlgumaResposta = temAlternativaUnica ||
        temAlternativasMultiplas ||
        temRespostaTexto;

    if (!temAlgumaResposta) {
      throw ArgumentError(
        'Informe pelo menos uma resposta correta para o gabarito.',
      );
    }
  }
}