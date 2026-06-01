import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  final FirebaseFirestore _firestore;

  GeradorCertificadoEventoService({
    CertificadoExportService? exportService,
    CertificadoEventoMapperService? mapperService,
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
  })  : _exportService = exportService ?? const CertificadoExportService(),
        _mapperService = mapperService ?? CertificadoEventoMapperService(),
        _storage = storage ?? FirebaseStorage.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

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
    if (pdfBytes.isEmpty) {
      throw Exception('PDF vazio. Não é possível salvar certificado.');
    }

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

  Future<String> uploadPdfDiretoERegistrar({
    required Uint8List pdfBytes,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    if (participante.participacaoId.trim().isEmpty) {
      throw Exception('Participação sem ID. Não é possível vincular certificado.');
    }

    final dadosAntigos = await _buscarDadosCertificadoAntigo(
      participacaoId: participante.participacaoId,
    );

    await _tentarApagarCertificadoAntigoDoStorage(dadosAntigos);

    final link = await uploadPdfDoParticipante(
      pdfBytes: pdfBytes,
      evento: evento,
      participante: participante,
    );

    final storagePath =
        'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/${nomeArquivoBase(evento: evento, participante: participante, extensao: 'pdf')}';

    await _mapperService.marcarCertificadoGerado(
      participacaoId: participante.participacaoId,
      linkCertificado: link,
      storagePath: storagePath,
      tipoArquivo: 'pdf',
    );

    return link;
  }

  Future<String> gerarUploadERegistrarPdf({
    required GlobalKey repaintKey,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) async {
    final pdfBytes = await gerarPdfDaPreview(repaintKey);

    return uploadPdfDiretoERegistrar(
      pdfBytes: pdfBytes,
      evento: evento,
      participante: participante,
    );
  }

  Future<Map<String, dynamic>> _buscarDadosCertificadoAntigo({
    required String participacaoId,
  }) async {
    try {
      final doc = await _firestore
          .collection('participacoes_eventos_em_andamento')
          .doc(participacaoId)
          .get();

      return doc.data() ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _tentarApagarCertificadoAntigoDoStorage(
      Map<String, dynamic> dados,
      ) async {
    final storagePath = _primeiroTextoNaoVazio([
      dados['certificado_storage_path'],
      dados['storage_path_certificado'],
      dados['certificado_path'],
      dados['link_certificado_storage_path'],
    ]);

    if (storagePath != null) {
      try {
        await _storage.ref().child(storagePath).delete();
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          // Continua tentando pelo link, se houver.
        }
      } catch (_) {
        // Continua tentando pelo link, se houver.
      }
    }

    final link = _primeiroTextoNaoVazio([
      dados['link_certificado'],
      dados['certificado_url'],
      dados['url_certificado'],
    ]);

    if (link == null || !_pareceUrlFirebaseStorage(link)) {
      return;
    }

    try {
      await _storage.refFromURL(link).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
    } catch (_) {
      // Link externo, link antigo inválido ou sem permissão: não bloqueia o novo upload.
    }
  }

  bool _pareceUrlFirebaseStorage(String value) {
    final lower = value.toLowerCase();

    return lower.contains('firebasestorage.googleapis.com') ||
        lower.contains('storage.googleapis.com') ||
        lower.startsWith('gs://');
  }

  String? _primeiroTextoNaoVazio(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }

    return null;
  }

  String nomeArquivoBase({
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
    String? extensao,
  }) {
    final alunoSlug = _slugify(participante.alunoNome);

    final base = alunoSlug.isEmpty ? 'certificado' : alunoSlug.toUpperCase();

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
