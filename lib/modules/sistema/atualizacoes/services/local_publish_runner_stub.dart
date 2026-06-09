// lib/modules/sistema/atualizacoes/services/local_publish_runner_stub.dart
//
// =====================================================
// 🚫 EXECUTOR INDISPONÍVEL DA AUTOMAÇÃO LOCAL - UAI
// =====================================================
//
// Este arquivo é seguro para PWA, APK e qualquer plataforma.
// Não usa dart:io.
// Ele é usado quando a plataforma não pode executar PowerShell.
//
// Importante:
// - PWA não pode executar scripts locais.
// - APK Android não pode gerar APK/deploy.
// - A automação completa fica liberada apenas no Windows Desktop.
// =====================================================

import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_base.dart';

LocalPublishRunner createLocalPublishRunner() {
  final platformInfo = const LocalPublishPlatformService().getInfo();
  return LocalPublishRunnerUnavailable(platformInfo);
}
