import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:xml/xml.dart' as xml;
import 'package:uai_capoeira/core/image_cache/uai_student_photo.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/services/uai_callable_client.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/shared/widgets/uai_theme_selector.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/core/theme/tema_global_service.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_config_service.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_session_service.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_eventos_service.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/escolher_aluno_vinculado_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_google_service.dart';
import 'package:uai_capoeira/modules/area_aluno/widgets/area_aluno_meus_eventos_section.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/screens/estudos_home_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/estudos_config_service.dart';
import 'package:uai_capoeira/modules/rhythm_studio/student/rhythm_guide_config.dart';
import 'package:uai_capoeira/modules/rhythm_studio/student/rhythm_student_preview_screen.dart';
import 'package:uai_capoeira/modules/usuarios/services/user_service.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';
import 'package:uai_capoeira/modules/site/screens/biografia_screen.dart';
import 'package:uai_capoeira/modules/site/screens/graduacoes_screen.dart';
import 'package:uai_capoeira/modules/site/screens/landing_page.dart';
import 'package:uai_capoeira/modules/site/screens/portfolio_web_screen.dart';
import 'package:uai_capoeira/modules/site/screens/regimento_screen.dart';

import 'area_aluno_certificados_screen.dart';
import 'area_aluno_evento_detalhe_screen.dart';
import 'area_aluno_frequencia_screen.dart';
import 'area_aluno_solicitar_alteracao_screen.dart';
import 'area_aluno_meus_pedidos_screen.dart';
import 'area_aluno_vincular_email_dialog.dart';

class AreaAlunoDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> config;
  final Map<String, dynamic> authPayload;
  final bool adminPreview;

  const AreaAlunoDashboardScreen({
    super.key,
    required this.aluno,
    required this.config,
    required this.authPayload,
    this.adminPreview = false,
  });

  @override
  State<AreaAlunoDashboardScreen> createState() =>
      _AreaAlunoDashboardScreenState();
}

class _AreaAlunoDashboardScreenState extends State<AreaAlunoDashboardScreen> {
  String? _cordaSvg;
  bool _vinculandoGoogle = false;
  bool _vinculandoEmail = false;
  bool _tutorialPosVinculoMostrado = false;
  bool _carregandoConfigEstudos = true;
  bool _mostrarEstudosFundamentos = false;
  bool _mostrarGuiaInstrumentacao = false;

  final RastreioSiteService _rastreioService = RastreioSiteService();
  final AreaAlunoSessionService _sessionService = AreaAlunoSessionService();
  final EstudosConfigService _estudosConfigService = EstudosConfigService();

  String get _nome => _safeText(widget.aluno['nome'], 'Aluno');
  String get _apelido => _safeText(widget.aluno['apelido'], '');
  String get _foto => _safeText(widget.aluno['foto_perfil_aluno'], '');
  String get _status => _safeText(widget.aluno['status_atividade'], '');
  String get _alunoId => _safeText(
    widget.aluno['aluno_id'] ?? widget.aluno['id'] ?? widget.aluno['docId'],
    '',
  );
  Map<String, dynamic> get _dispositivoLogin {
    final data = widget.authPayload['dispositivo_login'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  AreaAlunoConfig get _areaConfig {
    // As Cloud Functions já devolvem uma configuração EFETIVA para o método
    // de acesso atual (básico, Google ou Conta UAI/e-mail), copiando as
    // permissões do perfil correto para as chaves canônicas mostrar_*.
    //
    // O dashboard não deve aplicar novamente com_google_* / sem_google_*.
    // Essa segunda seleção fazia a Web/PWA poder reutilizar flags legadas e
    // ocultar os módulos mesmo quando o backend havia liberado o acesso.
    final modoAcesso = _safeText(
      widget.config['modo_acesso'] ?? widget.authPayload['modo_acesso'],
      'basico',
    ).toLowerCase();
    final configEfetiva = Map<String, dynamic>.from(widget.config)
      ..removeWhere(
        (key, _) =>
            key.startsWith('com_google_') || key.startsWith('sem_google_'),
      );

    return AreaAlunoConfig.fromMap({
      ...configEfetiva,
      'modo_acesso': modoAcesso,
    });
  }

  bool get _sessaoGoogleValidada {
    final modoAcesso = _safeText(
      widget.authPayload['modo_acesso'],
      '',
    ).toLowerCase();
    final googleUid = _safeText(widget.authPayload['google_uid'], '');
    final alunoPayloadId = _safeText(
      widget.authPayload['alunoSelecionadoId'] ??
          widget.authPayload['aluno_id_login'] ??
          widget.authPayload['aluno_id'],
      '',
    );
    final user = FirebaseAuth.instance.currentUser;

    return modoAcesso == 'google' &&
        googleUid.isNotEmpty &&
        user?.uid == googleUid &&
        _alunoId.isNotEmpty &&
        alunoPayloadId == _alunoId;
  }

  bool get _sessaoIdentidadeCompletaValidada {
    if (widget.adminPreview) return true;
    final modoAcesso = _safeText(
      widget.config['modo_acesso'] ?? widget.authPayload['modo_acesso'],
      '',
    ).toLowerCase();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    if (modoAcesso == 'google') {
      return _sessaoGoogleValidada;
    }

    if (modoAcesso == 'conta_uai' || modoAcesso == 'email') {
      final contaUid = _safeText(widget.authPayload['conta_uai_uid'], '');
      final alunoPayloadId = _safeText(
        widget.authPayload['alunoSelecionadoId'] ??
            widget.authPayload['aluno_id_login'] ??
            widget.authPayload['aluno_id'],
        '',
      );

      // Conta UAI é uma identidade autenticada própria. Quando o UID está no
      // payload, ele precisa coincidir. Para sessões antigas sem o UID salvo,
      // aceitamos somente se o backend já marcou a configuração como identidade
      // completa e o aluno do payload coincide com o dashboard atual.
      final uidOk = contaUid.isEmpty || contaUid == user.uid;
      final alunoOk = alunoPayloadId.isEmpty || alunoPayloadId == _alunoId;
      return uidOk && alunoOk && _areaConfig.acessoIdentidadeCompleta;
    }

    return false;
  }

  bool get _podeMostrarEstudosFundamentos =>
      _mostrarEstudosFundamentos && _sessaoIdentidadeCompletaValidada;

  bool get _temAcoesDashboard =>
      (_alunoId.isNotEmpty && _sessaoIdentidadeCompletaValidada) ||
      _areaConfig.mostrarDadosBasicos ||
      _areaConfig.mostrarSolicitacaoAlteracao ||
      _areaConfig.mostrarFrequencia ||
      _areaConfig.mostrarCertificados ||
      _podeMostrarEstudosFundamentos;

  Map<String, dynamic> get _turmaInfo {
    final data = widget.aluno['turma_info'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  String get _graduacao {
    return _safeText(
      widget.aluno['graduacao_nome'] ??
          widget.aluno['graduacao_atual'] ??
          widget.aluno['graduacao'],
      'Não informada',
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCordaSvg();
    _carregarConfigEstudosFundamentos();
    _carregarConfigGuiaInstrumentacao();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _talvezMostrarTutorialPosVinculo();
    });

    if (!widget.adminPreview) {
      _rastreioService.iniciarTela(
      'area_aluno_dashboard',
      origem: 'area_aluno_login',
      metadata: {
        'aluno_id': _alunoId,
        'aluno_nome': _nome,
        'aluno_apelido': _apelido,
        'status': _status,
        'graduacao': _graduacao,
        'turma': widget.aluno['turma']?.toString() ?? '',
        'academia': widget.aluno['academia']?.toString() ?? '',
        if (_dispositivoLogin.isNotEmpty) 'dispositivo': _dispositivoLogin,
      },
    );
      _rastreioService.marcarTempo('area_aluno_dashboard_tempo');
    }
  }

  @override
  void dispose() {
    if (!widget.adminPreview) {
      _rastreioService.registrarTempoMarcador(
      chave: 'area_aluno_dashboard_tempo',
      tipo: 'tempo_tela',
      nome: 'area_aluno_dashboard',
      origem: 'dispose',
      limparMarcador: true,
    );
      _rastreioService.finalizarTela(destino: 'saida_area_aluno_dashboard');
    }
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Future<void> _loadCordaSvg() async {
    try {
      final content = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/images/corda.svg');
      final graduacaoVisual = await _resolverGraduacaoVisual();
      final cordaSvg = _montarCordaSvg(content, graduacaoVisual);

      if (!mounted) return;

      setState(() {
        _cordaSvg = cordaSvg;
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar corda.svg no dashboard do aluno: $e');
    }
  }

  Future<Map<String, dynamic>> _resolverGraduacaoVisual() async {
    final nomeExibido = _graduacao;
    final porNome = await _buscarGraduacaoPorNome(nomeExibido);

    if (porNome != null) return porNome;

    final porId = await _buscarGraduacaoPorId(
      _safeText(
        widget.aluno['graduacao_id'] ??
            widget.aluno['graduacao_atual_id'] ??
            widget.aluno['graduacaoId'] ??
            widget.aluno['graduacaoAtualId'],
        '',
      ),
    );

    final nomePorId = _safeText(
      porId?['nome_graduacao'] ?? porId?['nome'] ?? porId?['titulo'],
      '',
    );

    if (porId != null &&
        _normalizarTextoGraduacao(nomePorId) ==
            _normalizarTextoGraduacao(nomeExibido)) {
      return porId;
    }

    return {...widget.aluno, 'nome_graduacao': nomeExibido};
  }

  Future<Map<String, dynamic>?> _buscarGraduacaoPorNome(String nome) async {
    final nomeNormalizado = _normalizarTextoGraduacao(nome);
    if (nomeNormalizado.isEmpty ||
        nomeNormalizado == _normalizarTextoGraduacao('Não informada')) {
      return null;
    }

    try {
      final db = FirebaseFirestore.instance;
      for (final campo in const ['nome_graduacao', 'nome', 'titulo']) {
        final snap = await db
            .collection('graduacoes')
            .where(campo, isEqualTo: nome)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          return {'id': snap.docs.first.id, ...snap.docs.first.data()};
        }
      }

      final snap = await db.collection('graduacoes').limit(500).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final candidatos = [
          data['nome_graduacao'],
          data['nome'],
          data['titulo'],
          data['descricaoCompleta'],
          data['descricao_completa'],
        ];

        for (final candidato in candidatos) {
          if (_normalizarTextoGraduacao(_safeText(candidato, '')) ==
              nomeNormalizado) {
            return {'id': doc.id, ...data};
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar graduação exibida "$nome": $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> _buscarGraduacaoPorId(
    String graduacaoId,
  ) async {
    final id = graduacaoId.trim();
    if (id.isEmpty || id == '0') return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('graduacoes')
          .doc(id)
          .get();
      if (!doc.exists) return null;
      return {'id': doc.id, ...?doc.data()};
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar graduação $graduacaoId: $e');
      return null;
    }
  }

  String _normalizarTextoGraduacao(String value) {
    const withAccents = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇñÑ';
    const withoutAccents = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUCnN';

    var normalized = value.trim();
    for (var i = 0; i < withAccents.length; i++) {
      normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
    }

    return normalized
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String? _montarCordaSvg(String svgContent, Map<String, dynamic> graduacao) {
    final cor1 = _pegarCor(graduacao, ['hex_cor1', 'graduacao_cor1']);
    final cor2 = _pegarCor(graduacao, ['hex_cor2', 'graduacao_cor2']);
    final ponta1 = _pegarCor(graduacao, ['hex_ponta1', 'graduacao_ponta1']);
    final ponta2 = _pegarCor(graduacao, ['hex_ponta2', 'graduacao_ponta2']);

    if (cor1 == null && cor2 == null && ponta1 == null && ponta2 == null) {
      return null;
    }

    try {
      final document = xml.XmlDocument.parse(svgContent);

      void changeColor(String id, String? hexColor) {
        if (hexColor == null || hexColor.trim().isEmpty) return;

        final hex = _normalizarHex(hexColor);
        if (hex == null) return;

        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
              orElse: () => xml.XmlElement(xml.XmlName('')),
            );

        if (element.name.local.isEmpty) return;

        final style = element.getAttribute('style') ?? '';
        final newStyle = style.contains('fill:')
            ? style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), 'fill:$hex')
            : 'fill:$hex;$style';

        element.setAttribute('style', newStyle);
      }

      changeColor('cor1', cor1);
      changeColor('cor2', cor2);
      changeColor('corponta1', ponta1);
      changeColor('corponta2', ponta2);

      return document.toXmlString();
    } catch (e) {
      debugPrint('⚠️ Erro ao montar SVG da corda no dashboard: $e');
      return null;
    }
  }

  String? _pegarCor(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') return value;
    }

    return null;
  }

  String? _normalizarHex(String value) {
    var hex = value.trim();

    if (hex.isEmpty || hex == 'null') return null;

    hex = hex.replaceAll('0x', '').replaceAll('0X', '');
    if (!hex.startsWith('#')) hex = '#$hex';

    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return null;
    }

    return hex.toUpperCase();
  }

  Color _turmaColor() {
    final cor = _normalizarHex(_turmaInfo['cor_turma']?.toString() ?? '');

    if (cor == null) return context.uai.info;

    try {
      return Color(int.parse('FF${cor.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return context.uai.info;
    }
  }

  String _safeText(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  Future<void> _carregarConfigGuiaInstrumentacao() async {
    try {
      final config = await RhythmGuideConfigService().load();
      if (mounted) setState(() => _mostrarGuiaInstrumentacao = config.mostrarCardAluno);
    } catch (_) {
      if (mounted) setState(() => _mostrarGuiaInstrumentacao = false);
    }
  }

  Future<void> _carregarConfigEstudosFundamentos() async {
    try {
      final disponivel = await _estudosConfigService
          .moduloDisponivelParaAluno();
      if (!mounted) return;
      setState(() {
        _mostrarEstudosFundamentos = disponivel;
        _carregandoConfigEstudos = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar config de Estudos e Fundamentos: $e');
      if (!mounted) return;
      setState(() {
        _mostrarEstudosFundamentos = false;
        _carregandoConfigEstudos = false;
      });
    }
  }

  Future<void> _sairAreaAluno() async {
    await _rastreioService.registrarEvento(
      tipo: 'area_aluno',
      nome: 'logout_area_aluno',
      origem: 'area_aluno_dashboard',
      metadata: {
        'aluno_id': _alunoId,
        'aluno_nome': _nome,
        if (_dispositivoLogin.isNotEmpty)
          'dispositivo_login': _dispositivoLogin,
      },
    );

    await _sessionService.limparSessao();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  Future<void> _irParaGestao() async {
    await AreaAlunoGoogleService().abrirGestao(context);
  }

  Future<void> _trocarAlunoVinculado(List<AlunoVinculadoGoogle> alunos) async {
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EscolherAlunoVinculadoScreen(alunos: alunos),
      ),
    );
  }

  Future<User?> _entrarComGoogle() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final credential = await FirebaseAuth.instance.signInWithPopup(provider);
      return credential.user;
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    return result.user;
  }

  Future<void> _confirmarVinculoGoogle() async {
    if (_vinculandoGoogle) return;

    _rastreioService.registrarClique(
      nome: 'abrir_explicacao_vinculo_google',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_id': _alunoId, 'aluno_nome': _nome},
    );

    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.surface);

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 20,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(t.cardRadius + 6),
                border: Border.all(color: t.border),
                boxShadow: t.cardShadow,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                accent.withAlpha(31),
                                t.surface,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: accent.withAlpha(46),
                              ),
                            ),
                            child: Icon(
                              Icons.g_mobiledata_rounded,
                              color: accent,
                              size: 36,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vincular conta Google',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Conecte este cadastro ao e-mail escolhido.',
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Para liberar o acesso completo, precisamos conectar o cadastro do aluno a uma conta Google.',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Essa conta será usada apenas para reconhecer com segurança quem está acessando a Área do Aluno. Nas próximas vezes, o aluno ou responsável poderá entrar com mais facilidade e segurança.',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildVinculoInfoBlock(
                        icon: Icons.badge_rounded,
                        title: 'Não cria outro cadastro',
                        text:
                            'A conta Google apenas se conecta ao cadastro já existente do aluno.',
                        color: t.info,
                      ),
                      const SizedBox(height: 8),
                      _buildVinculoInfoBlock(
                        icon: Icons.family_restroom_rounded,
                        title: 'Pode ser do aluno ou responsável',
                        text:
                            'Use o e-mail Google que será usado para acessar a Área do Aluno.',
                        color: t.associacao,
                      ),
                      const SizedBox(height: 8),
                      _buildVinculoInfoBlock(
                        icon: Icons.security_rounded,
                        title: 'Mais segurança no acesso',
                        text:
                            'Depois de vincular, o acesso completo é liberado conforme as configurações do sistema.',
                        color: t.success,
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Agora não'),
                          ),
                          FilledButton.icon(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            icon: const Icon(Icons.g_mobiledata_rounded),
                            label: const Text('Vincular Google'),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: _readableOn(accent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  t.buttonRadius,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmou != true || !mounted) return;

    _rastreioService.registrarClique(
      nome: 'confirmar_vinculo_google',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_id': _alunoId, 'aluno_nome': _nome},
    );

    await _vincularContaGoogle();
  }

  Future<void> _vincularContaGoogle() async {
    if (_vinculandoGoogle) return;

    setState(() => _vinculandoGoogle = true);
    final successColor = context.uai.success;
    final errorColor = context.uai.error;

    try {
      final user = await _entrarComGoogle();
      if (user == null) {
        _mostrarSnack('A vinculação foi cancelada.', errorColor);
        return;
      }

      final data = await UaiCallableClient.instance.call(
        'vincularGoogleAreaAluno',
        {
          'alunoId': _alunoId,
          'authPayload': widget.authPayload,
          'dispositivo': _dispositivoLogin,
          'origem': 'area_aluno_dashboard',
        },
      );
      if (data['success'] != true) {
        _mostrarSnack(
          data['message']?.toString() ??
              'Não foi possível vincular a conta Google.',
          errorColor,
        );
        return;
      }

      final aluno = Map<String, dynamic>.from(data['aluno'] as Map? ?? {});
      final config = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      final authPayload = {
        ...widget.authPayload,
        'modo_acesso': 'google',
        'google_uid': user.uid,
        'google_email': user.email ?? '',
        'login_google_em': DateTime.now().toIso8601String(),
        'mostrar_tutorial_pos_vinculo': true,
      };

      await _sessionService.salvarSessao(
        aluno: aluno,
        config: config,
        authPayload: authPayload,
      );

      if (!mounted) return;

      _mostrarSnack(
        'Conta Google vinculada com sucesso. Acesso completo liberado!',
        successColor,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AreaAlunoDashboardScreen(
            aluno: aluno,
            config: config,
            authPayload: authPayload,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _mostrarSnack(
        e.message ?? 'Não foi possível confirmar a conta Google.',
        errorColor,
      );
    } catch (e) {
      if (!mounted) return;
      _mostrarSnack(
        'Erro ao conectar com Google. Tente novamente.',
        errorColor,
      );
    } finally {
      if (mounted) setState(() => _vinculandoGoogle = false);
    }
  }

  Future<void> _vincularContaEmail() async {
    if (_vinculandoEmail || _alunoId.isEmpty) return;

    setState(() => _vinculandoEmail = true);
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AreaAlunoVincularEmailDialog(
          alunoId: _alunoId,
          authPayload: widget.authPayload,
          jaVinculado: _areaConfig.emailConfirmado,
          emailMascarado: _areaConfig.emailContaUaiMascarado,
        ),
      );

      if (data == null || !mounted) return;

      final aluno = Map<String, dynamic>.from(data['aluno'] as Map? ?? {});
      final config = Map<String, dynamic>.from(data['config'] as Map? ?? {});
      final user = FirebaseAuth.instance.currentUser;
      final vinculoId = data['vinculo_id']?.toString() ?? '';

      final authPayload = <String, dynamic>{
        ...widget.authPayload,
        'modo_acesso': 'conta_uai',
        'conta_uai_uid': user?.uid ?? '',
        'conta_uai_email': user?.email ?? '',
        'vinculo_id': vinculoId,
        'aluno_id_login': aluno['aluno_id']?.toString() ?? _alunoId,
        'mostrar_tutorial_pos_vinculo': true,
      };

      await _sessionService.salvarSessao(
        aluno: aluno,
        config: config,
        authPayload: authPayload,
        alunoSelecionadoId: aluno['aluno_id']?.toString() ?? _alunoId,
      );

      if (!mounted) return;

      _mostrarSnack(
        _areaConfig.emailConfirmado
            ? 'E-mail confirmado. Acesso completo liberado!'
            : 'E-mail vinculado com sucesso. Acesso completo liberado!',
        context.uai.success,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AreaAlunoDashboardScreen(
            aluno: aluno,
            config: config,
            authPayload: authPayload,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _vinculandoEmail = false);
    }
  }

  Future<void> _talvezMostrarTutorialPosVinculo() async {
    if (_tutorialPosVinculoMostrado || !mounted) return;

    final mostrar = widget.authPayload['mostrar_tutorial_pos_vinculo'] == true;
    if (!mostrar) return;

    _tutorialPosVinculoMostrado = true;

    await _limparFlagTutorialPosVinculo();

    if (!mounted) return;

    _rastreioService.registrarEvento(
      tipo: 'area_aluno',
      nome: 'tutorial_pos_vinculo_exibido',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_id': _alunoId, 'aluno_nome': _nome},
    );

    await _mostrarTutorialAreaAluno();
  }

  Future<void> _limparFlagTutorialPosVinculo() async {
    final authPayloadLimpo = Map<String, dynamic>.from(widget.authPayload)
      ..remove('mostrar_tutorial_pos_vinculo');

    try {
      await _sessionService.salvarSessao(
        aluno: widget.aluno,
        config: widget.config,
        authPayload: authPayloadLimpo,
      );
    } catch (e) {
      debugPrint('Erro ao limpar tutorial pós-vínculo da sessão: $e');
    }
  }

  Future<void> _mostrarTutorialAreaAluno() async {
    final pages = const [
      _TutorialAreaAlunoPage(
        icon: Icons.verified_user_rounded,
        title: 'Acesso completo liberado!',
        text:
            'Pronto! O cadastro foi vinculado a uma conta confirmada e a Área do Aluno está liberada conforme as permissões definidas pela coordenação.',
      ),
      _TutorialAreaAlunoPage(
        icon: Icons.person_search_rounded,
        title: 'Consulte seus dados',
        text:
            'Veja as informações do aluno, turma, graduação e dados cadastrados. Caso encontre algo errado, use a opção de solicitar alteração.',
      ),
      _TutorialAreaAlunoPage(
        icon: Icons.fact_check_rounded,
        title: 'Acompanhe a frequência',
        text:
            'Confira presenças e acompanhe a participação do aluno nas aulas.',
      ),
      _TutorialAreaAlunoPage(
        icon: Icons.card_membership_rounded,
        title: 'Eventos e certificados',
        text:
            'Veja eventos participados, certificados disponíveis e informações liberadas pela coordenação.',
      ),
      _TutorialAreaAlunoPage(
        icon: Icons.security_rounded,
        title: 'Mais segurança no acesso',
        text:
            'Nas próximas vezes, use a conta vinculada — Google ou e-mail verificado — para acessar com mais segurança e praticidade.',
      ),
    ];

    final pulou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AreaAlunoTutorialSheet(
        pages: pages,
        theme: context.uai,
        readableOn: _readableOn,
      ),
    );

    _rastreioService.registrarEvento(
      tipo: 'area_aluno',
      nome: pulou == true
          ? 'tutorial_pos_vinculo_pulado'
          : 'tutorial_pos_vinculo_concluido',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_id': _alunoId, 'aluno_nome': _nome},
    );
  }

  Widget _buildVinculoInfoBlock({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(20), t.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withAlpha(36)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarSnack(String mensagem, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _abrirTelaMenuAluno({required String titulo, required Widget tela}) {
    Navigator.pop(context);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _buildTelaPublicaAreaAlunoShell(titulo: titulo, tela: tela),
      ),
    );
  }

  Widget _buildTelaPublicaAreaAlunoShell({
    required String titulo,
    required Widget tela,
  }) {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = _readableOn(appBarBg);

    // Algumas telas públicas do site foram feitas para abrir dentro da
    // LandingPage, que já fornece Material/Scaffold/DefaultTextStyle.
    // Quando abrimos essas mesmas telas direto pela Área do Aluno,
    // precisamos fornecer o shell da Área do Aluno sem alterar a landing.
    return Scaffold(
      backgroundColor: t.background,
      drawer: Drawer(
        backgroundColor: t.surface,
        width: MediaQuery.of(context).size.width.clamp(280.0, 330.0),
        child: _buildDrawerMenu(emTelaInterna: true),
      ),
      appBar: AppBar(
        title: Text(
          titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Abrir menu',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Escolher tema',
              child: Material(
                color: appBarFg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _abrirSelecionarTemaPublico,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: appBarFg.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Icon(
                      Icons.palette_rounded,
                      color: appBarFg,
                      size: 21,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Material(
        color: t.background,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: t.textPrimary,
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: t.textPrimary),
            child: tela,
          ),
        ),
      ),
    );
  }

  Future<void> _abrirInfoAluno() async {
    _rastreioService.registrarClique(
      nome: 'abrir_informacoes_aluno',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    _showAlunoInfoSheet();
  }

  Future<void> _abrirSolicitarAlteracoes() async {
    _rastreioService.registrarClique(
      nome: 'abrir_solicitar_alteracoes',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoSolicitarAlteracaoScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirFrequencia() async {
    _rastreioService.registrarClique(
      nome: 'abrir_frequencia',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoFrequenciaScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirCertificados() async {
    _rastreioService.registrarClique(
      nome: 'abrir_certificados',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome},
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoCertificadosScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );
  }

  Future<void> _abrirEstudosFundamentos() async {
    if (!_sessaoIdentidadeCompletaValidada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Entre com uma Conta UAI verificada e vinculada a este aluno para acessar os Estudos e Fundamentos.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _rastreioService.registrarClique(
      nome: 'abrir_estudos_fundamentos',
      origem: 'area_aluno_dashboard',
      metadata: {'aluno_nome': _nome, 'aluno_id': _alunoId},
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstudosHomeScreen(
          aluno: widget.aluno,
          authPayload: widget.authPayload,
        ),
      ),
    );

    if (mounted) {
      await _carregarConfigEstudosFundamentos();
    }
  }

  Future<void> _abrirDetalhesEventoAluno(AreaAlunoEventoResumo evento) async {
    _rastreioService.registrarClique(
      nome: 'abrir_evento_area_aluno',
      origem: 'area_aluno_dashboard',
      metadata: {
        'aluno_nome': _nome,
        'evento_id': evento.eventoId ?? '',
        'evento_nome': evento.nomeEvento,
        'participacao_id': evento.participacaoId,
      },
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AreaAlunoEventoDetalheScreen(evento: evento, config: widget.config),
      ),
    );
  }

  Future<void> _abrirSelecionarTemaPublico() async {
    final t = context.uai;
    final controller = AppThemeController.instance;

    final temaGlobal = TemaGlobalService.instance;
    final presets = temaGlobal.resolvedAllowedPresets(
      includeUserPersonalizado: false,
    );
    final lockChoice =
        temaGlobal.forcarTemaGlobal || !temaGlobal.permitirUsuarioEscolher;
    final globalLockedMessage = temaGlobal.forcarTemaGlobal
        ? 'O tema global está sendo aplicado para todos.'
        : 'A escolha de tema está bloqueada pela administração.';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.86,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 4),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: t.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              gradient: t.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.palette_rounded,
                              color: _readableOn(t.primary),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Escolher tema',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  lockChoice
                                      ? globalLockedMessage
                                      : 'Temas liberados pela administração.',
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                        itemCount: presets.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final preset = presets[index];
                          final selected =
                              controller.effectivePreset == preset &&
                              controller.activeSavedThemeId == null;

                          return _buildThemePresetTile(
                            preset: preset,
                            selected: selected,
                            onTap: () async {
                              if (lockChoice) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(globalLockedMessage)),
                                );
                                return;
                              }

                              await fecharDialogoAposSalvarTema(
                                context,
                                () => controller.apply(
                                  preset: preset,
                                  mode: preset.isDark
                                      ? ThemeMode.dark
                                      : ThemeMode.light,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemePresetTile({
    required UaiThemePreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(preset.previewColor, t.card);

    return Material(
      color: selected
          ? Color.alphaBlend(accent.withAlpha(28), t.cardAlt)
          : t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(
              color: selected ? accent.withAlpha(89) : t.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(preset.icon, color: _readableOn(accent), size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? accent : t.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerMenu({bool emTelaInterna = false}) {
    final t = context.uai;

    final itens = [
      _AreaAlunoMenuItem('Início', Icons.home_rounded, () {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LandingPage()),
          (route) => false,
        );
      }),
      _AreaAlunoMenuItem('Regimento Interno', Icons.description_rounded, () {
        _abrirTelaMenuAluno(
          titulo: 'Regimento Interno',
          tela: const RegimentoScreen(),
        );
      }),
      _AreaAlunoMenuItem('Biografia', Icons.auto_stories_rounded, () {
        _abrirTelaMenuAluno(titulo: 'Biografia', tela: const BiografiaScreen());
      }),
      _AreaAlunoMenuItem('Graduações', Icons.emoji_events_rounded, () {
        _abrirTelaMenuAluno(
          titulo: 'Graduações',
          tela: const GraduacoesScreen(),
        );
      }),
      _AreaAlunoMenuItem('Área do Aluno', Icons.school_rounded, () {
        Navigator.pop(context);
        if (emTelaInterna) Navigator.pop(context);
      }, selecionado: true),
      _AreaAlunoMenuItem('Portfólio', Icons.photo_library_rounded, () {
        _abrirTelaMenuAluno(
          titulo: 'Portfólio',
          tela: const PortfolioWebScreen(),
        );
      }),
    ];

    final onPrimary = _readableOn(t.primary);

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
            decoration: BoxDecoration(gradient: t.primaryGradient),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: onPrimary.withAlpha(38),
                  child: _foto.isEmpty
                      ? Icon(Icons.person_rounded, color: onPrimary)
                      : ClipOval(
                          child: UaiStudentPhoto(
                            studentId: _alunoId,
                            imageUrl: _foto,
                            profile: UaiStudentPhotoProfile.compact,
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                            fallback: Icon(
                              Icons.person_rounded,
                              color: onPrimary,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Área do Aluno',
                        style: TextStyle(
                          color: onPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onPrimary.withAlpha(199),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              itemCount: itens.length,
              separatorBuilder: (_, _) => const SizedBox(height: 3),
              itemBuilder: (context, index) {
                final item = itens[index];
                final color = item.selecionado ? t.primary : t.textPrimary;
                final visible = _ensureVisible(color, t.surface);

                return Material(
                  color: item.selecionado
                      ? Color.alphaBlend(visible.withAlpha(20), t.surface)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: item.selecionado
                                  ? visible
                                  : Color.alphaBlend(
                                      visible.withAlpha(20),
                                      t.card,
                                    ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              item.icon,
                              color: item.selecionado
                                  ? _readableOn(visible)
                                  : visible,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: item.selecionado
                                    ? visible
                                    : t.textPrimary,
                                fontWeight: item.selecionado
                                    ? FontWeight.w900
                                    : FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          if (item.selecionado)
                            Icon(
                              Icons.check_circle_rounded,
                              color: visible,
                              size: 18,
                            )
                          else
                            Icon(
                              Icons.chevron_right_rounded,
                              color: t.textMuted,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildGestaoDrawerButton(t),
          _buildTrocarAlunoDrawerButton(t),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: t.cardAlt,
              border: Border(top: BorderSide(color: t.border)),
            ),
            child: OutlinedButton.icon(
              onPressed: _sairAreaAluno,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('SAIR DA ÁREA DO ALUNO'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ensureVisible(t.error, t.cardAlt),
                side: BorderSide(color: t.error.withAlpha(64)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGestaoDrawerButton(dynamic t) {
    return FutureBuilder<bool>(
      future: FirebaseAuth.instance.currentUser == null
          ? Future.value(false)
          : UserService.hasAccess(FirebaseAuth.instance.currentUser!.uid),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          color: t.cardAlt,
          child: FilledButton.icon(
            onPressed: _irParaGestao,
            icon: const Icon(Icons.home_work_rounded),
            label: const Text('IR PARA GESTÃO'),
            style: FilledButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrocarAlunoDrawerButton(dynamic t) {
    return FutureBuilder<List<AlunoVinculadoGoogle>>(
      future: AreaAlunoGoogleService().buscarAlunosVinculados(),
      builder: (context, snapshot) {
        final alunos = snapshot.data ?? const <AlunoVinculadoGoogle>[];
        if (alunos.length < 2) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          color: t.cardAlt,
          child: OutlinedButton.icon(
            onPressed: () => _trocarAlunoVinculado(alunos),
            icon: const Icon(Icons.switch_account_rounded),
            label: const Text('TROCAR ALUNO'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ensureVisible(t.info, t.cardAlt),
              side: BorderSide(color: t.info.withAlpha(64)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = _readableOn(appBarBg);

    return Scaffold(
      backgroundColor: t.background,
      drawer: widget.adminPreview
          ? null
          : Drawer(
              backgroundColor: t.surface,
              width: MediaQuery.of(context).size.width.clamp(280.0, 330.0),
              child: _buildDrawerMenu(),
            ),
      appBar: AppBar(
        title: Text(
          widget.adminPreview ? 'Prévia • Minha Área' : 'Minha Área',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        elevation: 0,
        leading: widget.adminPreview
            ? IconButton(
                tooltip: 'Voltar ao Admin',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : Builder(
                builder: (context) => IconButton(
                  tooltip: 'Abrir menu',
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Escolher tema',
              child: Material(
                color: appBarFg.withAlpha(31),
                borderRadius: BorderRadius.circular(13),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _abrirSelecionarTemaPublico,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: appBarFg.withAlpha(36)),
                    ),
                    child: Icon(
                      Icons.palette_rounded,
                      color: appBarFg,
                      size: 21,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final isMobile = maxWidth < 650;
          final contentWidth = maxWidth > 980 ? 980.0 : maxWidth;

          return RefreshIndicator(
            color: t.primary,
            backgroundColor: t.surface,
            onRefresh: () async => _loadCordaSvg(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 24,
                    14,
                    isMobile ? 14 : 24,
                    30,
                  ),
                  children: [
                    if (widget.adminPreview) ...[
                      _buildAdminPreviewBanner(),
                      const SizedBox(height: 12),
                    ],
                    _buildHeader(isMobile),
                    const SizedBox(height: 14),
                    _buildResumoCards(isMobile),
                    if (!_sessaoIdentidadeCompletaValidada) ...[
                      const SizedBox(height: 16),
                      _buildGoogleAccessCard(),
                    ],
                    if (_areaConfig.mostrarEventos) ...[
                      const SizedBox(height: 16),
                      AreaAlunoMeusEventosSection(
                        aluno: widget.aluno,
                        authPayload: widget.authPayload,
                        config: widget.config,
                        onAbrirEvento: widget.adminPreview
                            ? (_) => _bloquearAcaoPreview()
                            : _abrirDetalhesEventoAluno,
                      ),
                    ],
                    if (_temAcoesDashboard) ...[
                      const SizedBox(height: 16),
                      _buildSectionTitle(
                        icon: Icons.dashboard_customize_rounded,
                        title: 'Painel do aluno',
                        subtitle: 'Escolha o que deseja consultar',
                      ),
                      const SizedBox(height: 10),
                      _buildAcoesResponsive(maxWidth),
                    ],
                    const SizedBox(height: 16),
                    _buildAvisoSomenteLeitura(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _bloquearAcaoPreview() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Prévia administrativa: ações do aluno estão desativadas.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildAdminPreviewBanner() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(26), t.card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withAlpha(71)),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_rounded, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'VISUALIZAÇÃO ADMINISTRATIVA • Você está vendo as permissões '
              'e o dashboard deste aluno. Nenhuma ação será executada em nome dele.',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: EdgeInsets.all(isMobile ? 15 : 18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: t.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildAvatar(isMobile),
          SizedBox(width: isMobile ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.config['mensagem_topo']?.toString() ??
                      'Bem-vindo(a) à Área do Aluno',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary.withAlpha(209),
                    fontSize: isMobile ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _nome,
                  maxLines: isMobile ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                if (_apelido.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _apelido,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onPrimary.withAlpha(199),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildStatusChip(_status),
                    if (widget.aluno['academia']?.toString().isNotEmpty == true)
                      _buildSmallWhiteChip(
                        widget.aluno['academia'].toString(),
                        Icons.home_work_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);
    final size = isMobile ? 74.0 : 86.0;

    if (_foto.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: onPrimary.withAlpha(41),
        child: Icon(Icons.person_rounded, color: onPrimary, size: size * 0.55),
      );
    }

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: onPrimary.withAlpha(51),
      child: ClipOval(
        child: UaiStudentPhoto(
          studentId: _alunoId,
          imageUrl: _foto,
          profile: UaiStudentPhotoProfile.list,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fallback: Icon(
            Icons.person_rounded,
            color: onPrimary,
            size: size * 0.55,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final ativo = status == 'ATIVO(A)' || status == 'ATIVO';
    final onPrimary = _readableOn(context.uai.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ativo
            ? Colors.green.withAlpha(51)
            : Colors.orange.withAlpha(51),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onPrimary.withAlpha(51)),
      ),
      child: Text(
        ativo
            ? 'ALUNO ATIVO'
            : (status.isEmpty ? 'STATUS NÃO INFORMADO' : status),
        style: TextStyle(
          color: onPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSmallWhiteChip(String text, IconData icon) {
    final onPrimary = _readableOn(context.uai.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(36),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onPrimary.withAlpha(31)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: onPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCards(bool isMobile) {
    final cards = <Widget>[
      if (_areaConfig.mostrarAcademiaTurma) _buildTurmaResumoCard(),
      if (_areaConfig.mostrarGraduacaoAtual) _buildGraduacaoResumoCard(),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();

    if (isMobile) {
      return Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            cards[i],
          ],
        ],
      );
    }

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _buildTurmaResumoCard() {
    final t = context.uai;
    final color = _ensureVisible(_turmaColor(), t.card);
    final turmaNome = _safeText(widget.aluno['turma'], 'Não informada');
    final horarios = _turmaHorarios();

    String subtitle = 'Toque para ver informações da turma';

    if (horarios.isNotEmpty) {
      final primeiro = horarios.first;
      subtitle =
          '${primeiro['dia_nome'] ?? primeiro['dia'] ?? ''} • ${primeiro['horario_inicio'] ?? ''} às ${primeiro['horario_fim'] ?? ''}';
    }

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _abrirInfoTurma,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(33)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              _buildTurmaIcon(color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Turma',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      turmaNome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurmaIcon(Color color) {
    final t = context.uai;
    final logo = _turmaInfo['logo_url']?.toString() ?? '';

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withAlpha(26), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
      ),
      child: logo.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                logo,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return Icon(Icons.school_rounded, color: color, size: 30);
                },
              ),
            )
          : Icon(Icons.school_rounded, color: color, size: 30),
    );
  }

  Widget _buildGraduacaoResumoCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withAlpha(33)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withAlpha(26), t.cardAlt),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: accent,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Graduação',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _graduacao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (_cordaSvg != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              height: 52,
              child: SvgPicture.string(_cordaSvg!, fit: BoxFit.contain),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.background);

    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: Color.alphaBlend(primary.withAlpha(23), t.cardAlt),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: primary, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: t.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAcoesResponsive(double width) {
    final t = context.uai;

    final cards = [
      if (_alunoId.isNotEmpty &&
          _sessaoIdentidadeCompletaValidada &&
          _areaConfig.mostrarPedidos)
        _DashboardCardData(
          icon: Icons.shopping_bag_rounded,
          title: 'Meus pedidos',
          subtitle: 'Pedidos, remessas e compras',
          color: t.success,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AreaAlunoMeusPedidosScreen(alunoId: _alunoId))),
        ),
      if (_areaConfig.mostrarDadosBasicos)
        _DashboardCardData(
          icon: Icons.person_search_rounded,
          title: 'Informações do aluno',
          subtitle: 'Ver seus dados cadastrais',
          color: t.info,
          onTap: _abrirInfoAluno,
        ),
      if (_areaConfig.mostrarSolicitacaoAlteracao)
        _DashboardCardData(
          icon: Icons.edit_note_rounded,
          title: 'Solicitar alterações',
          subtitle: 'Pedir correção dos dados',
          color: t.associacao,
          onTap: _abrirSolicitarAlteracoes,
        ),
      if (_areaConfig.mostrarFrequencia)
        _DashboardCardData(
          icon: Icons.fact_check_rounded,
          title: 'Frequência',
          subtitle: 'Acompanhar presenças',
          color: t.success,
          onTap: _abrirFrequencia,
        ),
      if (_areaConfig.mostrarCertificados)
        _DashboardCardData(
          icon: Icons.card_membership_rounded,
          title: 'Certificados',
          subtitle: 'Eventos e certificados',
          color: t.warning,
          onTap: _abrirCertificados,
        ),
      if (_mostrarGuiaInstrumentacao && _sessaoIdentidadeCompletaValidada)
        _DashboardCardData(
          icon: Icons.music_note_rounded,
          title: 'Guia de Instrumentação',
          subtitle: 'Aprenda, ouça e toque os instrumentos',
          color: t.warning,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RhythmStudentPreviewScreen(alunoId: _alunoId),
          )),
        ),
      if (!_carregandoConfigEstudos && _podeMostrarEstudosFundamentos)
        _DashboardCardData(
          icon: Icons.history_edu_rounded,
          title: 'Estudos e Fundamentos',
          subtitle: 'Formacao teorica da capoeira',
          color: t.info,
          onTap: _abrirEstudosFundamentos,
        ),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        int columns;

        // Regra ajustada para PWA/celular real:
        // antes, abaixo de 390px virava lista. Em muitos celulares reais,
        // a largura útil cai para 360/370px por causa do padding da tela.
        // Agora mantém 2 colunas no mobile e só cai para 1 em largura extrema.
        if (maxWidth < 300) {
          columns = 1;
        } else if (maxWidth < 760) {
          columns = 2;
        } else {
          columns = 4;
        }

        final spacing = maxWidth < 390 ? 9.0 : 10.0;
        final cardWidth = (maxWidth - (spacing * (columns - 1))) / columns;
        final compact = cardWidth < 180;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: cardWidth,
              child: _buildDashboardActionCard(card, compact: compact),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDashboardActionCard(
    _DashboardCardData card, {
    bool compact = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(card.color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _rastreioService.registrarClique(
            nome: 'card_${card.title.toLowerCase().replaceAll(' ', '_')}',
            origem: 'area_aluno_dashboard',
            metadata: {'titulo': card.title, 'subtitulo': card.subtitle},
          );
          if (widget.adminPreview) {
            _bloquearAcaoPreview();
            return;
          }
          card.onTap();
        },
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 124 : 132),
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withAlpha(33)),
            boxShadow: t.softShadow,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              accent.withAlpha(26),
                              t.cardAlt,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(card.icon, color: accent, size: 25),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: accent,
                          size: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      card.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.2,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      card.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.2,
                        height: 1.20,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          accent.withAlpha(26),
                          t.cardAlt,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(card.icon, color: accent, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            card.subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11.5,
                              height: 1.20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: accent, size: 22),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAvisoSomenteLeitura() {
    final t = context.uai;
    final accent = _ensureVisible(t.info, t.card);
    final texto = _areaConfig.mostrarSolicitacaoAlteracao
        ? 'Esta área é somente leitura. Para alterar informações, use o card '
              '“Solicitar alterações”. A coordenação analisará antes de atualizar o cadastro oficial.'
        : 'Esta área é somente leitura. A coordenação controla quais informações ficam disponíveis para consulta.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(20), t.card),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withAlpha(36)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleAccessCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);
    final googleVinculado = _areaConfig.googleVinculado;
    final emailConfirmado = _areaConfig.emailConfirmado;
    final googleEmail = _areaConfig.googleEmailMascarado;
    final contaEmail = _areaConfig.emailContaUaiMascarado;
    final jaTemVinculo = googleVinculado || emailConfirmado;

    final titulo = jaTemVinculo
        ? 'Confirme sua conta para liberar o acesso completo'
        : 'Proteja e complete seu acesso';

    final descricao = jaTemVinculo
        ? 'Este aluno já possui uma conta vinculada. Você entrou pelos dados tradicionais; confirme a conta já cadastrada para liberar pedidos e os recursos protegidos.'
        : 'Você já está na área correta do aluno. Agora escolha como deseja vincular esta área: Google ou e-mail com código de 6 dígitos.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(20), t.card),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withAlpha(46)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withAlpha(26), t.card),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.shield_outlined, color: accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      descricao,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12.3,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (googleVinculado && googleEmail.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildVinculoInfoBlock(
              icon: Icons.g_mobiledata_rounded,
              title: 'Google já vinculado',
              text: googleEmail,
              color: t.info,
            ),
          ],
          if (emailConfirmado && contaEmail.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildVinculoInfoBlock(
              icon: Icons.alternate_email_rounded,
              title: 'E-mail já vinculado',
              text: contaEmail,
              color: t.success,
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;

              final googleButton = FilledButton.icon(
                onPressed: _vinculandoGoogle || _vinculandoEmail
                    ? null
                    : (googleVinculado
                          ? _vincularContaGoogle
                          : _confirmarVinculoGoogle),
                icon: _vinculandoGoogle
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata_rounded),
                label: Text(
                  _vinculandoGoogle
                      ? 'Conectando...'
                      : (googleVinculado
                            ? 'ENTRAR COM GOOGLE VINCULADO'
                            : 'VINCULAR COM GOOGLE'),
                ),
              );

              final emailButton = OutlinedButton.icon(
                onPressed: _vinculandoGoogle || _vinculandoEmail
                    ? null
                    : _vincularContaEmail,
                icon: _vinculandoEmail
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mark_email_read_rounded),
                label: Text(
                  _vinculandoEmail
                      ? 'Confirmando...'
                      : (emailConfirmado
                            ? 'ENTRAR COM E-MAIL VINCULADO'
                            : 'VINCULAR E-MAIL COM CÓDIGO'),
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_areaConfig.googleLoginAtivo || googleVinculado)
                      googleButton,
                    if (_areaConfig.googleLoginAtivo || googleVinculado)
                      const SizedBox(height: 9),
                    emailButton,
                  ],
                );
              }

              return Row(
                children: [
                  if (_areaConfig.googleLoginAtivo || googleVinculado) ...[
                    Expanded(child: googleButton),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: emailButton),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'O acesso tradicional continua disponível. Pedidos e outros dados protegidos só aparecem depois que a conta vinculada é autenticada.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10.8,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _abrirInfoTurma() {
    _rastreioService.registrarClique(
      nome: 'abrir_informacoes_turma',
      origem: 'area_aluno_dashboard',
      metadata: {'turma': widget.aluno['turma']?.toString() ?? ''},
    );

    final turma = _turmaInfo;

    if (turma.isEmpty) {
      _mostrarAviso(
        titulo: 'Informações da turma',
        mensagem:
            'As informações completas da turma ainda não foram encontradas.',
        icon: Icons.school_rounded,
        color: context.uai.info,
      );
      return;
    }

    final color = _ensureVisible(_turmaColor(), context.uai.surface);
    final horarios = _turmaHorarios();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 760
            ? 720
            : MediaQuery.of(context).size.width,
      ),
      builder: (_) {
        final t = context.uai;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.86,
              minChildSize: 0.45,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: t.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTurmaModalHeader(turma, color),
                    const SizedBox(height: 14),
                    _buildTurmaSection(
                      title: 'Horários de treino',
                      icon: Icons.calendar_month_rounded,
                      color: t.success,
                      children: horarios.isEmpty
                          ? [
                              _buildEmptyText(
                                'Nenhum horário cadastrado para esta turma.',
                              ),
                            ]
                          : horarios.map(_buildHorarioTile).toList(),
                    ),
                    if (_safeText(turma['observacoes'], '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildTurmaSection(
                        title: 'Observações',
                        icon: Icons.notes_rounded,
                        color: t.associacao,
                        children: [
                          _buildLongText(turma['observacoes'].toString()),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTurmaModalHeader(Map<String, dynamic> turma, Color color) {
    final logo = turma['logo_url']?.toString() ?? '';
    final onColor = _readableOn(color);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withAlpha(199)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: onColor.withAlpha(46),
              borderRadius: BorderRadius.circular(20),
            ),
            child: logo.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      logo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) {
                        return Icon(
                          Icons.school_rounded,
                          color: onColor,
                          size: 36,
                        );
                      },
                    ),
                  )
                : Icon(Icons.school_rounded, color: onColor, size: 36),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _safeText(turma['nome'], 'Turma'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildWhiteMiniChip(_safeText(turma['nivel'], '')),
                    _buildWhiteMiniChip(_safeText(turma['faixa_etaria'], '')),
                    _buildWhiteMiniChip(_safeText(turma['status'], '')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteMiniChip(String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    final onPrimary = _readableOn(context.uai.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(41),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onPrimary.withAlpha(41)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: onPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTurmaSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildHorarioTile(dynamic horario) {
    final t = context.uai;

    if (horario is! Map) {
      return _buildLongText(horario.toString());
    }

    final h = Map<String, dynamic>.from(horario);
    final dia = h['dia_nome'] ?? h['dia'] ?? 'Dia';
    final inicio = h['horario_inicio'] ?? '';
    final fim = h['horario_fim'] ?? '';
    final tipo = h['tipo_aula'] ?? h['tipo'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: t.primary, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              [
                dia,
                if (inicio.toString().isNotEmpty || fim.toString().isNotEmpty)
                  '$inicio às $fim',
                if (tipo.toString().isNotEmpty) tipo,
              ].join(' • '),
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLongText(String text) {
    final t = context.uai;

    return Text(
      text,
      style: TextStyle(
        color: t.textPrimary,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildEmptyText(String text) {
    final t = context.uai;

    return Text(
      text,
      style: TextStyle(color: t.textSecondary, fontStyle: FontStyle.italic),
    );
  }

  List<Map<String, dynamic>> _turmaHorarios() {
    final raw = _turmaInfo['horarios'];

    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return [];
  }

  void _showAlunoInfoSheet() {
    final t = context.uai;
    final rows = <Widget>[
      _infoRow('Nome', _nome),
      if (_apelido.isNotEmpty) _infoRow('Apelido', _apelido),
      _infoRow('Status', _status),
      if (_areaConfig.mostrarGraduacaoAtual) _infoRow('Graduação', _graduacao),
      if (_areaConfig.mostrarAcademiaTurma) ...[
        _infoRow('Turma', _safeText(widget.aluno['turma'], 'Não informada')),
        _infoRow(
          'Academia',
          _safeText(widget.aluno['academia'], 'Não informada'),
        ),
      ],
      if (_safeText(widget.aluno['cidade'], '').isNotEmpty)
        _infoRow('Cidade', _safeText(widget.aluno['cidade'], 'Não informada')),
      if (_safeText(widget.aluno['endereco'], '').isNotEmpty)
        _infoRow(
          'Endereço',
          _safeText(widget.aluno['endereco'], 'Não informado'),
        ),
      if (_safeText(widget.aluno['contato_aluno'], '').isNotEmpty)
        _infoRow(
          'Contato',
          _safeText(widget.aluno['contato_aluno'], 'Não informado'),
        ),
      if (_safeText(widget.aluno['nome_responsavel'], '').isNotEmpty)
        _infoRow(
          'Responsável',
          _safeText(widget.aluno['nome_responsavel'], 'Não informado'),
        ),
      if (_safeText(widget.aluno['contato_responsavel'], '').isNotEmpty)
        _infoRow(
          'Contato resp.',
          _safeText(widget.aluno['contato_responsavel'], 'Não informado'),
        ),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 760
            ? 720
            : MediaQuery.of(context).size.width,
      ),
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSheetHeader(
                    icon: Icons.person_search_rounded,
                    title: 'Informações do aluno',
                    color: t.info,
                  ),
                  const SizedBox(height: 14),
                  ...rows,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withAlpha(26), t.card),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close_rounded, color: t.textSecondary),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAviso({
    required String titulo,
    required String mensagem,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titulo, style: TextStyle(color: t.textPrimary)),
              ),
            ],
          ),
          content: Text(
            mensagem,
            style: TextStyle(color: t.textSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'ENTENDI',
                style: TextStyle(color: accent, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AreaAlunoTutorialSheet extends StatefulWidget {
  final List<_TutorialAreaAlunoPage> pages;
  final UaiThemeTokens theme;
  final Color Function(Color background) readableOn;

  const _AreaAlunoTutorialSheet({
    required this.pages,
    required this.theme,
    required this.readableOn,
  });

  @override
  State<_AreaAlunoTutorialSheet> createState() =>
      _AreaAlunoTutorialSheetState();
}

class _AreaAlunoTutorialSheetState extends State<_AreaAlunoTutorialSheet> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _proximo() {
    if (_index >= widget.pages.length - 1) {
      Navigator.pop(context, false);
      return;
    }

    _controller.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final accent = t.primary;
    final isLast = _index == widget.pages.length - 1;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 6),
          border: Border.all(color: t.border),
          boxShadow: t.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: t.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Flexible(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final page = widget.pages[index];

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 12),
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              accent.withAlpha(31),
                              t.surface,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: accent.withAlpha(46)),
                          ),
                          child: Icon(page.icon, color: accent, size: 38),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 22,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          page.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 14,
                            height: 1.42,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.pages.length, (index) {
                      final selected = index == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: selected ? 22 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: selected ? accent : t.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Pular'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _proximo,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: widget.readableOn(accent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                        child: Text(isLast ? 'Começar' : 'Próximo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialAreaAlunoPage {
  final IconData icon;
  final String title;
  final String text;

  const _TutorialAreaAlunoPage({
    required this.icon,
    required this.title,
    required this.text,
  });
}

class _DashboardCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _AreaAlunoMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selecionado;

  const _AreaAlunoMenuItem(
    this.label,
    this.icon,
    this.onTap, {
    this.selecionado = false,
  });
}
