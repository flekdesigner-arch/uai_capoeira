class AreaAlunoConfig {
  final Map<String, dynamic> raw;

  const AreaAlunoConfig(this.raw);

  factory AreaAlunoConfig.fromMap(Map<String, dynamic>? data) {
    return AreaAlunoConfig(Map<String, dynamic>.from(data ?? const {}));
  }

  bool _bool(String key, {bool defaultValue = true}) {
    final value = raw[key];
    if (value is bool) return value;
    return defaultValue;
  }

  bool _boolEfetivo(String key, {bool defaultValue = true}) {
    final scopedKey = _scopedKey(key);
    if (scopedKey != null && raw.containsKey(scopedKey)) {
      final value = raw[scopedKey];
      if (value is bool) return value;
    }

    return _bool(key, defaultValue: defaultValue);
  }

  String _string(String key, String defaultValue) {
    final value = raw[key]?.toString().trim();
    if (value == null || value.isEmpty || value == 'null') {
      return defaultValue;
    }
    return value;
  }

  String _stringEfetivo(String key, String defaultValue) {
    final scopedKey = _scopedKey(key);
    if (scopedKey != null && raw.containsKey(scopedKey)) {
      final value = raw[scopedKey]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    return _string(key, defaultValue);
  }

  String? _scopedKey(String key) {
    if (modoAcesso == 'google') return 'com_google_$key';
    if (modoAcesso == 'basico') return 'sem_google_$key';
    return null;
  }

  String get modoAcesso => _string('modo_acesso', 'basico').toLowerCase();

  bool get acessoGoogle => modoAcesso == 'google';

  bool get googleLoginAtivo => _bool('google_login_ativo', defaultValue: false);

  String get googleVinculacaoModo =>
      _string('google_vinculacao_modo', 'desativada').toLowerCase();

  bool get googleVinculado => _bool('google_vinculado', defaultValue: false);

  bool get exigeGoogleParaCompleto =>
      _bool('exige_google_para_completo', defaultValue: false);

  bool get permitirVincularGoogleNoPrimeiroAcesso =>
      _bool('permitir_vincular_google_no_primeiro_acesso', defaultValue: true);

  bool get deveMostrarCardGoogle {
    if (!googleLoginAtivo || acessoGoogle) return false;
    if (!permitirVincularGoogleNoPrimeiroAcesso && !googleVinculado) {
      return false;
    }

    return googleVinculado ||
        googleVinculacaoModo == 'opcional' ||
        googleVinculacaoModo == 'recomendada' ||
        googleVinculacaoModo == 'obrigatoria_para_completo' ||
        googleVinculacaoModo == 'obrigatoria_apos_vincular' ||
        exigeGoogleParaCompleto;
  }

  String get googleEmailMascarado => _string('google_email_mascarado', '');

  bool get ativo =>
      _bool('ativo', defaultValue: _bool('visivel_site', defaultValue: true));

  bool get mostrarDashboard => _boolEfetivo('mostrar_dashboard');

  bool get mostrarDadosBasicos =>
      _boolEfetivo('mostrar_dados_basicos') && modoDadosBasicos != 'oculto';

  bool get mostrarAcademiaTurma => _boolEfetivo('mostrar_academia_turma');

  bool get mostrarFrequencia => _boolEfetivo('mostrar_frequencia');

  bool get mostrarEventos => _boolEfetivo('mostrar_eventos');

  bool get mostrarCertificados => _boolEfetivo('mostrar_certificados');

  bool get mostrarFinanceiroEventos =>
      _boolEfetivo('mostrar_financeiro_eventos') && modoFinanceiro != 'oculto';

  bool get mostrarSolicitacaoAlteracao =>
      _boolEfetivo('mostrar_solicitacao_alteracao');

  bool get mostrarGraduacaoAtual => _bool(
    'mostrar_graduacao_atual',
    defaultValue: _boolEfetivo('mostrar_graduacao'),
  );

  bool get mostrarGraduacaoEvento =>
      _boolEfetivo('mostrar_graduacao_evento') &&
      modoGraduacaoEvento != 'oculto';

  bool get mostrarCamisaEvento => _boolEfetivo('mostrar_camisa_evento');

  bool get mostrarPresencaEvento => _boolEfetivo('mostrar_presenca_evento');

  bool get mostrarAvisoAuditoria => false;

  String get modoDadosBasicos =>
      _stringEfetivo('modo_dados_basicos', 'limitado').toLowerCase();

  String get modoTelefone =>
      _stringEfetivo('modo_telefone', 'mascarado').toLowerCase();

  String get modoEndereco =>
      _stringEfetivo('modo_endereco', 'cidade_bairro').toLowerCase();

  String get modoResponsavel =>
      _stringEfetivo('modo_responsavel', 'nome').toLowerCase();

  String get modoFinanceiro =>
      _stringEfetivo('modo_financeiro', 'completo').toLowerCase();

  String get modoGraduacaoEvento =>
      _stringEfetivo('modo_graduacao_evento', 'completo').toLowerCase();

  String get mensagemTopo =>
      _string('mensagem_topo', 'Bem-vindo(a) à Área do Aluno');

  String get mensagemAreaDesativada => _string(
    'mensagem_area_desativada',
    'A Área do Aluno não está disponível no momento.',
  );

  String get mensagemDadosOcultos => _string(
    'mensagem_dados_ocultos',
    'Algumas informações foram ocultadas pela coordenação.',
  );

  String get avisoAuditoriaAcesso => _string(
    'aviso_auditoria_acesso',
    'Por segurança, este acesso pode ser registrado pela coordenação.',
  );

  bool get financeiroResumo => modoFinanceiro == 'resumo';

  bool get graduacaoEventoSuspense => modoGraduacaoEvento == 'suspense';
}
