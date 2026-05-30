import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CertificadoZipShareService {
  const CertificadoZipShareService();

  String _limparNome(String nome) {
    final base = nome.trim().isEmpty ? 'certificados.zip' : nome.trim();
    return base.toLowerCase().endsWith('.zip') ? base : '$base.zip';
  }

  Future<File> _gravarTemporario({
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_limparNome(nomeArquivo)}');

    if (await file.exists()) {
      await file.delete();
    }

    return file.writeAsBytes(bytes, flush: true);
  }

  /// Salva no navegador/PWA usando FileSaver.
  /// No Android/iOS, compartilha o arquivo ZIP, que é mais confiável que abrir
  /// seletor de pasta dentro do emulador/celular.
  Future<void> entregarZip({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('ZIP vazio. Nada para salvar ou compartilhar.');
    }

    final nome = _limparNome(nomeArquivo);

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.zip', ''),
        bytes: bytes,
        ext: 'zip',
        mimeType: MimeType.zip,
      );
      return;
    }

    await compartilharZip(
      bytes: bytes,
      nomeArquivo: nome,
      texto: texto,
    );
  }

  Future<void> compartilharZip({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('ZIP vazio. Nada para compartilhar.');
    }

    final file = await _gravarTemporario(
      bytes: bytes,
      nomeArquivo: nomeArquivo,
    );

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          name: _limparNome(nomeArquivo),
          mimeType: 'application/zip',
        ),
      ],
      text: texto ?? 'Pacote de certificados para gráfica.',
      subject: _limparNome(nomeArquivo),
    );
  }

  /// Tenta salvar em Downloads no Android/desktop.
  /// Se o sistema bloquear, cai para compartilhar.
  Future<void> salvarOuCompartilharZip({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('ZIP vazio. Nada para salvar.');
    }

    final nome = _limparNome(nomeArquivo);

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.zip', ''),
        bytes: bytes,
        ext: 'zip',
        mimeType: MimeType.zip,
      );
      return;
    }

    try {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.zip', ''),
        bytes: bytes,
        ext: 'zip',
        mimeType: MimeType.zip,
      );
    } catch (_) {
      await compartilharZip(
        bytes: bytes,
        nomeArquivo: nome,
        texto: texto,
      );
    }
  }
}
