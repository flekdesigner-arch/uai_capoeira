import 'package:cloud_functions/cloud_functions.dart';

import 'package:uai_capoeira/modules/sistema/firebase_saude/models/firebase_saude_models.dart';
import 'package:uai_capoeira/modules/sistema/firebase_saude/services/firebase_saude_callable_client.dart';

class FirebaseSaudeService {
  FirebaseSaudeService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  static const String _region = 'us-central1';

  final FirebaseFunctions _functions;

  Future<FirebaseSaudeResumo> obterResumo() async {
    final data = await _call('obterResumoSaudeFirebase');
    return FirebaseSaudeResumo.fromMap(data);
  }

  Future<List<FirebaseSaudeColecao>> listarColecoes() async {
    final data = await _call('listarColecoesFirebaseSaude');
    final colecoes = data['colecoes'];
    if (colecoes is! List) return const <FirebaseSaudeColecao>[];
    return colecoes
        .whereType<Map>()
        .map(
          (item) => FirebaseSaudeColecao.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<FirebaseSaudeDocumentosPage> listarDocumentos({
    required String colecao,
    int limit = 25,
    String? startAfter,
    String? filtro,
  }) async {
    final data = await _call('listarDocumentosColecaoFirebaseSaude', <
      String,
      dynamic
    >{
      'colecao': colecao,
      'limit': limit,
      if (startAfter != null && startAfter.isNotEmpty) 'startAfter': startAfter,
      if (filtro != null && filtro.trim().isNotEmpty) 'filtro': filtro.trim(),
    });
    return FirebaseSaudeDocumentosPage.fromMap(data);
  }

  Future<FirebaseSaudeDocumento> obterDocumento({
    required String colecao,
    required String docId,
  }) async {
    final data = await _call('obterDocumentoFirebaseSaude', <String, dynamic>{
      'colecao': colecao,
      'docId': docId,
    });
    return FirebaseSaudeDocumento.fromMap(data);
  }

  Future<List<FirebaseSaudeStorageItem>> listarStorage({
    String? prefixo,
    int limit = 40,
    String? pageToken,
  }) async {
    final data =
        await _call('listarArquivosStorageFirebaseSaude', <String, dynamic>{
          'limit': limit,
          if (prefixo != null && prefixo.isNotEmpty) 'prefixo': prefixo,
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        });
    final arquivos = data['arquivos'];
    if (arquivos is! List) return const <FirebaseSaudeStorageItem>[];
    return arquivos
        .whereType<Map>()
        .map(
          (item) => FirebaseSaudeStorageItem.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<List<FirebaseSaudeFunctionInfo>> listarFunctions() async {
    final data = await _call('listarFunctionsFirebaseSaude');
    final functions = data['functions'];
    if (functions is! List) return const <FirebaseSaudeFunctionInfo>[];
    return functions
        .whereType<Map>()
        .map(
          (item) => FirebaseSaudeFunctionInfo.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic>? payload,
  ]) async {
    return callFirebaseSaudeCallable(
      functions: _functions,
      functionName: name,
      data: payload ?? const <String, dynamic>{},
      region: _region,
    );
  }
}
