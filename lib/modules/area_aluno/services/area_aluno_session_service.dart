import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AreaAlunoSessionService {
  static const String _sessionKey = 'uai_area_aluno_session_v1';

  /// Tempo máximo para manter a sessão simples do aluno.
  /// Mesmo com sessão salva, a Cloud Function é chamada novamente para revalidar.
  static const Duration _validade = Duration(days: 30);

  Future<void> salvarSessao({
    required Map<String, dynamic> aluno,
    required Map<String, dynamic> config,
    required Map<String, dynamic> authPayload,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final agora = DateTime.now();
    final alunoId = aluno['id']?.toString() ?? aluno['docId']?.toString() ?? '';

    final payload = {
      'versao': 1,
      'aluno_id': alunoId,
      'aluno_nome': aluno['nome']?.toString() ?? '',
      'authPayload': authPayload,
      'alunoCache': aluno,
      'configCache': config,
      'loginEm': agora.toIso8601String(),
      'expiraEm': agora.add(_validade).toIso8601String(),
    };

    await prefs.setString(_sessionKey, jsonEncode(payload));

    debugPrint('✅ Sessão da Área do Aluno salva localmente: $alunoId');
  }

  Future<Map<String, dynamic>?> lerSessaoBruta() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);

    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final data = jsonDecode(raw);

      if (data is! Map) return null;

      final map = Map<String, dynamic>.from(data);
      final expiraEm = DateTime.tryParse(map['expiraEm']?.toString() ?? '');

      if (expiraEm == null || DateTime.now().isAfter(expiraEm)) {
        await limparSessao();
        return null;
      }

      return map;
    } catch (e) {
      debugPrint('⚠️ Erro ao ler sessão da Área do Aluno: $e');
      await limparSessao();
      return null;
    }
  }

  Future<bool> temSessaoValidaLocal() async {
    final sessao = await lerSessaoBruta();
    return sessao != null;
  }

  Future<Map<String, dynamic>?> restaurarSessaoRevalidando() async {
    final sessao = await lerSessaoBruta();

    if (sessao == null) return null;

    final authRaw = sessao['authPayload'];
    if (authRaw is! Map) {
      await limparSessao();
      return null;
    }

    final authPayload = Map<String, dynamic>.from(authRaw);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'validarAcessoAreaAluno',
      );

      final result = await callable.call({
        'dataNascimento': authPayload['dataNascimento']?.toString() ?? '',
        'iniciais': authPayload['iniciais']?.toString() ?? '',
        'telefoneFinal': authPayload['telefoneFinal']?.toString() ?? '',
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final success = data['success'] == true;

      if (!success) {
        debugPrint('⚠️ Sessão da Área do Aluno não foi revalidada.');
        await limparSessao();
        return null;
      }

      final aluno = Map<String, dynamic>.from(data['aluno'] as Map? ?? {});
      final config = Map<String, dynamic>.from(data['config'] as Map? ?? {});

      await salvarSessao(
        aluno: aluno,
        config: config,
        authPayload: authPayload,
      );

      return {
        'aluno': aluno,
        'config': config,
        'authPayload': authPayload,
      };
    } catch (e) {
      debugPrint('⚠️ Erro ao revalidar sessão da Área do Aluno: $e');

      // Se não conseguir revalidar por internet/instabilidade, usa cache local.
      // O próximo acesso tenta revalidar novamente.
      final alunoCacheRaw = sessao['alunoCache'];
      final configCacheRaw = sessao['configCache'];

      if (alunoCacheRaw is Map && configCacheRaw is Map) {
        return {
          'aluno': Map<String, dynamic>.from(alunoCacheRaw),
          'config': Map<String, dynamic>.from(configCacheRaw),
          'authPayload': authPayload,
          'offline': true,
        };
      }

      return null;
    }
  }

  Future<void> limparSessao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    debugPrint('🚪 Sessão da Área do Aluno removida.');
  }
}
