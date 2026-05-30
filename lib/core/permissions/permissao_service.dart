import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Serviço central de permissões do app.
///
/// Ideia principal:
/// - Admin continua podendo tudo.
/// - Usuário bloqueado/inativo não gerencia nada.
/// - Aluno comum não gerencia evento.
/// - Monitor/professor/instrutor etc. pode gerenciar evento se tiver a chave individual.
/// - Chaves antigas continuam funcionando por compatibilidade.
/// - Telas antigas que usam temPermissao('chave') continuam funcionando.
class PermissaoService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache para evitar múltiplas leituras.
  static final Map<String, Map<String, bool>> _cachePermissoes = {};
  static final Map<String, bool> _cacheAdmin = {};
  static final Map<String, Map<String, dynamic>> _cacheUsuario = {};

  // Peso mínimo para um usuário NÃO admin poder gerenciar partes de evento.
  static const int pesoMinimoGestaoEvento = 30;
  static const int pesoAdmin = 90;

  // ==================== CHAVES PADRÃO ====================
  // Visibilidade.
  static const String chaveAcessarEventos = 'podeAcessarEventos';
  static const String chaveAcessarInscricoes = 'podeAcessarInscricoes';
  static const String chaveAcessarUniformes = 'podeAcessarUniformes';
  static const String chaveAcessarAssociacao = 'podeAcessarAssociacao';
  static const String chaveAcessarRifas = 'podeAcessarRifas';
  static const String chaveMostrarAlunosDrawer = 'pode_mostrar_alunos_drawer';

  // Eventos - geral.
  static const String chaveVerEventos = 'pode_ver_eventos';
  static const String chaveVerEventosAndamento = 'pode_ver_eventos_andamento';
  static const String chaveCriarEvento = 'pode_criar_evento';
  static const String chaveEditarEvento = 'pode_editar_evento';
  static const String chaveExcluirEvento = 'pode_excluir_evento';
  static const String chaveFinalizarEvento = 'pode_finalizar_evento';

  // Eventos - participantes.
  static const String chaveGerenciarParticipantesEvento = 'pode_gerenciar_participantes_evento';
  static const String chaveAdicionarParticipanteEvento = 'pode_adicionar_participante_evento';
  static const String chaveEditarParticipanteEvento = 'pode_editar_participante_evento';
  static const String chaveRemoverParticipanteEvento = 'pode_remover_participante_evento';
  static const String chaveConcluirParticipacaoEvento = 'pode_concluir_participacao_evento';

  // Eventos - financeiro/módulos.
  static const String chaveGerenciarCamisasEvento = 'pode_gerenciar_camisas_evento';
  static const String chaveGerenciarPatrocinadoresEvento = 'pode_gerenciar_patrocinadores_evento';
  static const String chaveGerenciarGastosEvento = 'pode_gerenciar_gastos_evento';
  static const String chaveVerRelatorioEvento = 'pode_ver_relatorio_evento';
  static const String chaveGerarCertificadosEvento = 'pode_gerar_certificados_evento';

  /// Aliases/compatibilidade.
  ///
  /// A chave principal é a nova. A lista contém nomes antigos ou nomes usados
  /// por telas antigas. Assim você pode evoluir o sistema sem perder permissões
  /// já salvas no Firestore.
  static const Map<String, List<String>> _aliasesPermissoes = {
    chaveAcessarEventos: [
      'pode_acessar_eventos',
      'pode_ver_eventos',
    ],
    chaveMostrarAlunosDrawer: [
      'podeMostrarAlunosDrawer',
    ],
    chaveVerEventos: [
      chaveAcessarEventos,
      'pode_acessar_eventos',
    ],
    chaveVerEventosAndamento: [
      'pode_acessar_eventos_andamento',
      'pode_gerenciar_eventos_andamento',
    ],
    chaveCriarEvento: [
      'pode_cadastrar_evento',
    ],
    chaveEditarEvento: [
      'pode_alterar_evento',
    ],
    chaveFinalizarEvento: [
      'pode_concluir_evento',
    ],

    chaveGerenciarParticipantesEvento: [
      'pode_gerenciar_participantes',
      'pode_gerenciar_participantes_eventos',
      'pode_adcionar_aluno_a_eventos',
      'pode_adicionar_aluno_a_eventos',
      'pode_remover_alunos_de_eventos',
    ],
    chaveAdicionarParticipanteEvento: [
      'pode_adcionar_aluno_a_eventos', // chave antiga com erro de digitação.
      'pode_adicionar_aluno_a_eventos',
      'pode_adicionar_aluno_evento',
    ],
    chaveEditarParticipanteEvento: [
      'pode_editar_participacao_evento',
      'pode_editar_participante',
    ],
    chaveRemoverParticipanteEvento: [
      'pode_remover_alunos_de_eventos',
      'pode_remover_aluno_evento',
    ],
    chaveConcluirParticipacaoEvento: [
      'pode_concluir_participacao',
      'pode_confirmar_participacao_evento',
    ],

    chaveGerenciarCamisasEvento: [
      'pode_gerenciar_camisas',
      'pode_gerenciar_camisas_eventos',
    ],
    chaveGerenciarPatrocinadoresEvento: [
      'pode_gerenciar_patrocinadores',
      'pode_gerenciar_patrocinadores_eventos',
    ],
    chaveGerenciarGastosEvento: [
      'pode_gerenciar_financeiro',
      'pode_gerenciar_taxas',
      'pode_gerenciar_gastos',
      'pode_gerenciar_gastos_eventos',
    ],
    chaveVerRelatorioEvento: [
      'pode_ver_relatorios',
      'pode_visualizar_relatorios',
      'pode_visualizar_relatorio_evento',
    ],
    chaveGerarCertificadosEvento: [
      'pode_gerar_certificados',
      'pode_emitir_certificados',
      'pode_gerar_certificado_evento',
    ],
  };

  // ==================== BASE ====================

  User? get usuarioAtual => _auth.currentUser;

  Future<bool> temPermissao(String permissao) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final dadosUsuario = await _carregarDadosUsuario(user.uid);
      if (!_usuarioEstaAtivo(dadosUsuario)) return false;

      if (_usuarioEhAdmin(dadosUsuario)) return true;

      final permissoes = await _getPermissoesUsuario(user.uid);
      return _temPermissaoNoMapa(permissoes, permissao);
    } catch (e) {
      debugPrint('❌ Erro ao verificar permissão "$permissao": $e');
      return false;
    }
  }

  Future<bool> temQualquerPermissao(List<String> permissoes) async {
    for (final permissao in permissoes) {
      if (await temPermissao(permissao)) return true;
    }
    return false;
  }

  /// Verifica somente as chaves informadas diretamente no documento.
  ///
  /// IMPORTANTE:
  /// - Usa admin como liberado total.
  /// - NÃO usa aliases.
  /// - NÃO usa compatibilidade inversa.
  /// - Ideal para ações sensíveis como adicionar/remover/editar participante
  ///   e editar/excluir pagamento.
  Future<bool> temQualquerPermissaoDireta(List<String> permissoes) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final dadosUsuario = await _carregarDadosUsuario(user.uid);
      if (!_usuarioEstaAtivo(dadosUsuario)) return false;

      if (_usuarioEhAdmin(dadosUsuario)) return true;

      final mapa = await _getPermissoesUsuario(user.uid);

      for (final permissao in permissoes) {
        if (mapa[permissao] == true) return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Erro ao verificar permissões diretas "$permissoes": $e');
      return false;
    }
  }

  Future<bool> temTodasPermissoes(List<String> permissoes) async {
    for (final permissao in permissoes) {
      if (!await temPermissao(permissao)) return false;
    }
    return true;
  }

  Future<Map<String, bool>> verificarMultiplasPermissoes(List<String> permissoes) async {
    final resultado = <String, bool>{};
    for (final permissao in permissoes) {
      resultado[permissao] = await temPermissao(permissao);
    }
    return resultado;
  }

  Future<Map<String, bool>> getTodasPermissoes() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    final dadosUsuario = await _carregarDadosUsuario(user.uid);
    if (!_usuarioEstaAtivo(dadosUsuario)) return {};

    if (_usuarioEhAdmin(dadosUsuario)) {
      return _permissoesAdminCompletas();
    }

    final permissoes = await _getPermissoesUsuario(user.uid);
    return _expandirPermissoesComAliases(permissoes);
  }

  Future<Map<String, dynamic>> getDadosUsuarioAtual() async {
    final user = _auth.currentUser;
    if (user == null) return {};
    return _carregarDadosUsuario(user.uid);
  }

  Future<int> getPesoUsuarioAtual() async {
    final data = await getDadosUsuarioAtual();
    return _intSeguro(data['peso_permissao']);
  }

  Future<bool> usuarioAtualEhAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    if (_cacheAdmin.containsKey(user.uid)) {
      return _cacheAdmin[user.uid] == true;
    }

    final dados = await _carregarDadosUsuario(user.uid);
    final isAdmin = _usuarioEstaAtivo(dados) && _usuarioEhAdmin(dados);
    _cacheAdmin[user.uid] = isAdmin;
    return isAdmin;
  }

  Future<bool> usuarioAtualPodeGerenciarComPeso({int minPeso = pesoMinimoGestaoEvento}) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final dados = await _carregarDadosUsuario(user.uid);
    if (!_usuarioEstaAtivo(dados)) return false;
    if (_usuarioEhAdmin(dados)) return true;

    return _intSeguro(dados['peso_permissao']) >= minPeso;
  }

  Future<Map<String, dynamic>> _carregarDadosUsuario(String userId) async {
    if (_cacheUsuario.containsKey(userId)) {
      return _cacheUsuario[userId]!;
    }

    try {
      final userDoc = await _firestore.collection('usuarios').doc(userId).get();
      if (!userDoc.exists) {
        _cacheUsuario[userId] = {};
        _cacheAdmin[userId] = false;
        return {};
      }

      final data = userDoc.data() ?? {};
      _cacheUsuario[userId] = data;
      _cacheAdmin[userId] = _usuarioEhAdmin(data);
      return data;
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados do usuário: $e');
      return {};
    }
  }

  Future<Map<String, bool>> _getPermissoesUsuario(String userId) async {
    if (_cachePermissoes.containsKey(userId)) {
      return _cachePermissoes[userId]!;
    }

    await _carregarTodasPermissoes(userId);
    return _cachePermissoes[userId] ?? {};
  }

  Future<void> _carregarTodasPermissoes(String userId) async {
    try {
      final permissoesDoc = await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (!permissoesDoc.exists) {
        _cachePermissoes[userId] = {};
        return;
      }

      final data = permissoesDoc.data() ?? {};
      final permissoes = <String, bool>{};

      data.forEach((key, value) {
        permissoes[key] = value is bool ? value : false;
      });

      _cachePermissoes[userId] = permissoes;
    } catch (e) {
      debugPrint('❌ Erro ao carregar permissões: $e');
      _cachePermissoes[userId] = {};
    }
  }

  bool _temPermissaoNoMapa(Map<String, bool> permissoes, String permissao) {
    if (permissoes[permissao] == true) return true;

    final aliases = _aliasesPermissoes[permissao] ?? const <String>[];
    for (final alias in aliases) {
      if (permissoes[alias] == true) return true;
    }

    // Compatibilidade inversa: se a tela antiga pedir uma chave antiga,
    // verifica se essa chave aparece como alias de alguma chave nova.
    for (final entry in _aliasesPermissoes.entries) {
      if (entry.value.contains(permissao) && permissoes[entry.key] == true) {
        return true;
      }
    }

    return false;
  }

  Map<String, bool> _expandirPermissoesComAliases(Map<String, bool> permissoes) {
    final resultado = Map<String, bool>.from(permissoes);

    for (final entry in _aliasesPermissoes.entries) {
      final chavePrincipal = entry.key;
      final aliases = entry.value;

      final liberada = _temPermissaoNoMapa(permissoes, chavePrincipal);
      if (liberada) {
        resultado[chavePrincipal] = true;
        for (final alias in aliases) {
          resultado[alias] = true;
        }
      }
    }

    return resultado;
  }

  bool _usuarioEstaAtivo(Map<String, dynamic> data) {
    if (data.isEmpty) return false;

    final status = (data['status_conta'] ?? '').toString().trim().toLowerCase();
    if (status == 'bloqueada' || status == 'bloqueado') return false;
    if (status == 'inativa' || status == 'inativo') return false;
    if (status == 'rejeitada' || status == 'rejeitado') return false;

    // Se não existir status por ser usuário antigo, não bloqueia.
    return true;
  }

  bool _usuarioEhAdmin(Map<String, dynamic> data) {
    final peso = _intSeguro(data['peso_permissao']);
    final tipo = (data['tipo'] ?? '').toString().trim().toLowerCase();

    return peso >= pesoAdmin || tipo == 'admin' || tipo == 'administrador';
  }

  int _intSeguro(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, bool> _permissoesAdminCompletas() {
    final map = <String, bool>{};

    for (final chave in chavesEventoPadrao) {
      map[chave] = true;
    }

    for (final chave in chavesVisibilidadePadrao) {
      map[chave] = true;
    }

    for (final entry in _aliasesPermissoes.entries) {
      map[entry.key] = true;
      for (final alias in entry.value) {
        map[alias] = true;
      }
    }

    return map;
  }

  // ==================== LISTAS PÚBLICAS PARA TELAS ====================

  static List<String> get chavesVisibilidadePadrao => const [
    chaveAcessarEventos,
    chaveAcessarInscricoes,
    chaveAcessarUniformes,
    chaveAcessarAssociacao,
    chaveAcessarRifas,
  ];

  static List<String> get chavesEventoPadrao => const [
    chaveVerEventos,
    chaveVerEventosAndamento,
    chaveCriarEvento,
    chaveEditarEvento,
    chaveExcluirEvento,
    chaveFinalizarEvento,
    chaveGerenciarParticipantesEvento,
    chaveAdicionarParticipanteEvento,
    chaveEditarParticipanteEvento,
    chaveRemoverParticipanteEvento,
    chaveConcluirParticipacaoEvento,
    chaveGerenciarCamisasEvento,
    chaveGerenciarPatrocinadoresEvento,
    chaveGerenciarGastosEvento,
    chaveVerRelatorioEvento,
    chaveGerarCertificadosEvento,
  ];

  // Lista pronta para a próxima fase: tela de usuário entregar as chaves.
  static List<Map<String, dynamic>> permissoesEventoParaTela() {
    return [
      {
        'titulo': 'Acessar eventos',
        'descricao': 'Permite abrir a tela de eventos no menu',
        'chave': chaveAcessarEventos,
        'categoria': 'EVENTOS — ACESSO',
        'icone': Icons.event_rounded,
        'cor': Colors.teal,
      },
      {
        'titulo': 'Ver eventos',
        'descricao': 'Permite visualizar a lista de eventos',
        'chave': chaveVerEventos,
        'categoria': 'EVENTOS — ACESSO',
        'icone': Icons.visibility_rounded,
        'cor': Colors.teal,
      },
      {
        'titulo': 'Ver andamento',
        'descricao': 'Permite acessar eventos em andamento',
        'chave': chaveVerEventosAndamento,
        'categoria': 'EVENTOS — ACESSO',
        'icone': Icons.pending_actions_rounded,
        'cor': Colors.teal,
      },
      {
        'titulo': 'Criar evento',
        'descricao': 'Permite criar novos eventos',
        'chave': chaveCriarEvento,
        'categoria': 'EVENTOS — GERAL',
        'icone': Icons.add_circle_rounded,
        'cor': Colors.blue,
      },
      {
        'titulo': 'Editar evento',
        'descricao': 'Permite editar dados do evento',
        'chave': chaveEditarEvento,
        'categoria': 'EVENTOS — GERAL',
        'icone': Icons.edit_calendar_rounded,
        'cor': Colors.blue,
      },
      {
        'titulo': 'Excluir evento',
        'descricao': 'Permite excluir eventos',
        'chave': chaveExcluirEvento,
        'categoria': 'EVENTOS — GERAL',
        'icone': Icons.delete_forever_rounded,
        'cor': Colors.red,
      },
      {
        'titulo': 'Finalizar evento',
        'descricao': 'Permite finalizar/concluir evento',
        'chave': chaveFinalizarEvento,
        'categoria': 'EVENTOS — GERAL',
        'icone': Icons.flag_circle_rounded,
        'cor': Colors.green,
      },
      {
        'titulo': 'Gerenciar participantes',
        'descricao': 'Permite abrir a gestão de participantes',
        'chave': chaveGerenciarParticipantesEvento,
        'categoria': 'EVENTOS — PARTICIPANTES',
        'icone': Icons.groups_rounded,
        'cor': Colors.deepPurple,
      },
      {
        'titulo': 'Adicionar participante',
        'descricao': 'Permite adicionar alunos ao evento',
        'chave': chaveAdicionarParticipanteEvento,
        'categoria': 'EVENTOS — PARTICIPANTES',
        'icone': Icons.person_add_rounded,
        'cor': Colors.deepPurple,
      },
      {
        'titulo': 'Editar participação',
        'descricao': 'Permite alterar dados de participação',
        'chave': chaveEditarParticipanteEvento,
        'categoria': 'EVENTOS — PARTICIPANTES',
        'icone': Icons.edit_note_rounded,
        'cor': Colors.deepPurple,
      },
      {
        'titulo': 'Remover participante',
        'descricao': 'Permite remover alunos do evento',
        'chave': chaveRemoverParticipanteEvento,
        'categoria': 'EVENTOS — PARTICIPANTES',
        'icone': Icons.person_remove_rounded,
        'cor': Colors.red,
      },
      {
        'titulo': 'Concluir participação',
        'descricao': 'Permite confirmar/concluir participação do aluno',
        'chave': chaveConcluirParticipacaoEvento,
        'categoria': 'EVENTOS — PARTICIPANTES',
        'icone': Icons.task_alt_rounded,
        'cor': Colors.green,
      },
      {
        'titulo': 'Gerenciar camisas',
        'descricao': 'Permite cadastrar, editar, entregar e marcar pagamento de camisas',
        'chave': chaveGerenciarCamisasEvento,
        'categoria': 'EVENTOS — FINANCEIRO',
        'icone': Icons.checkroom_rounded,
        'cor': Colors.orange,
      },
      {
        'titulo': 'Gerenciar patrocinadores',
        'descricao': 'Permite cadastrar e controlar patrocinadores',
        'chave': chaveGerenciarPatrocinadoresEvento,
        'categoria': 'EVENTOS — FINANCEIRO',
        'icone': Icons.handshake_rounded,
        'cor': Colors.amber,
      },
      {
        'titulo': 'Gerenciar gastos',
        'descricao': 'Permite cadastrar e excluir gastos do evento',
        'chave': chaveGerenciarGastosEvento,
        'categoria': 'EVENTOS — FINANCEIRO',
        'icone': Icons.payments_rounded,
        'cor': Colors.green,
      },
      {
        'titulo': 'Ver relatórios',
        'descricao': 'Permite abrir relatórios financeiros do evento',
        'chave': chaveVerRelatorioEvento,
        'categoria': 'EVENTOS — RELATÓRIOS',
        'icone': Icons.assessment_rounded,
        'cor': Colors.indigo,
      },
      {
        'titulo': 'Gerar certificados',
        'descricao': 'Permite gerar certificados dos participantes',
        'chave': chaveGerarCertificadosEvento,
        'categoria': 'EVENTOS — RELATÓRIOS',
        'icone': Icons.card_membership_rounded,
        'cor': Colors.indigo,
      },
    ];
  }

  // ==================== REGRAS PROFISSIONAIS DE EVENTO ====================

  Future<bool> _podeGerenciarComPermissaoEvento(String permissao) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final dadosUsuario = await _carregarDadosUsuario(user.uid);
    if (!_usuarioEstaAtivo(dadosUsuario)) return false;
    if (_usuarioEhAdmin(dadosUsuario)) return true;

    final peso = _intSeguro(dadosUsuario['peso_permissao']);
    if (peso < pesoMinimoGestaoEvento) return false;

    final permissoes = await _getPermissoesUsuario(user.uid);
    return _temPermissaoNoMapa(permissoes, permissao);
  }

  Future<bool> podeAcessarEventos() async {
    return await _podeGerenciarComPermissaoEvento(chaveAcessarEventos) ||
        await _podeGerenciarComPermissaoEvento(chaveVerEventos);
  }

  Future<bool> podeVerEventos() async {
    return await _podeGerenciarComPermissaoEvento(chaveVerEventos) ||
        await podeAcessarEventos();
  }

  Future<bool> podeVerEventosEmAndamento() async {
    return await _podeGerenciarComPermissaoEvento(chaveVerEventosAndamento);
  }

  Future<bool> podeCriarEvento() => _podeGerenciarComPermissaoEvento(chaveCriarEvento);

  Future<bool> podeEditarEvento() => _podeGerenciarComPermissaoEvento(chaveEditarEvento);

  Future<bool> podeExcluirEvento() => _podeGerenciarComPermissaoEvento(chaveExcluirEvento);

  Future<bool> podeFinalizarEvento() => _podeGerenciarComPermissaoEvento(chaveFinalizarEvento);

  Future<bool> podeGerenciarParticipantesEvento() {
    return _podeGerenciarComPermissaoEvento(chaveGerenciarParticipantesEvento);
  }

  Future<bool> podeAdicionarParticipanteEvento() {
    return _podeGerenciarComPermissaoEvento(chaveAdicionarParticipanteEvento);
  }

  Future<bool> podeEditarParticipanteEvento() {
    return _podeGerenciarComPermissaoEvento(chaveEditarParticipanteEvento);
  }

  Future<bool> podeRemoverParticipanteEvento() {
    return _podeGerenciarComPermissaoEvento(chaveRemoverParticipanteEvento);
  }

  Future<bool> podeConcluirParticipacaoEvento() {
    return _podeGerenciarComPermissaoEvento(chaveConcluirParticipacaoEvento);
  }

  Future<bool> podeGerenciarCamisasEvento() {
    return _podeGerenciarComPermissaoEvento(chaveGerenciarCamisasEvento);
  }

  Future<bool> podeGerenciarPatrocinadoresEvento() {
    return _podeGerenciarComPermissaoEvento(chaveGerenciarPatrocinadoresEvento);
  }

  Future<bool> podeGerenciarGastosEvento() {
    return _podeGerenciarComPermissaoEvento(chaveGerenciarGastosEvento);
  }

  Future<bool> podeGerenciarFinanceiroEvento() async {
    return await podeGerenciarGastosEvento() ||
        await podeGerenciarPatrocinadoresEvento() ||
        await podeGerenciarCamisasEvento();
  }

  Future<bool> podeVerRelatorioEvento() {
    return _podeGerenciarComPermissaoEvento(chaveVerRelatorioEvento);
  }

  Future<bool> podeGerarCertificadosEvento() {
    return _podeGerenciarComPermissaoEvento(chaveGerarCertificadosEvento);
  }

  /// Carrega todas as permissões principais usadas no painel de evento.
  /// Isso evita vários awaits espalhados nas telas.
  Future<Map<String, bool>> getPermissoesEvento() async {
    return {
      'podeAcessarEventos': await podeAcessarEventos(),
      'podeVerEventos': await podeVerEventos(),
      'podeVerEventosEmAndamento': await podeVerEventosEmAndamento(),
      'podeCriarEvento': await podeCriarEvento(),
      'podeEditarEvento': await podeEditarEvento(),
      'podeExcluirEvento': await podeExcluirEvento(),
      'podeFinalizarEvento': await podeFinalizarEvento(),
      'podeGerenciarParticipantesEvento': await podeGerenciarParticipantesEvento(),
      'podeAdicionarParticipanteEvento': await podeAdicionarParticipanteEvento(),
      'podeEditarParticipanteEvento': await podeEditarParticipanteEvento(),
      'podeRemoverParticipanteEvento': await podeRemoverParticipanteEvento(),
      'podeConcluirParticipacaoEvento': await podeConcluirParticipacaoEvento(),
      'podeGerenciarCamisasEvento': await podeGerenciarCamisasEvento(),
      'podeGerenciarPatrocinadoresEvento': await podeGerenciarPatrocinadoresEvento(),
      'podeGerenciarGastosEvento': await podeGerenciarGastosEvento(),
      'podeGerenciarFinanceiroEvento': await podeGerenciarFinanceiroEvento(),
      'podeVerRelatorioEvento': await podeVerRelatorioEvento(),
      'podeGerarCertificadosEvento': await podeGerarCertificadosEvento(),
    };
  }

  // ==================== COMPATIBILIDADE COM NOMES ANTIGOS ====================

  Future<bool> podeGerenciarParticipantes() => podeGerenciarParticipantesEvento();

  Future<bool> podeGerenciarFinanceiro() => podeGerenciarFinanceiroEvento();

  Future<bool> podeGerenciarPatrocinadores() => podeGerenciarPatrocinadoresEvento();

  Future<bool> podeGerenciarCamisas() => podeGerenciarCamisasEvento();

  Future<bool> podeVerRelatorios() => podeVerRelarioOuRelatoriosEvento();

  Future<bool> podeVerRelarioOuRelatoriosEvento() => podeVerRelatorioEvento();

  // ==================== CACHE ====================

  Future<void> recarregarPermissoes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    limparCacheDoUsuario(user.uid);

    await _carregarDadosUsuario(user.uid);
    await _carregarTodasPermissoes(user.uid);
  }

  Future<void> recarregarPermissoesDoUsuario(String userId) async {
    limparCacheDoUsuario(userId);
    await _carregarDadosUsuario(userId);
    await _carregarTodasPermissoes(userId);
  }

  void limparCacheDoUsuario(String userId) {
    _cachePermissoes.remove(userId);
    _cacheAdmin.remove(userId);
    _cacheUsuario.remove(userId);
  }

  void limparCache() {
    _cachePermissoes.clear();
    _cacheAdmin.clear();
    _cacheUsuario.clear();
  }

  // ==================== WIDGETS AUXILIARES ====================

  Widget buildIfPermissao({
    required BuildContext context,
    required String permissao,
    required Widget child,
    Widget? fallback,
  }) {
    return FutureBuilder<bool>(
      future: temPermissao(permissao),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return fallback ?? const SizedBox.shrink();
        }

        if (snapshot.data == true) return child;
        return fallback ?? const SizedBox.shrink();
      },
    );
  }

  Widget buildIfPermissaoFromMap({
    required Map<String, bool> permissoes,
    required String permissao,
    required Widget child,
    Widget? fallback,
  }) {
    if (permissoes[permissao] == true) return child;

    final aliases = _aliasesPermissoes[permissao] ?? const <String>[];
    for (final alias in aliases) {
      if (permissoes[alias] == true) return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}
