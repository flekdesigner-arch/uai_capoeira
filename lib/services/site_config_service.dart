import 'package:cloud_firestore/cloud_firestore.dart';

class SiteConfigService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Carrega todas as configurações do site
  Future<Map<String, dynamic>> carregarConfiguracoesSite() async {
    try {
      final configDoc = await _firestore.collection('configuracoes_site').doc('menu').get();

      if (configDoc.exists) {
        return configDoc.data() ?? {};
      }

      // Se não existir, retorna configurações padrão
      return {};
    } catch (e) {
      print('Erro ao carregar configurações: $e');
      return {};
    }
  }

  // Salva a ordem dos itens do menu
  Future<void> salvarOrdemMenu(List<String> ordem) async {
    await _firestore.collection('configuracoes_site').doc('menu').set({
      'ordem': ordem,
      'ultima_atualizacao': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Salva títulos personalizados
  Future<void> salvarTitulos(Map<String, String> titulos) async {
    await _firestore.collection('configuracoes_site').doc('menu').set({
      'titulos': titulos,
      'ultima_atualizacao': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Salva descrições personalizadas
  Future<void> salvarDescricoes(Map<String, String> descricoes) async {
    await _firestore.collection('configuracoes_site').doc('menu').set({
      'descricoes': descricoes,
      'ultima_atualizacao': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Altera visibilidade de uma seção
  Future<void> alterarVisibilidade(String secaoId, bool visivel) async {
    await _firestore.collection('configuracoes_site').doc('menu').set({
      'visibilidade.$secaoId': visivel,
      'ultima_atualizacao': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Altera a senha do app
  Future<void> alterarSenhaApp(String novaSenha) async {
    await _firestore.collection('configuracoes').doc('app').set({
      'senha_acesso': novaSenha,
      'ultima_alteracao_senha': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Busca a senha atual do app
  Future<String> getSenhaApp() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('app').get();
      if (doc.exists && doc.data()?['senha_acesso'] != null) {
        return doc.data()!['senha_acesso'];
      }
    } catch (e) {
      print('Erro ao buscar senha: $e');
    }
    return 'uai2026app'; // Senha padrão
  }
}