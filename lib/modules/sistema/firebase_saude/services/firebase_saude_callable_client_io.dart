import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FirebaseSaudeCallableException implements Exception {
  const FirebaseSaudeCallableException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callFirebaseSaudeCallable({
  required FirebaseFunctions functions,
  required String functionName,
  Map<String, dynamic> data = const <String, dynamic>{},
  String region = 'us-central1',
}) async {
  if (!_isDesktop) {
    final callable = functions.httpsCallable(functionName);
    final result = await callable.call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  return _callViaHttp(functionName: functionName, data: data, region: region);
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<Map<String, dynamic>> _callViaHttp({
  required String functionName,
  required Map<String, dynamic> data,
  required String region,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw const FirebaseSaudeCallableException('Usuário não autenticado.');
  }

  final idToken = await user.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const FirebaseSaudeCallableException('Usuário não autenticado.');
  }

  final projectId = Firebase.app().options.projectId.trim();
  if (projectId.isEmpty) {
    throw const FirebaseSaudeCallableException(
      'Não foi possível identificar o projeto Firebase.',
    );
  }

  final uri = Uri.https(
    '$region-$projectId.cloudfunctions.net',
    '/$functionName',
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
      _logHttpFailure(functionName, response.statusCode, response.body);
      throw const FirebaseSaudeCallableException(
        'Não foi possível carregar os dados do Firebase. Verifique se as '
        'funções foram publicadas e tente novamente.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      _logHttpFailure(functionName, response.statusCode, response.body);
      throw const FirebaseSaudeCallableException(
        'Não foi possível carregar os dados do Firebase. Verifique se as '
        'funções foram publicadas e tente novamente.',
      );
    }

    final responseMap = decoded.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );

    if (responseMap['error'] != null) {
      _logHttpFailure(functionName, response.statusCode, response.body);
      throw FirebaseSaudeCallableException(_errorMessage(responseMap['error']));
    }

    final payload = responseMap.containsKey('result')
        ? responseMap['result']
        : responseMap['data'];

    if (payload is Map) {
      return payload.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    _logHttpFailure(functionName, response.statusCode, response.body);
    throw const FirebaseSaudeCallableException(
      'Não foi possível carregar os dados do Firebase. Verifique se as '
      'funções foram publicadas e tente novamente.',
    );
  } on FirebaseSaudeCallableException {
    rethrow;
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
        'Firebase Saúde HTTP callable falhou em $functionName: $error',
      );
    }
    throw const FirebaseSaudeCallableException(
      'Não foi possível carregar os dados do Firebase. Verifique se as '
      'funções foram publicadas e tente novamente.',
    );
  }
}

String _errorMessage(Object? error) {
  if (error is Map) {
    final message = error['message']?.toString().trim();
    if (message != null && message.isNotEmpty) return message;
  }
  return 'Não foi possível carregar os dados do Firebase. Verifique se as '
      'funções foram publicadas e tente novamente.';
}

void _logHttpFailure(String functionName, int statusCode, String body) {
  if (!kDebugMode) return;
  debugPrint(
    'Firebase Saúde HTTP callable falhou: functionName=$functionName '
    'statusCode=$statusCode body=${_summarizeBody(body)}',
  );
}

String _summarizeBody(String body) {
  const maxLength = 800;
  if (body.length <= maxLength) return body;
  return '${body.substring(0, maxLength)}...';
}
