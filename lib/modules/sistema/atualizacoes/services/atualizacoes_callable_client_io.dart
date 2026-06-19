import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AtualizacoesCallableException implements Exception {
  const AtualizacoesCallableException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callNotifyNewAppVersion(
  Map<String, dynamic> data,
) async {
  if (!_isDesktop) {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('notifyNewAppVersion');
    final result = await callable.call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  return _callViaHttp(data);
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<Map<String, dynamic>> _callViaHttp(Map<String, dynamic> data) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw const AtualizacoesCallableException(
      'Usuário não autenticado. Faça login novamente.',
    );
  }

  final idToken = await user.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const AtualizacoesCallableException(
      'Usuário não autenticado. Faça login novamente.',
    );
  }

  final projectId = Firebase.app().options.projectId.trim();
  if (projectId.isEmpty) {
    throw const AtualizacoesCallableException(
      'Não foi possível identificar o projeto Firebase.',
    );
  }

  final uri = Uri.https(
    'us-central1-$projectId.cloudfunctions.net',
    '/notifyNewAppVersion',
  );

  try {
    final response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(<String, dynamic>{'data': data}),
    );

    if (response.statusCode != 200) {
      _logHttpFailure(response.statusCode, response.body);
      throw const AtualizacoesCallableException(
        'Não foi possível enviar a notificação. Verifique as funções '
        'publicadas e tente novamente.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      _logHttpFailure(response.statusCode, response.body);
      throw const AtualizacoesCallableException(
        'Não foi possível enviar a notificação. Verifique as funções '
        'publicadas e tente novamente.',
      );
    }

    final responseMap = decoded.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );

    if (responseMap['error'] != null) {
      _logHttpFailure(response.statusCode, response.body);
      throw AtualizacoesCallableException(
        _callableErrorMessage(responseMap['error']),
      );
    }

    final payload = responseMap.containsKey('result')
        ? responseMap['result']
        : responseMap['data'];

    if (payload is Map) {
      return payload.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    _logHttpFailure(response.statusCode, response.body);
    throw const AtualizacoesCallableException(
      'Não foi possível enviar a notificação. Verifique as funções publicadas '
      'e tente novamente.',
    );
  } on AtualizacoesCallableException {
    rethrow;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('notifyNewAppVersion HTTP callable falhou: $error');
    }
    throw const AtualizacoesCallableException(
      'Não foi possível enviar a notificação. Verifique as funções publicadas '
      'e tente novamente.',
    );
  }
}

String _callableErrorMessage(Object? error) {
  if (error is Map) {
    final code = error['code']?.toString().trim();
    final message = error['message']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      if (code != null && code.isNotEmpty) return '$message ($code)';
      return message;
    }
    if (code != null && code.isNotEmpty) return code;
  }

  return 'Não foi possível enviar a notificação. Verifique as funções '
      'publicadas e tente novamente.';
}

void _logHttpFailure(int statusCode, String body) {
  if (!kDebugMode) return;
  debugPrint(
    'notifyNewAppVersion HTTP callable falhou: statusCode=$statusCode '
    'body=${_summarizeBody(body)}',
  );
}

String _summarizeBody(String body) {
  const maxLength = 800;
  if (body.length <= maxLength) return body;
  return '${body.substring(0, maxLength)}...';
}
