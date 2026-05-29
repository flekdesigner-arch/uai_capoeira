// lib/services/validation_service.dart
class ValidationService {
  // Validação de email
  static bool isEmailValid(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+(?:\.[a-zA-Z]+)?$',
    );
    return emailRegex.hasMatch(email.trim());
  }

  // Validação de senha forte
  static bool isStrongPassword(String password) {
    if (password.length < 8) return false;

    // Deve conter pelo menos uma letra maiúscula
    if (!password.contains(RegExp(r'[A-Z]'))) return false;

    // Deve conter pelo menos uma letra minúscula
    if (!password.contains(RegExp(r'[a-z]'))) return false;

    // Deve conter pelo menos um número
    if (!password.contains(RegExp(r'[0-9]'))) return false;

    // Deve conter pelo menos um caractere especial
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return false;

    return true;
  }

  // Mensagem amigável para requisitos de senha
  static String getPasswordRequirements() {
    return 'Mínimo 8 caracteres, incluindo:\n'
        '• Letra maiúscula\n'
        '• Letra minúscula\n'
        '• Número\n'
        '• Caractere especial (!@#\$%^&*)';
  }

  // Validação de nome completo
  static bool isNameValid(String name) {
    name = name.trim();
    if (name.isEmpty) return false;
    if (name.length < 5) return false;
    if (!name.contains(' ')) return false; // Deve ter pelo menos um sobrenome
    return true;
  }

  // Validação de telefone
  static bool isPhoneValid(String phone) {
    // Remove formatação e mantém só números
    final numbersOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Aceita 10 (fixo) ou 11 (celular) dígitos
    return numbersOnly.length == 10 || numbersOnly.length == 11;
  }

  // Extrai apenas números do telefone
  static String extractPhoneNumbers(String phone) {
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }
}