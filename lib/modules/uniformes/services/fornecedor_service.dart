import 'package:cloud_firestore/cloud_firestore.dart';
import 'uniformes_admin_service.dart';

class FornecedorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UniformesAdminService _backend = UniformesAdminService();

  // Criar fornecedor
  Future<String> criarFornecedor(Map<String, dynamic> dados) async {
    final result = await _backend.operar('salvar_fornecedor', {
      'fornecedor': dados,
    });
    return result['id'].toString();
  }

  // Atualizar fornecedor
  Future<void> atualizarFornecedor(
    String fornecedorId,
    Map<String, dynamic> dados,
  ) async {
    await _backend.operar('salvar_fornecedor', {
      'fornecedorId': fornecedorId,
      'fornecedor': dados,
    });
  }

  // Excluir fornecedor (soft delete)
  Future<void> excluirFornecedor(
    String fornecedorId, {
    required String motivo,
  }) async {
    await _backend.operar('excluir_fornecedor', {
      'fornecedorId': fornecedorId,
      'motivo': motivo,
      'confirmacao': true,
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
