// lib/modules/sistema/atualizacoes/services/local_apk_file_loader_factory.dart
//
// =====================================================
// 🧩 FACTORY SEGURA DO LEITOR LOCAL DE APK - UAI
// =====================================================
//
// A tela deve importar somente este arquivo.
//
// - Web/PWA: usa stub seguro.
// - Nativo com dart:io: usa leitor real.
// =====================================================

import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_apk_file_loader_base.dart';

import 'local_apk_file_loader_stub.dart'
if (dart.library.io) 'local_apk_file_loader_io.dart';

LocalApkFileLoader getLocalApkFileLoader() {
  return createLocalApkFileLoader();
}
