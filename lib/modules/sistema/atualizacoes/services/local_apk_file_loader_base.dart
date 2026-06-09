// lib/modules/sistema/atualizacoes/services/local_apk_file_loader_base.dart
//
// =====================================================
// 📦 BASE DO LEITOR LOCAL DE APK - UAI
// =====================================================
//
// Este arquivo é seguro para APK, PWA e Windows.
// Não usa dart:io.
// Ele define o contrato para ler o APK gerado no Windows.
//
// Na versão 64, depois que o script gerar:
// build/app/outputs/uai-apks/uai_capoeira_X.X.X.apk
//
// O app Windows vai ler esse arquivo como bytes e usar o
// AppUpdateAdminService.uploadApkBytes() que já existe.
// =====================================================

import 'dart:typed_data';

class LocalApkFileResult {
  final bool success;
  final String path;
  final String fileName;
  final Uint8List? bytes;
  final int sizeBytes;
  final String? errorMessage;

  const LocalApkFileResult({
    required this.success,
    required this.path,
    required this.fileName,
    required this.bytes,
    required this.sizeBytes,
    this.errorMessage,
  });

  String get sizeFormatted {
    if (sizeBytes <= 0) return '0 B';

    const kb = 1024;
    const mb = kb * 1024;

    if (sizeBytes >= mb) {
      return '${(sizeBytes / mb).toStringAsFixed(2)} MB';
    }

    if (sizeBytes >= kb) {
      return '${(sizeBytes / kb).toStringAsFixed(2)} KB';
    }

    return '$sizeBytes B';
  }
}

abstract class LocalApkFileLoader {
  const LocalApkFileLoader();

  Future<LocalApkFileResult> readApk(String path);
}
