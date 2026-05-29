import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/area_aluno_dashboard_screen.dart'
as area_aluno_dashboard;
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_session_service.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';
import 'package:uai_capoeira/shared/services/pwa_install_service.dart';

class AreaAlunoLoginScreen extends StatefulWidget {
  const AreaAlunoLoginScreen({super.key});

  @override
  State<AreaAlunoLoginScreen> createState() => _AreaAlunoLoginScreenState();
}

class _AreaAlunoLoginScreenState extends State<AreaAlunoLoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _dataNascimentoController =
  TextEditingController();
  final TextEditingController _iniciaisController = TextEditingController();
  final TextEditingController _telefoneFinalController =
  TextEditingController();

  bool _carregando = false;
  bool _restaurandoSessao = true;

  final RastreioSiteService _rastreioService = RastreioSiteService();
  final AreaAlunoSessionService _sessionService = AreaAlunoSessionService();
  final PwaInstallService _pwaInstallService = PwaInstallService.instance;

  StreamSubscription<bool>? _pwaInstallSub;
  bool _pwaPodeInstalar = false;

  @override
  void initState() {
    super.initState();

    _rastreioService.iniciarTela(
      'area_aluno_login',
      origem: 'site',
      metadata: {
        'descricao': 'Tela de login público da Área do Aluno',
      },
    );
    _rastreioService.marcarTempo('area_aluno_login_tempo');

    _configurarInstalacaoPwa();
    _tentarRestaurarSessaoAluno();
  }

  @override
  void dispose() {
    _pwaInstallSub?.cancel();

    _dataNascimentoController.dispose();
    _iniciaisController.dispose();
    _telefoneFinalController.dispose();

    _rastreioService.registrarTempoMarcador(
      chave: 'area_aluno_login_tempo',
      tipo: 'tempo_tela',
      nome: 'area_aluno_login',
      origem: 'dispose',
      limparMarcador: true,
    );
    _rastreioService.finalizarTela(destino: 'saida_area_aluno_login');

    super.dispose();
  }

  void _configurarInstalacaoPwa() {
    if (!kIsWeb) return;

    _pwaPodeInstalar = _pwaInstallService.isInstallPromptAvailable;

    _pwaInstallSub =
        _pwaInstallService.installAvailableStream.listen((available) {
          if (!mounted) return;
          setState(() => _pwaPodeInstalar = available);
        });
  }

  Future<void> _tentarRestaurarSessaoAluno() async {
    try {
      final sessao = await _sessionService.restaurarSessaoRevalidando();

      if (!mounted) return;

      if (sessao != null) {
        _rastreioService.registrarConversao(
          nome: 'area_aluno_sessao_restaurada',
          origem: 'area_aluno_login',
          metadata: {
            'offline': sessao['offline'] == true,
            'aluno_id': (sessao['aluno'] as Map?)?['id']?.toString(),
          },
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => area_aluno_dashboard.AreaAlunoDashboardScreen(
              aluno: Map<String, dynamic>.from(sessao['aluno'] as Map),
              config: Map<String, dynamic>.from(sessao['config'] as Map),
              authPayload: Map<String, dynamic>.from(
                sessao['authPayload'] as Map,
              ),
            ),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Não foi possível restaurar sessão da Área do Aluno: $e');
    } finally {
      if (mounted) {
        setState(() => _restaurandoSessao = false);
      }
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  String _normalizarIniciais(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-ZÀ-Ú0-9]'), '');
  }

  void _registrarSnapshotLogin(String momento) {
    _rastreioService.registrarSnapshotFormulario(
      formulario: 'area_aluno_login',
      momento: momento,
      origem: 'area_aluno_login',
      campos: {
        'data_nascimento': _dataNascimentoController.text.trim(),
        'iniciais': _normalizarIniciais(_iniciaisController.text),
        'telefone_final': _telefoneFinalController.text.trim(),
      },
      camposSensiveis: const ['data_nascimento', 'telefone_final'],
    );
  }

  Future<void> _acessarAreaAluno() async {
    _rastreioService.registrarClique(
      nome: 'tentar_acessar_area_aluno',
      origem: 'area_aluno_login',
    );
    _registrarSnapshotLogin('tentativa_login');

    if (!_formKey.currentState!.validate()) {
      _rastreioService.registrarErroFormulario(
        formulario: 'area_aluno_login',
        local: 'validacao_campos',
        erros: const ['Campos inválidos ou incompletos'],
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _carregando = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'validarAcessoAreaAluno',
      );

      final result = await callable.call({
        'dataNascimento': _dataNascimentoController.text.trim(),
        'iniciais': _normalizarIniciais(_iniciaisController.text),
        'telefoneFinal': _telefoneFinalController.text.trim(),
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final success = data['success'] == true;

      if (!success) {
        final msg = data['message']?.toString() ??
            'Não foi possível validar o acesso. Confira os dados e tente novamente.';

        _rastreioService.registrarErroFormulario(
          formulario: 'area_aluno_login',
          local: 'validacao_cloud_function',
          erros: [msg],
          metadata: {'success': false},
        );

        _mostrarErro(msg);
        return;
      }

      final aluno = Map<String, dynamic>.from(data['aluno'] as Map? ?? {});
      final config = Map<String, dynamic>.from(data['config'] as Map? ?? {});

      _rastreioService.registrarConversao(
        nome: 'area_aluno_login_sucesso',
        origem: 'area_aluno_login',
        metadata: {
          'aluno_id': aluno['id']?.toString() ?? aluno['docId']?.toString(),
          'tem_config': config.isNotEmpty,
        },
      );

      final authPayload = {
        'dataNascimento': _dataNascimentoController.text.trim(),
        'iniciais': _normalizarIniciais(_iniciaisController.text),
        'telefoneFinal': _telefoneFinalController.text.trim(),
      };

      await _sessionService.salvarSessao(
        aluno: aluno,
        config: config,
        authPayload: authPayload,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => area_aluno_dashboard.AreaAlunoDashboardScreen(
            aluno: aluno,
            config: config,
            authPayload: authPayload,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      _rastreioService.registrarErroFormulario(
        formulario: 'area_aluno_login',
        local: 'firebase_functions',
        erros: [e.message ?? e.code],
        metadata: {'code': e.code},
      );

      _mostrarErro(
        e.message ?? 'Erro ao validar acesso. Tente novamente em instantes.',
      );
    } catch (e) {
      _rastreioService.registrarErroFormulario(
        formulario: 'area_aluno_login',
        local: 'erro_inesperado',
        erros: ['Erro ao acessar a Área do Aluno: $e'],
      );
      _mostrarErro('Erro ao acessar a Área do Aluno: $e');
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;

    final t = context.uai;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: t.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _instalarOuMostrarAjudaPwa() async {
    _rastreioService.registrarClique(
      nome: 'instalar_pwa_area_aluno',
      origem: 'area_aluno_login',
      metadata: {
        'prompt_disponivel': _pwaPodeInstalar,
      },
    );

    if (_pwaPodeInstalar) {
      final instalado = await _pwaInstallService.promptInstall();

      if (!mounted) return;

      final t = context.uai;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            instalado
                ? 'App instalado com sucesso!'
                : 'Instalação não concluída. Você pode tentar novamente pelo menu do navegador.',
          ),
          backgroundColor: instalado ? t.success : t.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _mostrarInstrucoesInstalacaoPwa();
  }

  void _mostrarInstrucoesInstalacaoPwa() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);

    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Icon(Icons.install_mobile_rounded, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Instalar no celular',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'No Android/Chrome: toque nos três pontinhos do navegador e escolha '
                '“Adicionar à tela inicial” ou “Instalar app”.\n\n'
                'No iPhone/Safari: toque no botão de compartilhar e escolha '
                '“Adicionar à Tela de Início”.',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'ENTENDI',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final isMobile = MediaQuery.of(context).size.width < 650;

    if (_restaurandoSessao) {
      return Scaffold(
        backgroundColor: t.background,
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(22),
            margin: const EdgeInsets.all(22),
            decoration: _cardDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: t.primary),
                const SizedBox(height: 14),
                Text(
                  'Verificando acesso salvo...',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [t.background, t.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 16 : 28),
                child: Column(
                  children: [
                    _buildHeader(isMobile),
                    const SizedBox(height: 18),
                    _buildLoginCard(isMobile),
                    const SizedBox(height: 14),
                    _buildInstalarPwaCard(),
                    const SizedBox(height: 14),
                    _buildAjudaCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.softShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 540;

          final icon = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.school_rounded,
              color: onPrimary,
              size: 36,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Área do Aluno',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: isMobile ? 23 : 26,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Consulte seus dados, frequência, eventos e certificados.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.32,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 15),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginCard(bool isMobile) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: _cardDecoration(borderColor: primary.withOpacity(0.12)),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Icon(
              Icons.verified_user_rounded,
              color: primary,
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              'Identificação do aluno',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Digite seus dados exatamente como estão no cadastro.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            _buildDataNascimentoField(),
            const SizedBox(height: 14),
            _buildIniciaisField(),
            const SizedBox(height: 14),
            _buildTelefoneFinalField(),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _carregando ? null : _acessarAreaAluno,
                icon: _carregando
                    ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: _readableOn(t.primary),
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.login_rounded),
                label: Text(
                  _carregando ? 'Validando...' : 'ACESSAR MINHA ÁREA',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  disabledBackgroundColor: t.cardAlt,
                  foregroundColor: _readableOn(t.primary),
                  disabledForegroundColor: t.textMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataNascimentoField() {
    final t = context.uai;

    return TextFormField(
      controller: _dataNascimentoController,
      keyboardType: TextInputType.datetime,
      style: TextStyle(color: t.textPrimary),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
        LengthLimitingTextInputFormatter(10),
        _DataNascimentoInputFormatter(),
      ],
      decoration: _inputDecoration(
        label: 'Data de nascimento',
        hint: 'dd/mm/aaaa',
        icon: Icons.cake_rounded,
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return 'Informe sua data de nascimento';
        if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) {
          return 'Use o formato dd/mm/aaaa';
        }
        return null;
      },
    );
  }

  Widget _buildIniciaisField() {
    final t = context.uai;

    return TextFormField(
      controller: _iniciaisController,
      textCapitalization: TextCapitalization.characters,
      style: TextStyle(color: t.textPrimary),
      inputFormatters: [
        LengthLimitingTextInputFormatter(10),
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÀ-ú0-9]')),
        UpperCaseTextFormatter(),
      ],
      decoration: _inputDecoration(
        label: 'Iniciais do nome completo',
        hint: 'Ex: AESL',
        icon: Icons.badge_rounded,
      ),
      validator: (value) {
        final text = _normalizarIniciais(value ?? '');
        if (text.isEmpty) return 'Informe as iniciais';
        if (text.length < 2) return 'Informe pelo menos 2 iniciais';
        return null;
      },
    );
  }

  Widget _buildTelefoneFinalField() {
    final t = context.uai;

    return TextFormField(
      controller: _telefoneFinalController,
      keyboardType: TextInputType.number,
      obscureText: true,
      style: TextStyle(color: t.textPrimary),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: _inputDecoration(
        label: 'Últimos 4 dígitos do telefone',
        hint: 'Ex: 6237',
        icon: Icons.phone_android_rounded,
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return 'Informe os últimos 4 dígitos';
        if (text.length != 4) return 'Digite exatamente 4 números';
        return null;
      },
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: Icon(icon, color: primary),
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
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error, width: 1.4),
      ),
    );
  }

  Widget _buildInstalarPwaCard() {
    if (!kIsWeb) return const SizedBox.shrink();

    final t = context.uai;

    return _infoCard(
      icon: Icons.install_mobile_rounded,
      color: t.primary,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Instale a Área do Aluno no celular para abrir como app e manter seu acesso salvo.',
              style: TextStyle(
                color: _ensureVisible(t.primary, t.cardAlt),
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _instalarOuMostrarAjudaPwa,
            style: FilledButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
            child: Text(
              _pwaPodeInstalar ? 'INSTALAR' : 'COMO?',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAjudaCard() {
    final t = context.uai;

    return _infoCard(
      icon: Icons.info_outline_rounded,
      color: t.warning,
      child: Text(
        'As iniciais são formadas pelo primeiro caractere de cada nome. '
            'Exemplo: ARTHUR EDUARDO SILVA LIMA = AESL. '
            'Preposições como DE, DA, DO, DOS e DAS são ignoradas.',
        style: TextStyle(
          color: _ensureVisible(t.warning, t.cardAlt),
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: _readableOn(accent),
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.softShadow,
    );
  }
}

class _DataNascimentoInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
    }

    final text = buffer.toString();

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
