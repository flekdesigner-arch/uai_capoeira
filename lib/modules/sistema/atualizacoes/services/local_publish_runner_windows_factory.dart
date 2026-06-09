// lib/modules/sistema/atualizacoes/services/local_publish_runner_windows_factory.dart
//
// =====================================================
// 🖥️ FACTORY WINDOWS/NATIVA DO EXECUTOR LOCAL - UAI
// =====================================================
//
// Este arquivo só entra quando dart:io está disponível.
// Ele ainda respeita a regra:
// - só executa automação se a plataforma for Windows Desktop;
// - em Android/iOS/macOS/Linux, retorna runner indisponível.
// =====================================================

import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_base.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_windows.dart';

LocalPublishRunner createLocalPublishRunner() {
  final platformInfo = const LocalPublishPlatformService().getInfo();

  if (!platformInfo.canRunLocalAutomation) {
    return LocalPublishRunnerUnavailable(platformInfo);
  }

  return LocalPublishRunnerWindows(platformInfo: platformInfo);
}
