import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;

class EstudosMidiasUploadResultado {
  final String downloadUrl;
  final String storagePath;
  final int tamanhoOriginalBytes;
  final int tamanhoFinalBytes;
  final double percentualReducao;
  final int larguraFinal;
  final int alturaFinal;

  const EstudosMidiasUploadResultado({
    required this.downloadUrl,
    required this.storagePath,
    required this.tamanhoOriginalBytes,
    required this.tamanhoFinalBytes,
    required this.percentualReducao,
    required this.larguraFinal,
    required this.alturaFinal,
  });

  String get resumoTamanho {
    return '${_formatBytes(tamanhoOriginalBytes)} -> ${_formatBytes(tamanhoFinalBytes)} (${percentualReducao.toStringAsFixed(0)}% menor)';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }
}

class EstudosMidiasStorageService {
  static const int tamanhoMaximoBytes = 15 * 1024 * 1024;
  static const int larguraMaximaPadrao = 1600;
  static const List<int> compressoesPermitidas = [5, 10, 15, 20, 25, 30];

  final FirebaseStorage _storage;
  final Random _random = Random.secure();

  EstudosMidiasStorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  Future<EstudosMidiasUploadResultado?> enviarCapaCiclo({
    required String cicloId,
    required int compressaoPercentual,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _selecionarComprimirEnviar(
      storagePath:
          'estudos_fundamentos/ciclos/$cicloId/capa/capa_$timestamp.jpg',
      compressaoPercentual: compressaoPercentual,
      larguraMaxima: larguraMaximaPadrao,
    );
  }

  Future<EstudosMidiasUploadResultado?> enviarCapaEstudo({
    required String cicloId,
    required String estudoId,
    required int compressaoPercentual,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _selecionarComprimirEnviar(
      storagePath:
          'estudos_fundamentos/ciclos/$cicloId/estudos/$estudoId/capa/capa_$timestamp.jpg',
      compressaoPercentual: compressaoPercentual,
      larguraMaxima: larguraMaximaPadrao,
    );
  }

  Future<EstudosMidiasUploadResultado?> enviarImagemEstudo({
    required String cicloId,
    required String estudoId,
    required int compressaoPercentual,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _random.nextInt(999999999).toString().padLeft(9, '0');
    return _selecionarComprimirEnviar(
      storagePath:
          'estudos_fundamentos/ciclos/$cicloId/estudos/$estudoId/imagens/img_${timestamp}_$random.jpg',
      compressaoPercentual: compressaoPercentual,
      larguraMaxima: larguraMaximaPadrao,
    );
  }

  Future<void> apagarArquivoSeguro(String storagePath) async {
    if (!storagePathSeguro(storagePath)) return;
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }

  bool storagePathSeguro(String value) {
    final path = value.trim();
    return path.isNotEmpty &&
        path.startsWith('estudos_fundamentos/') &&
        !path.startsWith('/') &&
        !path.contains('..') &&
        !path.contains('//');
  }

  Future<EstudosMidiasUploadResultado?> _selecionarComprimirEnviar({
    required String storagePath,
    required int compressaoPercentual,
    required int larguraMaxima,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const EstudosMidiasUploadException(
        'Não foi possível ler o arquivo selecionado.',
      );
    }
    if (bytes.length > tamanhoMaximoBytes) {
      throw const EstudosMidiasUploadException(
        'Imagem muito grande. Use um arquivo de até 15 MB.',
      );
    }

    final ext = (file.extension ?? '').toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      throw const EstudosMidiasUploadException(
        'Selecione uma imagem JPG, PNG ou WEBP.',
      );
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const EstudosMidiasUploadException(
        'Não foi possível processar esta imagem.',
      );
    }

    final resized = decoded.width > larguraMaxima
        ? img.copyResize(decoded, width: larguraMaxima)
        : decoded;
    final qualidade = _qualidadeParaCompressao(compressaoPercentual);
    final encoded = Uint8List.fromList(
      img.encodeJpg(resized, quality: qualidade),
    );

    final ref = _storage.ref(storagePath);
    await ref.putData(
      encoded,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'origem': 'estudos_fundamentos_admin',
          'compressaoPercentual': compressaoPercentual.toString(),
        },
      ),
    );

    final original = bytes.length;
    final finalBytes = encoded.length;
    final reducao = original <= 0
        ? 0.0
        : max(0, (1 - (finalBytes / original)) * 100).toDouble();

    return EstudosMidiasUploadResultado(
      downloadUrl: await ref.getDownloadURL(),
      storagePath: storagePath,
      tamanhoOriginalBytes: original,
      tamanhoFinalBytes: finalBytes,
      percentualReducao: reducao,
      larguraFinal: resized.width,
      alturaFinal: resized.height,
    );
  }

  int _qualidadeParaCompressao(int compressaoPercentual) {
    final compressao = compressoesPermitidas.contains(compressaoPercentual)
        ? compressaoPercentual
        : 15;
    return 100 - compressao;
  }
}

class EstudosMidiasUploadException implements Exception {
  final String message;

  const EstudosMidiasUploadException(this.message);

  @override
  String toString() => message;
}
