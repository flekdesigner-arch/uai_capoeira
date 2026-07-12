import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ExclusaoEstudosResumo {
  final bool success;
  final String tipo;
  final String id;
  final int ciclosApagados;
  final int estudosApagados;
  final int perguntasApagadas;
  final int gabaritosApagados;
  final int tentativasApagadas;
  final int resultadosApagados;
  final int progressosApagados;

  const ExclusaoEstudosResumo({
    required this.success,
    required this.tipo,
    required this.id,
    required this.ciclosApagados,
    required this.estudosApagados,
    required this.perguntasApagadas,
    required this.gabaritosApagados,
    required this.tentativasApagadas,
    required this.resultadosApagados,
    required this.progressosApagados,
  });

  factory ExclusaoEstudosResumo.fromMap(Map<String, dynamic> data) {
    return ExclusaoEstudosResumo(
      success: data['success'] == true,
      tipo: _text(data['tipo']),
      id: _text(data['id']),
      ciclosApagados: _intValue(data['ciclosApagados']),
      estudosApagados: _intValue(data['estudosApagados']),
      perguntasApagadas: _intValue(data['perguntasApagadas']),
      gabaritosApagados: _intValue(data['gabaritosApagados']),
      tentativasApagadas: _intValue(data['tentativasApagadas']),
      resultadosApagados: _intValue(data['resultadosApagados']),
      progressosApagados: _intValue(data['progressosApagados']),
    );
  }

  String get textoResumo {
    final partes = <String>[];
    if (ciclosApagados > 0) partes.add('$ciclosApagados ciclo(s)');
    if (estudosApagados > 0) partes.add('$estudosApagados estudo(s)');
    if (perguntasApagadas > 0) partes.add('$perguntasApagadas pergunta(s)');
    if (gabaritosApagados > 0) partes.add('$gabaritosApagados gabarito(s)');
    if (tentativasApagadas > 0) partes.add('$tentativasApagadas tentativa(s)');
    if (resultadosApagados > 0) partes.add('$resultadosApagados resultado(s)');
    if (progressosApagados > 0) partes.add('$progressosApagados progresso(s)');
    return partes.isEmpty ? 'Nenhum documento apagado.' : partes.join(', ');
  }
}

class ExclusaoEstudosAdminService {
  static const String _functionName = 'excluirConteudoEstudosFundamentos';
  static const String _functionEndpoint =
      'https://us-central1-uai-capoeira-52753.cloudfunctions.net/$_functionName';

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final http.Client _httpClient;

  ExclusaoEstudosAdminService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    http.Client? httpClient,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _auth = auth ?? FirebaseAuth.instance,
       _httpClient = httpClient ?? http.Client();

  Future<ExclusaoEstudosResumo> excluir({
    required String tipo,
    required String id,
  }) async {
    final payload = {'tipo': tipo, 'id': id, 'confirmar': true};
    final data = _isWindowsDesktop
        ? await _callWindowsRest(payload)
        : await _callCallable(payload);
    return ExclusaoEstudosResumo.fromMap(data);
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
        throw Exception('Usuario nao autenticado para excluir conteudo.');
      }

      final response = await _httpClient.post(
        Uri.parse(_functionEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'data': payload}),
      );

      final decoded = _decodeResponseBody(response.body);
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
        throw Exception('Cloud Function retornou HTTP ${response.statusCode}.');
      }

      final result = decoded['result'];
      if (result is Map) return Map<String, dynamic>.from(result);
      throw Exception('Resposta invalida da Cloud Function.');
    } catch (error) {
      throw Exception(
        'Falha ao chamar a Cloud Function no Windows Desktop: $error',
      );
    }
  }

  Map<String, dynamic> _decodeResponseBody(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
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
