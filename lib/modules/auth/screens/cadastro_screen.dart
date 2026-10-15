import 'dart:async';

import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/shared/services/phone_mask_service.dart';
import 'package:uai_capoeira/shared/services/validation_service.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/core/services/uai_callable_client.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _contatoController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  final _emailFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  Color get _primaryRed => Theme.of(context).colorScheme.primary;

  bool _isCadastroPasswordValid(String password) {
    if (password.length < 8) return false;
    if (!password.contains(RegExp(r'[A-Z]'))) return false;
    if (!password.contains(RegExp(r'[a-z]'))) return false;
    if (!password.contains(RegExp(r'[0-9]'))) return false;
    return true;
  }

  bool get _isFormReady {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _contatoController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    return ValidationService.isNameValid(name) &&
        ValidationService.isEmailValid(email) &&
        ValidationService.isPhoneValid(phone) &&
        _isCadastroPasswordValid(password) &&
        confirmPassword.isNotEmpty &&
        confirmPassword == password;
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    final tokens = UaiThemeTokens.of(context);
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: tokens.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _primaryRed, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.error, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final cardWidth = isDesktop ? 620.0 : 680.0;
    final tokens = UaiThemeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: tokens.background,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -70,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.primary.withAlpha(isDark ? 26 : 13),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -90,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.primary.withAlpha(isDark ? 31 : 18),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cardWidth),
                  child: Card(
                    elevation: 0,
                    color: tokens.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: BorderSide(color: tokens.border),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 34 : 22,
                        18,
                        isDesktop ? 34 : 22,
                        28,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  style: IconButton.styleFrom(
                                    backgroundColor: tokens.cardAlt,
                                    foregroundColor: tokens.textPrimary,
                                  ),
                                ),
                                const Spacer(),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                width: 106,
                                height: 106,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: tokens.primary.withAlpha(isDark ? 31 : 18),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: _primaryRed.withAlpha(20),
                                  ),
                                ),
                                child: SvgPicture.asset(
                                  'assets/logo_uai_tema_seguro.svg',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Center(
                              child: Text(
                                'Crie sua conta',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 470),
                                child: Text(
                                  'Cadastre-se para acessar a gestão do UAI Capoeira com um visual moderno, seguro e responsivo.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            _buildFieldLabel('Nome completo'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameController,
                              onChanged: (_) => setState(() {}),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  FocusScope.of(context).requestFocus(_emailFocusNode),
                              decoration: _inputDecoration(
                                hint: 'Digite seu nome completo',
                                icon: Icons.person_outline,
                              ),
                              validator: (value) {
                                if (!ValidationService.isNameValid(value ?? '')) {
                                  return 'Digite seu nome completo com sobrenome';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFieldLabel('Email'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailController,
                              onChanged: (_) => setState(() {}),
                              focusNode: _emailFocusNode,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  FocusScope.of(context).requestFocus(_phoneFocusNode),
                              decoration: _inputDecoration(
                                hint: 'nome@email.com',
                                icon: Icons.email_outlined,
                              ),
                              validator: (value) {
                                if (!ValidationService.isEmailValid(value ?? '')) {
                                  return 'Digite um email válido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFieldLabel('Telefone (WhatsApp)'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _contatoController,
                              onChanged: (_) => setState(() {}),
                              focusNode: _phoneFocusNode,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  FocusScope.of(context).requestFocus(_passwordFocusNode),
                              inputFormatters: [PhoneMaskService.phoneInputFormatter],
                              decoration: _inputDecoration(
                                hint: '(38) 99999-9999',
                                icon: Icons.phone_outlined,
                              ),
                              validator: (value) {
                                if (!ValidationService.isPhoneValid(value ?? '')) {
                                  return 'Digite um telefone válido com DDD';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 22),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: tokens.cardAlt,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        color: _primaryRed,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Defina uma senha forte',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: tokens.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _buildFieldLabel('Senha'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _passwordController,
                                    onChanged: (_) => setState(() {}),
                                    focusNode: _passwordFocusNode,
                                    obscureText: !_isPasswordVisible,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) => FocusScope.of(context)
                                        .requestFocus(_confirmPasswordFocusNode),
                                    decoration: _inputDecoration(
                                      hint: 'Digite sua senha',
                                      icon: Icons.lock_outline,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isPasswordVisible =
                                                !_isPasswordVisible;
                                          });
                                        },
                                      ),
                                    ),
                                    validator: (value) {
                                      if (!_isCadastroPasswordValid(value ?? '')) {
                                        return 'Use pelo menos 8 caracteres, com maiúscula, minúscula e número';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Mínimo 8 caracteres, com letra maiúscula, letra minúscula e número.',
                                    style: TextStyle(
                                      color: tokens.textSecondary,
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildFieldLabel('Confirmar senha'),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _confirmPasswordController,
                                    onChanged: (_) => setState(() {}),
                                    focusNode: _confirmPasswordFocusNode,
                                    obscureText: !_isConfirmPasswordVisible,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) {
                                      if (_isFormReady) {
                                        _cadastrar();
                                      }
                                    },
                                    decoration: _inputDecoration(
                                      hint: 'Repita sua senha',
                                      icon: Icons.lock_outline,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isConfirmPasswordVisible
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isConfirmPasswordVisible =
                                                !_isConfirmPasswordVisible;
                                          });
                                        },
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value != _passwordController.text) {
                                        return 'As senhas não coincidem';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isFormReady ? _cadastrar : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryRed,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      tokens.textSecondary.withAlpha(46),
                                  disabledForegroundColor:
                                      tokens.textSecondary.withAlpha(148),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'CADASTRAR',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: tokens.info.withAlpha(isDark ? 31 : 20),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: tokens.info.withAlpha(89)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: tokens.info,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Sua conta será analisada por um administrador antes de ser ativada. Você receberá um retorno quando o acesso estiver liberado.',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: tokens.textPrimary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    final tokens = UaiThemeTokens.of(context);
    return Text(
      text,
      style: TextStyle(
        color: tokens.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate() || !_isFormReady) return;

    final email = _emailController.text.trim().toLowerCase();
    final verificationToken = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CadastroEmailVerificationDialog(email: email),
    );
    if (!mounted || verificationToken == null || verificationToken.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final tokens = UaiThemeTokens.of(dialogContext);
        return AlertDialog(
          backgroundColor: tokens.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const CircularProgressIndicator(),
                const SizedBox(height: 22),
                Text('Criando sua conta...', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: tokens.textPrimary)),
                const SizedBox(height: 8),
                Text('E-mail confirmado. Agora estamos preparando sua solicitação de acesso à gestão.', textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary, height: 1.4)),
              ],
            ),
          ),
        );
      },
    );

    try {
      final payload = <String, dynamic>{
        'email': email,
        'verificationToken': verificationToken,
        'nome': _nameController.text.trim(),
        'contato': ValidationService.extractPhoneNumbers(_contatoController.text),
        'senha': _passwordController.text,
      };

      // A conta do Firebase Auth só é criada pelo backend DEPOIS de o token
      // de verificação do e-mail ser validado. Sem validação, não existe conta.
      await UaiCallableClient.instance.call('concluirCadastroGestaoVerificado', payload);

      // Depois de a criação segura no servidor, autentica normalmente no cliente.
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      await FirebaseAuth.instance.currentUser?.reload();

      if (mounted) Navigator.pop(context);
      if (mounted) _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorSnackBar(_getFriendlyErrorMessage(e.code));
    } catch (e) {
      debugPrint('Erro ao concluir cadastro verificado: $e');
      if (mounted) Navigator.pop(context);
      if (mounted) {
        _showErrorSnackBar('Não foi possível concluir o cadastro. A conta só é criada após a confirmação válida do e-mail. Tente novamente.');
      }
    }
  }

  String _getFriendlyErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Este email já está cadastrado. Faça login ou use outro email.';
      case 'weak-password':
        return 'Sua senha é muito fraca. Siga os requisitos de segurança.';
      case 'invalid-email':
        return 'O email digitado não é válido. Verifique e tente novamente.';
      default:
        return 'Erro ao cadastrar. Tente novamente mais tarde.';
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('✨ Cadastro realizado!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 60,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sua conta foi criada com sucesso e está aguardando aprovação.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Você receberá um email quando sua conta for ativada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade900),
            child: const Text('ENTENDI'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _contatoController.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }
}

class _CadastroEmailVerificationDialog extends StatefulWidget {
  const _CadastroEmailVerificationDialog({required this.email});
  final String email;

  @override
  State<_CadastroEmailVerificationDialog> createState() => _CadastroEmailVerificationDialogState();
}

class _CadastroEmailVerificationDialogState extends State<_CadastroEmailVerificationDialog> {
  final _codigoController = TextEditingController();
  Timer? _timer;
  int _segundos = 60;
  bool _enviando = true;
  bool _validando = false;
  bool _confirmado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enviarCodigo());
  }

  Future<void> _enviarCodigo() async {
    if (!mounted) return;
    setState(() { _enviando = true; _erro = null; });
    try {
      await UaiCallableClient.instance.call('solicitarCodigoCadastroGestao', {'email': widget.email});
      if (!mounted) return;
      _segundos = 60;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (_segundos <= 1) { timer.cancel(); setState(() => _segundos = 0); }
        else { setState(() => _segundos--); }
      });
    } catch (e) {
      if (mounted) setState(() => _erro = _limparErro(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _validar() async {
    final codigo = _codigoController.text.replaceAll(RegExp(r'\D'), '');
    if (codigo.length != 6 || _validando) return;
    setState(() { _validando = true; _erro = null; });
    try {
      final result = await UaiCallableClient.instance.call('validarCodigoCadastroGestao', {'email': widget.email, 'codigo': codigo});
      final token = (result['verification_token'] ?? '').toString();
      if (token.isEmpty) throw StateError('Validação concluída sem token seguro.');
      if (!mounted) return;
      setState(() => _confirmado = true);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) Navigator.of(context).pop(token);
    } catch (e) {
      if (mounted) setState(() => _erro = _limparErro(e));
    } finally {
      if (mounted) setState(() => _validando = false);
    }
  }

  String _limparErro(Object error) {
    var text = error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
    text = text.replaceAll(RegExp(r'\s*\([A-Z_]+\)\s*$'), '');
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UaiThemeTokens.of(context);
    final pronto = _codigoController.text.replaceAll(RegExp(r'\D'), '').length == 6;
    return PopScope(
      canPop: !_validando && !_confirmado,
      child: AlertDialog(
        backgroundColor: tokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: tokens.border)),
        contentPadding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
        content: SizedBox(
          width: 430,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _confirmado
                ? Column(key: const ValueKey('ok'), mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 78, height: 78, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withAlpha(26)), child: const Icon(Icons.verified_rounded, color: Colors.green, size: 44)),
                    const SizedBox(height: 18),
                    Text('E-mail confirmado!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: tokens.textPrimary)),
                    const SizedBox(height: 8),
                    Text('Tudo certo. Vamos criar sua conta com segurança.', textAlign: TextAlign.center, style: TextStyle(color: tokens.textSecondary)),
                  ])
                : Column(key: const ValueKey('form'), mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 72, height: 72, decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: tokens.primary.withAlpha(26)), child: Icon(Icons.mark_email_read_outlined, color: tokens.primary, size: 38)),
                    const SizedBox(height: 16),
                    Text('Confirme seu e-mail', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: tokens.textPrimary)),
                    const SizedBox(height: 8),
                    Text('Enviamos um código de 6 dígitos para', style: TextStyle(color: tokens.textSecondary)),
                    const SizedBox(height: 4),
                    Text(widget.email, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                    const SizedBox(height: 22),
                    if (_enviando) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('Enviando código seguro...', style: TextStyle(color: tokens.textSecondary)),
                    ] else ...[
                      TextField(
                        controller: _codigoController,
                        autofocus: true,
                        enabled: !_validando,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _validar(),
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8, color: tokens.textPrimary),
                        decoration: InputDecoration(counterText: '', hintText: '000000', filled: true, fillColor: tokens.cardAlt, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: tokens.border))),
                      ),
                      if (_erro != null) ...[
                        const SizedBox(height: 10),
                        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: tokens.error.withAlpha(20), borderRadius: BorderRadius.circular(14), border: Border.all(color: tokens.error.withAlpha(71))), child: Text(_erro!, textAlign: TextAlign.center, style: TextStyle(color: tokens.error, fontWeight: FontWeight.w700))),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: pronto && !_validando ? _validar : null, icon: _validando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined), label: Text(_validando ? 'VALIDANDO...' : 'CONFIRMAR E-MAIL'), style: ElevatedButton.styleFrom(backgroundColor: tokens.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
                      const SizedBox(height: 10),
                      TextButton(onPressed: _segundos == 0 && !_validando ? _enviarCodigo : null, child: Text(_segundos > 0 ? 'Reenviar código em ${_segundos}s' : 'REENVIAR CÓDIGO')),
                      TextButton(onPressed: _validando ? null : () => Navigator.pop(context), child: const Text('ALTERAR E-MAIL')),
                    ],
                    const SizedBox(height: 6),
                    Text('A confirmação prova que este e-mail é seu. O acesso à gestão ainda será analisado pela administração.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.35, color: tokens.textSecondary)),
                  ]),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codigoController.dispose();
    super.dispose();
  }
}

