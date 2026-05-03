import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RemessaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Future<String> criarRemessa(Map<String, dynamic> dados) async {
    dados.addAll({
      'criado_em': FieldValue.serverTimestamp(),
      'criado_por': currentUser?.uid,
      'status': dados['status'] ?? 'pendente',
    });
    final docRef = await _firestore.collection('remessas').add(dados);
    return docRef.id;
  }

  Future<void> atualizarRemessa(String remessaId, Map<String, dynamic> dados) async {
    dados['atualizado_em'] = FieldValue.serverTimestamp();
    dados['atualizado_por'] = currentUser?.uid;
    await _firestore.collection('remessas').doc(remessaId).update(dados);
  }

  Future<void> excluirRemessa(String remessaId) async {
    final pedidos = await _firestore
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .get();
    for (var doc in pedidos.docs) {
      await doc.reference.update({'remessa_id': FieldValue.delete()});
    }
    await _firestore.collection('remessas').doc(remessaId).delete();
  }

  Future<void> vincularPedido(String pedidoId, String remessaId) async {
    await _firestore.collection('pedidos_uniformes').doc(pedidoId).update({
      'remessa_id': remessaId,
    });
    await _firestore.collection('remessas').doc(remessaId).update({
      'pedidos_ids': FieldValue.arrayUnion([pedidoId]),
    });
  }

  Future<void> desvincularPedido(String pedidoId, String remessaId) async {
    await _firestore.collection('pedidos_uniformes').doc(pedidoId).update({
      'remessa_id': FieldValue.delete(),
    });
    await _firestore.collection('remessas').doc(remessaId).update({
      'pedidos_ids': FieldValue.arrayRemove([pedidoId]),
    });
  }

  Stream<QuerySnapshot> getPedidosDaRemessa(String remessaId) {
    return _firestore
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .orderBy('data_pedido', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getTodasRemessas() {
    return _firestore
        .collection('remessas')
        .orderBy('criado_em', descending: true)
        .snapshots();
  }
}