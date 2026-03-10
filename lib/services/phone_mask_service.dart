// lib/services/phone_mask_service.dart
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class PhoneMaskService {
  // Aplica máscara de telefone
  static String applyPhoneMask(String value) {
    // Remove tudo que não é número
    value = value.replaceAll(RegExp(r'[^\d]'), '');

    if (value.length > 11) value = value.substring(0, 11);

    if (value.isNotEmpty) {
      if (value.length <= 2) {
        return '($value';
      } else if (value.length <= 7) {
        return '(${value.substring(0, 2)}) ${value.substring(2)}';
      } else {
        return '(${value.substring(0, 2)}) ${value.substring(2, 7)}-${value.substring(7)}';
      }
    }
    return value;
  }

  // InputFormatter para usar diretamente no TextField
  static TextInputFormatter get phoneInputFormatter {
    return _PhoneMaskFormatter();
  }
}

// Formatter personalizado para máscara de telefone
class _PhoneMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    // Se apagou tudo, retorna vazio
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Aplica a máscara
    final masked = PhoneMaskService.applyPhoneMask(newValue.text);

    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}