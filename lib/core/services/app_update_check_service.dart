// lib/core/services/app_update_check_service.dart
//
// =====================================================
// 🛡️ SERVIÇO DE VERIFICAÇÃO/BLOQUEIO DE VERSÃO
// =====================================================
//
// Este service é a ponte entre o app do usuário e o Laboratório
// de Atualizações.
//
// Ele lê:
//
// configuracoes/app
//   versao_atual
//   versao_minima_obrigatoria
//   atualizacao_obrigatoria
//   ultima_versao_id
//   titulo_atualizacao
//   mensagem_atualizacao
//   apk_path
//   apk_url
//
// E tenta buscar também:
//
// versoes_app/{ultima_versao_id}
//
// Resultado:
// - sabe se existe atualização opcional;
// - sabe se existe atualização obrigatória;
// - sabe se precisa bloquear o uso;
// - devolve dados para uma tela/diálogo de atualização.
//
// Próximo passo depois deste arquivo:
// - criar o widget/tela de bloqueio UpdateGate;
// - depois encaixar no main.dart/Home.
// =====================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class AppUpdateCheckService {
  AppUpdateCheckService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String configCollection = 'configuracoes';
  static const String configAppDoc = 'app';
  static const String versoesCollection = 'versoes_app';

  // =====================================================
  // 📱 VERSÃO LOCAL
  // =====================================================
  Future<String> getVersaoLocal() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      debugPrint('❌ AppUpdateCheckService: erro ao obter versão local: $e');
      return '1.0.0';
    }
  }

  Future<int> getBuildLocal() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (e) {
      debugPrint('❌ AppUpdateCheckService: erro ao obter build local: $e');
      return 0;
    }
  }

  // =====================================================
  // 🔎 VERIFICAR STATUS DA ATUALIZAÇÃO
  // =====================================================
  Future<AppUpdateStatus> verificarStatus() async {
    final versaoLocal = await getVersaoLocal();
    final buildLocal = await getBuildLocal();

    try {
      final configDoc = await _firestore
          .collection(configCollection)
          .doc(configAppDoc)
          .get(const GetOptions(source: Source.server));

      final config = configDoc.data() ?? {};

      final versaoAtualServidor =
      (config['versao_atual'] ?? '').toString().trim();

      if (versaoAtualServidor.isEmpty) {
        return AppUpdateStatus.semConfiguracao(
          versaoLocal: versaoLocal,
          buildLocal: buildLocal,
        );
      }

      final ultimaVersaoId =
      (config['ultima_versao_id'] ?? '').toString().trim();

      final versaoMinimaObrigatoria =
      (config['versao_minima_obrigatoria'] ?? '').toString().trim();

      final atualizacaoObrigatoria =
          config['atualizacao_obrigatoria'] == true;

      final precisaAtualizar = AppVersionModel.precisaAtualizar(
        versaoLocal: versaoLocal,
        versaoRemota: versaoAtualServidor,
      );

      final estaAbaixoDaMinima = versaoMinimaObrigatoria.isNotEmpty
          ? AppVersionModel.precisaAtualizar(
        versaoLocal: versaoLocal,
        versaoRemota: versaoMinimaObrigatoria,
      )
          : false;

      final deveBloquear = atualizacaoObrigatoria && estaAbaixoDaMinima;

      AppVersionModel? versionModel;

      if (ultimaVersaoId.isNotEmpty) {
        versionModel = await _buscarVersaoPorId(ultimaVersaoId);
      }

      versionModel ??= await _buscarVersaoPorVersao(versaoAtualServidor);

      final titulo = versionModel?.titulo.trim().isNotEmpty == true
          ? versionModel!.titulo
          : (config['titulo_atualizacao'] ?? 'Nova versão disponível')
          .toString();

      final mensagem = versionModel?.resumo.trim().isNotEmpty == true
          ? versionModel!.resumo
          : (config['mensagem_atualizacao'] ??
          'Atualize para receber melhorias e correções.')
          .toString();

      final apkPath = versionModel?.storagePath.trim().isNotEmpty == true
          ? versionModel!.storagePath
          : (config['apk_path'] ?? '').toString();

      final apkUrl = versionModel?.downloadUrl.trim().isNotEmpty == true
          ? versionModel!.downloadUrl
          : (config['apk_url'] ?? '').toString();

      return AppUpdateStatus(
        carregou: true,
        erro: null,
        versaoLocal: versaoLocal,
        buildLocal: buildLocal,
        versaoServidor: versaoAtualServidor,
        versaoMinimaObrigatoria: versaoMinimaObrigatoria,
        precisaAtualizar: precisaAtualizar,
        atualizacaoObrigatoria: atualizacaoObrigatoria,
        deveBloquear: deveBloquear,
        titulo: titulo,
        mensagem: mensagem,
        apkPath: apkPath,
        apkUrl: apkUrl,
        versionModel: versionModel,
        config: config,
      );
    } catch (e) {
      debugPrint('❌ AppUpdateCheckService: erro ao verificar status: $e');

      return AppUpdateStatus.erro(
        versaoLocal: versaoLocal,
        buildLocal: buildLocal,
        erro: e.toString(),
      );
    }
  }

  Future<AppVersionModel?> _buscarVersaoPorId(String versionId) async {
    try {
      final doc = await _firestore
          .collection(versoesCollection)
          .doc(versionId)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) return null;

      return AppVersionModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('⚠️ AppUpdateCheckService: erro ao buscar versão por id: $e');
      return null;
    }
  }

  Future<AppVersionModel?> _buscarVersaoPorVersao(String versao) async {
    try {
      final id = AppVersionModel.gerarVersionId(versao);

      if (id.isEmpty) return null;

      return _buscarVersaoPorId(id);
    } catch (e) {
      debugPrint('⚠️ AppUpdateCheckService: erro ao buscar versão por número: $e');
      return null;
    }
  }
}

// =====================================================
// 📦 STATUS DA ATUALIZAÇÃO
// =====================================================
class AppUpdateStatus {
  final bool carregou;
  final String? erro;

  final String versaoLocal;
  final int buildLocal;

  final String versaoServidor;
  final String versaoMinimaObrigatoria;

  final bool precisaAtualizar;
  final bool atualizacaoObrigatoria;
  final bool deveBloquear;

  final String titulo;
  final String mensagem;

  final String apkPath;
  final String apkUrl;

  final AppVersionModel? versionModel;
  final Map<String, dynamic> config;

  const AppUpdateStatus({
    required this.carregou,
    required this.erro,
    required this.versaoLocal,
    required this.buildLocal,
    required this.versaoServidor,
    required this.versaoMinimaObrigatoria,
    required this.precisaAtualizar,
    required this.atualizacaoObrigatoria,
    required this.deveBloquear,
    required this.titulo,
    required this.mensagem,
    required this.apkPath,
    required this.apkUrl,
    required this.versionModel,
    required this.config,
  });

  factory AppUpdateStatus.semConfiguracao({
    required String versaoLocal,
    required int buildLocal,
  }) {
    return AppUpdateStatus(
      carregou: true,
      erro: null,
      versaoLocal: versaoLocal,
      buildLocal: buildLocal,
      versaoServidor: '',
      versaoMinimaObrigatoria: '',
      precisaAtualizar: false,
      atualizacaoObrigatoria: false,
      deveBloquear: false,
      titulo: 'App atualizado',
      mensagem: 'Nenhuma configuração de atualização foi encontrada.',
      apkPath: '',
      apkUrl: '',
      versionModel: null,
      config: const {},
    );
  }

  factory AppUpdateStatus.erro({
    required String versaoLocal,
    required int buildLocal,
    required String erro,
  }) {
    return AppUpdateStatus(
      carregou: false,
      erro: erro,
      versaoLocal: versaoLocal,
      buildLocal: buildLocal,
      versaoServidor: '',
      versaoMinimaObrigatoria: '',
      precisaAtualizar: false,
      atualizacaoObrigatoria: false,
      deveBloquear: false,
      titulo: 'Não foi possível verificar atualização',
      mensagem: erro,
      apkPath: '',
      apkUrl: '',
      versionModel: null,
      config: const {},
    );
  }

  bool get estaAtualizado => !precisaAtualizar && !deveBloquear;

  bool get temApkConfigurado => apkPath.trim().isNotEmpty || apkUrl.trim().isNotEmpty;

  String get statusLabel {
    if (deveBloquear) return 'Obrigatória';
    if (precisaAtualizar) return 'Opcional';
    if (!carregou) return 'Erro';
    return 'Atualizado';
  }

  String get versaoDestino {
    if (versaoServidor.trim().isNotEmpty) return versaoServidor;
    return versaoLocal;
  }

  List<String> get melhorias => versionModel?.melhorias ?? const [];
  List<String> get correcoes => versionModel?.correcoes ?? const [];
  List<String> get implementacoes => versionModel?.implementacoes ?? const [];
  List<String> get removidos => versionModel?.removidos ?? const [];
}
