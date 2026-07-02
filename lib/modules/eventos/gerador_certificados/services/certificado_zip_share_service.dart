import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CertificadoZipShareService {
  const CertificadoZipShareService();

  bool get _isDesktop {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

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

  Future<File?> _salvarComDialogDesktop({
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    if (!_isDesktop) return null;

    final nome = _limparNome(nomeArquivo);

    final location = await fs.getSaveLocation(
      suggestedName: nome,
      acceptedTypeGroups: const [
        fs.XTypeGroup(
          label: 'Arquivo ZIP',
          extensions: ['zip'],
          mimeTypes: ['application/zip'],
        ),
      ],
    );

    // Usuário cancelou a janela de salvar.
    if (location == null) return null;

    var path = location.path.trim();
    if (!path.toLowerCase().endsWith('.zip')) {
      path = '$path.zip';
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
        await Process.start('explorer.exe', [
          '/select,',
          file.path,
        ], runInShell: false);
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await Process.start('open', ['-R', file.path], runInShell: false);
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.linux) {
        await Process.start('xdg-open', [file.parent.path], runInShell: false);
      }
    } catch (_) {
      // Se o sistema não conseguir abrir o explorador, o arquivo já foi salvo.
      // Não precisa quebrar o fluxo por causa disso.
    }
  }

  /// Salva no navegador/PWA usando FileSaver.
  /// No Windows/macOS/Linux abre uma janela real para escolher onde salvar.
  /// No Android/iOS compartilha o ZIP, que é mais confiável do que seletor de pasta.
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

    if (_isDesktop) {
      await _salvarComDialogDesktop(bytes: bytes, nomeArquivo: nome);
      return;
    }

    await compartilharZip(bytes: bytes, nomeArquivo: nome, texto: texto);
  }

  Future<void> compartilharZip({
    required Uint8List bytes,
    required String nomeArquivo,
    String? texto,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('ZIP vazio. Nada para compartilhar.');
    }

    final nome = _limparNome(nomeArquivo);

    // No desktop, share_plus pode não abrir nada dependendo do Windows.
    // Para não deixar o usuário sem retorno visual, abrimos o mesmo fluxo de salvar.
    if (_isDesktop) {
      await _salvarComDialogDesktop(bytes: bytes, nomeArquivo: nome);
      return;
    }

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: nome.replaceAll('.zip', ''),
        bytes: bytes,
        ext: 'zip',
        mimeType: MimeType.zip,
      );
      return;
    }

    final file = await _gravarTemporario(bytes: bytes, nomeArquivo: nome);

    await Share.shareXFiles(
      [XFile(file.path, name: nome, mimeType: 'application/zip')],
      text: texto ?? 'Pacote de certificados para gráfica.',
      subject: nome,
    );
  }

  /// No Windows/macOS/Linux abre janela para escolher onde salvar.
  /// No PWA baixa pelo navegador.
  /// No Android/iOS tenta FileSaver e, se o sistema bloquear, compartilha.
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

    if (_isDesktop) {
      await _salvarComDialogDesktop(bytes: bytes, nomeArquivo: nome);
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
      await compartilharZip(bytes: bytes, nomeArquivo: nome, texto: texto);
    }
  }
}
