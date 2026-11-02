// lib/core/services/atualizacao_dialog_service.dart
import 'dart:async' show unawaited;
//
// =====================================================
// 🚀 SERVIÇO DE DIÁLOGO DE ATUALIZAÇÃO - UAI CAPOEIRA
// =====================================================
//
// Refatorado para o Laboratório de Atualizações.
//
// Agora ele lê:
// configuracoes/app
//   versao_atual
//   versao_minima_obrigatoria
//   atualizacao_obrigatoria
//   ultima_versao_id
//   titulo_atualizacao
//   mensagem_atualizacao
//
// E, quando existir, também lê:
// versoes_app/{ultima_versao_id}
//
// Para mostrar changelog real:
// - Melhorias
// - Correções
// - Implementações
// - Removidos
//
// Comportamento:
// - Atualização opcional: usuário pode tocar em "Agora não".
// - Atualização obrigatória: usuário não consegue fechar o diálogo pelo botão
//   "Agora não" nem clicando fora.
// - Visual acompanha o tema atual do app usando context.uai.
// =====================================================


import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/core/services/update_wifi_service.dart';
import 'package:uai_capoeira/core/services/official_apk_website_service.dart';
import 'package:uai_capoeira/shared/widgets/update_compact_panel.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/services/atualizacao_direta_service.dart';
import 'package:uai_capoeira/core/services/app_update_check_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class AtualizacaoDialogService {
  static final AtualizacaoDialogService _instance =
      AtualizacaoDialogService._internal();

  factory AtualizacaoDialogService() => _instance;

  AtualizacaoDialogService._internal();

  final AtualizacaoDiretaService _atualizacaoService =
      AtualizacaoDiretaService();

  bool _dialogoJaMostrado = false;

  // =====================================================
  // 🔥 VERIFICAR E MOSTRAR DIÁLOGO
  // =====================================================
  Future<void> verificarEMostrarDialogo(BuildContext context) async {
    if (_dialogoJaMostrado) return;
    if (kIsWeb) {
      debugPrint('Atualização por APK ignorada no PWA/Web.');
      return;
    }
    try {
      final status = await AppUpdateCheckService().verificarStatus();
      if (!status.carregou || (!status.precisaAtualizar && !status.deveBloquear)) return;
      final novaVersao = status.versaoServidor;
      if (novaVersao.trim().isEmpty) return;
      // Windows mantém a verificação legada de disponibilidade; no Android,
      // a interface não deve desaparecer só porque o APK falhou no Storage.
      if (!UpdateWifiService.instance.isSupported &&
          !await _atualizacaoService.apkExiste(novaVersao)) {
        return;
      }
      // Agenda sem bloquear a exibição do diálogo. WorkManager aguardará o Wi-Fi.
      // Nada é iniciado sem consentimento salvo pelo usuário.
      if (UpdateWifiService.instance.isSupported) {
        _agendarWifiSemInterromper(novaVersao);
      }
      if (!context.mounted) return;
      _dialogoJaMostrado = true;
      await _mostrarDialogoAtualizacao(
        context: context,
        versaoAtual: status.versaoLocal == novaVersao
            ? '${status.versaoLocal}+${status.buildLocal}'
            : status.versaoLocal,
        novaVersao: novaVersao,
        obrigatoria: status.deveBloquear,
        config: {...status.config, 'canal_release': status.canal},
        versionModel: status.versionModel,
      );
    } catch (e) {
      debugPrint('❌ Erro ao verificar atualização: $e');
    }
  }

  Future<void> _agendarWifiSemInterromper(String versao) async {
    try {
      await UpdateWifiService.instance.scheduleIfEnabled(versao);
    } catch (e) {
      debugPrint('Atualizador Wi-Fi: $e');
    }
  }

  /// Usa exatamente a mesma apresentação compacta do bloqueio obrigatório.
  Future<void> _mostrarDialogoAtualizacao({
    required BuildContext context,
    required String versaoAtual,
    required String novaVersao,
    required bool obrigatoria,
    required Map<String, dynamic> config,
    required AppVersionModel? versionModel,
  }) async {
    final titulo = versionModel?.titulo.trim().isNotEmpty == true
        ? versionModel!.titulo : (config['titulo_atualizacao'] ?? 'Nova versão disponível').toString();
    final resumo = versionModel?.resumo.trim().isNotEmpty == true
        ? versionModel!.resumo : (config['mensagem_atualizacao'] ?? '').toString();
    final changes = <String>[
      ...?versionModel?.implementacoes,
      ...?versionModel?.melhorias,
      ...?versionModel?.correcoes,
      ...?versionModel?.removidos,
    ];
    await showDialog<void>(
      context: context,
      barrierDismissible: !obrigatoria,
      builder: (dialogContext) => PopScope(
        canPop: !obrigatoria,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          backgroundColor: Colors.transparent,
          child: LayoutBuilder(builder: (context, constraints) {
            final height = constraints.maxHeight.clamp(0.0, 620.0).toDouble();
            return SizedBox(height: height, child: UpdateCompactPanel(
              requiredUpdate: obrigatoria,
              installedVersion: versaoAtual,
              targetVersion: novaVersao,
              title: titulo,
              summary: resumo,
              changes: changes,
              onLater: obrigatoria ? null : () {
                Navigator.of(dialogContext).pop();
                _dialogoJaMostrado = false;
              },
              onUpdate: () {
                if (!obrigatoria) Navigator.of(dialogContext).pop();
                unawaited(iniciarAtualizacao(context, novaVersao));
              },
              onOfficialSite: () => OfficialApkWebsiteService.open(context),
              onVerify: () async {
                final newStatus = await AppUpdateCheckService().verificarStatus();
                if (!dialogContext.mounted) return;
                if (newStatus.carregou && !newStatus.precisaAtualizar && !newStatus.deveBloquear) {
                  Navigator.of(dialogContext).pop();
                  _dialogoJaMostrado = false;
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(
                    content: Text('A atualização ainda não foi detectada neste aparelho.'),
                  ));
                }
              },
            ));
          }),
        ),
      ),
    );
  }

  // =====================================================
  // 📥 INICIAR ATUALIZAÇÃO
  // =====================================================
  Future<void> iniciarAtualizacao(BuildContext context, String versao) async {
    // Android: antes de qualquer instalação, consulte a release mais nova
    // elegível, inclusive no caminho manual. Nunca reabra APK obsoleto.
    if (UpdateWifiService.instance.isSupported &&
        FirebaseAuth.instance.currentUser != null) {
      final verification = await UpdateWifiService.instance.validateLatest(versao);
      if (!context.mounted) return;
      if (verification != 'current') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(verification == 'superseded'
              ? 'Existe uma versão mais recente disponível. Reabra a tela de atualização.'
              : 'Não foi possível confirmar a última versão. Conecte-se à internet e tente novamente.'),
        ));
        return;
      }
      final state = await UpdateWifiService.instance.getState(versao);
      if (!context.mounted) return;
      if (state.ready) {
        final result = await UpdateWifiService.instance.installReady(versao);
        // Jamais cair no fluxo manual com uma versão que o validador rejeitou.
        if (result != 'not_ready') {
          if (result != 'installer_opened' && result != 'permission_required' && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('A versão baixada não é mais válida. Aguarde o download da atualização mais recente.'),
            ));
          }
          return;
        }
      }
    }
    // No primeiro acesso, antes do login, o UpdateGate precisa continuar
    // permitindo a atualização obrigatória. Confere a produção no servidor.
    if (UpdateWifiService.instance.isSupported &&
        FirebaseAuth.instance.currentUser == null) {
      final status = await AppUpdateCheckService().verificarStatus();
      if (!context.mounted) return;
      if (!status.carregou || status.versaoDestino != versao ||
          status.canal != 'producao' ||
          (!status.precisaAtualizar && !status.deveBloquear)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível validar esta atualização. Verifique sua conexão.'),
        ));
        return;
      }
    }
    if (!context.mounted) return;
    await _atualizacaoService.baixarEInstalarComFeedback(context, versao);
  }

  // =====================================================
  // 🔄 RESETAR FLAG
  // =====================================================
  void resetarDialogoJaMostrado() {
    _dialogoJaMostrado = false;
  }
}

