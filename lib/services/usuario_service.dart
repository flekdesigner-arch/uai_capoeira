import 'package:cloud_firestore/cloud_firestore.dart';

class UsuarioService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache simples para evitar buscas repetidas
  static final Map<String, Map<String, dynamic>> _cache = {};

  Future<Map<String, dynamic>> buscarUsuario(String uid, {bool forceRefresh = false}) async {
    // Se forçar atualização, remove do cache primeiro
    if (forceRefresh && _cache.containsKey(uid)) {
      print('🔄 Forçando refresh - removendo cache de $uid');
      _cache.remove(uid);
    }

    // Verifica se já está em cache (apenas se não forçar refresh)
    if (!forceRefresh && _cache.containsKey(uid)) {
      print('📦 Cache hit para $uid');
      return _cache[uid]!;
    }

    try {
      print('🔍 Buscando usuário $uid no Firebase...');

      // 🔥 CORREÇÃO: Buscar no local correto!
      final doc = await _firestore
          .collection('usuarios')
          .doc(uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        print('✅ Permissões encontradas!');

        // 🔥 Adicionar também os dados básicos do usuário
        final userDoc = await _firestore.collection('usuarios').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          data.addAll({
            'nome_completo': userData['nome_completo'],
            'email': userData['email'],
            'peso_permissao': userData['peso_permissao'] ?? 0,
            'tipo': userData['tipo'],
          });
        }

        _cache[uid] = data;
        return data;
      } else {
        print('⚠️ Permissões não encontradas - buscando apenas dados do usuário');

        // Fallback: buscar apenas dados básicos do usuário
        final userDoc = await _firestore.collection('usuarios').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          _cache[uid] = userData;
          return userData;
        }
      }
    } catch (e) {
      print('❌ Erro ao buscar usuário $uid: $e');
    }

    return {};
  }

  // 🔥 MÉTODO ESPECÍFICO PARA BUSCAR APENAS PERMISSÕES
  Future<Map<String, bool>> buscarPermissoes(String uid, {bool forceRefresh = false}) async {
    if (forceRefresh && _cache.containsKey(uid)) {
      _cache.remove(uid);
    }

    try {
      final doc = await _firestore
          .collection('usuarios')
          .doc(uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        return data.map((key, value) => MapEntry(key, value as bool? ?? false));
      }
    } catch (e) {
      print('❌ Erro ao buscar permissões: $e');
    }

    return {};
  }

  Future<String> getNomeUsuario(String uid, {bool forceRefresh = false}) async {
    if (uid.isEmpty) return 'Usuário não identificado';

    final dados = await buscarUsuario(uid, forceRefresh: forceRefresh);
    return dados['nome_completo'] ?? 'Usuário ID: ${uid.substring(0, 6)}...';
  }

  Future<bool> verificarPermissao(String uid, String chavePermissao, {bool forceRefresh = false}) async {
    if (uid.isEmpty) return false;

    final dados = await buscarUsuario(uid, forceRefresh: forceRefresh);
    // Verifica a permissão específica
    return dados[chavePermissao] ?? false;
  }

  // 🔥 MÉTODOS PARA UNIFORMES
  Future<bool> podeEditarVenda(String uid, {bool forceRefresh = false}) async {
    return verificarPermissao(uid, 'pode_editar_venda', forceRefresh: forceRefresh);
  }

  Future<bool> podeExcluirVenda(String uid, {bool forceRefresh = false}) async {
    return verificarPermissao(uid, 'pode_excluir_venda', forceRefresh: forceRefresh);
  }

  Future<bool> podeEditarPedido(String uid, {bool forceRefresh = false}) async {
    return verificarPermissao(uid, 'pode_editar_pedido', forceRefresh: forceRefresh);
  }

  Future<bool> podeExcluirPedido(String uid, {bool forceRefresh = false}) async {
    return verificarPermissao(uid, 'pode_excluir_pedido', forceRefresh: forceRefresh);
  }

  Future<bool> podeGerenciarEstoque(String uid, {bool forceRefresh = false}) async {
    return verificarPermissao(uid, 'pode_gerenciar_estoque', forceRefresh: forceRefresh);
  }

  // 🔥 Método para limpar cache
  static void limparCache() {
    print('🧹 Limpando todo o cache');
    _cache.clear();
  }
}