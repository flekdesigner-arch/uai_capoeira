import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'cadastro_screen.dart';
import '../../screens/auth/auth_check.dart';
import '../../config/app_config.dart';
import '../../services/user_service.dart';
import '../../services/validation_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  // Login com Email/Senha
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;

      // Verificar se usuário tem acesso
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final hasAccess = await UserService.hasAccess(user.uid);

        if (!hasAccess) {
          // Mostrar mensagem amigável para contas pendentes/bloqueadas
          _showPendingAccountDialog();
          return;
        }
      }

      // Login bem-sucedido
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthCheck()),
      );

    } on FirebaseAuthException catch (e) {
      _handleLoginError(e);
    } catch (e) {
      _showErrorSnackBar('Ocorreu um erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLoginError(FirebaseAuthException e) {
    String message;

    switch (e.code) {
      case 'user-not-found':
        message = 'Usuário não encontrado. Verifique seu email.';
        break;
      case 'wrong-password':
        message = 'Senha incorreta. Tente novamente.';
        break;
      case 'invalid-email':
        message = 'Formato de email inválido.';
        break;
      case 'user-disabled':
        message = 'Esta conta está desativada. Entre em contato com o suporte.';
        break;
      case 'too-many-requests':
        message = 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
        break;
      case 'network-request-failed':
        message = 'Sem conexão com a internet. Verifique sua rede.';
        break;
      default:
        message = 'Erro ao fazer login. Tente novamente.';
    }

    _showErrorSnackBar(message);
  }

  // Login com Google
  Future<void> _loginComGoogle() async {
    setState(() => _isLoading = true);

    try {
      // Configuração específica para Web
      final GoogleSignIn _googleSignIn = kIsWeb
          ? GoogleSignIn(clientId: AppConfig.googleWebClientId)
          : GoogleSignIn();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return; // Usuário cancelou
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user!;

      // Usa o serviço unificado para criar/atualizar documento
      await UserService.createOrUpdateUserDocument(
        user: user,
        isGoogleLogin: true,
      );

      if (!mounted) return;

      // Verificar acesso
      final hasAccess = await UserService.hasAccess(user.uid);

      if (!hasAccess) {
        _showPendingAccountDialog();
        return;
      }

      // Login bem-sucedido
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthCheck()),
      );

    } on FirebaseAuthException catch (e) {
      String message = 'Erro no login com Google';
      if (e.code == 'account-exists-with-different-credential') {
        message = 'Já existe uma conta com este email. Use outro método de login.';
      }
      _showErrorSnackBar(message);
    } catch (e) {
      _showErrorSnackBar('Erro ao conectar com Google. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Fecha dialog
              FirebaseAuth.instance.signOut(); // Faz logout
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade900,
            ),
            child: const Text('VOLTAR'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Container(
                      margin: const EdgeInsets.only(bottom: 40),
                      child: Image.asset(
                        'assets/images/logo_uai.png',
                        height: 150,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) {
                          return Column(
                            children: [
                              Icon(
                                Icons.sports_martial_arts,
                                size: 100,
                                color: Colors.red.shade900,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'UAI CAPOEIRA',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Campo de Email
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (!ValidationService.isEmailValid(value ?? '')) {
                          return 'Digite um email válido';
                        }
                        return null;
                      },
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 20),

                    // Campo de Senha
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Digite sua senha';
                        }
                        return null;
                      },
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 10),

                    // Link "Esqueceu a senha?"
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading ? null : () {
                          // TODO: Implementar recuperação de senha
                        },
                        child: Text(
                          'Esqueceu a senha?',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Botão de Login
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Text(
                          'ENTRAR',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Divisor "OU"
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey[400])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OU',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Botão do Google
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _loginComGoogle,
                        icon: Image.asset(
                          'assets/images/google_logo.png',
                          height: 24,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.g_mobiledata,
                              size: 28,
                              color: Colors.blue,
                            );
                          },
                        ),
                        label: Text(
                          'CONTINUAR COM GOOGLE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: _isLoading ? Colors.grey : Colors.grey[800],
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[800],
                          side: BorderSide(color: Colors.grey[400]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Link para cadastro
                    TextButton(
                      onPressed: _isLoading ? null : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CadastroScreen()),
                        );
                      },
                      child: Text(
                        'Não tem uma conta? Cadastre-se',
                        style: TextStyle(
                          color: _isLoading ? Colors.grey : Colors.grey[800],
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Versão do app
                    Text(
                      'v1.0.0',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Overlay de loading para toda a tela
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Aguarde...'),
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
    super.dispose();
  }
}