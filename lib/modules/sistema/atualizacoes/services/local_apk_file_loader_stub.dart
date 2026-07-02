// lib/modules/sistema/atualizacoes/services/local_apk_file_loader_stub.dart
//
// =====================================================
// 🚫 LEITOR DE APK INDISPONÍVEL - UAI
// =====================================================
//
// Seguro para PWA/APK.
// Não usa dart:io.
// =====================================================

import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_apk_file_loader_base.dart';

class LocalApkFileLoaderStub extends LocalApkFileLoader {
  const LocalApkFileLoaderStub();

  @override
  Future<LocalApkFileResult> readApk(String path) async {
    return LocalApkFileResult(
      success: false,
      path: path,
      fileName: '',
      bytes: null,
      sizeBytes: 0,
      errorMessage:
          'Leitura local de APK disponível apenas no Windows Desktop.',
    );
  }
}

LocalApkFileLoader createLocalApkFileLoader() {
  return const LocalApkFileLoaderStub();
}
