// lib/modules/sistema/atualizacoes/services/local_publish_runner_factory.dart
//
// =====================================================
// 🧩 FACTORY SEGURA DO EXECUTOR LOCAL - UAI
// =====================================================
//
// Este é o ÚNICO arquivo que a tela deve importar para obter o runner.
//
// Ele usa import condicional para evitar quebrar o PWA:
//
// - Web/PWA/APK/outros: usa local_publish_runner_stub.dart
// - Windows/Desktop nativo: usa local_publish_runner_windows.dart
//
// Observação:
// O Dart não permite escolher import por "Windows" diretamente aqui.
// A segurança vem do fato de que o arquivo Windows só é usado no ambiente
// nativo com dart:io disponível, e o runner ainda checa a plataforma antes
// de liberar execução.
// =====================================================

import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_base.dart';

import 'local_publish_runner_stub.dart'
if (dart.library.io) 'local_publish_runner_windows_factory.dart';

LocalPublishRunner getLocalPublishRunner() {
  return createLocalPublishRunner();
}
