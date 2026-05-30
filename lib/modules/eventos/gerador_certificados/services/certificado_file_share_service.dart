import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CertificadoFileShareService {
  const CertificadoFileShareService();

  Future<File> _gravarTemporario({
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$nomeArquivo');

    if (await file.exists()) {
      await file.delete();
    }

    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> salvarOuCompartilharPdf({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('PDF vazio. Nada para salvar.');
    }

    final nome = _garantirExtensao(nomeArquivo, 'pdf');

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.pdf', ''),
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
      return;
    }

    try {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.pdf', ''),
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
    } catch (_) {
      await compartilharPdf(
        bytes: bytes,
        nomeArquivo: nome,
        texto: texto,
      );
    }
  }

  Future<void> salvarOuCompartilharPng({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('PNG vazio. Nada para salvar.');
    }

    final nome = _garantirExtensao(nomeArquivo, 'png');

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.png', ''),
        bytes: bytes,
        ext: 'png',
        mimeType: MimeType.png,
      );
      return;
    }

    try {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.png', ''),
        bytes: bytes,
        ext: 'png',
        mimeType: MimeType.png,
      );
    } catch (_) {
      await compartilharPng(
        bytes: bytes,
        nomeArquivo: nome,
        texto: texto,
      );
    }
  }

  Future<void> compartilharPdf({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('PDF vazio. Nada para compartilhar.');
    }

    final nome = _garantirExtensao(nomeArquivo, 'pdf');
    final file = await _gravarTemporario(
      bytes: bytes,
      nomeArquivo: nome,
    );

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          name: nome,
          mimeType: 'application/pdf',
        ),
      ],
      text: texto ?? 'Certificado em PDF.',
      subject: nome,
    );
  }

  Future<void> compartilharPng({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('PNG vazio. Nada para compartilhar.');
    }

    final nome = _garantirExtensao(nomeArquivo, 'png');
    final file = await _gravarTemporario(
      bytes: bytes,
      nomeArquivo: nome,
    );

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          name: nome,
          mimeType: 'image/png',
        ),
      ],
      text: texto ?? 'Certificado em PNG.',
      subject: nome,
    );
  }

  String _garantirExtensao(String nome, String extensao) {
    final ext = extensao.replaceAll('.', '').toLowerCase();
    final clean = nome.trim().isEmpty ? 'certificado.$ext' : nome.trim();

    if (clean.toLowerCase().endsWith('.$ext')) {
      return clean;
    }

    return '$clean.$ext';
  }
}
