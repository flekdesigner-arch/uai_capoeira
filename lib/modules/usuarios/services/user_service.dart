// lib/services/user_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserService {
  static Future<Map<String, dynamic>> ensureInitialUserProfile(
    User user, {
    String? nomeCompleto,
    String? contato,
    bool isGoogleLogin = false,
    String origem = 'auth',
    String? plataforma,
  }) async {
    final provider = isGoogleLogin ? 'google.com' : 'password';

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'criarPerfilUsuarioInicial',
      );

      final result = await callable.call({
        'nome': nomeCompleto ?? user.displayName ?? '',
        'email': user.email ?? '',
        'fotoUrl': user.photoURL ?? '',
        'contato': contato ?? '',
        'provider': provider,
        'origem': origem,
        if (plataforma != null && plataforma.isNotEmpty)
          'plataforma': plataforma,
      });

      return Map<String, dynamic>.from(result.data as Map);
    } catch (e, stack) {
      debugPrint('Erro ao preparar perfil inicial do usuario ${user.uid}: $e');
      debugPrintStack(stackTrace: stack);
      rethrow;
    }
  }

  // Mantem a API usada pelas telas, mas a criacao/update seguro agora fica na Function.
  static Future<void> createOrUpdateUserDocument({
    required User user,
    String? nomeCompleto,
    String? contato,
    bool isGoogleLogin = false,
  }) async {
    await ensureInitialUserProfile(
      user,
      nomeCompleto: nomeCompleto,
      contato: contato,
      isGoogleLogin: isGoogleLogin,
      origem: isGoogleLogin ? 'login_google' : 'cadastro',
    );
  }

  // Verifica se o usuario tem permissao para acessar
  static Future<bool> hasAccess(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final status = doc.data()?['status_conta'] as String?;
      return status == 'ativa';
    } catch (e) {
      debugPrint('Erro ao verificar acesso do usuario: $e');
      return false;
    }
  }
}
