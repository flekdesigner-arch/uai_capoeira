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
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';
import 'package:uai_capoeira/core/services/uai_callable_client.dart';

class AppUpdateCheckService {
  AppUpdateCheckService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

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
    final buildLocalRaw = await getBuildLocal();
    // --split-per-abi altera versionCode do APK (base+1000/2000/4000).
    // O Firestore/release V3 guarda o build-base, não o código por ABI.
    var buildLocal = buildLocalRaw;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
        final abi = abis.firstWhere(
          (item) => const ['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(item),
          orElse: () => '',
        );
        final offset = switch (abi) {
          'armeabi-v7a' => 1000,
          'arm64-v8a' => 2000,
          'x86_64' => 4000,
          _ => 0,
        };
        if (offset > 0 && buildLocalRaw > offset) {
          buildLocal = buildLocalRaw - offset;
        }
      } catch (e) {
        debugPrint('Update: não foi possível normalizar build por ABI: $e');
      }
    }

    try {
      final configDoc = await _firestore
          .collection(configCollection)
          .doc(configAppDoc)
          .get(const GetOptions(source: Source.server));
      final config = configDoc.data() ?? {};

      AppVersionModel? versionModel;
      String canal = 'producao';
      bool resolverV3Respondeu = false;
      bool releaseIncompativel = false;
      try {
        final payload = <String, dynamic>{'versaoLocal': versaoLocal, 'buildLocal': buildLocal};
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          try {
            final android = await DeviceInfoPlugin().androidInfo;
            payload['androidSdk'] = android.version.sdkInt;
            payload['abis'] = android.supportedAbis;
          } catch (_) {}
        }
        final map = await UaiCallableClient.instance.call(
          'resolverAtualizacaoDisponivelV3',
          payload,
        );
        if (map.isNotEmpty) {
          resolverV3Respondeu = true;
          releaseIncompativel = map['incompatible'] == true;
          if (map['release'] is Map) {
            versionModel = AppVersionModel.fromMap(
              Map<String, dynamic>.from(map['release'] as Map),
              fallbackId: (map['release'] as Map)['versionId']?.toString(),
            );
            canal = versionModel.canal;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Resolver V3 indisponível, usando produção legada: $e');
      }

      final versaoProducao = (config['versao_atual'] ?? '').toString().trim();
      if (resolverV3Respondeu && releaseIncompativel && versionModel == null) {
        return AppUpdateStatus(
          carregou: true, erro: null, versaoLocal: versaoLocal, buildLocal: buildLocal,
          versaoServidor: versaoProducao, versaoMinimaObrigatoria: '', precisaAtualizar: false,
          atualizacaoObrigatoria: false, deveBloquear: false,
          titulo: 'Versão atual incompatível com este dispositivo',
          mensagem: 'A atualização disponível não é compatível com este aparelho ou com a versão instalada.',
          apkPath: '', apkUrl: '', versionModel: null, config: config, canal: 'producao',
        );
      }
      final versaoServidor = versionModel?.versao.trim().isNotEmpty == true
          ? versionModel!.versao.trim()
          : versaoProducao;
      if (versaoServidor.isEmpty) {
        return AppUpdateStatus.semConfiguracao(versaoLocal: versaoLocal, buildLocal: buildLocal);
      }

      final versaoMinimaObrigatoria = (config['versao_minima_obrigatoria'] ?? '').toString().trim();
      final precisaAtualizarVersao = AppVersionModel.precisaAtualizar(versaoLocal: versaoLocal, versaoRemota: versaoServidor);
      final estaAbaixoDaMinima = versaoMinimaObrigatoria.isNotEmpty
          ? AppVersionModel.precisaAtualizar(versaoLocal: versaoLocal, versaoRemota: versaoMinimaObrigatoria)
          : false;

      if (versionModel == null) {
        final ultimaVersaoId = (config['ultima_versao_id'] ?? '').toString().trim();
        if (ultimaVersaoId.isNotEmpty) versionModel = await _buscarVersaoPorId(ultimaVersaoId);
        versionModel ??= await _buscarVersaoPorVersao(versaoServidor);
        canal = versionModel?.canal ?? canal;
      }

      // O canal efetivo só está decidido após resolver a versão no histórico.
      final atualizacaoObrigatoria = canal == 'producao' &&
          config['atualizacao_obrigatoria'] == true;
      final deveBloquear = atualizacaoObrigatoria && estaAbaixoDaMinima;

      // Mesmo número semântico pode receber um novo APK assinado com build
      // maior. O resolvedor V3 diferencia versionName e versionCode.
      final buildServidor = versionModel?.build ??
          int.tryParse('${config['build_atual'] ?? 0}') ?? 0;
      final precisaAtualizar = precisaAtualizarVersao ||
          (versaoServidor == versaoLocal && buildServidor > buildLocal);

      final titulo = versionModel?.titulo.trim().isNotEmpty == true
          ? versionModel!.titulo
          : (canal == 'beta'
              ? 'Atualização BETA disponível'
              : (canal == 'teste_interno' ? 'Atualização de TESTE INTERNO disponível' : (config['titulo_atualizacao'] ?? 'Nova versão disponível').toString()));
      final mensagem = versionModel?.resumo.trim().isNotEmpty == true
          ? versionModel!.resumo
          : (config['mensagem_atualizacao'] ?? 'Atualize para receber melhorias e correções.').toString();
      final apkPath = versionModel?.storagePath.trim().isNotEmpty == true ? versionModel!.storagePath : (config['apk_path'] ?? '').toString();
      final apkUrl = versionModel?.downloadUrl.trim().isNotEmpty == true ? versionModel!.downloadUrl : (config['apk_url'] ?? '').toString();

      return AppUpdateStatus(
        carregou: true,
        erro: null,
        versaoLocal: versaoLocal,
        buildLocal: buildLocal,
        versaoServidor: versaoServidor,
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
        canal: canal,
      );
    } catch (e) {
      debugPrint('❌ AppUpdateCheckService: erro ao verificar status: $e');
      return AppUpdateStatus.erro(versaoLocal: versaoLocal, buildLocal: buildLocal, erro: e.toString());
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
      debugPrint(
        '⚠️ AppUpdateCheckService: erro ao buscar versão por número: $e',
      );
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
  final String canal;

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
    this.canal = 'producao',
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

  bool get isBeta => canal == 'beta';
  bool get isTesteInterno => canal == 'teste_interno' || canal == 'teste';

  bool get estaAtualizado => !precisaAtualizar && !deveBloquear;

  bool get temApkConfigurado =>
      apkPath.trim().isNotEmpty || apkUrl.trim().isNotEmpty;

  String get statusLabel {
    if (isBeta) return 'BETA';
    if (isTesteInterno) return 'TESTE INTERNO';
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
