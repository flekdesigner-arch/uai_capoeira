import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';

import 'package:uai_capoeira/modules/certificados/services/certificado_export_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_evento_mapper_service.dart';

class GeradorCertificadoEventoService {
  final CertificadoExportService _exportService;
  final CertificadoEventoMapperService _mapperService;
  final FirebaseStorage _storage;

  GeradorCertificadoEventoService({
    CertificadoExportService? exportService,
    CertificadoEventoMapperService? mapperService,
    FirebaseStorage? storage,
  })  : _exportService = exportService ?? const CertificadoExportService(),
        _mapperService = mapperService ?? CertificadoEventoMapperService(),
        _storage = storage ?? FirebaseStorage.instance;

  Future<Uint8List> capturarPngDaPreview(
      GlobalKey repaintKey, {
        double pixelRatio = 4.0,
      }) {
    return _exportService.capturarPreviewComoPng(
      repaintKey,
      pixelRatio: pixelRatio,
    );
  }

  Future<Uint8List> gerarPdfDaPreview(
      GlobalKey repaintKey, {
        double pixelRatio = 4.0,
      }) async {
    final pngBytes = await capturarPngDaPreview(
      repaintKey,
      pixelRatio: pixelRatio,
    );

    return _exportService.gerarPdfA4Paisagem(pngBytes);
  }

  Future<void> baixarPngDaPreview({
    required GlobalKey repaintKey,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    final pngBytes = await capturarPngDaPreview(repaintKey);

    await _exportService.salvarPng(
      bytes: pngBytes,
      nomeBase: nomeArquivoBase(
        evento: evento,
        participante: participante,
        extensao: null,
      ),
    );
  }

  Future<void> baixarPdfDaPreview({
    required GlobalKey repaintKey,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    final pdfBytes = await gerarPdfDaPreview(repaintKey);

    await _exportService.salvarPdf(
      bytes: pdfBytes,
      nomeBase: nomeArquivoBase(
        evento: evento,
        participante: participante,
        extensao: null,
      ),
    );
  }

  Future<void> imprimirPdfDaPreview({
    required GlobalKey repaintKey,
  }) async {
    final pdfBytes = await gerarPdfDaPreview(repaintKey);
    await _exportService.imprimirPdf(pdfBytes);
  }

  Future<void> compartilharPdfDaPreview({
    required GlobalKey repaintKey,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    final pdfBytes = await gerarPdfDaPreview(repaintKey);

    await _exportService.compartilharPdf(
      bytes: pdfBytes,
      nomeBase: nomeArquivoBase(
        evento: evento,
        participante: participante,
        extensao: null,
      ),
    );
  }

  Future<String> uploadPdfDoParticipante({
    required Uint8List pdfBytes,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    if (evento.eventoId.trim().isEmpty) {
      throw Exception('Evento sem ID. Não é possível salvar certificado.');
    }

    if (participante.participacaoId.trim().isEmpty) {
      throw Exception('Participação sem ID. Não é possível salvar certificado.');
    }

    final fileName = nomeArquivoBase(
      evento: evento,
      participante: participante,
      extensao: 'pdf',
    );

    final path =
        'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/$fileName';

    final ref = _storage.ref().child(path);

    await ref.putData(
      pdfBytes,
      SettableMetadata(
        contentType: 'application/pdf',
        customMetadata: {
          'evento_id': evento.eventoId,
          'participacao_id': participante.participacaoId,
          'aluno_id': participante.alunoId,
          'aluno_nome': participante.alunoNome,
          'graduacao_nova_id': participante.graduacaoNovaId,
          'graduacao_nova': participante.graduacaoNova,
          'tipo_certificado': participante.certificadoOuDiploma,
          'gerado_em': DateTime.now().toIso8601String(),
        },
      ),
    );

    return ref.getDownloadURL();
  }

  Future<String> gerarUploadERegistrarPdf({
    required GlobalKey repaintKey,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    final pdfBytes = await gerarPdfDaPreview(repaintKey);

    final link = await uploadPdfDoParticipante(
      pdfBytes: pdfBytes,
      evento: evento,
      participante: participante,
    );

    await _mapperService.marcarCertificadoGerado(
      participacaoId: participante.participacaoId,
      linkCertificado: link,
      storagePath:
      'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/${nomeArquivoBase(evento: evento, participante: participante, extensao: 'pdf')}',
      tipoArquivo: 'pdf',
    );

    return link;
  }

  String nomeArquivoBase({
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
    String? extensao,
  }) {
    final eventoSlug = _slugify(evento.eventoNome);
    final alunoSlug = _slugify(participante.alunoNome);
    final graduacaoSlug = _slugify(participante.graduacaoNova);
    final tipoSlug = _slugify(participante.certificadoOuDiploma);

    final base = [
      'certificado',
      if (eventoSlug.isNotEmpty) eventoSlug,
      if (tipoSlug.isNotEmpty) tipoSlug,
      if (alunoSlug.isNotEmpty) alunoSlug,
      if (graduacaoSlug.isNotEmpty) graduacaoSlug,
    ].join('_');

    if (extensao == null || extensao.trim().isEmpty) return base;

    final cleanExt = extensao.replaceAll('.', '').trim();
    return '$base.$cleanExt';
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
