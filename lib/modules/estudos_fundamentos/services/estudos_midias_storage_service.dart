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

  String get resumoTamanho =>
      '${formatBytes(tamanhoOriginalBytes)} -> ${formatBytes(tamanhoFinalBytes)} (${percentualReducao.toStringAsFixed(0)}% menor)';

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }
}

class EstudosMidiasUploadLoteResultado {
  final int totalSelecionadas;
  final List<EstudosMidiasUploadResultado> enviados;
  final List<String> falhas;

  const EstudosMidiasUploadLoteResultado({
    required this.totalSelecionadas,
    required this.enviados,
    required this.falhas,
  });

  int get totalEnviadas => enviados.length;
  int get totalFalhas => falhas.length;
  int get tamanhoOriginalTotal =>
      enviados.fold(0, (sum, item) => sum + item.tamanhoOriginalBytes);
  int get tamanhoFinalTotal =>
      enviados.fold(0, (sum, item) => sum + item.tamanhoFinalBytes);
  double get percentualReducaoTotal {
    if (tamanhoOriginalTotal <= 0) return 0;
    return max(
      0,
      (1 - (tamanhoFinalTotal / tamanhoOriginalTotal)) * 100,
    ).toDouble();
  }

  String get resumo =>
      '$totalEnviadas/$totalSelecionadas enviadas, $totalFalhas falhas. '
      '${EstudosMidiasUploadResultado.formatBytes(tamanhoOriginalTotal)} -> '
      '${EstudosMidiasUploadResultado.formatBytes(tamanhoFinalTotal)} '
      '(${percentualReducaoTotal.toStringAsFixed(0)}% menor)';
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
  }) async {
    final file = await _selecionarArquivoUnico();
    if (file == null) return null;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _comprimirEnviarArquivo(
      file: file,
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
  }) async {
    final file = await _selecionarArquivoUnico();
    if (file == null) return null;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return _comprimirEnviarArquivo(
      file: file,
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
  }) async {
    final lote = await enviarImagensEstudo(
      cicloId: cicloId,
      estudoId: estudoId,
      compressaoPercentual: compressaoPercentual,
      allowMultiple: false,
    );
    return lote == null || lote.enviados.isEmpty ? null : lote.enviados.first;
  }

  Future<EstudosMidiasUploadLoteResultado?> enviarImagensEstudo({
    required String cicloId,
    required String estudoId,
    required int compressaoPercentual,
    bool allowMultiple = true,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: allowMultiple,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final enviados = <EstudosMidiasUploadResultado>[];
    final falhas = <String>[];
    for (final file in result.files) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final random = _random.nextInt(999999999).toString().padLeft(9, '0');
        enviados.add(
          await _comprimirEnviarArquivo(
            file: file,
            storagePath:
                'estudos_fundamentos/ciclos/$cicloId/estudos/$estudoId/imagens/img_${timestamp}_$random.jpg',
            compressaoPercentual: compressaoPercentual,
            larguraMaxima: larguraMaximaPadrao,
          ),
        );
      } catch (error) {
        falhas.add('${file.name}: $error');
      }
    }

    return EstudosMidiasUploadLoteResultado(
      totalSelecionadas: result.files.length,
      enviados: enviados,
      falhas: falhas,
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

  Future<PlatformFile?> _selecionarArquivoUnico() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single;
  }

  Future<EstudosMidiasUploadResultado> _comprimirEnviarArquivo({
    required PlatformFile file,
    required String storagePath,
    required int compressaoPercentual,
    required int larguraMaxima,
  }) async {
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
