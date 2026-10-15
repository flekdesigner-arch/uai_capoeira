// lib/shared/services/google_sheets_oauth_service.dart
//
// PATCH SITE 13 - SEGURANÇA
// Credenciais de conta de serviço NUNCA ficam em assets do Flutter.
// Web/PWA, APK e Windows chamam a mesma Cloud Function autenticada.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class GoogleSheetsOAuthService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<Map<String, dynamic>> adicionarParticipantes(
    List<Map<String, dynamic>> participantes,
  ) async {
    try {
      final payload = participantes
          .map(
            (p) => <String, dynamic>{
              'aluno_nome': (p['aluno_nome'] ?? '').toString(),
              'cpf': (p['cpf'] ?? '0').toString(),
              'graduacao_nova': (p['graduacao_nova'] ?? '').toString(),
            },
          )
          .toList(growable: false);

      final callable =
          _functions.httpsCallable('adicionarParticipantesGoogleSheets');
      final result = await callable.call(<String, dynamic>{
        'participantes': payload,
      });

      final raw = result.data;
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }

      return const {
        'sucesso': false,
        'mensagem': 'Resposta inválida do servidor.',
      };
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Google Sheets callable falhou: ${e.code} - ${e.message}',
        );
      }
      return {
        'sucesso': false,
        'mensagem': e.message ?? 'Não foi possível enviar para a planilha.',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Google Sheets: erro inesperado: $e');
      }
      return const {
        'sucesso': false,
        'mensagem': 'Não foi possível enviar para a planilha.',
      };
    }
  }

  static Future<Map<String, dynamic>> testarConexao() async {
    try {
      final callable =
          _functions.httpsCallable('testarConexaoGoogleSheets');
      final result = await callable.call();

      final raw = result.data;
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }

      return const {
        'sucesso': false,
        'mensagem': 'Resposta inválida do servidor.',
      };
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Teste Google Sheets falhou: ${e.code} - ${e.message}',
        );
      }
      return {
        'sucesso': false,
        'mensagem': e.message ?? 'Não foi possível testar a planilha.',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Teste Google Sheets: erro inesperado: $e');
      }
      return const {
        'sucesso': false,
        'mensagem': 'Não foi possível testar a planilha.',
      };
    }
  }
}
