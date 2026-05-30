import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CertificadoExportService {
  const CertificadoExportService();

  Future<Uint8List> capturarPreviewComoPng(
      GlobalKey repaintKey, {
        double pixelRatio = 4.0,
      }) async {
    // Dá tempo do SvgPicture/FutureBuilder estabilizar antes da captura.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final context = repaintKey.currentContext;
    if (context == null) {
      throw Exception('A prévia ainda não está pronta para exportação.');
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw Exception(
        'A prévia não está dentro de um RepaintBoundary para exportação.',
      );
    }

    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('Não foi possível converter a prévia para PNG.');
    }

    return byteData.buffer.asUint8List();
  }

  Future<Uint8List> gerarPdfA4Paisagem(Uint8List pngBytes) async {
    final documento = pw.Document();
    final imagem = pw.MemoryImage(pngBytes);

    documento.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Container(
            width: PdfPageFormat.a4.landscape.width,
            height: PdfPageFormat.a4.landscape.height,
            color: PdfColors.white,
            alignment: pw.Alignment.center,
            child: pw.Image(
              imagem,
              fit: pw.BoxFit.contain,
              width: PdfPageFormat.a4.landscape.width,
              height: PdfPageFormat.a4.landscape.height,
            ),
          );
        },
      ),
    );

    return documento.save();
  }

  Future<void> salvarPdf({
    required Uint8List bytes,
    required String nomeBase,
  }) async {
    await FileSaver.instance.saveFile(
      name: nomeBase,
      bytes: bytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> salvarPng({
    required Uint8List bytes,
    required String nomeBase,
  }) async {
    await FileSaver.instance.saveFile(
      name: nomeBase,
      bytes: bytes,
      ext: 'png',
      mimeType: MimeType.png,
    );
  }

  Future<void> imprimirPdf(Uint8List pdfBytes) async {
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      usePrinterSettings: true,
      dynamicLayout: false,
    );
  }

  Future<void> compartilharPdf({
    required Uint8List bytes,
    required String nomeBase,
  }) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: '$nomeBase.pdf',
    );
  }
}
