// lib/modules/sistema/atualizacoes/services/local_apk_file_loader_io.dart
//
// =====================================================
// 🖥️ LEITOR LOCAL DE APK COM dart:io - UAI
// =====================================================
//
// ATENÇÃO:
// Este arquivo usa dart:io.
// Não importe diretamente em tela Web/PWA.
// Use sempre local_apk_file_loader_factory.dart.
// =====================================================

import 'dart:io';

import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_apk_file_loader_base.dart';

class LocalApkFileLoaderIo extends LocalApkFileLoader {
  const LocalApkFileLoaderIo();

  @override
  Future<LocalApkFileResult> readApk(String path) async {
    try {
      final file = File(path);

      if (!await file.exists()) {
        return LocalApkFileResult(
          success: false,
          path: path,
          fileName: '',
          bytes: null,
          sizeBytes: 0,
          errorMessage: 'APK não encontrado em: $path',
        );
      }

      if (!path.toLowerCase().endsWith('.apk')) {
        return LocalApkFileResult(
          success: false,
          path: path,
          fileName: file.uri.pathSegments.isEmpty
              ? ''
              : file.uri.pathSegments.last,
          bytes: null,
          sizeBytes: 0,
          errorMessage: 'O arquivo encontrado não é um APK válido: $path',
        );
      }

      final bytes = await file.readAsBytes();
      final stat = await file.stat();

      return LocalApkFileResult(
        success: true,
        path: path,
        fileName: file.uri.pathSegments.isEmpty
            ? 'app-release.apk'
            : file.uri.pathSegments.last,
        bytes: bytes,
        sizeBytes: stat.size,
      );
    } catch (e) {
      return LocalApkFileResult(
        success: false,
        path: path,
        fileName: '',
        bytes: null,
        sizeBytes: 0,
        errorMessage: 'Erro ao ler APK local: $e',
      );
    }
  }
}

LocalApkFileLoader createLocalApkFileLoader() {
  return const LocalApkFileLoaderIo();
}
