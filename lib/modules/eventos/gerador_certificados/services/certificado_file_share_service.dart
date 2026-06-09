import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CertificadoFileShareService {
  const CertificadoFileShareService();

  bool get _isDesktop {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

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

  Future<File?> _salvarComDialogDesktop({
    required Uint8List bytes,
    required String nomeArquivo,
    required String extensao,
    required String label,
    required List<String> mimeTypes,
  }) async {
    if (!_isDesktop) return null;

    final ext = extensao.replaceAll('.', '').trim().toLowerCase();
    final nome = _garantirExtensao(nomeArquivo, ext);

    final location = await fs.getSaveLocation(
      suggestedName: nome,
      acceptedTypeGroups: [
        fs.XTypeGroup(
          label: label,
          extensions: [ext],
          mimeTypes: mimeTypes,
        ),
      ],
    );

    // Usuário cancelou a janela de salvar.
    if (location == null) return null;

    var path = location.path.trim();
    if (!path.toLowerCase().endsWith('.$ext')) {
      path = '$path.$ext';
    }

    final file = File(path);

    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    await file.writeAsBytes(bytes, flush: true);
    await _revelarArquivoNoDesktop(file);

    return file;
  }

  Future<void> _revelarArquivoNoDesktop(File file) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await Process.start(
          'explorer.exe',
          ['/select,', file.path],
          runInShell: false,
        );
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await Process.start(
          'open',
          ['-R', file.path],
          runInShell: false,
        );
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.linux) {
        await Process.start(
          'xdg-open',
          [file.parent.path],
          runInShell: false,
        );
      }
    } catch (_) {
      // Se o sistema não conseguir abrir o explorador, o arquivo já foi salvo.
      // Não precisa quebrar o fluxo por causa disso.
    }
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

    if (_isDesktop) {
      await _salvarComDialogDesktop(
        bytes: bytes,
        nomeArquivo: nome,
        extensao: 'pdf',
        label: 'Arquivo PDF',
        mimeTypes: const ['application/pdf'],
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

    if (_isDesktop) {
      await _salvarComDialogDesktop(
        bytes: bytes,
        nomeArquivo: nome,
        extensao: 'png',
        label: 'Imagem PNG',
        mimeTypes: const ['image/png'],
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

    // PWA/Web não possui implementação do path_provider.
    // Na Web o comportamento correto é baixar o arquivo pelo navegador.
    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.pdf', ''),
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
      return;
    }

    // No Windows/macOS/Linux, compartilhar PDF pode não abrir nada dependendo
    // do plugin/sistema. Para garantir retorno visual, abre o diálogo de salvar.
    if (_isDesktop) {
      await _salvarComDialogDesktop(
        bytes: bytes,
        nomeArquivo: nome,
        extensao: 'pdf',
        label: 'Arquivo PDF',
        mimeTypes: const ['application/pdf'],
      );
      return;
    }

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

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.png', ''),
        bytes: bytes,
        ext: 'png',
        mimeType: MimeType.png,
      );
      return;
    }

    // No Windows/macOS/Linux, compartilhar PNG pode não abrir nada dependendo
    // do plugin/sistema. Para garantir retorno visual, abre o diálogo de salvar.
    if (_isDesktop) {
      await _salvarComDialogDesktop(
        bytes: bytes,
        nomeArquivo: nome,
        extensao: 'png',
        label: 'Imagem PNG',
        mimeTypes: const ['image/png'],
      );
      return;
    }

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
