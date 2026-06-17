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
      'ativo': false,
      'aceitar_apenas_ativos': true,
      'exigir_telefone_confirmacao': true,
      'mostrar_dashboard': true,
      'mostrar_foto': true,
      'mostrar_dados_basicos': true,
      'mostrar_academia_turma': true,
      'mostrar_graduacao': true,
      'mostrar_graduacao_atual': true,
      'mostrar_frequencia': true,
      'mostrar_eventos': true,
      'mostrar_certificados': true,
      'mostrar_financeiro_eventos': true,
      'mostrar_solicitacao_alteracao': true,
      'mostrar_graduacao_evento': true,
      'mostrar_camisa_evento': true,
      'mostrar_presenca_evento': true,
      'mostrar_presencas': false,
      'mostrar_historico_chamadas': false,
      'modo_dados_basicos': 'limitado',
      'modo_telefone': 'mascarado',
      'modo_endereco': 'cidade_bairro',
      'modo_responsavel': 'nome',
      'modo_financeiro': 'completo',
      'modo_graduacao_evento': 'completo',
      'google_login_ativo': false,
      'google_vinculacao_modo': 'desativada',
      'permitir_acesso_basico_sem_google': true,
      'permitir_vincular_google_no_primeiro_acesso': true,
      'permitir_trocar_google_sem_admin': false,
      'sem_google_mostrar_dashboard': true,
      'sem_google_mostrar_dados_basicos': true,
      'sem_google_modo_dados_basicos': 'limitado',
      'sem_google_mostrar_frequencia': true,
      'sem_google_mostrar_eventos': true,
      'sem_google_mostrar_certificados': true,
      'sem_google_mostrar_financeiro_eventos': true,
      'sem_google_modo_financeiro': 'completo',
      'sem_google_mostrar_graduacao_evento': true,
      'sem_google_modo_graduacao_evento': 'completo',
      'sem_google_mostrar_camisa_evento': true,
      'sem_google_mostrar_presenca_evento': true,
      'sem_google_mostrar_solicitacao_alteracao': true,
      'com_google_mostrar_dashboard': true,
      'com_google_mostrar_dados_basicos': true,
      'com_google_modo_dados_basicos': 'limitado',
      'com_google_mostrar_frequencia': true,
      'com_google_mostrar_eventos': true,
      'com_google_mostrar_certificados': true,
      'com_google_mostrar_financeiro_eventos': true,
      'com_google_modo_financeiro': 'completo',
      'com_google_mostrar_graduacao_evento': true,
      'com_google_modo_graduacao_evento': 'completo',
      'com_google_mostrar_camisa_evento': true,
      'com_google_mostrar_presenca_evento': true,
      'com_google_mostrar_solicitacao_alteracao': true,
      'mostrar_aviso_auditoria': false,
      'mensagem_topo': 'Bem-vindo(a) à Área do Aluno',
      'mensagem_area_desativada':
          'A Área do Aluno não está disponível no momento.',
      'mensagem_dados_ocultos':
          'Algumas informações foram ocultadas pela coordenação.',
      'aviso_auditoria_acesso': '',
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

      return {...padrao, ...data};
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
      'ativo': visivel,
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
