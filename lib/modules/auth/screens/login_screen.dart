import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_svg/flutter_svg.dart';

import 'cadastro_screen.dart';
import 'package:uai_capoeira/modules/auth/screens/auth_check.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/escolher_aluno_vinculado_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_google_service.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_acesso_service.dart';
import 'package:uai_capoeira/modules/usuarios/services/user_service.dart';
import 'package:uai_capoeira/shared/services/validation_service.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _passwordFocusNode = FocusNode();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String _versaoApp = 'Carregando...';

  Color get _primaryRed => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _carregarVersao();
  }

  Future<void> _carregarVersao() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('configuracoes')
          .doc('app')
          .get();

      if (!mounted) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final versao = data['versao_atual'] ?? '1.0.0';

        setState(() {
          _versaoApp = versao;
        });

        developer.log('✅ Versão carregada do Firestore: $_versaoApp');
      } else {
        setState(() {
          _versaoApp = '1.0.0';
        });

        developer.log(
          '⚠️ Documento "configuracoes/app" não encontrado, usando versão padrão',
        );
      }
    } catch (e) {
      developer.log('❌ Erro ao carregar versão: $e');

      if (!mounted) return;

      setState(() {
        _versaoApp = '1.0.0';
      });
    }
  }

  Future<void> _atualizarSessaoAposLogin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        developer.log('⚠️ Nenhum usuário logado para atualizar sessão.');
        return;
      }

      await user.reload();
      developer.log('✅ Sessão do FirebaseAuth recarregada para: ${user.email}');
    } catch (e) {
      developer.log('⚠️ Não foi possível recarregar sessão após login: $e');
    }
  }

  Future<void> _verificarAcessoENavegar(User user, {String? provider}) async {
    final hasAccess = await UserService.hasAccess(user.uid);

    if (!mounted) return;

    if (!hasAccess) {
      try {
        final googleService = AreaAlunoGoogleService();
        final alunos = await googleService.buscarAlunosVinculados();

        if (!mounted) return;

        if (alunos.length == 1) {
          await googleService.abrirAreaAlunoVinculado(context, alunos.first);
          return;
        }

        if (alunos.length > 1) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => EscolherAlunoVinculadoScreen(alunos: alunos),
            ),
            (route) => false,
          );
          return;
        }
      } catch (e) {
        debugPrint('Erro ao verificar Área do Aluno vinculada: $e');
      }

      _showPendingAccountDialog();
      return;
    }

    final loginRegistrado = await UsuarioAcessoService()
        .registrarUltimoLoginGestao(uid: user.uid, provider: provider);

    debugPrint(
      loginRegistrado
          ? '✅ Login de gestão registrado para ${user.uid}'
          : '⚠️ Login de gestão não foi registrado para ${user.uid}',
    );

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AuthCheck()),
      (route) => false,
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        developer.log('✅ Persistência LOCAL confirmada antes do login por email.');
      }

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = credential.user ?? FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Usuário não encontrado após login.',
        );
      }

      await _atualizarSessaoAposLogin();

      await UserService.createOrUpdateUserDocument(
        user: user,
        origem: 'login_gestao',
      );

      if (!mounted) return;

      await _verificarAcessoENavegar(user, provider: 'password');
    } on FirebaseAuthException catch (e) {
      _handleLoginError(e);
    } catch (e) {
      developer.log('❌ Erro inesperado no login: $e');
      _showErrorSnackBar('Ocorreu um erro inesperado. Tente novamente.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleLoginError(FirebaseAuthException e) {
    String message;

    switch (e.code) {
      case 'user-not-found':
        message = 'Usuário não encontrado. Verifique seu email.';
        break;
      case 'wrong-password':
      case 'invalid-credential':
        message = 'Email ou senha incorretos. Tente novamente.';
        break;
      case 'invalid-email':
        message = 'Formato de email inválido.';
        break;
      case 'user-disabled':
        message = 'Esta conta está desativada. Entre em contato com o suporte.';
        break;
      case 'too-many-requests':
        message =
            'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
        break;
      case 'network-request-failed':
        message = 'Sem conexão com a internet. Verifique sua rede.';
        break;
      default:
        message = 'Erro ao fazer login. Tente novamente.';
    }

    _showErrorSnackBar(message);
  }

  Future<void> _loginComGoogle() async {
    setState(() => _isLoading = true);

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        developer.log('✅ Persistência LOCAL confirmada antes do login Google Web.');

        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});

        final UserCredential userCredential =
            await FirebaseAuth.instance.signInWithPopup(provider);

        final user = userCredential.user;

        if (user == null) {
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'Usuário Google não encontrado após login.',
          );
        }

        await _atualizarSessaoAposLogin();

        await UserService.createOrUpdateUserDocument(
          user: user,
          isGoogleLogin: true,
          origem: 'login_google_gestao',
        );

        if (!mounted) return;

        await _verificarAcessoENavegar(user, provider: 'google');
        return;
      }

      // O plugin google_sign_in não executa o fluxo nativo de seleção
      // de contas no Windows. O Firebase Auth possui provedor OAuth
      // próprio nessa plataforma; não usar login WebView nem tokens manuais.
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        final userCredential = await FirebaseAuth.instance
            .signInWithProvider(provider);
        final user = userCredential.user;
        if (user == null) {
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'A autenticação Google não retornou um usuário.',
          );
        }
        await _atualizarSessaoAposLogin();
        await UserService.createOrUpdateUserDocument(
          user: user,
          isGoogleLogin: true,
          origem: 'login_google_gestao',
        );
        if (!mounted) return;
        await _verificarAcessoENavegar(user, provider: 'google');
        return;
      }

      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);

      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Usuário Google não encontrado após login.',
        );
      }

      await _atualizarSessaoAposLogin();

      await UserService.createOrUpdateUserDocument(
        user: user,
        isGoogleLogin: true,
        origem: 'login_google_gestao',
      );

      if (!mounted) return;

      await _verificarAcessoENavegar(user, provider: 'google');
    } on FirebaseAuthException catch (e) {
      String message = 'Não foi possível entrar com Google.';

      if (e.code == 'account-exists-with-different-credential') {
        message =
            'Já existe uma conta com este email. Use outro método de login.';
      } else if (e.code == 'network-request-failed') {
        message = 'Sem conexão com a internet. Verifique sua rede.';
      } else if (e.code == 'popup-closed-by-user') {
        message = 'Login cancelado antes de concluir.';
      } else if (e.code == 'popup-blocked') {
        message =
            'O navegador bloqueou a janela de login. Libere pop-ups para este site.';
      } else if (e.code == 'unsupported-platform' ||
          e.code == 'operation-not-supported-in-this-environment') {
        message = 'Login Google indisponível nesta versão do Windows. '
            'Atualize o aplicativo e o Firebase Auth.';
      } else if (e.code == 'operation-not-allowed') {
        message = 'Login Google não habilitado no Firebase Authentication.';
      }

      _showErrorSnackBar(message);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'Erro ao preparar perfil apos login Google: ${e.code} - ${e.message}',
      );
      _showErrorSnackBar(
        'Seu login foi feito, mas não foi possível preparar seu perfil. Tente novamente.',
      );
    } catch (e) {
      debugPrint('Erro inesperado no login com Google: $e');
      _showErrorSnackBar(
        'Não foi possível entrar com Google. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPendingAccountDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⏳ Aguardando Aprovação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 50,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sua conta ainda não foi aprovada por um administrador.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Você receberá uma notificação quando tiver acesso liberado.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade900),
            child: const Text('VOLTAR'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Widget _buildLogoBadge() {
    return Container(
      width: 98,
      height: 98,
      decoration: BoxDecoration(
        color: _primaryRed.withAlpha(18),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _primaryRed.withAlpha(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: SvgPicture.asset(
        'assets/logo_uai_tema_seguro.svg',
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;
    final cardWidth = isDesktop ? 490.0 : 560.0;
    final tokens = UaiThemeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final inputDecoration = InputDecoration(
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

    return Scaffold(
      backgroundColor: tokens.background,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.primary.withAlpha(isDark ? 31 : 20),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.primary.withAlpha(isDark ? 26 : 15),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardWidth),
                child: Card(
                  elevation: 0,
                  color: tokens.card,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: BorderSide(color: tokens.border),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 38 : 22,
                      28,
                      isDesktop ? 38 : 22,
                      24,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoBadge(),
                          const SizedBox(height: 18),
                          Text(
                            'Bem-vindo ao UAI Capoeira',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Acesse sua gestão com um visual mais moderno, rápido e responsivo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 26),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Email',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            enabled: !_isLoading,
                            onFieldSubmitted: (_) {
                              FocusScope.of(context).requestFocus(_passwordFocusNode);
                            },
                            decoration: inputDecoration.copyWith(
                              hintText: 'seuemail@exemplo.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              if (!ValidationService.isEmailValid(value ?? '')) {
                                return 'Digite um email válido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Senha',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            obscureText: !_isPasswordVisible,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _isLoading ? null : _login(),
                            enabled: !_isLoading,
                            decoration: inputDecoration.copyWith(
                              hintText: 'Digite sua senha',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(
                                          () => _isPasswordVisible = !_isPasswordVisible,
                                        ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Digite sua senha';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : () {},
                              child: Text(
                                'Esqueceu a senha?',
                                style: TextStyle(
                                  color: _primaryRed,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryRed,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'ENTRAR',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: tokens.border),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'OU',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: tokens.border),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton.icon(
                              onPressed: _isLoading ? null : _loginComGoogle,
                              icon: Image.asset(
                                'assets/images/google_logo.png',
                                height: 22,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.g_mobiledata, size: 30),
                              ),
                              label: Text(
                                'CONTINUAR COM GOOGLE',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _isLoading
                                      ? tokens.textMuted
                                      : tokens.textPrimary,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: tokens.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const CadastroScreen(),
                                      ),
                                    );
                                  },
                            child: const Text(
                              'Não tem uma conta? Cadastre-se',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Versão $_versaoApp',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 12,
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
          if (_isLoading)
            Container(
              color: Colors.black.withAlpha(isDark ? 82 : 46),
              child: Center(
                child: Card(
                  color: tokens.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: tokens.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Entrando...',
                          style: TextStyle(color: tokens.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }
}
