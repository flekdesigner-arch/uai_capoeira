// lib/services/google_sheets_oauth_service.dart

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';

class GoogleSheetsOAuthService {
  static const String _spreadsheetId = '1twmPps17joiGtsCxzi3NYmMN0ql0gyti5J-PsaVd6ng';
  static const String _sheetName = 'BASE_NOMES';

  Future<Map<String, dynamic>> adicionarParticipantes(
      List<Map<String, dynamic>> participantes,
      ) async {
    try {
      debugPrint('📤 Carregando credenciais...');

      final jsonString = await rootBundle.loadString('assets/credentials.json');
      final credentials = ServiceAccountCredentials.fromJson(jsonString);
      const scopes = [SheetsApi.spreadsheetsScope];

      debugPrint('🔑 Autenticando...');
      final client = await clientViaServiceAccount(credentials, scopes);
      final sheets = SheetsApi(client);

      // 🔥 VERIFICAR SE A ABA EXISTE E CRIAR CABEÇALHO SE NECESSÁRIO
      debugPrint('🔍 Verificando se a aba "$_sheetName" existe...');

      try {
        // Tenta ler a célula A1 para ver se a aba existe
        final resposta = await sheets.spreadsheets.values.get(
            _spreadsheetId,
            '$_sheetName!A1:A1'
        );

        debugPrint('📊 Resposta da célula A1: ${resposta.values}');

        // Se não tem valor em A1, adiciona cabeçalho
        if (resposta.values == null || resposta.values!.isEmpty) {
          debugPrint('📝 Célula A1 vazia! Adicionando cabeçalho...');

          final cabecalho = BatchUpdateValuesRequest(
            data: [
              ValueRange(
                range: '$_sheetName!A1:C1',
                values: [['aluno_nome', 'cpf', 'graduacao_nova']],
              )
            ],
            valueInputOption: 'USER_ENTERED',
          );

          await sheets.spreadsheets.values.batchUpdate(cabecalho, _spreadsheetId);
          debugPrint('✅ Cabeçalho adicionado com sucesso!');
        } else {
          debugPrint('✅ Cabeçalho já existe: ${resposta.values!.first.first}');
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao acessar aba: $e');
        debugPrint('📝 Tentando criar a aba "$_sheetName"...');

        // Se a aba não existe, não podemos criá-la via API facilmente
        // Vamos apenas retornar erro pedindo para criar manualmente
        client.close();
        return {
          'sucesso': false,
          'mensagem': '❌ A aba "$_sheetName" não existe. Crie ela manualmente na planilha com os cabeçalhos: aluno_nome, cpf, graduacao_nova'
        };
      }

      // Prepara os dados dos participantes
      final List<List<Object>> valores = [];
      for (var p in participantes) {
        valores.add([
          p['aluno_nome'] ?? '',
          p['cpf'] ?? '0',
          p['graduacao_nova']?.isEmpty ?? true
              ? 'SEM GRADUAÇÃO'
              : p['graduacao_nova'],
        ]);
      }

      debugPrint('📤 Enviando ${valores.length} linha(s)...');

      // Encontra a última linha para adicionar após o cabeçalho
      final getData = await sheets.spreadsheets.values.get(
          _spreadsheetId,
          '$_sheetName!A:A'
      );

      int lastRow = getData.values?.length ?? 1;
      String range = '$_sheetName!A${lastRow + 1}:C${lastRow + valores.length}';

      debugPrint('📍 Adicionando na range: $range');

      // Cria a requisição de update (não append, para ter mais controle)
      final request = BatchUpdateValuesRequest(
        data: [
          ValueRange(
            range: range,
            values: valores,
          )
        ],
        valueInputOption: 'USER_ENTERED',
      );

      // Envia
      final resultado = await sheets.spreadsheets.values.batchUpdate(request, _spreadsheetId);
      debugPrint('✅ Dados enviados! ${resultado.totalUpdatedRows} linha(s) atualizada(s)');

      client.close();

      return {
        'sucesso': true,
        'mensagem': '✅ ${valores.length} participante(s) enviado(s)!'
      };
    } catch (e) {
      debugPrint('❌ ERRO GERAL: $e');
      return {
        'sucesso': false,
        'mensagem': 'Erro: $e'
      };
    }
  }

  static Future<Map<String, dynamic>> testarConexao() async {
    try {
      final jsonString = await rootBundle.loadString('assets/credentials.json');
      final credentials = ServiceAccountCredentials.fromJson(jsonString);
      const scopes = [SheetsApi.spreadsheetsScope];

      final client = await clientViaServiceAccount(credentials, scopes);
      final sheets = SheetsApi(client);

      // Tenta ler a aba para ver se existe
      try {
        final resposta = await sheets.spreadsheets.values.get(
            _spreadsheetId,
            '$_sheetName!A1:A1'
        );
        debugPrint('📊 Teste - Valor em A1: ${resposta.values}');
        client.close();
        return {'sucesso': true, 'mensagem': '✅ API funcionando!'};
      } catch (e) {
        client.close();
        return {
          'sucesso': false,
          'mensagem': '❌ Aba "$_sheetName" não encontrada. Crie ela manualmente na planilha.'
        };
      }
    } catch (e) {
      debugPrint('❌ Teste - Erro: $e');
      return {'sucesso': false, 'mensagem': 'Erro: $e'};
    }
  }
}