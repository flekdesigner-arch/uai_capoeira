import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/inscricoes/services/inscricoes_permission_service.dart';

import 'gerenciar_inscricoes_screen.dart';
import 'configuracoes_avancadas_inscricoes_screen.dart';
import 'auditoria_inscricoes_screen.dart';
import 'configurar_card_inscricao_screen.dart';

class ConfigurarInscricoesScreen extends StatefulWidget {
  const ConfigurarInscricoesScreen({super.key});

  @override
  State<ConfigurarInscricoesScreen> createState() =>
      _ConfigurarInscricoesScreenState();
}

class _ConfigurarInscricoesScreenState
    extends State<ConfigurarInscricoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final InscricoesPermissionService _inscricoesPermissionService =
      InscricoesPermissionService();
  bool _permissoesCarregadas = false;
  bool _podeVerAuditoria = false;

  bool _inscricoesAbertas = false;
  int _vagasDisponiveis = 0;
  int _totalInscricoes = 0;

  int _idadeMinima = 5;
  int _idadeMaxima = 16;

  bool _recolherAssinatura = true;
  bool _segurancaDetectarDuplicidade = true;
  bool _segurancaDetectarTelefoneSuspeito = true;
  bool _segurancaDetectarPreenchimentoRapido = true;
  bool _segurancaDetectarNomeSuspeito = true;

  bool _roboAulaAtivo = true;
  bool _roboEnviarEmail = true;
  Map<String, dynamic> _roboUltimoResultado = const {};
  Timestamp? _roboUltimaExecucaoEm;
  bool _executandoRobo = false;

  bool _roboLimpezaAtivo = false;
  bool _roboLimpezaSimulacao = false;
  bool _roboLimpezaSinalizar = true;
  bool _roboLimpezaSemMovimento = true;
  bool _roboLimpezaInteressado = true;
  bool _roboLimpezaAulaVencida = true;
  bool _roboLimpezaExpirada = true;
  bool _roboLimpezaProtegerAulaFutura = true;
  Map<String, dynamic> _roboLimpezaUltimoResultado = const {};
  Timestamp? _roboLimpezaUltimaExecucaoEm;
  bool _executandoRoboLimpeza = false;
  bool _integrarChamadaConversao = true;
  final TextEditingController _limpezaAlertarDiasController = TextEditingController(text: '7');
  final TextEditingController _limpezaSemMovimentoDiasController = TextEditingController(text: '30');
  final TextEditingController _limpezaInteressadoDiasController = TextEditingController(text: '21');
  final TextEditingController _limpezaAulaVencidaDiasController = TextEditingController(text: '7');
  final TextEditingController _limpezaLimiteController = TextEditingController(text: '100');

  final TextEditingController _idadeMinimaController = TextEditingController();
  final TextEditingController _idadeMaximaController = TextEditingController();
  final TextEditingController _vagasController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarPermissoes();
    _carregarConfiguracao();
  }

  Future<void> _carregarPermissoes() async {
    try {
      final permissoes = await _inscricoesPermissionService.carregar();
      if (!mounted) return;
      setState(() {
        _podeVerAuditoria = permissoes.verAuditoria;
        _permissoesCarregadas = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _podeVerAuditoria = false;
        _permissoesCarregadas = true;
      });
    }
  }

  @override
  void dispose() {
    _idadeMinimaController.dispose();
    _idadeMaximaController.dispose();
    _vagasController.dispose();
    _limpezaAlertarDiasController.dispose();
    _limpezaSemMovimentoDiasController.dispose();
    _limpezaInteressadoDiasController.dispose();
    _limpezaAulaVencidaDiasController.dispose();
    _limpezaLimiteController.dispose();
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
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0).toDouble())
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withAlpha(173);

  bool _temaPrimarioMuitoClaroEmFundoEscuro() {
    final t = context.uai;
    final primary = t.primary;
    final hsl = HSLColor.fromColor(primary);

    return primary.computeLuminance() > 0.50 &&
        t.background.computeLuminance() < 0.36 &&
        hsl.saturation > 0.55;
  }

  Color _safeHeroBase() {
    final t = context.uai;
    if (_temaPrimarioMuitoClaroEmFundoEscuro()) {
      return Color.alphaBlend(t.primary.withAlpha(148), t.surface);
    }
    return t.primary;
  }

  LinearGradient _safeHeroGradient() {
    final base = _safeHeroBase();
    final hsl = HSLColor.fromColor(base);
    final bgIsDark = base.computeLuminance() < 0.45;
    final endLightness = bgIsDark
        ? (hsl.lightness + 0.08).clamp(0.0, 1.0).toDouble()
        : (hsl.lightness - 0.08).clamp(0.0, 1.0).toDouble();
    final end = hsl
        .withLightness(endLightness)
        .withSaturation((hsl.saturation + 0.04).clamp(0.0, 1.0).toDouble())
        .toColor();

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [base, end],
    );
  }

  Color _onHero() {
    if (_temaPrimarioMuitoClaroEmFundoEscuro()) {
      return const Color(0xFFFFFFFF);
    }
    return _readableOn(_safeHeroBase());
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  bool get _isWideDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900;
  }

  bool get _isDesktopDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 1180;
  }

  double get _dashboardMaxWidth {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) return 1240;
    if (width >= 1180) return 1120;
    if (width >= 900) return 1040;
    return width;
  }

  EdgeInsets get _dashboardPagePadding {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1180) return const EdgeInsets.fromLTRB(22, 18, 22, 28);
    if (width >= 900) return const EdgeInsets.fromLTRB(18, 16, 18, 24);
    if (width <= 390) return const EdgeInsets.fromLTRB(14, 12, 14, 18);
    return const EdgeInsets.fromLTRB(16, 14, 16, 22);
  }

  Widget _dashboardWidthLimiter(Widget child) {
    if (!_isWideDashboard) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _dashboardMaxWidth),
        child: child,
      ),
    );
  }

  Widget _responsiveWrap({
    required List<Widget> children,
    double minItemWidth = 360,
    int maxColumns = 4,
    double spacing = 12,
    double runSpacing = 12,
    bool centerLastRow = true,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(children.length, (index) {
              final isLast = index == children.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : runSpacing),
                child: SizedBox(width: double.infinity, child: children[index]),
              );
            }),
          );
        }

        final columns = (width / minItemWidth)
            .floor()
            .clamp(1, maxColumns)
            .toInt();
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          alignment: centerLastRow ? WrapAlignment.center : WrapAlignment.start,
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }

  Future<void> _carregarConfiguracao() async {
    try {
      final doc = await _firestore
          .collection('configuracoes')
          .doc('inscricoes')
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        _inscricoesAbertas = data['inscricoes_abertas'] ?? false;
        _vagasDisponiveis = data['vagas_disponiveis'] ?? 0;
        _totalInscricoes = data['total_inscricoes'] ?? 0;
        _idadeMinima = data['idade_minima'] ?? 5;
        _idadeMaxima = data['idade_maxima'] ?? 16;
        _recolherAssinatura = data['recolher_assinatura'] ?? true;
        _segurancaDetectarDuplicidade =
            data['seguranca_detectar_duplicidade'] ?? true;
        _segurancaDetectarTelefoneSuspeito =
            data['seguranca_detectar_telefone_suspeito'] ?? true;
        _segurancaDetectarPreenchimentoRapido =
            data['seguranca_detectar_preenchimento_rapido'] ?? true;
        _segurancaDetectarNomeSuspeito =
            data['seguranca_detectar_nome_suspeito'] ?? true;
        final robo = Map<String, dynamic>.from(
          data['robo_aula_experimental'] as Map? ?? const {},
        );
        _roboAulaAtivo = robo['ativo'] != false;
        _roboEnviarEmail = robo['enviar_email'] != false;
        _roboUltimoResultado = Map<String, dynamic>.from(
          robo['ultima_execucao_resultado'] as Map? ?? const {},
        );
        _roboUltimaExecucaoEm = robo['ultima_execucao_em'] as Timestamp?;

        final limpeza = Map<String, dynamic>.from(
          data['robo_limpeza_inscricoes'] as Map? ?? const {},
        );
        _roboLimpezaAtivo = limpeza['ativo'] == true;
        _roboLimpezaSimulacao = limpeza['modo_simulacao'] == true;
        _roboLimpezaSinalizar = limpeza['sinalizar_sem_movimento'] != false;
        _roboLimpezaSemMovimento = limpeza['arquivar_sem_movimento'] != false;
        _roboLimpezaInteressado = limpeza['arquivar_interessado'] != false;
        _roboLimpezaAulaVencida = limpeza['arquivar_aula_vencida'] != false;
        _roboLimpezaExpirada = limpeza['arquivar_expirada'] != false;
        _roboLimpezaProtegerAulaFutura = limpeza['proteger_aula_futura'] != false;
        _limpezaAlertarDiasController.text = '${limpeza['alertar_dias'] ?? 7}';
        _limpezaSemMovimentoDiasController.text = '${limpeza['dias_sem_movimento'] ?? 30}';
        _limpezaInteressadoDiasController.text = '${limpeza['dias_interessado'] ?? 21}';
        _limpezaAulaVencidaDiasController.text = '${limpeza['dias_apos_aula'] ?? 7}';
        _limpezaLimiteController.text = '${limpeza['limite_por_execucao'] ?? 100}';
        _roboLimpezaUltimoResultado = Map<String, dynamic>.from(
          limpeza['ultima_execucao_resultado'] as Map? ?? const {},
        );
        _roboLimpezaUltimaExecucaoEm = limpeza['ultima_execucao_em'] as Timestamp?;

        final integracao = Map<String, dynamic>.from(
          data['integracao_chamada_conversao'] as Map? ?? const {},
        );
        _integrarChamadaConversao = integracao['ativo'] != false;
      }

      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      _totalInscricoes = inscricoesSnapshot.docs.length;
      _idadeMinimaController.text = _idadeMinima.toString();
      _idadeMaximaController.text = _idadeMaxima.toString();
      _vagasController.text = _vagasDisponiveis.toString();

      if (mounted) {
        setState(() => _carregando = false);
      }
    } catch (e) {
      if (mounted) {
        _mostrarErro('Erro ao carregar: $e');
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _salvarConfiguracao() async {
    if (_salvando) return;
    setState(() => _salvando = true);

    try {
      final idadeMin = int.tryParse(_idadeMinimaController.text) ?? 0;
      final idadeMax = int.tryParse(_idadeMaximaController.text) ?? 0;
      final vagas = int.tryParse(_vagasController.text) ?? 0;

      if (idadeMin < 1) {
        _mostrarErro('Idade mínima deve ser maior que 0');
        setState(() => _salvando = false);
        return;
      }

      if (idadeMax < idadeMin) {
        _mostrarErro('Idade máxima não pode ser menor que a idade mínima');
        setState(() => _salvando = false);
        return;
      }

      if (idadeMax > 120) {
        _mostrarErro('Idade máxima inválida');
        setState(() => _salvando = false);
        return;
      }

      if (vagas < 0) {
        _mostrarErro('O número de vagas não pode ser negativo');
        setState(() => _salvando = false);
        return;
      }

      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'inscricoes_abertas': _inscricoesAbertas,
        'vagas_disponiveis': vagas,
        'total_inscricoes': _totalInscricoes,
        'idade_minima': idadeMin,
        'idade_maxima': idadeMax,
        'recolher_assinatura': _recolherAssinatura,
        'seguranca_detectar_duplicidade': _segurancaDetectarDuplicidade,
        'seguranca_detectar_telefone_suspeito':
            _segurancaDetectarTelefoneSuspeito,
        'seguranca_detectar_preenchimento_rapido':
            _segurancaDetectarPreenchimentoRapido,
        'seguranca_detectar_nome_suspeito': _segurancaDetectarNomeSuspeito,
        'seguranca_modo': 'alertar_sem_bloquear',
        'robo_aula_experimental': {
          'ativo': _roboAulaAtivo,
          'enviar_email': _roboEnviarEmail,
          'horario': '12:00',
          'fuso': 'America/Sao_Paulo',
          'somente_email_confirmado': true,
          'somente_aula_do_dia': true,
          if (_roboUltimoResultado.isNotEmpty)
            'ultima_execucao_resultado': _roboUltimoResultado,
          if (_roboUltimaExecucaoEm != null)
            'ultima_execucao_em': _roboUltimaExecucaoEm,
        },
        'robo_limpeza_inscricoes': {
          'ativo': _roboLimpezaAtivo,
          'horario': '11:00',
          'fuso': 'America/Sao_Paulo',
          'modo_simulacao': _roboLimpezaSimulacao,
          'sinalizar_sem_movimento': _roboLimpezaSinalizar,
          'alertar_dias': int.tryParse(_limpezaAlertarDiasController.text.trim()) ?? 7,
          'arquivar_sem_movimento': _roboLimpezaSemMovimento,
          'dias_sem_movimento': int.tryParse(_limpezaSemMovimentoDiasController.text.trim()) ?? 30,
          'arquivar_interessado': _roboLimpezaInteressado,
          'dias_interessado': int.tryParse(_limpezaInteressadoDiasController.text.trim()) ?? 21,
          'arquivar_aula_vencida': _roboLimpezaAulaVencida,
          'dias_apos_aula': int.tryParse(_limpezaAulaVencidaDiasController.text.trim()) ?? 7,
          'arquivar_expirada': _roboLimpezaExpirada,
          'proteger_aula_futura': _roboLimpezaProtegerAulaFutura,
          'limite_por_execucao': int.tryParse(_limpezaLimiteController.text.trim()) ?? 100,
          if (_roboLimpezaUltimoResultado.isNotEmpty)
            'ultima_execucao_resultado': _roboLimpezaUltimoResultado,
          if (_roboLimpezaUltimaExecucaoEm != null)
            'ultima_execucao_em': _roboLimpezaUltimaExecucaoEm,
        },
        'integracao_chamada_conversao': {
          'ativo': _integrarChamadaConversao,
          'modo_presenca': 'resultado_aula',
          'somente_mesmo_dia': true,
          'somente_mesma_turma': true,
        },
        'config_alterada_por_uid': FirebaseAuth.instance.currentUser?.uid,
        'config_alterada_por_email': FirebaseAuth.instance.currentUser?.email,
        'config_alterada_em': FieldValue.serverTimestamp(),
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _idadeMinima = idadeMin;
        _idadeMaxima = idadeMax;
        _vagasDisponiveis = vagas;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Configurações salvas!'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int get _vagasRestantes {
    final restantes = _vagasDisponiveis - _totalInscricoes;
    return restantes < 0 ? 0 : restantes;
  }

  double get _percentualVagas {
    if (_vagasDisponiveis <= 0) return 0;
    return (_totalInscricoes / _vagasDisponiveis).clamp(0, 1).toDouble();
  }

  Future<void> _executarRoboAgora() async {
    if (_executandoRobo) return;
    setState(() => _executandoRobo = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('executarRoboAulaExperimentalAgora');
      final response = await callable.call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(response.data);
      if (!mounted) return;
      setState(() => _roboUltimoResultado = data);
      final enviadas = data['enviadas'] ?? 0;
      final falhas = data['falhas'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Robô concluído: $enviadas e-mail(s) enviado(s), $falhas falha(s).'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _mostrarErro(e.message ?? 'Não foi possível executar o robô agora.');
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Não foi possível executar o robô agora: $e');
    } finally {
      if (mounted) setState(() => _executandoRobo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregando) {
      return Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          title: const Text(
            'Configurar Inscrições',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: _buildLoadingState(),
      );
    }

    final showBottomSaveBar = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Configurar Inscrições',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (_permissoesCarregadas && _podeVerAuditoria)
            IconButton(
              tooltip: 'Auditoria',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuditoriaInscricoesScreen()),
              ),
              icon: const Icon(Icons.fact_check_rounded),
            ),
          IconButton(
            tooltip: 'Salvar',
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: _appBarFg(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.cardAlt, t.background],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useTwoColumns = constraints.maxWidth >= 940;
            final pad = _dashboardPagePadding;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                pad.left,
                pad.top,
                pad.right,
                showBottomSaveBar ? 104 : pad.bottom,
              ),
              children: [
                Center(
                  child: _dashboardWidthLimiter(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(),
                        const SizedBox(height: 12),
                        _buildStatusCards(),
                        const SizedBox(height: 14),
                        if (useTwoColumns)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 11,
                                child: _buildMainSettingsColumn(),
                              ),
                              const SizedBox(width: 14),
                              Expanded(flex: 9, child: _buildResumoColumn()),
                            ],
                          )
                        else ...[
                          _buildMainSettingsColumn(),
                          const SizedBox(height: 14),
                          _buildResumoColumn(),
                        ],
                        if (!showBottomSaveBar) ...[
                          const SizedBox(height: 14),
                          _buildInlineSaveCard(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: showBottomSaveBar ? _buildBottomSaveBar() : null,
    );
  }

  Widget _buildInlineSaveCard() {
    final t = context.uai;
    final bg = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _salvando
                  ? 'Salvando alterações...'
                  : 'Revise os campos e salve as configurações.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: ElevatedButton.icon(
              onPressed: _salvando ? null : _salvarConfiguracao,
              icon: _salvando
                  ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: _readableOn(bg),
                  strokeWidth: 2,
                ),
              )
                  : const Icon(Icons.save_rounded),
              label: Text(_salvando ? 'SALVANDO...' : 'SALVAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: _readableOn(bg),
                padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildBottomSaveBar() {
    final t = context.uai;
    final bg = _ensureVisible(t.primary, t.surface);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(t.surface.withAlpha(240), t.background),
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: t.softShadow,
        ),
        child: _dashboardWidthLimiter(
          ElevatedButton.icon(
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: _readableOn(bg),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR CONFIGURAÇÕES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: _readableOn(bg),
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _executarRoboLimpezaAgora({required bool simular}) async {
    if (_executandoRoboLimpeza) return;
    setState(() => _executandoRoboLimpeza = true);
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('executarRoboLimpezaInscricoesAgora');
      final response = await callable.call({'simular': simular});
      final data = Map<String, dynamic>.from(response.data as Map? ?? const {});
      if (!mounted) return;
      setState(() => _roboLimpezaUltimoResultado = data);
      final quantidade = simular
          ? (data['seriam_arquivadas'] ?? 0)
          : (data['arquivadas'] ?? 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(simular
              ? 'Simulação concluída: $quantidade inscrição(ões) seriam arquivadas.'
              : 'Limpeza concluída: $quantidade inscrição(ões) arquivadas.'),
          backgroundColor: simular ? context.uai.info : context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) _mostrarErro('Erro ao executar robô de limpeza: $e');
    } finally {
      if (mounted) setState(() => _executandoRoboLimpeza = false);
    }
  }

  Widget _buildHeroCard() {
    final t = context.uai;
    final onHero = _onHero();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_isDesktopDashboard ? 20 : 16),
      decoration: BoxDecoration(
        gradient: _safeHeroGradient(),
        borderRadius: BorderRadius.circular(t.cardRadius + 6),
        border: Border.all(color: onHero.withAlpha(33)),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: narrow ? 58 : 64,
            height: narrow ? 58 : 64,
            decoration: BoxDecoration(
              color: onHero.withAlpha(36),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onHero.withAlpha(41)),
            ),
            child: Icon(
              Icons.app_registration_rounded,
              color: onHero,
              size: narrow ? 31 : 35,
            ),
          );

          final statusChip = _buildHeroStatusChip(narrow: narrow);

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Inscrições da Aula Experimental',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onHero,
                  fontSize: narrow ? 21 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Controle vagas, idade permitida, assinatura digital e status público do formulário.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onHero.withAlpha(209),
                  fontSize: narrow ? 12.2 : 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (narrow) ...[
                const SizedBox(height: 12),
                statusChip,
              ],
            ],
          );

          if (narrow) {
            return Column(
              children: [icon, const SizedBox(height: 13), text],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
              const SizedBox(width: 12),
              statusChip,
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroStatusChip({required bool narrow}) {
    final t = context.uai;
    final onHero = _onHero();
    final statusColor = _inscricoesAbertas ? t.success : t.error;
    final visibleStatus = _ensureVisible(statusColor, _safeHeroBase());

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 12 : 14,
        vertical: narrow ? 8 : 9,
      ),
      decoration: BoxDecoration(
        color: onHero.withAlpha(36),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onHero.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _inscricoesAbertas
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: visibleStatus,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(
            _inscricoesAbertas ? 'Formulário aberto' : 'Formulário fechado',
            style: TextStyle(
              color: onHero,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards() {
    final t = context.uai;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 760 ? 4 : 2;
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing * (cols - 1)) / cols;

        final cards = [
          _miniStat(
            title: 'Status',
            value: _inscricoesAbertas ? 'Aberta' : 'Fechada',
            icon: _inscricoesAbertas
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: _inscricoesAbertas ? t.success : t.error,
          ),
          _miniStat(
            title: 'Vagas',
            value: '$_vagasDisponiveis',
            icon: Icons.event_seat_rounded,
            color: t.info,
          ),
          _miniStat(
            title: 'Pendentes',
            value: '$_totalInscricoes',
            icon: Icons.pending_actions_rounded,
            color: t.warning,
          ),
          _miniStat(
            title: 'Restam',
            value: '$_vagasRestantes',
            icon: Icons.how_to_reg_rounded,
            color: t.associacao,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(),
        );
      },
    );
  }

  Widget _miniStat({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    final compact = MediaQuery.sizeOf(context).width < 430;

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 82 : 96),
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: _cardDecoration(color: accent),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withAlpha(31), t.cardAlt),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: accent.withAlpha(36)),
            ),
            child: Icon(icon, color: accent, size: compact ? 19 : 21),
          ),
          SizedBox(height: compact ? 6 : 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainSettingsColumn() {
    final t = context.uai;

    return Column(
      children: [
        _buildSwitchCard(
          icon: Icons.public_rounded,
          title: 'Status das inscrições',
          subtitle: _inscricoesAbertas
              ? 'O formulário público está aceitando inscrições.'
              : 'O formulário público está fechado.',
          color: _inscricoesAbertas ? t.success : t.error,
          value: _inscricoesAbertas,
          onChanged: (value) => setState(() => _inscricoesAbertas = value),
        ),
        const SizedBox(height: 12),
        _buildSwitchCard(
          icon: Icons.draw_rounded,
          title: 'Assinatura digital',
          subtitle: _recolherAssinatura
              ? 'O responsável precisará assinar o termo digitalmente.'
              : 'A inscrição será concluída sem assinatura digital.',
          color: t.associacao,
          value: _recolherAssinatura,
          onChanged: (value) => setState(() => _recolherAssinatura = value),
        ),
        const SizedBox(height: 12),
        _buildAgeCard(),
        const SizedBox(height: 12),
        _buildVagasCard(),
        const SizedBox(height: 12),
        _buildSecurityCard(),
        const SizedBox(height: 12),
        _buildCardLegoCard(),
        const SizedBox(height: 12),
        _buildIntegracaoChamadaCard(),
        const SizedBox(height: 12),
        _buildRoboAulaCard(),
        const SizedBox(height: 12),
        _buildRoboLimpezaCard(),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.tune_rounded, color: t.primary),
                const SizedBox(width: 8),
                Text('Jornada do Pré-Aluno', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
              ]),
              const SizedBox(height: 8),
              Text(
                'Configure campos do formulário, mensagens, expiração por inatividade e comunicação da nova Minha UAI.',
                style: TextStyle(color: t.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfiguracoesAvancadasInscricoesScreen()),
                ),
                icon: const Icon(Icons.settings_suggest_rounded),
                label: const Text('ABRIR CONFIGURAÇÕES AVANÇADAS'),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildCardLegoCard() {
    final t = context.uai;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.dashboard_customize_rounded, color: t.info),
          const SizedBox(width: 9),
          Expanded(child: Text('Card LEGO das inscrições', style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 7),
        Text('Monte o card do seu jeito: ordem dos blocos, itens visíveis, texto e cor de cada etapa.', style: TextStyle(color: t.textSecondary, height: 1.35)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfigurarCardInscricaoScreen())),
          icon: const Icon(Icons.view_quilt_rounded),
          label: const Text('MONTAR CARD'),
        ),
      ]),
    );
  }

  Widget _buildIntegracaoChamadaCard() {
    final t = context.uai;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.success.withAlpha(56)),
        boxShadow: t.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.how_to_reg_rounded, color: t.success),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Conversão → chamada do dia', style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
            Text('Evita o novo aluno ficar fora da chamada que já foi feita.', style: TextStyle(color: t.textSecondary, fontSize: 11.5)),
          ])),
          Switch.adaptive(value: _integrarChamadaConversao, onChanged: (v) => setState(() => _integrarChamadaConversao = v)),
        ]),
        const SizedBox(height: 10),
        Text(
          'Ao converter uma inscrição, o sistema procura uma chamada da mesma turma no mesmo dia. Se existir, inclui apenas esse aluno de forma idempotente. Se o resultado da aula experimental estiver como “compareceu”, ele entra presente; caso contrário entra ausente para não inventar presença.',
          style: TextStyle(color: t.textSecondary, height: 1.4),
        ),
      ]),
    );
  }

  Widget _buildRoboAulaCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.associacao, t.card);
    final enviadas = _roboUltimoResultado['enviadas'];
    final falhas = _roboUltimoResultado['falhas'];
    final encontradas = _roboUltimoResultado['encontradas'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withAlpha(51)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: accent.withAlpha(31), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.smart_toy_rounded, color: accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Robô da Aula Experimental', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text('Todos os dias às 12:00 • horário de Brasília', style: TextStyle(color: t.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ]),
              ),
              Switch.adaptive(
                value: _roboAulaAtivo,
                onChanged: (v) => setState(() => _roboAulaAtivo = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: t.cardAlt, borderRadius: BorderRadius.circular(15), border: Border.all(color: t.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.mark_email_read_rounded, color: accent, size: 19),
                const SizedBox(width: 8),
                Expanded(child: Text('Enviar automaticamente o e-mail da aula agendada', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800))),
                Switch.adaptive(value: _roboEnviarEmail, onChanged: _roboAulaAtivo ? (v) => setState(() => _roboEnviarEmail = v) : null),
              ]),
              Text('Somente inscrições pendentes, com aula marcada para o dia e e-mail confirmado. O mesmo aluno não recebe duas vezes pelo robô na mesma data.', style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.4)),
            ]),
          ),
          if (_roboUltimoResultado.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _roboMiniInfo('Encontradas', '${encontradas ?? 0}', Icons.search_rounded, t.info),
              _roboMiniInfo('Enviadas', '${enviadas ?? 0}', Icons.mark_email_read_rounded, t.success),
              _roboMiniInfo('Falhas', '${falhas ?? 0}', Icons.error_outline_rounded, t.error),
            ]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (_permissoesCarregadas && _podeVerAuditoria) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditoriaInscricoesScreen())),
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('AUDITORIA'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: _roboAulaAtivo && !_executandoRobo ? _executarRoboAgora : null,
                icon: _executandoRobo
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_executandoRobo ? 'EXECUTANDO...' : 'EXECUTAR AGORA'),
              ),
            ),
          ]),
        ],
      ),
    );
  }


  Widget _buildRoboLimpezaCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);
    final r = _roboLimpezaUltimoResultado;
    final arquivadas = r['arquivadas'] ?? r['seriam_arquivadas'] ?? 0;
    final protegidas = r['protegidas'] ?? 0;
    final sinalizadas = r['sinalizadas'] ?? 0;

    Widget numero(String label, TextEditingController controller, {int max = 365}) {
      return SizedBox(
        width: 145,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
          ),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null && n > max) controller.text = '$max';
          },
        ),
      );
    }

    Widget regra({required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool>? onChanged, Widget? trailing}) {
      return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: t.cardAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: t.border)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 11.2, height: 1.3)),
          ])),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          Switch.adaptive(value: value, onChanged: onChanged),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withAlpha(64)),
        boxShadow: t.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: accent.withAlpha(31), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.auto_delete_rounded, color: accent),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Robô de Limpeza das Inscrições', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 3),
            Text('Todos os dias às 11:00 • horário de Brasília', style: TextStyle(color: t.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ])),
          Switch.adaptive(value: _roboLimpezaAtivo, onChanged: (v) => setState(() => _roboLimpezaAtivo = v)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: accent.withAlpha(18), borderRadius: BorderRadius.circular(14), border: Border.all(color: accent.withAlpha(46))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.shield_outlined, color: accent, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Ele só analisa inscrições PENDENTES. Aula futura fica protegida. Antes de ativar pela primeira vez, use SIMULAR para conferir exatamente o que seria arquivado.',
              style: TextStyle(color: t.textPrimary, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w700),
            )),
          ]),
        ),
        const SizedBox(height: 10),
        regra(
          icon: Icons.visibility_rounded,
          title: 'Modo simulação no horário automático',
          subtitle: 'Às 11h o robô apenas calcula e registra a auditoria, sem mover inscrições.',
          value: _roboLimpezaSimulacao,
          onChanged: _roboLimpezaAtivo ? (v) => setState(() => _roboLimpezaSimulacao = v) : null,
        ),
        const SizedBox(height: 8),
        regra(
          icon: Icons.notification_important_outlined,
          title: 'Sinalizar inscrições paradas',
          subtitle: 'Antes de arquivar, marca o card como sem movimento.',
          value: _roboLimpezaSinalizar,
          onChanged: (v) => setState(() => _roboLimpezaSinalizar = v),
          trailing: numero('Alertar após', _limpezaAlertarDiasController),
        ),
        const SizedBox(height: 8),
        regra(
          icon: Icons.hourglass_bottom_rounded,
          title: 'Arquivar por inatividade geral',
          subtitle: 'Inscrições esquecidas sem qualquer andamento por muitos dias.',
          value: _roboLimpezaSemMovimento,
          onChanged: (v) => setState(() => _roboLimpezaSemMovimento = v),
          trailing: numero('Dias parados', _limpezaSemMovimentoDiasController),
        ),
        const SizedBox(height: 8),
        regra(
          icon: Icons.person_search_rounded,
          title: 'Arquivar interessados sem retorno',
          subtitle: 'Etapas “nova” ou “interessado” que não evoluíram.',
          value: _roboLimpezaInteressado,
          onChanged: (v) => setState(() => _roboLimpezaInteressado = v),
          trailing: numero('Dias', _limpezaInteressadoDiasController),
        ),
        const SizedBox(height: 8),
        regra(
          icon: Icons.event_busy_rounded,
          title: 'Arquivar aula experimental vencida',
          subtitle: 'Aula já passou e a inscrição continuou como “aula agendada”.',
          value: _roboLimpezaAulaVencida,
          onChanged: (v) => setState(() => _roboLimpezaAulaVencida = v),
          trailing: numero('Após a aula', _limpezaAulaVencidaDiasController),
        ),
        const SizedBox(height: 8),
        regra(
          icon: Icons.inventory_2_outlined,
          title: 'Arquivar inscrições já expiradas',
          subtitle: 'Resolve automaticamente registros que já foram marcados como expirados.',
          value: _roboLimpezaExpirada,
          onChanged: (v) => setState(() => _roboLimpezaExpirada = v),
        ),
        const SizedBox(height: 8),
        regra(
          icon: Icons.event_available_rounded,
          title: 'Proteger qualquer aula futura',
          subtitle: 'Nunca arquiva uma inscrição que ainda possui aula experimental futura marcada.',
          value: _roboLimpezaProtegerAulaFutura,
          onChanged: (v) => setState(() => _roboLimpezaProtegerAulaFutura = v),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          numero('Máx. por execução', _limpezaLimiteController, max: 500),
          if (r.isNotEmpty) ...[
            _roboMiniInfo('Arquivadas', '$arquivadas', Icons.inventory_2_rounded, t.warning),
            _roboMiniInfo('Sinalizadas', '$sinalizadas', Icons.flag_rounded, t.info),
            _roboMiniInfo('Protegidas', '$protegidas', Icons.shield_rounded, t.success),
          ],
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: _executandoRoboLimpeza ? null : () => _executarRoboLimpezaAgora(simular: true),
            icon: const Icon(Icons.science_outlined),
            label: const Text('SIMULAR AGORA'),
          ),
          FilledButton.icon(
            onPressed: _executandoRoboLimpeza ? null : () => _executarRoboLimpezaAgora(simular: false),
            icon: _executandoRoboLimpeza
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cleaning_services_rounded),
            label: Text(_executandoRoboLimpeza ? 'EXECUTANDO...' : 'EXECUTAR LIMPEZA'),
          ),
          if (_permissoesCarregadas && _podeVerAuditoria)
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditoriaInscricoesScreen())),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('VER AUDITORIA'),
            ),
        ]),
      ]),
    );
  }

  Widget _roboMiniInfo(String label, String value, IconData icon, Color color) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 5),
        Text('$label: $value', style: TextStyle(color: t.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _buildResumoColumn() {
    final t = context.uai;
    final info = _ensureVisible(t.info, t.card);

    return Column(
      children: [
        _buildResumoCard(),
        const SizedBox(height: 12),
        _buildInfoCard(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GerenciarInscricoesScreen(),
                ),
              );
            },
            icon: const Icon(Icons.list_alt_rounded),
            label: const Text('VER INSCRIÇÕES PENDENTES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: info,
              foregroundColor: _readableOn(info),
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final veryNarrow = constraints.maxWidth < 360;

          final iconBox = Container(
            width: veryNarrow ? 44 : 48,
            height: veryNarrow ? 44 : 48,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withAlpha(31), t.cardAlt),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: accent.withAlpha(41)),
            ),
            child: Icon(icon, color: accent, size: veryNarrow ? 23 : 26),
          );

          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: veryNarrow ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 12),
              Expanded(child: text),
              const SizedBox(width: 8),
              Switch(
                value: value,
                activeThumbColor: accent,
                onChanged: onChanged,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSecurityCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.error, t.card);

    Widget option({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onChanged(!value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(accent.withAlpha(11), t.cardAlt),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border.withAlpha(184)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: value ? accent : t.textMuted, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: value,
                    activeThumbColor: accent,
                    onChanged: onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: Icons.shield_outlined,
            title: 'Segurança e qualidade',
            color: accent,
          ),
          const SizedBox(height: 8),
          _noticeBox(
            icon: Icons.info_outline_rounded,
            color: accent,
            text:
                'As verificações apenas criam alertas para a equipe. Nenhuma inscrição será bloqueada automaticamente.',
          ),
          option(
            icon: Icons.content_copy_rounded,
            title: 'Detectar possíveis duplicidades',
            subtitle:
                'CPF e nome + nascimento. Responsáveis compartilhados entre alunos não são tratados como duplicidade.',
            value: _segurancaDetectarDuplicidade,
            onChanged: (v) =>
                setState(() => _segurancaDetectarDuplicidade = v),
          ),
          option(
            icon: Icons.phone_in_talk_rounded,
            title: 'Detectar telefone suspeito',
            subtitle: 'Sinaliza sequências improváveis ou números fora do padrão.',
            value: _segurancaDetectarTelefoneSuspeito,
            onChanged: (v) =>
                setState(() => _segurancaDetectarTelefoneSuspeito = v),
          ),
          option(
            icon: Icons.speed_rounded,
            title: 'Detectar preenchimento muito rápido',
            subtitle:
                'Ajuda a identificar testes automatizados sem impedir o envio.',
            value: _segurancaDetectarPreenchimentoRapido,
            onChanged: (v) =>
                setState(() => _segurancaDetectarPreenchimentoRapido = v),
          ),
          option(
            icon: Icons.person_search_rounded,
            title: 'Detectar nome suspeito',
            subtitle:
                'Sinaliza padrões como TESTE, ASDF e repetições exageradas.',
            value: _segurancaDetectarNomeSuspeito,
            onChanged: (v) =>
                setState(() => _segurancaDetectarNomeSuspeito = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeCard() {
    final t = context.uai;
    final valido = _idadeMinima <= _idadeMaxima;
    final color = valido ? t.warning : t.error;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.cake_rounded,
            title: 'Faixa etária aceita',
            color: accent,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 460;

              final fields = [
                _numberField(
                  controller: _idadeMinimaController,
                  label: 'Idade mínima',
                  icon: Icons.child_care_rounded,
                  onChanged: (value) {
                    setState(() => _idadeMinima = int.tryParse(value) ?? 0);
                  },
                ),
                _numberField(
                  controller: _idadeMaximaController,
                  label: 'Idade máxima',
                  icon: Icons.elderly_rounded,
                  onChanged: (value) {
                    setState(() => _idadeMaxima = int.tryParse(value) ?? 0);
                  },
                ),
              ];

              if (narrow) {
                return Column(
                  children: [fields[0], const SizedBox(height: 10), fields[1]],
                );
              }

              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _noticeBox(
            icon: valido ? Icons.info_outline_rounded : Icons.warning_rounded,
            color: accent,
            text: valido
                ? 'Serão aceitos alunos com idade entre $_idadeMinima e $_idadeMaxima anos.'
                : 'Idade mínima não pode ser maior que a idade máxima.',
          ),
        ],
      ),
    );
  }

  Widget _buildVagasCard() {
    final t = context.uai;
    final estourou =
        _vagasDisponiveis > 0 && _totalInscricoes > _vagasDisponiveis;
    final color = estourou ? t.error : t.info;
    final accent = _ensureVisible(color, t.card);
    final progressColor = estourou ? t.error : t.success;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.event_seat_rounded,
            title: 'Controle de vagas',
            color: accent,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              final counter = Container(
                width: narrow ? double.infinity : 104,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withAlpha(20), t.cardAlt),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withAlpha(36)),
                ),
                child: Column(
                  children: [
                    Text(
                      '$_totalInscricoes',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    Text(
                      'Pendentes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: t.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );

              final input = _numberField(
                controller: _vagasController,
                label: 'Vagas disponíveis',
                icon: Icons.event_available_rounded,
                onChanged: (value) {
                  setState(() {
                    _vagasDisponiveis = int.tryParse(value) ?? 0;
                  });
                },
              );

              if (narrow) {
                return Column(
                  children: [input, const SizedBox(height: 10), counter],
                );
              }

              return Row(
                children: [
                  Expanded(child: input),
                  const SizedBox(width: 10),
                  counter,
                ],
              );
            },
          ),
          if (_vagasDisponiveis > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: _percentualVagas,
                backgroundColor: t.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _ensureVisible(progressColor, t.border),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_percentualVagas * 100).toStringAsFixed(1)}% das vagas preenchidas',
              style: TextStyle(
                color: _ensureVisible(progressColor, t.card),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (estourou) ...[
            const SizedBox(height: 10),
            _noticeBox(
              icon: Icons.warning_rounded,
              color: _ensureVisible(t.error, t.card),
              text:
              '${_totalInscricoes - _vagasDisponiveis} inscrições excedem as vagas configuradas.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumoCard() {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: success),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.summarize_rounded,
            title: 'Resumo das configurações',
            color: success,
          ),
          const SizedBox(height: 12),
          _buildResumoRow(
            label: 'Status',
            value: _inscricoesAbertas ? 'ABERTAS' : 'FECHADAS',
            color: _inscricoesAbertas ? t.success : t.error,
          ),
          _buildResumoRow(
            label: 'Assinatura',
            value: _recolherAssinatura ? 'SIM' : 'NÃO',
            color: t.associacao,
          ),
          _buildResumoRow(
            label: 'Vagas',
            value: '$_vagasDisponiveis vagas',
            color: t.info,
          ),
          _buildResumoRow(
            label: 'Inscrições',
            value: '$_totalInscricoes pendentes',
            color: t.warning,
          ),
          _buildResumoRow(
            label: 'Idade',
            value: '$_idadeMinima a $_idadeMaxima anos',
            color: t.associacao,
          ),
          _buildResumoRow(
            label: 'Triagem',
            value: 'ALERTAR, NÃO BLOQUEAR',
            color: t.error,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(color: accent),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withAlpha(31), t.cardAlt),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: accent.withAlpha(36)),
            ),
            child: Icon(Icons.info_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Para aprovar, recusar ou acompanhar candidatos, acesse a lista de inscrições pendentes.',
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

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withAlpha(31), t.cardAlt),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withAlpha(36)),
          ),
          child: Icon(icon, color: accent, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      cursorColor: accent,
      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textSecondary),
        prefixIcon: Icon(icon, color: accent),
        filled: true,
        fillColor: t.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
    );
  }

  Widget _noticeBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(20), t.cardAlt),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withAlpha(36)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoRow({
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(18), t.cardAlt),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withAlpha(31)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;
    final pad = _dashboardPagePadding;

    return Container(
      color: t.background,
      padding: pad,
      child: Center(
        child: _dashboardWidthLimiter(
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(_isDesktopDashboard ? 30 : 24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    color: t.primary,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Carregando configurações de inscrições...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _onCardMuted(),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({required Color color}) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: accent.withAlpha(31)),
      boxShadow: t.softShadow,
    );
  }
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 11:28
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================
