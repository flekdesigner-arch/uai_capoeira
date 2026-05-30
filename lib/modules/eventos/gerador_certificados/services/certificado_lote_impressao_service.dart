import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';

class CertificadoLoteImpressaoService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CertificadoLoteImpressaoService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  static const int tamanhoPadraoLote = 10;

  List<List<T>> dividirEmLotes<T>(
      List<T> items, {
        int tamanhoLote = tamanhoPadraoLote,
      }) {
    if (items.isEmpty) return [];

    final tamanhoSeguro = tamanhoLote <= 0 ? tamanhoPadraoLote : tamanhoLote;
    final lotes = <List<T>>[];

    for (var i = 0; i < items.length; i += tamanhoSeguro) {
      final fim = (i + tamanhoSeguro) > items.length
          ? items.length
          : i + tamanhoSeguro;

      lotes.add(items.sublist(i, fim));
    }

    return lotes;
  }

  /// Gera 1 PDF A4 paisagem a partir de 1 PNG do certificado.
  ///
  /// Esse método é usado pelo pacote para gráfica:
  /// renderiza/captura um aluno, gera PDF, coloca no ZIP e libera o PNG.
  Future<Uint8List> gerarPdfIndividualA4Paisagem(Uint8List pngBytes) async {
    if (pngBytes.isEmpty) {
      throw Exception('PNG vazio. Não foi possível gerar o PDF individual.');
    }

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

  /// Gera 1 PDF multipágina A4 paisagem usando PNGs já capturados.
  ///
  /// Uso principal: impressão em lotes, por exemplo 70 certificados
  /// virando 7 PDFs com 10 páginas.
  Future<Uint8List> gerarPdfMultipaginaComPngs({
    required List<CertificadoArquivoGerado> certificados,
  }) async {
    if (certificados.isEmpty) {
      throw Exception('Nenhum certificado informado para gerar PDF.');
    }

    final documento = pw.Document();

    for (final certificado in certificados) {
      final png = certificado.pngBytes;

      if (png == null || png.isEmpty) {
        throw Exception(
          'O certificado de ${certificado.participante.alunoNome} não tem PNG para montar o PDF multipágina.',
        );
      }

      final image = pw.MemoryImage(png);

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
                image,
                fit: pw.BoxFit.contain,
                width: PdfPageFormat.a4.landscape.width,
                height: PdfPageFormat.a4.landscape.height,
              ),
            );
          },
        ),
      );
    }

    return documento.save();
  }

  Future<List<CertificadoLoteGerado>> gerarLotesImpressao({
    required CertificadoEventoData evento,
    required List<CertificadoArquivoGerado> certificados,
    int tamanhoLote = tamanhoPadraoLote,
    bool enviarStorage = false,
    bool registrarFirestore = true,
  }) async {
    if (evento.eventoId.trim().isEmpty) {
      throw Exception('Evento sem ID. Não é possível criar lotes.');
    }

    if (certificados.isEmpty) {
      throw Exception('Nenhum certificado selecionado.');
    }

    final grupos = dividirEmLotes<CertificadoArquivoGerado>(
      certificados,
      tamanhoLote: tamanhoLote,
    );

    final lotesGerados = <CertificadoLoteGerado>[];

    for (var i = 0; i < grupos.length; i++) {
      final numeroLote = i + 1;
      final grupo = grupos[i];

      final pdfBytes = await gerarPdfMultipaginaComPngs(
        certificados: grupo,
      );

      final nomeArquivo = nomeArquivoLote(
        evento: evento,
        numeroLote: numeroLote,
        totalLotes: grupos.length,
      );

      String? linkPdf;
      String? storagePath;

      if (enviarStorage) {
        storagePath =
        'eventos/${evento.eventoId}/certificados/lotes_impressao/$nomeArquivo';

        linkPdf = await _uploadBytes(
          bytes: pdfBytes,
          storagePath: storagePath,
          contentType: 'application/pdf',
          metadata: {
            'evento_id': evento.eventoId,
            'numero_lote': numeroLote.toString(),
            'total_lotes': grupos.length.toString(),
            'total_certificados': grupo.length.toString(),
            'tipo': 'lote_impressao',
            'gerado_em': DateTime.now().toIso8601String(),
          },
        );
      }

      final lote = CertificadoLoteGerado(
        id: '',
        eventoId: evento.eventoId,
        numeroLote: numeroLote,
        totalLotes: grupos.length,
        totalCertificados: grupo.length,
        nomeArquivo: nomeArquivo,
        pdfBytes: pdfBytes,
        linkPdf: linkPdf,
        storagePath: storagePath,
        participacoesIds:
        grupo.map((item) => item.participante.participacaoId).toList(),
        participantesNomes:
        grupo.map((item) => item.participante.alunoNome).toList(),
        status: 'gerado',
        criadoEm: DateTime.now(),
        impresso: false,
      );

      if (registrarFirestore) {
        final loteId = await registrarLoteImpressao(lote);
        lotesGerados.add(lote.copyWith(id: loteId));
      } else {
        lotesGerados.add(lote);
      }
    }

    return lotesGerados;
  }

  Future<String> registrarLoteImpressao(CertificadoLoteGerado lote) async {
    if (lote.eventoId.trim().isEmpty) {
      throw Exception('Evento sem ID para registrar lote.');
    }

    final docRef = await _firestore
        .collection('eventos')
        .doc(lote.eventoId)
        .collection('lotes_certificados')
        .add(lote.toMap());

    final batch = _firestore.batch();

    for (final participacaoId in lote.participacoesIds) {
      if (participacaoId.trim().isEmpty) continue;

      final ref = _firestore
          .collection('participacoes_eventos_em_andamento')
          .doc(participacaoId);

      batch.update(ref, {
        'certificado_lote_impressao': lote.numeroLote,
        'certificado_arquivo_lote': lote.nomeArquivo,
        'certificado_lote_id': docRef.id,
        'certificado_impresso': false,
        'certificado_atualizado_em': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    return docRef.id;
  }

  Future<void> marcarLoteComoImpresso({
    required String eventoId,
    required String loteId,
    required List<String> participacoesIds,
    bool impresso = true,
  }) async {
    if (eventoId.trim().isEmpty || loteId.trim().isEmpty) {
      throw Exception('Evento ou lote não informado.');
    }

    final batch = _firestore.batch();

    final loteRef = _firestore
        .collection('eventos')
        .doc(eventoId)
        .collection('lotes_certificados')
        .doc(loteId);

    batch.update(loteRef, {
      'impresso': impresso,
      'status': impresso ? 'impresso' : 'gerado',
      'impresso_em': impresso ? FieldValue.serverTimestamp() : null,
      'atualizado_em': FieldValue.serverTimestamp(),
    });

    for (final participacaoId in participacoesIds) {
      if (participacaoId.trim().isEmpty) continue;

      final ref = _firestore
          .collection('participacoes_eventos_em_andamento')
          .doc(participacaoId);

      batch.update(ref, {
        'certificado_impresso': impresso,
        'certificado_impresso_em':
        impresso ? FieldValue.serverTimestamp() : null,
        'certificado_atualizado_em': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<void> marcarParticipanteImpresso({
    required String participacaoId,
    bool impresso = true,
  }) async {
    if (participacaoId.trim().isEmpty) {
      throw Exception('Participação não informada.');
    }

    await _firestore
        .collection('participacoes_eventos_em_andamento')
        .doc(participacaoId)
        .update({
      'certificado_impresso': impresso,
      'certificado_impresso_em':
      impresso ? FieldValue.serverTimestamp() : null,
      'certificado_atualizado_em': FieldValue.serverTimestamp(),
    });
  }

  Future<Uint8List> gerarRelatorioGraficaPdf({
    required CertificadoEventoData evento,
    required List<CertificadoArquivoGerado> certificados,
    String titulo = 'Relatório de Certificados para Gráfica',
  }) async {
    final itens = certificados
        .map(
          (cert) => CertificadoPacoteGraficaItem(
        numero: certificados.indexOf(cert) + 1,
        participacaoId: cert.participante.participacaoId,
        alunoNome: cert.participante.alunoNome,
        graduacao: cert.participante.graduacaoNova,
        modelo: cert.participante.certificadoOuDiploma,
        nomeArquivo: cert.nomeArquivo,
      ),
    )
        .toList();

    return gerarRelatorioGraficaPdfPorItens(
      evento: evento,
      itens: itens,
      erros: const [],
      titulo: titulo,
    );
  }

  Future<Uint8List> gerarRelatorioGraficaPdfPorItens({
    required CertificadoEventoData evento,
    required List<CertificadoPacoteGraficaItem> itens,
    List<CertificadoPacoteGraficaErro> erros = const [],
    String titulo = 'Relatório de Certificados para Gráfica',
  }) async {
    final documento = pw.Document();

    final porModelo = <String, int>{};
    final porGraduacao = <String, int>{};

    for (final item in itens) {
      porModelo[item.modelo] = (porModelo[item.modelo] ?? 0) + 1;
      porGraduacao[item.graduacao] = (porGraduacao[item.graduacao] ?? 0) + 1;
    }

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return [
            pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Evento: ${evento.eventoNome}'),
            pw.Text('Cidade/Data: ${evento.localData}'),
            pw.Text('Total no pacote: ${itens.length}'),
            pw.Text('Erros/pulados: ${erros.length}'),
            pw.Text('Gerado em: ${DateTime.now().toIso8601String()}'),
            pw.SizedBox(height: 16),
            pw.Text(
              'Resumo por modelo',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Modelo', 'Quantidade'],
              data: porModelo.entries
                  .map((entry) => [entry.key, entry.value.toString()])
                  .toList(),
              border: pw.TableBorder.all(width: 0.4),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Resumo por graduação',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Graduação', 'Quantidade'],
              data: porGraduacao.entries
                  .map((entry) => [entry.key, entry.value.toString()])
                  .toList(),
              border: pw.TableBorder.all(width: 0.4),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Arquivos incluídos no ZIP',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['#', 'Aluno', 'Graduação', 'Modelo', 'Arquivo'],
              data: itens.map((item) {
                return [
                  item.numero.toString(),
                  item.alunoNome,
                  item.graduacao,
                  item.modelo,
                  item.nomeArquivo,
                ];
              }).toList(),
              border: pw.TableBorder.all(width: 0.35),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7.6),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FixedColumnWidth(22),
                1: const pw.FlexColumnWidth(2.4),
                2: const pw.FlexColumnWidth(1.6),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(2.4),
              },
            ),
            if (erros.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Certificados com erro ou ignorados',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ['Aluno', 'Motivo'],
                data: erros
                    .map((erro) => [erro.alunoNome, erro.mensagem])
                    .toList(),
                border: pw.TableBorder.all(width: 0.35),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ],
          ];
        },
      ),
    );

    return documento.save();
  }

  /// Método antigo mantido para compatibilidade.
  ///
  /// Para o fluxo otimizado de PDF individual dentro do ZIP, prefira montar
  /// o Archive em fila na tela e finalizar com [baixarZipBytes].
  Future<CertificadoPacoteGraficaGerado> gerarZipGrafica({
    required CertificadoEventoData evento,
    required List<CertificadoArquivoGerado> certificados,
    bool preferirPdf = true,
    bool enviarStorage = false,
    bool registrarFirestore = true,
  }) async {
    if (evento.eventoId.trim().isEmpty) {
      throw Exception('Evento sem ID. Não é possível gerar pacote.');
    }

    if (certificados.isEmpty) {
      throw Exception('Nenhum certificado informado para o pacote.');
    }

    final relatorioBytes = await gerarRelatorioGraficaPdf(
      evento: evento,
      certificados: certificados,
    );

    final archive = Archive();

    for (final certificado in certificados) {
      final bytes = preferirPdf
          ? certificado.pdfBytes ?? certificado.pngBytes
          : certificado.pngBytes ?? certificado.pdfBytes;

      if (bytes == null || bytes.isEmpty) {
        throw Exception(
          'Certificado sem bytes: ${certificado.participante.alunoNome}',
        );
      }

      archive.addFile(
        ArchiveFile(
          'certificados/${certificado.nomeArquivo}',
          bytes.length,
          bytes,
        ),
      );
    }

    const relatorioNome = 'RELATORIO_CERTIFICADOS_GRAFICA.pdf';

    archive.addFile(
      ArchiveFile(
        relatorioNome,
        relatorioBytes.length,
        relatorioBytes,
      ),
    );

    final zipBytes = Uint8List.fromList(
      ZipEncoder().encode(archive) ?? <int>[],
    );

    final resultado = CertificadoPacoteGraficaGerado(
      id: '',
      eventoId: evento.eventoId,
      nomeArquivoZip: nomeArquivoPacoteGrafica(evento),
      zipBytes: zipBytes,
      relatorioBytes: relatorioBytes,
      relatorioNome: relatorioNome,
      totalCertificados: certificados.length,
      linkZip: null,
      storagePath: null,
      certificadosNomes: certificados.map((e) => e.nomeArquivo).toList(),
      participacoesIds:
      certificados.map((e) => e.participante.participacaoId).toList(),
      criadoEm: DateTime.now(),
    );

    if (registrarFirestore) {
      final pacoteId = await registrarPacoteGrafica(resultado);
      return resultado.copyWith(id: pacoteId);
    }

    return resultado;
  }

  Future<CertificadoPacoteGraficaGerado> montarResultadoPacoteGrafica({
    required CertificadoEventoData evento,
    required Uint8List zipBytes,
    required Uint8List relatorioBytes,
    required List<CertificadoPacoteGraficaItem> itens,
    String relatorioNome = 'RELATORIO_CERTIFICADOS_GRAFICA.pdf',
    bool registrarFirestore = true,
  }) async {
    final resultado = CertificadoPacoteGraficaGerado(
      id: '',
      eventoId: evento.eventoId,
      nomeArquivoZip: nomeArquivoPacoteGrafica(evento),
      zipBytes: zipBytes,
      relatorioBytes: relatorioBytes,
      relatorioNome: relatorioNome,
      totalCertificados: itens.length,
      linkZip: null,
      storagePath: null,
      certificadosNomes: itens.map((e) => e.nomeArquivo).toList(),
      participacoesIds: itens.map((e) => e.participacaoId).toList(),
      criadoEm: DateTime.now(),
    );

    if (registrarFirestore) {
      final pacoteId = await registrarPacoteGrafica(resultado);
      return resultado.copyWith(id: pacoteId);
    }

    return resultado;
  }

  Future<String> registrarPacoteGrafica(
      CertificadoPacoteGraficaGerado pacote,
      ) async {
    if (pacote.eventoId.trim().isEmpty) {
      throw Exception('Evento sem ID para registrar pacote.');
    }

    final docRef = await _firestore
        .collection('eventos')
        .doc(pacote.eventoId)
        .collection('pacotes_grafica')
        .add(pacote.toMap());

    final batch = _firestore.batch();

    for (final participacaoId in pacote.participacoesIds) {
      if (participacaoId.trim().isEmpty) continue;

      final ref = _firestore
          .collection('participacoes_eventos_em_andamento')
          .doc(participacaoId);

      batch.update(ref, {
        'certificado_incluido_zip': true,
        'certificado_pacote_grafica_id': docRef.id,
        'certificado_pacote_grafica_nome': pacote.nomeArquivoZip,
        'certificado_atualizado_em': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    return docRef.id;
  }

  Future<void> baixarZipGrafica({
    required CertificadoPacoteGraficaGerado pacote,
  }) async {
    await baixarZipBytes(
      bytes: pacote.zipBytes,
      nomeArquivoZip: pacote.nomeArquivoZip,
    );
  }

  Future<void> baixarZipBytes({
    required Uint8List bytes,
    required String nomeArquivoZip,
  }) async {
    await FileSaver.instance.saveFile(
      name: nomeArquivoZip.replaceAll('.zip', ''),
      bytes: bytes,
      ext: 'zip',
      mimeType: MimeType.zip,
    );
  }

  Future<void> baixarRelatorioGrafica({
    required CertificadoPacoteGraficaGerado pacote,
  }) async {
    await FileSaver.instance.saveFile(
      name: pacote.relatorioNome.replaceAll('.pdf', ''),
      bytes: pacote.relatorioBytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> baixarLotePdf({
    required CertificadoLoteGerado lote,
  }) async {
    await FileSaver.instance.saveFile(
      name: lote.nomeArquivo.replaceAll('.pdf', ''),
      bytes: lote.pdfBytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<String> _uploadBytes({
    required Uint8List bytes,
    required String storagePath,
    required String contentType,
    Map<String, String>? metadata,
  }) async {
    final ref = _storage.ref().child(storagePath);

    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: metadata,
      ),
    );

    return ref.getDownloadURL();
  }

  String nomeArquivoLote({
    required CertificadoEventoData evento,
    required int numeroLote,
    required int totalLotes,
  }) {
    final eventoSlug = _slugify(evento.eventoNome);
    final lote = numeroLote.toString().padLeft(2, '0');
    final total = totalLotes.toString().padLeft(2, '0');

    return 'lote_${lote}_de_${total}_certificados_$eventoSlug.pdf';
  }

  String nomeArquivoPacoteGrafica(CertificadoEventoData evento) {
    final eventoSlug = _slugify(evento.eventoNome);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'pacote_grafica_certificados_${eventoSlug}_$timestamp.zip';
  }

  String _slugify(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}

class CertificadoArquivoGerado {
  final CertificadoParticipanteData participante;
  final String nomeArquivo;
  final Uint8List? pdfBytes;
  final Uint8List? pngBytes;

  const CertificadoArquivoGerado({
    required this.participante,
    required this.nomeArquivo,
    this.pdfBytes,
    this.pngBytes,
  });

  bool get temPdf => pdfBytes != null && pdfBytes!.isNotEmpty;
  bool get temPng => pngBytes != null && pngBytes!.isNotEmpty;

  CertificadoArquivoGerado copyWith({
    CertificadoParticipanteData? participante,
    String? nomeArquivo,
    Uint8List? pdfBytes,
    Uint8List? pngBytes,
  }) {
    return CertificadoArquivoGerado(
      participante: participante ?? this.participante,
      nomeArquivo: nomeArquivo ?? this.nomeArquivo,
      pdfBytes: pdfBytes ?? this.pdfBytes,
      pngBytes: pngBytes ?? this.pngBytes,
    );
  }
}

class CertificadoPacoteGraficaItem {
  final int numero;
  final String participacaoId;
  final String alunoNome;
  final String graduacao;
  final String modelo;
  final String nomeArquivo;

  const CertificadoPacoteGraficaItem({
    required this.numero,
    required this.participacaoId,
    required this.alunoNome,
    required this.graduacao,
    required this.modelo,
    required this.nomeArquivo,
  });
}

class CertificadoPacoteGraficaErro {
  final String alunoNome;
  final String mensagem;

  const CertificadoPacoteGraficaErro({
    required this.alunoNome,
    required this.mensagem,
  });
}

class CertificadoLoteGerado {
  final String id;
  final String eventoId;
  final int numeroLote;
  final int totalLotes;
  final int totalCertificados;
  final String nomeArquivo;
  final Uint8List pdfBytes;
  final String? linkPdf;
  final String? storagePath;
  final List<String> participacoesIds;
  final List<String> participantesNomes;
  final String status;
  final DateTime criadoEm;
  final bool impresso;

  const CertificadoLoteGerado({
    required this.id,
    required this.eventoId,
    required this.numeroLote,
    required this.totalLotes,
    required this.totalCertificados,
    required this.nomeArquivo,
    required this.pdfBytes,
    this.linkPdf,
    this.storagePath,
    required this.participacoesIds,
    required this.participantesNomes,
    required this.status,
    required this.criadoEm,
    required this.impresso,
  });

  Map<String, dynamic> toMap() {
    return {
      'evento_id': eventoId,
      'numero_lote': numeroLote,
      'total_lotes': totalLotes,
      'total_certificados': totalCertificados,
      'nome_arquivo': nomeArquivo,
      'link_pdf': linkPdf,
      'storage_path': storagePath,
      'participacoes': participacoesIds,
      'participantes_nomes': participantesNomes,
      'status': status,
      'impresso': impresso,
      'criado_em': Timestamp.fromDate(criadoEm),
      'atualizado_em': FieldValue.serverTimestamp(),
    };
  }

  CertificadoLoteGerado copyWith({
    String? id,
    String? eventoId,
    int? numeroLote,
    int? totalLotes,
    int? totalCertificados,
    String? nomeArquivo,
    Uint8List? pdfBytes,
    String? linkPdf,
    String? storagePath,
    List<String>? participacoesIds,
    List<String>? participantesNomes,
    String? status,
    DateTime? criadoEm,
    bool? impresso,
  }) {
    return CertificadoLoteGerado(
      id: id ?? this.id,
      eventoId: eventoId ?? this.eventoId,
      numeroLote: numeroLote ?? this.numeroLote,
      totalLotes: totalLotes ?? this.totalLotes,
      totalCertificados: totalCertificados ?? this.totalCertificados,
      nomeArquivo: nomeArquivo ?? this.nomeArquivo,
      pdfBytes: pdfBytes ?? this.pdfBytes,
      linkPdf: linkPdf ?? this.linkPdf,
      storagePath: storagePath ?? this.storagePath,
      participacoesIds: participacoesIds ?? this.participacoesIds,
      participantesNomes: participantesNomes ?? this.participantesNomes,
      status: status ?? this.status,
      criadoEm: criadoEm ?? this.criadoEm,
      impresso: impresso ?? this.impresso,
    );
  }
}

class CertificadoPacoteGraficaGerado {
  final String id;
  final String eventoId;
  final String nomeArquivoZip;
  final Uint8List zipBytes;
  final Uint8List relatorioBytes;
  final String relatorioNome;
  final int totalCertificados;
  final String? linkZip;
  final String? storagePath;
  final List<String> certificadosNomes;
  final List<String> participacoesIds;
  final DateTime criadoEm;

  const CertificadoPacoteGraficaGerado({
    required this.id,
    required this.eventoId,
    required this.nomeArquivoZip,
    required this.zipBytes,
    required this.relatorioBytes,
    required this.relatorioNome,
    required this.totalCertificados,
    this.linkZip,
    this.storagePath,
    required this.certificadosNomes,
    required this.participacoesIds,
    required this.criadoEm,
  });

  Map<String, dynamic> toMap() {
    return {
      'evento_id': eventoId,
      'nome_arquivo_zip': nomeArquivoZip,
      'relatorio_nome': relatorioNome,
      'total_certificados': totalCertificados,
      'link_zip': linkZip,
      'storage_path': storagePath,
      'certificados_nomes': certificadosNomes,
      'participacoes': participacoesIds,
      'status': 'gerado',
      'criado_em': Timestamp.fromDate(criadoEm),
      'atualizado_em': FieldValue.serverTimestamp(),
    };
  }

  CertificadoPacoteGraficaGerado copyWith({
    String? id,
    String? eventoId,
    String? nomeArquivoZip,
    Uint8List? zipBytes,
    Uint8List? relatorioBytes,
    String? relatorioNome,
    int? totalCertificados,
    String? linkZip,
    String? storagePath,
    List<String>? certificadosNomes,
    List<String>? participacoesIds,
    DateTime? criadoEm,
  }) {
    return CertificadoPacoteGraficaGerado(
      id: id ?? this.id,
      eventoId: eventoId ?? this.eventoId,
      nomeArquivoZip: nomeArquivoZip ?? this.nomeArquivoZip,
      zipBytes: zipBytes ?? this.zipBytes,
      relatorioBytes: relatorioBytes ?? this.relatorioBytes,
      relatorioNome: relatorioNome ?? this.relatorioNome,
      totalCertificados: totalCertificados ?? this.totalCertificados,
      linkZip: linkZip ?? this.linkZip,
      storagePath: storagePath ?? this.storagePath,
      certificadosNomes: certificadosNomes ?? this.certificadosNomes,
      participacoesIds: participacoesIds ?? this.participacoesIds,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }
}
