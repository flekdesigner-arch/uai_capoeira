import 'package:cloud_firestore/cloud_firestore.dart';

class SiteConfigService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Carrega todas as configurações do site
  Future<Map<String, dynamic>> carregarConfiguracoesSite() async {
    try {
      final configDoc = await _firestore
          .collection('configuracoes_site')
          .doc('menu')
          .get();

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

  // Altera visibilidade de uma seção do menu/site
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

  // ═══════════════════════════════════════════════════════════
  // ÁREA DO ALUNO
  // ═══════════════════════════════════════════════════════════

  Map<String, dynamic> configuracaoPadraoAreaAluno() {
    return {
      'visivel_site': false,
      'aceitar_apenas_ativos': true,
      'exigir_telefone_confirmacao': true,
      'mostrar_foto': true,
      'mostrar_dados_basicos': true,
      'mostrar_academia_turma': true,
      'mostrar_graduacao': true,
      'mostrar_presencas': false,
      'mostrar_historico_chamadas': false,
      'mensagem_topo': 'Bem-vindo(a) à Área do Aluno',
      'texto_ajuda':
      'Informe sua data de nascimento, as iniciais do seu nome completo e os últimos 4 dígitos do telefone cadastrado.',
      'ultima_atualizacao': null,
    };
  }

  Future<Map<String, dynamic>> carregarConfiguracoesAreaAluno() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_site')
          .doc('area_aluno')
          .get();

      final padrao = configuracaoPadraoAreaAluno();

      if (!doc.exists || doc.data() == null) {
        return padrao;
      }

      final data = doc.data() ?? {};

      return {
        ...padrao,
        ...data,
      };
    } catch (e) {
      print('Erro ao carregar configurações da Área do Aluno: $e');
      return configuracaoPadraoAreaAluno();
    }
  }

  Future<void> salvarConfiguracoesAreaAluno(
      Map<String, dynamic> configuracoes, {
        String? atualizadoPor,
      }) async {
    await _firestore.collection('configuracoes_site').doc('area_aluno').set({
      ...configuracoes,
      'ultima_atualizacao': FieldValue.serverTimestamp(),
      if (atualizadoPor != null) 'atualizado_por': atualizadoPor,
    }, SetOptions(merge: true));
  }

  Future<void> alterarVisibilidadeAreaAluno(bool visivel) async {
    await _firestore.collection('configuracoes_site').doc('area_aluno').set({
      'visivel_site': visivel,
      'ultima_atualizacao': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Também deixa a seção preparada no menu do site.
    await alterarVisibilidade('area_aluno', visivel);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamLogsAcessoAreaAluno({
    int limite = 30,
  }) {
    return _firestore
        .collection('area_aluno_logs_acesso')
        .orderBy('acesso_em', descending: true)
        .limit(limite)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamLogsErroAreaAluno({
    int limite = 30,
  }) {
    return _firestore
        .collection('area_aluno_logs_erro')
        .orderBy('tentativa_em', descending: true)
        .limit(limite)
        .snapshots();
  }
}
