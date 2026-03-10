import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/validation_service.dart';
import '../../services/phone_mask_service.dart';
import '../../services/user_service.dart';

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
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text('Crie sua Conta'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.grey[800],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO
                Container(
                  margin: const EdgeInsets.only(bottom: 40),
                  child: Image.asset(
                    'assets/images/logo_uai.png',
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 120,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.sports_martial_arts,
                              size: 50,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'UAI\nCAPOEIRA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Nome Completo
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nome Completo *',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Digite seu nome completo (com sobrenome)',
                  ),
                  validator: (value) {
                    if (!ValidationService.isNameValid(value ?? '')) {
                      return 'Digite seu nome completo (mínimo 5 caracteres e sobrenome)';
                    }
                    return null;
                  },
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 20),

                // Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email *',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Ex: nome@email.com',
                  ),
                  validator: (value) {
                    if (!ValidationService.isEmailValid(value ?? '')) {
                      return 'Digite um email válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Telefone com máscara
                TextFormField(
                  controller: _contatoController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Telefone (WhatsApp) *',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: '(38) 99999-9999',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'DDD + número (10 ou 11 dígitos)',
                  ),
                  inputFormatters: [
                    PhoneMaskService.phoneInputFormatter,
                  ],
                  validator: (value) {
                    if (!ValidationService.isPhoneValid(value ?? '')) {
                      return 'Digite um telefone válido (DDD + número)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Senha
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Senha *',
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
                    helperText: ValidationService.getPasswordRequirements(),
                  ),
                  validator: (value) {
                    if (!ValidationService.isStrongPassword(value ?? '')) {
                      return 'Siga os requisitos de senha forte';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Confirmar Senha
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: !_isConfirmPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Confirmar Senha *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'As senhas não coincidem';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                // Botão de Cadastro
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _cadastrar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'CADASTRAR',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // Informação sobre aprovação
                Container(
                  margin: const EdgeInsets.only(top: 30),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                      const SizedBox(height: 8),
                      Text(
                        'Sua conta será analisada por um administrador antes de ser ativada.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade800,
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
    );
  }

  Future<void> _cadastrar() async {
    // Validar formulário
    if (!_formKey.currentState!.validate()) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. Criar usuário no Firebase Auth
      final UserCredential userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (userCredential.user != null) {
        final user = userCredential.user!;

        // 2. Salvar no Firestore usando o serviço
        await UserService.createOrUpdateUserDocument(
          user: user,
          nomeCompleto: _nameController.text.trim(),
          contato: ValidationService.extractPhoneNumbers(_contatoController.text),
        );
      }

      if (mounted) Navigator.pop(context); // Fecha o progresso

      // Mostrar mensagem de sucesso amigável
      if (mounted) {
        _showSuccessDialog();
      }

    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.pop(context);

      String errorMessage = _getFriendlyErrorMessage(e.code);

      _showErrorSnackBar(errorMessage);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorSnackBar('Ocorreu um erro inesperado. Tente novamente.');
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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
              Navigator.pop(context); // Fecha o alerta
              Navigator.pop(context); // Volta para login
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade900,
            ),
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
    super.dispose();
  }
}