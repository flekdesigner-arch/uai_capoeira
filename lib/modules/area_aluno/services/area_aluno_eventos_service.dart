// lib/modules/area_aluno/services/area_aluno_eventos_service.dart
//
// Service público da Área do Aluno para consultar eventos em que o aluno
// está participando.
//
// IMPORTANTE:
// - Esta camada é SOMENTE LEITURA.
// - Não registra pagamento.
// - Não altera camisa.
// - Não altera graduação.
// - Não altera participação.
// - Apenas busca e organiza os dados para exibição na Área do Aluno.
//
// AJUSTE V5:
// - Mantém a imagem do evento pelo mesmo padrão da tela EventosScreen:
//   linkBanner / link_banner.
// - Busca dados reais da graduação nova na coleção graduacoes:
//   certificado_ou_diploma, frase, descrição e cores.
// - Entrega dados suficientes para a Área do Aluno mostrar a prévia real
//   usando CertificadoPreviewWidget, e não um desenho fake.

import 'package:cloud_firestore/cloud_firestore.dart';

class AreaAlunoEventosService {
  final FirebaseFirestore _db;

  AreaAlunoEventosService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<List<AreaAlunoEventoResumo>> listarEventosEmAndamentoDoAluno({
    required Map<String, dynamic> aluno,
    required Map<String, dynamic> authPayload,
  }) async {
    final alunoId = _resolverAlunoId(aluno: aluno, authPayload: authPayload);

    if (alunoId == null || alunoId.trim().isEmpty) {
      return [];
    }

    try {
      final snap = await _db
          .collection('participacoes_eventos_em_andamento')
          .where('aluno_id', isEqualTo: alunoId)
          .get();

      final result = <AreaAlunoEventoResumo>[];

      for (final doc in snap.docs) {
        final participacao = doc.data();
        final eventoId = _textoLimpo(
          participacao['evento_id'] ??
              participacao['eventoId'] ??
              participacao['id_evento'],
        );

        Map<String, dynamic> evento = {};

        if (eventoId != null) {
          final eventoDoc = await _db.collection('eventos').doc(eventoId).get();

          if (eventoDoc.exists) {
            evento = eventoDoc.data() ?? {};
          }
        }

        final patrocinioInfo = await _carregarPatrocinioParticipacao(
          eventoId: eventoId,
          participacaoId: doc.id,
        );

        final graduacaoNovaInfo = await _carregarGraduacaoNovaInfo(
          participacao: participacao,
        );

        final resumo = AreaAlunoEventoResumo.fromFirestore(
          participacaoId: doc.id,
          participacao: participacao,
          eventoId: eventoId,
          evento: evento,
          patrocinioInfo: patrocinioInfo,
          graduacaoNovaInfo: graduacaoNovaInfo,
        );

        if (resumo.eventoEmAndamento) {
          result.add(resumo);
        }
      }

      result.sort((a, b) {
        final aDate = a.dataEvento ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.dataEvento ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<AreaAlunoEventoResumo>> listarTodosEventosDoAluno({
    required Map<String, dynamic> aluno,
    required Map<String, dynamic> authPayload,
  }) async {
    final alunoId = _resolverAlunoId(aluno: aluno, authPayload: authPayload);

    if (alunoId == null || alunoId.trim().isEmpty) {
      return [];
    }

    try {
      final snap = await _db
          .collection('participacoes_eventos_em_andamento')
          .where('aluno_id', isEqualTo: alunoId)
          .get();

      final result = <AreaAlunoEventoResumo>[];

      for (final doc in snap.docs) {
        final participacao = doc.data();
        final eventoId = _textoLimpo(
          participacao['evento_id'] ??
              participacao['eventoId'] ??
              participacao['id_evento'],
        );

        Map<String, dynamic> evento = {};

        if (eventoId != null) {
          final eventoDoc = await _db.collection('eventos').doc(eventoId).get();

          if (eventoDoc.exists) {
            evento = eventoDoc.data() ?? {};
          }
        }

        final patrocinioInfo = await _carregarPatrocinioParticipacao(
          eventoId: eventoId,
          participacaoId: doc.id,
        );

        final graduacaoNovaInfo = await _carregarGraduacaoNovaInfo(
          participacao: participacao,
        );

        result.add(
          AreaAlunoEventoResumo.fromFirestore(
            participacaoId: doc.id,
            participacao: participacao,
            eventoId: eventoId,
            evento: evento,
            patrocinioInfo: patrocinioInfo,
            graduacaoNovaInfo: graduacaoNovaInfo,
          ),
        );
      }

      result.sort((a, b) {
        final aDate = a.dataEvento ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.dataEvento ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<_PatrocinioParticipacaoInfo> _carregarPatrocinioParticipacao({
    required String? eventoId,
    required String participacaoId,
  }) async {
    if (eventoId == null || eventoId.trim().isEmpty) {
      return const _PatrocinioParticipacaoInfo();
    }

    try {
      final patrocinadoresSnap = await _db
          .collection('patrocinadores_eventos')
          .where('evento_id', isEqualTo: eventoId)
          .get();

      double totalPatrocinado = 0;
      bool encontrouUso = false;

      for (final patrocinador in patrocinadoresSnap.docs) {
        final usosSnap = await patrocinador.reference
            .collection('usos')
            .where('participacao_id', isEqualTo: participacaoId)
            .get();

        for (final uso in usosSnap.docs) {
          encontrouUso = true;
          final data = uso.data();
          totalPatrocinado += _asDoubleSeguro(data['valor']);
        }
      }

      return _PatrocinioParticipacaoInfo(
        possuiPatrocinio: encontrouUso,
        totalPatrocinado: totalPatrocinado,
      );
    } catch (_) {
      return const _PatrocinioParticipacaoInfo();
    }
  }

  Future<_GraduacaoNovaInfo> _carregarGraduacaoNovaInfo({
    required Map<String, dynamic> participacao,
  }) async {
    final nomeDireto = _textoLimpo(
      participacao['graduacao_nova'] ?? participacao['graduacaoNova'],
    );

    final cor1Direta = _textoLimpo(
      participacao['graduacao_nova_cor1'] ??
          participacao['hex_cor1'] ??
          participacao['graduacao_cor1'],
    );

    final cor2Direta = _textoLimpo(
      participacao['graduacao_nova_cor2'] ??
          participacao['hex_cor2'] ??
          participacao['graduacao_cor2'],
    );

    final ponta1Direta = _textoLimpo(
      participacao['graduacao_nova_ponta1'] ??
          participacao['hex_ponta1'] ??
          participacao['graduacao_ponta1'],
    );

    final ponta2Direta = _textoLimpo(
      participacao['graduacao_nova_ponta2'] ??
          participacao['hex_ponta2'] ??
          participacao['graduacao_ponta2'],
    );

    final fraseDireta = _textoLimpo(
      participacao['frase'] ??
          participacao['frase_certificado'] ??
          participacao['fraseCertificado'],
    );

    final certificadoOuDiplomaDireto = _textoLimpo(
      participacao['certificado_ou_diploma'] ??
          participacao['certificadoOuDiploma'] ??
          participacao['tipo_certificado'] ??
          participacao['tipoCertificado'],
    );

    final graduacaoId = _textoLimpo(
      participacao['graduacao_nova_id'] ??
          participacao['graduacaoNovaId'] ??
          participacao['nova_graduacao_id'] ??
          participacao['novaGraduacaoId'],
    );

    if (graduacaoId == null || graduacaoId.trim().isEmpty) {
      return _GraduacaoNovaInfo(
        id: '',
        nome: nomeDireto ?? '',
        cor1: cor1Direta ?? '',
        cor2: cor2Direta ?? '',
        ponta1: ponta1Direta ?? '',
        ponta2: ponta2Direta ?? '',
        frase: fraseDireta ?? '',
        certificadoOuDiploma: certificadoOuDiplomaDireto ?? '',
      );
    }

    try {
      final doc = await _db.collection('graduacoes').doc(graduacaoId).get();

      if (!doc.exists) {
        return _GraduacaoNovaInfo(
          id: graduacaoId,
          nome: nomeDireto ?? '',
          cor1: cor1Direta ?? '',
          cor2: cor2Direta ?? '',
          ponta1: ponta1Direta ?? '',
          ponta2: ponta2Direta ?? '',
          frase: fraseDireta ?? '',
          certificadoOuDiploma: certificadoOuDiplomaDireto ?? '',
        );
      }

      final data = doc.data() ?? {};

      return _GraduacaoNovaInfo(
        id: graduacaoId,
        nome:
            nomeDireto ??
            _textoLimpo(
              data['nome_graduacao'] ??
                  data['nome'] ??
                  data['descricaoCompleta'] ??
                  data['descricao_completa'],
            ) ??
            '',
        cor1:
            cor1Direta ??
            _textoLimpo(data['hex_cor1'] ?? data['graduacao_cor1']) ??
            '',
        cor2:
            cor2Direta ??
            _textoLimpo(data['hex_cor2'] ?? data['graduacao_cor2']) ??
            '',
        ponta1:
            ponta1Direta ??
            _textoLimpo(data['hex_ponta1'] ?? data['graduacao_ponta1']) ??
            '',
        ponta2:
            ponta2Direta ??
            _textoLimpo(data['hex_ponta2'] ?? data['graduacao_ponta2']) ??
            '',
        frase:
            fraseDireta ??
            _textoLimpo(
              data['frase'] ??
                  data['frase_certificado'] ??
                  data['fraseCertificado'],
            ) ??
            '',
        certificadoOuDiploma:
            certificadoOuDiplomaDireto ??
            _textoLimpo(
              data['certificado_ou_diploma'] ??
                  data['certificadoOuDiploma'] ??
                  data['tipo_certificado'] ??
                  data['tipoCertificado'],
            ) ??
            '',
      );
    } catch (_) {
      return _GraduacaoNovaInfo(
        id: graduacaoId,
        nome: nomeDireto ?? '',
        cor1: cor1Direta ?? '',
        cor2: cor2Direta ?? '',
        ponta1: ponta1Direta ?? '',
        ponta2: ponta2Direta ?? '',
        frase: fraseDireta ?? '',
        certificadoOuDiploma: certificadoOuDiplomaDireto ?? '',
      );
    }
  }

  String? _resolverAlunoId({
    required Map<String, dynamic> aluno,
    required Map<String, dynamic> authPayload,
  }) {
    final candidatos = <dynamic>[
      aluno['id'],
      aluno['docId'],
      aluno['doc_id'],
      aluno['aluno_id'],
      aluno['alunoId'],
      authPayload['aluno_id'],
      authPayload['alunoId'],
      authPayload['id'],
      authPayload['docId'],
      authPayload['doc_id'],
    ];

    for (final item in candidatos) {
      final clean = _textoLimpo(item);
      if (clean != null) return clean;
    }

    return null;
  }

  static String? _textoLimpo(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'null') return null;

    return text;
  }

  static double _asDoubleSeguro(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().replaceAll(',', '.').trim() ?? '';
    if (text.isEmpty) return fallback;

    return double.tryParse(text) ?? fallback;
  }
}

class AreaAlunoEventoResumo {
  final String participacaoId;
  final String? eventoId;

  final Map<String, dynamic> participacao;
  final Map<String, dynamic> evento;

  final String nomeEvento;
  final String tipoEvento;
  final String statusEvento;
  final String statusParticipacao;

  final DateTime? dataEvento;
  final String cidade;
  final String local;
  final String logoEventoUrl;

  final String graduacaoAtual;
  final String graduacaoNova;
  final String graduacaoNovaId;
  final String graduacaoNovaCor1;
  final String graduacaoNovaCor2;
  final String graduacaoNovaPonta1;
  final String graduacaoNovaPonta2;
  final String graduacaoNovaFrase;
  final String certificadoOuDiploma;

  final String alunoNome;
  final String alunoCpf;
  final String alunoSexo;

  final String tipoCamisa;
  final String modelagemCamisa;
  final String tamanhoCamisa;
  final bool camisaEntregue;
  final bool presente;

  final double valorInscricao;
  final double valorCamisa;
  final double valorTotal;
  final double totalPago;
  final double saldo;
  final double totalPatrocinado;
  final double totalPagoDireto;
  final bool possuiPatrocinio;

  final String? linkCertificado;

  const AreaAlunoEventoResumo({
    required this.participacaoId,
    required this.eventoId,
    required this.participacao,
    required this.evento,
    required this.nomeEvento,
    required this.tipoEvento,
    required this.statusEvento,
    required this.statusParticipacao,
    required this.dataEvento,
    required this.cidade,
    required this.local,
    required this.logoEventoUrl,
    required this.graduacaoAtual,
    required this.graduacaoNova,
    required this.graduacaoNovaId,
    required this.graduacaoNovaCor1,
    required this.graduacaoNovaCor2,
    required this.graduacaoNovaPonta1,
    required this.graduacaoNovaPonta2,
    required this.graduacaoNovaFrase,
    required this.certificadoOuDiploma,
    required this.alunoNome,
    required this.alunoCpf,
    required this.alunoSexo,
    required this.tipoCamisa,
    required this.modelagemCamisa,
    required this.tamanhoCamisa,
    required this.camisaEntregue,
    required this.presente,
    required this.valorInscricao,
    required this.valorCamisa,
    required this.valorTotal,
    required this.totalPago,
    required this.saldo,
    required this.totalPatrocinado,
    required this.totalPagoDireto,
    required this.possuiPatrocinio,
    required this.linkCertificado,
  });

  factory AreaAlunoEventoResumo.fromFirestore({
    required String participacaoId,
    required String? eventoId,
    required Map<String, dynamic> participacao,
    required Map<String, dynamic> evento,
    required _PatrocinioParticipacaoInfo patrocinioInfo,
    required _GraduacaoNovaInfo graduacaoNovaInfo,
  }) {
    final nomeEvento =
        _textoLimpo(
          participacao['evento_nome'] ??
              participacao['nome_evento'] ??
              evento['nome'] ??
              evento['titulo'],
        ) ??
        'Evento';

    final tipoEvento =
        _textoLimpo(participacao['tipo_evento'] ?? evento['tipo']) ?? 'EVENTO';

    final statusEvento = _textoLimpo(evento['status']) ?? 'andamento';
    final statusParticipacao =
        _textoLimpo(participacao['status']) ?? 'pendente';

    final dataEvento = _converterData(
      participacao['data_evento'] ??
          participacao['dataEvento'] ??
          evento['data'] ??
          evento['data_evento'],
    );

    final valorInscricao = _asDoubleSeguro(
      participacao['valor_inscricao'] ?? participacao['valorInscricao'],
    );

    final valorCamisa = _asDoubleSeguro(
      participacao['valor_camisa'] ?? participacao['valorCamisa'],
    );

    final valorTotalFirestore = _asDoubleSeguro(
      participacao['valor_total'] ?? participacao['valorTotal'],
      fallback: -1,
    );

    final valorTotal = valorTotalFirestore >= 0
        ? valorTotalFirestore
        : valorInscricao + valorCamisa;

    final totalPago = _asDoubleSeguro(
      participacao['total_pago'] ?? participacao['totalPago'],
    );

    final saldo = (valorTotal - totalPago).clamp(0, double.infinity).toDouble();
    final totalPatrocinado = patrocinioInfo.totalPatrocinado;
    final totalPagoDireto = (totalPago - totalPatrocinado)
        .clamp(0, double.infinity)
        .toDouble();

    return AreaAlunoEventoResumo(
      participacaoId: participacaoId,
      eventoId: eventoId,
      participacao: participacao,
      evento: evento,
      nomeEvento: nomeEvento,
      tipoEvento: tipoEvento,
      statusEvento: statusEvento,
      statusParticipacao: statusParticipacao,
      dataEvento: dataEvento,
      cidade: _textoLimpo(evento['cidade'] ?? participacao['cidade']) ?? '',
      local:
          _textoLimpo(
            evento['local'] ??
                evento['local_evento'] ??
                participacao['local_evento'],
          ) ??
          '',
      logoEventoUrl: _extrairLogoEvento(evento, participacao) ?? '',
      graduacaoAtual:
          _textoLimpo(
            participacao['graduacao'] ??
                participacao['graduacao_atual'] ??
                participacao['graduacaoAtual'],
          ) ??
          '',
      graduacaoNova: graduacaoNovaInfo.nome,
      graduacaoNovaId: graduacaoNovaInfo.id,
      graduacaoNovaCor1: graduacaoNovaInfo.cor1,
      graduacaoNovaCor2: graduacaoNovaInfo.cor2,
      graduacaoNovaPonta1: graduacaoNovaInfo.ponta1,
      graduacaoNovaPonta2: graduacaoNovaInfo.ponta2,
      graduacaoNovaFrase: graduacaoNovaInfo.frase,
      certificadoOuDiploma: graduacaoNovaInfo.certificadoOuDiploma,
      alunoNome:
          _textoLimpo(
            participacao['aluno_nome'] ??
                participacao['nome_aluno'] ??
                participacao['nome'],
          ) ??
          'Aluno',
      alunoCpf:
          _textoLimpo(
            participacao['cpf'] ??
                participacao['aluno_cpf'] ??
                participacao['cpf_aluno'],
          ) ??
          '',
      alunoSexo:
          _textoLimpo(
            participacao['sexo'] ??
                participacao['aluno_sexo'] ??
                participacao['sexo_aluno'] ??
                participacao['genero'],
          ) ??
          '',
      tipoCamisa: _tipoCamisaLabel(participacao['tipo_camisa']),
      modelagemCamisa: _modelagemCamisaLabel(participacao['modelagem_camisa']),
      tamanhoCamisa: _textoLimpo(participacao['tamanho_camisa']) ?? '',
      camisaEntregue: participacao['camisa_entregue'] == true,
      presente: participacao['presente'] == true,
      valorInscricao: valorInscricao,
      valorCamisa: valorCamisa,
      valorTotal: valorTotal,
      totalPago: totalPago,
      saldo: saldo,
      totalPatrocinado: totalPatrocinado,
      totalPagoDireto: totalPagoDireto,
      possuiPatrocinio: patrocinioInfo.possuiPatrocinio,
      linkCertificado: _extrairLinkCertificado(participacao),
    );
  }

  bool get eventoEmAndamento {
    final status = statusEvento.toLowerCase().trim();
    return status == 'andamento' ||
        status == 'em andamento' ||
        status == 'ativo' ||
        status == 'aberto';
  }

  bool get eventoFinalizado {
    final status = statusEvento.toLowerCase().trim();
    return status == 'finalizado' ||
        status == 'encerrado' ||
        status == 'concluido' ||
        status == 'concluído';
  }

  bool get temCamisa => tamanhoCamisa.trim().isNotEmpty;

  bool get temCertificado =>
      linkCertificado != null && linkCertificado!.trim().isNotEmpty;

  bool get pagamentoQuitado => valorTotal > 0 && saldo <= 0.01;

  bool get pagamentoParcial => totalPago > 0 && saldo > 0.01;

  bool get temNovaGraduacao => graduacaoNova.trim().isNotEmpty;

  bool get temCoresNovaGraduacao {
    return graduacaoNovaCor1.trim().isNotEmpty ||
        graduacaoNovaCor2.trim().isNotEmpty ||
        graduacaoNovaPonta1.trim().isNotEmpty ||
        graduacaoNovaPonta2.trim().isNotEmpty;
  }

  String get statusPagamentoLabel {
    if (valorTotal <= 0) return 'Sem cobrança';
    if (pagamentoQuitado) return 'Pago';
    if (pagamentoParcial) return 'Parcial';
    return 'Pendente';
  }

  String get origemPagamentoLabel {
    if (valorTotal <= 0) return 'Sem cobrança';
    if (possuiPatrocinio && totalPagoDireto > 0.01) {
      return 'Pagamento + patrocínio';
    }
    if (possuiPatrocinio) return 'Patrocinado';
    return 'Pagamento';
  }

  String get camisaLabel {
    if (!temCamisa) return 'Não informada';

    final partes = <String>[
      if (modelagemCamisa.isNotEmpty) modelagemCamisa,
      if (tipoCamisa.isNotEmpty) tipoCamisa,
      tamanhoCamisa,
    ];

    return partes.join(' • ');
  }

  String get certificadoLabel {
    if (temCertificado) return 'Disponível';
    return 'Ainda não disponível';
  }

  static String? _textoLimpo(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'null') return null;

    return text;
  }

  static double _asDoubleSeguro(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().replaceAll(',', '.').trim() ?? '';
    if (text.isEmpty) return fallback;

    return double.tryParse(text) ?? fallback;
  }

  static DateTime? _converterData(dynamic value) {
    if (value == null) return null;

    try {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;

      if (value is String) {
        final text = value.trim();
        if (text.isEmpty) return null;
        return DateTime.tryParse(text);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static String _normalizarTipoCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'MANGA_LONGA' ||
        clean == 'LONGA' ||
        clean == 'MANGA_COMPRIDA') {
      return 'MANGA_LONGA';
    }

    if (clean == 'REGATA') return 'REGATA';

    return 'MANGA';
  }

  static String _tipoCamisaLabel(dynamic value) {
    switch (_normalizarTipoCamisa(value)) {
      case 'MANGA_LONGA':
        return 'Manga Longa';
      case 'REGATA':
        return 'Regata';
      case 'MANGA':
      default:
        return 'Manga';
    }
  }

  static String _normalizarModelagemCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'BABYLOOK' ||
        clean == 'BABY_LOOK' ||
        clean == 'BABY_LOOK_FEMININA' ||
        clean == 'FEMININA') {
      return 'BABY_LOOK';
    }

    return 'NORMAL';
  }

  static String _modelagemCamisaLabel(dynamic value) {
    switch (_normalizarModelagemCamisa(value)) {
      case 'BABY_LOOK':
        return 'Baby Look';
      case 'NORMAL':
      default:
        return 'Normal';
    }
  }

  static String? _extrairLogoEvento(
    Map<String, dynamic> evento,
    Map<String, dynamic> participacao,
  ) {
    final candidatos = <dynamic>[
      evento['linkBanner'],
      evento['link_banner'],
      evento['banner'],
      evento['bannerUrl'],
      evento['banner_url'],
      evento['logo_url'],
      evento['logoUrl'],
      evento['imagem_url'],
      evento['imagemUrl'],
      evento['arte_url'],
      evento['arteUrl'],
      evento['foto_url'],
      evento['fotoUrl'],
      evento['logo'],
      evento['imagem'],
      participacao['evento_link_banner'],
      participacao['eventoLinkBanner'],
      participacao['evento_logo_url'],
      participacao['eventoLogoUrl'],
      participacao['logo_evento'],
    ];

    for (final item in candidatos) {
      final clean = _textoLimpo(item);
      if (clean != null) return clean;
    }

    return null;
  }

  static String? _extrairLinkCertificado(Map<String, dynamic> data) {
    final candidatos = <dynamic>[
      data['link_certificado'],
      data['linkCertificado'],
      data['certificado_url'],
      data['certificadoUrl'],
      data['url_certificado'],
      data['urlCertificado'],
      data['certificado'],
      data['certificado_link'],
      data['certificadoLink'],
    ];

    for (final item in candidatos) {
      final clean = _textoLimpo(item);
      if (clean != null) return clean;
    }

    return null;
  }
}

class _PatrocinioParticipacaoInfo {
  final bool possuiPatrocinio;
  final double totalPatrocinado;

  const _PatrocinioParticipacaoInfo({
    this.possuiPatrocinio = false,
    this.totalPatrocinado = 0,
  });
}

class _GraduacaoNovaInfo {
  final String id;
  final String nome;
  final String cor1;
  final String cor2;
  final String ponta1;
  final String ponta2;
  final String frase;
  final String certificadoOuDiploma;

  const _GraduacaoNovaInfo({
    required this.id,
    required this.nome,
    required this.cor1,
    required this.cor2,
    required this.ponta1,
    required this.ponta2,
    required this.frase,
    required this.certificadoOuDiploma,
  });
}
