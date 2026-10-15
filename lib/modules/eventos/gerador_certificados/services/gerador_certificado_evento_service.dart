import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';

import 'package:uai_capoeira/modules/certificados/services/certificado_export_service.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/services/certificado_evento_mapper_service.dart';

typedef CertificadoVinculoLog = void Function(String mensagem);

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
  }) : _exportService = exportService ?? const CertificadoExportService(),
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

  Future<void> imprimirPdfDaPreview({required GlobalKey repaintKey}) async {
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
    String? emissaoKey,
  }) async {
    if (pdfBytes.isEmpty) {
      throw Exception('PDF vazio. Não é possível salvar certificado.');
    }

    if (evento.eventoId.trim().isEmpty) {
      throw Exception('Evento sem ID. Não é possível salvar certificado.');
    }

    if (participante.participacaoId.trim().isEmpty) {
      throw Exception(
        'Participação sem ID. Não é possível salvar certificado.',
      );
    }

    final fileName = nomeArquivoBase(
      evento: evento,
      participante: participante,
      extensao: 'pdf',
    );

    final slot = (emissaoKey ?? '').trim();
    final path = slot.isEmpty
        ? 'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/$fileName'
        : 'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/$slot/$fileName';

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
          if ((emissaoKey ?? '').trim().isNotEmpty)
            'emissao_key': emissaoKey!.trim(),
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
    String? emissaoV2Id,
    String? emissaoKey,
    String? codigoPublico,
    String? codigoHumano,
    String? urlAutenticidade,
    CertificadoVinculoLog? onLog,
  }) async {
    if (participante.participacaoId.trim().isEmpty) {
      throw Exception(
        'Participação sem ID. Não é possível vincular certificado.',
      );
    }

    // PATCH 2: nunca apague o certificado anterior antes do novo upload.
    // O putData no mesmo path publica a nova geração apenas quando o envio
    // conclui; se houver falha, não fazemos um delete destrutivo previamente.
    onLog?.call('☁️ Enviando novo PDF com substituição segura no Storage...');

    final link = await uploadPdfDoParticipante(
      pdfBytes: pdfBytes,
      evento: evento,
      participante: participante,
      emissaoKey: emissaoKey,
    );

    final slot = (emissaoKey ?? '').trim();
    final fileName = nomeArquivoBase(
      evento: evento,
      participante: participante,
      extensao: 'pdf',
    );
    final storagePath = slot.isEmpty
        ? 'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/$fileName'
        : 'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/$slot/$fileName';

    onLog?.call('🔗 Atualizando link do certificado na participação...');

    await _mapperService.marcarCertificadoGerado(
      participacaoId: participante.participacaoId,
      linkCertificado: link,
      storagePath: storagePath,
      tipoArquivo: 'pdf',
      // A identidade V2 só é confirmada no batch atômico de finalizar().
      // Antes disso a participação pode ter estado preparando/gerando/publicando,
      // mas nunca deve parecer OFICIAL apenas porque o upload terminou.
    );

    onLog?.call(
      emissaoV2Id != null && emissaoV2Id.trim().isNotEmpty
          ? '✅ PDF enviado. Aguardando confirmação atômica da emissão oficial...'
          : '✅ Novo certificado vinculado com sucesso.',
    );

    return link;
  }

  Future<String> gerarUploadERegistrarPdf({
    required GlobalKey repaintKey,
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
    CertificadoVinculoLog? onLog,
  }) async {
    final pdfBytes = await gerarPdfDaPreview(repaintKey);

    return uploadPdfDiretoERegistrar(
      pdfBytes: pdfBytes,
      evento: evento,
      participante: participante,
      onLog: onLog,
    );
  }

  // O Patch 2 removeu a exclusão antecipada do arquivo antigo.
  // O upload no mesmo path é suficiente e evita perder o PDF válido se a
  // rede falhar durante uma reemissão.

  String storagePathParticipante({
    required CertificadoEventoData evento,
    required CertificadoParticipanteData participante,
  }) {
    return 'eventos/${evento.eventoId}/certificados/${participante.participacaoId}/${nomeArquivoBase(evento: evento, participante: participante, extensao: 'pdf')}';
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
