import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ImportarCicloCompletoResumo {
  final bool success;
  final String modo;
  final String cicloId;
  final String estudoId;
  final int ciclosCriados;
  final int estudosCriados;
  final int perguntasCriadas;
  final int gabaritosCriados;
  final int totalCriado;
  final String statusImportado;

  const ImportarCicloCompletoResumo({
    required this.success,
    required this.modo,
    required this.cicloId,
    required this.estudoId,
    required this.ciclosCriados,
    required this.estudosCriados,
    required this.perguntasCriadas,
    required this.gabaritosCriados,
    required this.totalCriado,
    required this.statusImportado,
  });

  factory ImportarCicloCompletoResumo.fromMap(Map<String, dynamic> data) {
    return ImportarCicloCompletoResumo(
      success: data['success'] == true,
      modo: _text(data['modo']),
      cicloId: _text(data['cicloId']),
      estudoId: _text(data['estudoId']),
      ciclosCriados: _intValue(data['ciclosCriados']),
      estudosCriados: _intValue(data['estudosCriados']),
      perguntasCriadas: _intValue(data['perguntasCriadas']),
      gabaritosCriados: _intValue(data['gabaritosCriados']),
      totalCriado: _intValue(data['totalCriado']),
      statusImportado: _text(data['statusImportado']).isEmpty
          ? 'rascunho'
          : _text(data['statusImportado']),
    );
  }
}

class ImportarCicloCompletoService {
  static const String _functionName = 'importarCicloCompletoEstudosFundamentos';
  static const String _functionEndpoint =
      'https://us-central1-uai-capoeira-52753.cloudfunctions.net/$_functionName';

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final http.Client _httpClient;

  ImportarCicloCompletoService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    http.Client? httpClient,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _auth = auth ?? FirebaseAuth.instance,
       _httpClient = httpClient ?? http.Client();

  Future<ImportarCicloCompletoResumo> importarCicloCompleto({
    required Map<String, dynamic> ciclo,
    required List<Map<String, dynamic>> estudos,
  }) {
    return importarConteudoEstudos(
      modo: 'novo_ciclo',
      ciclo: ciclo,
      estudos: estudos,
    );
  }

  Future<ImportarCicloCompletoResumo> importarConteudoEstudos({
    required String modo,
    Map<String, dynamic>? ciclo,
    List<Map<String, dynamic>>? estudos,
    List<Map<String, dynamic>>? perguntas,
    String? cicloIdExistente,
    String? estudoIdExistente,
  }) async {
    final payload = <String, dynamic>{'modo': modo, 'confirmar': true};
    if (ciclo != null) payload['ciclo'] = ciclo;
    if (estudos != null) payload['estudos'] = estudos;
    if (perguntas != null) payload['perguntas'] = perguntas;
    if (_text(cicloIdExistente).isNotEmpty) {
      payload['cicloIdExistente'] = _text(cicloIdExistente);
    }
    if (_text(estudoIdExistente).isNotEmpty) {
      payload['estudoIdExistente'] = _text(estudoIdExistente);
    }

    final data = _isWindowsDesktop
        ? await _callWindowsRest(payload)
        : await _callCallable(payload);
    return ImportarCicloCompletoResumo.fromMap(data);
  }

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<Map<String, dynamic>> _callCallable(
    Map<String, dynamic> payload,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(_functionName)
          .call(payload);
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw Exception(error.message ?? 'Cloud Function retornou erro.');
    }
  }

  Future<Map<String, dynamic>> _callWindowsRest(
    Map<String, dynamic> payload,
  ) async {
    try {
      final user = _auth.currentUser;
      final token = await user?.getIdToken(true);
      if (token == null || token.trim().isEmpty) {
        throw Exception('Usuario nao autenticado para importar conteudo.');
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
          'A funcao de importacao ainda nao esta publicada no Firebase. Faca o deploy da Function importarCicloCompletoEstudosFundamentos antes de usar esta ferramenta.',
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
      throw Exception('Resposta invalida da Cloud Function.');
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      throw Exception(message);
    }
  }

  Map<String, dynamic> _tryDecodeResponseBody(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw Exception('Resposta invalida da Cloud Function.');
    }
    throw Exception('Resposta invalida da Cloud Function.');
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
