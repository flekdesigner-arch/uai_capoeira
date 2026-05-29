import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FornecedorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Criar fornecedor
  Future<String> criarFornecedor(Map<String, dynamic> dados) async {
    dados.addAll({
      'criado_em': FieldValue.serverTimestamp(),
      'criado_por': currentUser?.uid,
      'status': 'ativo',
    });
    final docRef = await _firestore.collection('fornecedores').add(dados);
    return docRef.id;
  }

  // Atualizar fornecedor
  Future<void> atualizarFornecedor(String fornecedorId, Map<String, dynamic> dados) async {
    dados['atualizado_em'] = FieldValue.serverTimestamp();
    dados['atualizado_por'] = currentUser?.uid;
    await _firestore.collection('fornecedores').doc(fornecedorId).update(dados);
  }

  // Excluir fornecedor (soft delete)
  Future<void> excluirFornecedor(String fornecedorId) async {
    await _firestore.collection('fornecedores').doc(fornecedorId).update({
      'status': 'inativo',
      'excluido_em': FieldValue.serverTimestamp(),
      'excluido_por': currentUser?.uid,
    });
  }

  // Stream de fornecedores ativos
  Stream<QuerySnapshot> getFornecedoresAtivos() {
    return _firestore
        .collection('fornecedores')
        .where('status', isEqualTo: 'ativo')
        .orderBy('nome')
        .snapshots();
  }

  // Buscar fornecedor por ID
  Future<DocumentSnapshot> getFornecedor(String fornecedorId) async {
    return await _firestore.collection('fornecedores').doc(fornecedorId).get();
  }
}