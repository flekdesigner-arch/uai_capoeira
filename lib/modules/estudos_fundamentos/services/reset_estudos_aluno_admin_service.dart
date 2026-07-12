import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ResetEstudosAlunoResumo {
  final bool success;
  final String alunoId;
  final int progressoApagados;
  final int resultadosApagados;
  final int tentativasApagadas;
  final int totalApagado;

  const ResetEstudosAlunoResumo({
    required this.success,
    required this.alunoId,
    required this.progressoApagados,
    required this.resultadosApagados,
    required this.tentativasApagadas,
    required this.totalApagado,
  });

  factory ResetEstudosAlunoResumo.fromMap(Map<String, dynamic> data) {
    return ResetEstudosAlunoResumo(
      success: data['success'] == true,
      alunoId: _text(data['alunoId']),
      progressoApagados: _intValue(data['progressoApagados']),
      resultadosApagados: _intValue(data['resultadosApagados']),
      tentativasApagadas: _intValue(data['tentativasApagadas']),
      totalApagado: _intValue(data['totalApagado']),
    );
  }
}

class ResetEstudosAlunoAdminService {
  static const String _functionName = 'resetarProgressoEstudosAluno';
  static const String _functionEndpoint =
      'https://us-central1-uai-capoeira-52753.cloudfunctions.net/$_functionName';

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final http.Client _httpClient;

  ResetEstudosAlunoAdminService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    http.Client? httpClient,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _auth = auth ?? FirebaseAuth.instance,
       _httpClient = httpClient ?? http.Client();

  Future<ResetEstudosAlunoResumo> resetarEstudosAluno({
    required String alunoId,
  }) async {
    final id = alunoId.trim();
    if (id.isEmpty) {
      throw Exception('Aluno inválido para resetar estudos.');
    }
    final payload = {'alunoId': id, 'confirmar': true};
    final data = _isWindowsDesktop
        ? await _callWindowsRest(payload)
        : await _callCallable(payload);
    return ResetEstudosAlunoResumo.fromMap(data);
  }

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<Map<String, dynamic>> _callCallable(
    Map<String, dynamic> payload,
  ) async {
    final result = await _functions.httpsCallable(_functionName).call(payload);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> _callWindowsRest(
    Map<String, dynamic> payload,
  ) async {
    try {
      final user = _auth.currentUser;
      final token = await user?.getIdToken(true);
      if (token == null || token.trim().isEmpty) {
        throw Exception(
          'Usuário não autenticado para resetar estudos do aluno.',
        );
      }

      final response = await _httpClient.post(
        Uri.parse(_functionEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'data': payload}),
      );

      final contentType = response.headers['content-type'] ?? '';
      final body = response.body.trimLeft();
      final bodyEhHtml =
          body.toLowerCase().startsWith('<html') ||
          contentType.toLowerCase().contains('text/html');
      if (response.statusCode == 404 || bodyEhHtml) {
        throw Exception(
          'A função de reset ainda não está publicada no Firebase. Faça o deploy da Function resetarProgressoEstudosAluno antes de usar este botão.',
        );
      }

      final decoded = _tryDecodeResponseBody(response.body);
      final error = decoded['error'];
      if (error is Map) {
        final message = _text(error['message']);
        final status = _text(error['status']);
        throw Exception(
          message.isNotEmpty
              ? message
              : 'Cloud Function retornou erro${status.isEmpty ? '' : ' ($status)'}.',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Cloud Function retornou HTTP ${response.statusCode}. Tente novamente mais tarde.',
        );
      }

      final result = decoded['result'];
      if (result is Map) return Map<String, dynamic>.from(result);
      throw Exception('Resposta inválida da Cloud Function.');
    } catch (error) {
      throw Exception(
        'Falha ao chamar a Cloud Function no Windows Desktop: $error',
      );
    }
  }

  Map<String, dynamic> _tryDecodeResponseBody(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw Exception('Resposta inválida da Cloud Function.');
    }
    throw Exception('Resposta inválida da Cloud Function.');
  }
}

String _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return '';
  return text;
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}
