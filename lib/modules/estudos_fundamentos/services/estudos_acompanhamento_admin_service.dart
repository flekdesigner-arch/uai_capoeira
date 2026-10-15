import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';

class EstudosAcompanhamentoAdminService {
  final FirebaseFirestore _firestore;

  EstudosAcompanhamentoAdminService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<EstudosAcompanhamentoGeral> carregarResumoAlunosVinculados({
    int limiteAlunos = 300,
  }) async {
    final base = await _carregarBase();
    final alunos = await carregarAlunosVinculados(limite: limiteAlunos);
    final resumos = <AlunoEstudosResumo>[];

    for (final aluno in alunos) {
      resumos.add(await _carregarResumoAluno(aluno, base));
    }

    return EstudosAcompanhamentoGeral(base: base, alunos: resumos);
  }

  Future<AlunoEstudosDashboard> carregarDashboardAluno(String alunoId) async {
    final base = await _carregarBase();
    final alunoDoc = await _firestore.collection('alunos').doc(alunoId).get();
    final aluno = AlunoVinculadoEstudos.tryFromDoc(alunoDoc);
    if (aluno == null) {
      throw Exception('Aluno não encontrado ou com dados inválidos.');
    }
    final progresso = await carregarProgressoAluno(alunoId);
    final resultados = await carregarResultadosAluno(alunoId);
    final tentativas = await carregarTentativasAluno(alunoId, limite: 100);
    final estudosValidos = base.estudoIdsPublicados;
    final progressoAtual = Map<String, ProgressoEstudoAdmin>.fromEntries(
      progresso.entries.where(
        (entry) => estudosValidos.contains(entry.value.estudoId),
      ),
    );
    final resultadosAtuais = Map<String, ResultadoEstudoAdmin>.fromEntries(
      resultados.entries.where(
        (entry) => estudosValidos.contains(entry.value.estudoId),
      ),
    );
    final tentativasAtuais = tentativas
        .where((tentativa) => estudosValidos.contains(tentativa.estudoId))
        .toList(growable: false);
    final registrosAntigos =
        progresso.length +
        resultados.length +
        tentativas.length -
        progressoAtual.length -
        resultadosAtuais.length -
        tentativasAtuais.length;
    final estudos = base.estudosPublicados
        .map((estudo) {
          final prog = progressoAtual[estudo.id];
          final result = resultadosAtuais[estudo.id];
          final tentativasEstudo = tentativasAtuais
              .where((tentativa) => tentativa.estudoId == estudo.id)
              .toList(growable: false);
          return EstudoProgressoAdmin(
            estudo: estudo,
            ciclo: base.cicloPorId[estudo.cicloId],
            progresso: prog,
            resultado: result,
            tentativas: tentativasEstudo,
          );
        })
        .toList(growable: false);
    final resumo = _montarResumo(
      aluno,
      base,
      progressoAtual,
      resultadosAtuais,
      tentativasAtuais,
      totalTentativas: tentativasAtuais.length,
      contarTentativasAntigas: true,
    );

    return AlunoEstudosDashboard(
      aluno: aluno,
      base: base,
      resumo: resumo,
      estudos: estudos,
      tentativas: tentativasAtuais,
      registrosAntigos: registrosAntigos,
    );
  }

  Future<List<AlunoVinculadoEstudos>> carregarAlunosVinculados({
    int limite = 300,
  }) async {
    final porId = <String, AlunoVinculadoEstudos>{};

    Future<void> adicionarDocs(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) async {
      for (final doc in docs) {
        if (porId.length >= limite) break;
        final aluno = AlunoVinculadoEstudos.tryFromDoc(doc);
        if (aluno != null && aluno.vinculadoConta) {
          porId[aluno.id] = aluno;
        }
      }
    }

    try {
      final vinculadosSnap = await _firestore
          .collection('alunos')
          .where('areaAlunoGoogleVinculado', isEqualTo: true)
          .limit(limite)
          .get(const GetOptions(source: Source.serverAndCache));
      await adicionarDocs(vinculadosSnap.docs);
    } catch (e) {
      debugPrint('Fallback ao buscar alunos vinculados por flag: $e');
    }

    DocumentSnapshot<Map<String, dynamic>>? ultimoDoc;
    var documentosLidos = 0;
    const tamanhoPagina = 300;
    final limiteLeitura = limite * 10;
    while (porId.length < limite && documentosLidos < limiteLeitura) {
      var query = _firestore
          .collection('alunos')
          .orderBy(FieldPath.documentId)
          .limit(tamanhoPagina);
      if (ultimoDoc != null) {
        query = query.startAfterDocument(ultimoDoc);
      }
      final snap = await query.get(
        const GetOptions(source: Source.serverAndCache),
      );
      if (snap.docs.isEmpty) break;
      documentosLidos += snap.docs.length;
      ultimoDoc = snap.docs.last;
      await adicionarDocs(snap.docs);
      if (snap.docs.length < tamanhoPagina) break;
    }

    final alunos = porId.values.toList();
    alunos.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return alunos;
  }

  Future<Map<String, ProgressoEstudoAdmin>> carregarProgressoAluno(
    String alunoId,
  ) async {
    final snap = await _firestore
        .collection('alunos_estudos_progresso')
        .doc(alunoId)
        .collection('estudos')
        .get();
    return {
      for (final doc in snap.docs)
        doc.id: ProgressoEstudoAdmin.fromDoc(doc, fallbackEstudoId: doc.id),
    };
  }

  Future<Map<String, ResultadoEstudoAdmin>> carregarResultadosAluno(
    String alunoId,
  ) async {
    final snap = await _firestore
        .collection('alunos_estudos_resultados')
        .doc(alunoId)
        .collection('estudos')
        .get();
    return {
      for (final doc in snap.docs)
        doc.id: ResultadoEstudoAdmin.fromDoc(doc, fallbackEstudoId: doc.id),
    };
  }

  Future<List<TentativaEstudoAdmin>> carregarTentativasAluno(
    String alunoId, {
    int limite = 30,
    bool incluirRespostas = true,
  }) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _firestore
          .collection('estudos_tentativas')
          .where('alunoId', isEqualTo: alunoId)
          .orderBy('finalizadoEm', descending: true)
          .limit(limite)
          .get();
    } catch (e) {
      debugPrint('Fallback ao ordenar tentativas por finalizadoEm: $e');
      try {
        snap = await _firestore
            .collection('estudos_tentativas')
            .where('alunoId', isEqualTo: alunoId)
            .orderBy('criadoEm', descending: true)
            .limit(limite)
            .get();
      } catch (e) {
        debugPrint('Fallback ao buscar tentativas sem orderBy: $e');
        snap = await _firestore
            .collection('estudos_tentativas')
            .where('alunoId', isEqualTo: alunoId)
            .limit(limite)
            .get();
      }
    }
    final tentativas = snap.docs
        .map(
          (doc) => TentativaEstudoAdmin.fromDoc(
            doc,
            incluirRespostas: incluirRespostas,
          ),
        )
        .toList();
    _ordenarTentativasMaisRecentes(tentativas);
    return tentativas;
  }

  Future<int?> contarTentativasAluno(String alunoId) async {
    final query = _firestore
        .collection('estudos_tentativas')
        .where('alunoId', isEqualTo: alunoId);
    try {
      final snap = await query.count().get();
      return snap.count ?? 0;
    } catch (e) {
      debugPrint(
        'Não foi possível contar tentativas do aluno $alunoId; exibindo contagem desconhecida: $e',
      );
      return null;
    }
  }

  Future<EstudosAcompanhamentoBase> _carregarBase() async {
    final ciclosSnap = await _firestore.collection('estudos_ciclos').get();
    final estudosSnap = await _firestore.collection('estudos').get();
    final ciclos = ciclosSnap.docs
        .map(EstudoCicloModel.fromDoc)
        .where((ciclo) => ciclo.status == EstudoCicloStatus.publicado)
        .toList();
    ciclos.sort((a, b) {
      final ordem = a.ordem.compareTo(b.ordem);
      if (ordem != 0) return ordem;
      return a.numero.compareTo(b.numero);
    });
    final cicloIds = ciclos.map((ciclo) => ciclo.id).toSet();
    final estudos = estudosSnap.docs
        .map(EstudoModel.fromDoc)
        .where(
          (estudo) =>
              estudo.status == EstudoCicloStatus.publicado &&
              estudo.mostrarNaLinhaDoTempo &&
              cicloIds.contains(estudo.cicloId),
        )
        .toList();
    estudos.sort((a, b) {
      final ciclo = a.cicloId.compareTo(b.cicloId);
      if (ciclo != 0) return ciclo;
      final ordem = a.ordem.compareTo(b.ordem);
      if (ordem != 0) return ordem;
      return a.numero.compareTo(b.numero);
    });
    return EstudosAcompanhamentoBase(
      ciclos: ciclos,
      estudosPublicados: estudos,
    );
  }

  Future<AlunoEstudosResumo> _carregarResumoAluno(
    AlunoVinculadoEstudos aluno,
    EstudosAcompanhamentoBase base,
  ) async {
    final progresso = await carregarProgressoAluno(aluno.id);
    final resultados = await carregarResultadosAluno(aluno.id);
    final totalTentativas = await contarTentativasAluno(aluno.id);
    final ultimaTentativa = await carregarTentativasAluno(
      aluno.id,
      limite: 1,
      incluirRespostas: false,
    );
    return _montarResumo(
      aluno,
      base,
      progresso,
      resultados,
      ultimaTentativa,
      totalTentativas: totalTentativas,
      contarTentativasAntigas: false,
    );
  }

  AlunoEstudosResumo _montarResumo(
    AlunoVinculadoEstudos aluno,
    EstudosAcompanhamentoBase base,
    Map<String, ProgressoEstudoAdmin> progresso,
    Map<String, ResultadoEstudoAdmin> resultados,
    List<TentativaEstudoAdmin> tentativas, {
    required int? totalTentativas,
    required bool contarTentativasAntigas,
  }) {
    final estudosValidos = base.estudoIdsPublicados;
    final progressoAtual = progresso.values
        .where((item) => estudosValidos.contains(item.estudoId))
        .toList(growable: false);
    final resultadosAtuais = resultados.values
        .where((item) => estudosValidos.contains(item.estudoId))
        .toList(growable: false);
    final tentativasAtuais = tentativas
        .where((item) => estudosValidos.contains(item.estudoId))
        .toList(growable: false);
    final total = base.estudosPublicados.length;
    final iniciados = progressoAtual
        .where((item) => item.iniciado)
        .length
        .clamp(0, total);
    final concluidosProgresso = progressoAtual
        .where((item) => item.concluido)
        .map((item) => item.estudoId)
        .toSet();
    final aprovados = resultadosAtuais
        .where((item) => item.aprovado)
        .map((item) => item.estudoId)
        .toSet();
    final concluidos = {
      ...concluidosProgresso,
      ...aprovados,
    }.length.clamp(0, total);
    final notas = <double>[
      ...resultadosAtuais.map((r) => r.nota).whereType<double>(),
    ];
    final media = notas.isEmpty
        ? null
        : notas.reduce((a, b) => a + b) / notas.length;
    final ultimoProgresso =
        progressoAtual
            .map((item) => item.dataReferencia)
            .whereType<DateTime>()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final ultimaTentativa = tentativasAtuais.isEmpty
        ? null
        : tentativasAtuais.first;
    final ultimoEstudoId = _ultimoEstudoId(
      Map.fromEntries(
        progressoAtual.map((item) => MapEntry(item.estudoId, item)),
      ),
      Map.fromEntries(
        resultadosAtuais.map((item) => MapEntry(item.estudoId, item)),
      ),
      tentativasAtuais,
    );
    final ultimoEstudo = base.estudoPorId[ultimoEstudoId];
    final percentual = total <= 0 ? 0 : ((concluidos / total) * 100).round();
    return AlunoEstudosResumo(
      aluno: aluno,
      totalEstudos: total,
      iniciados: iniciados,
      concluidos: concluidos,
      aprovados: aprovados.length.clamp(0, total),
      percentual: percentual,
      tentativas: totalTentativas,
      notaMedia: media,
      melhorNota: notas.isEmpty ? null : notas.reduce((a, b) => a > b ? a : b),
      ultimoAcesso:
          aluno.ultimoAcesso ??
          (ultimoProgresso.isEmpty ? null : ultimoProgresso.first) ??
          ultimaTentativa?.dataReferencia,
      ultimoEstudoTitulo: ultimoEstudo?.titulo ?? '',
      ultimaTentativa: ultimaTentativa?.dataReferencia,
      registrosAntigos:
          progresso.length +
          resultados.length -
          progressoAtual.length -
          resultadosAtuais.length +
          (contarTentativasAntigas
              ? (totalTentativas ?? tentativasAtuais.length) -
                    tentativasAtuais.length
              : 0),
    );
  }

  String _ultimoEstudoId(
    Map<String, ProgressoEstudoAdmin> progresso,
    Map<String, ResultadoEstudoAdmin> resultados,
    List<TentativaEstudoAdmin> tentativas,
  ) {
    final candidatos = <({String estudoId, DateTime data})>[];
    for (final item in progresso.values) {
      final data = item.dataReferencia;
      if (data != null && item.estudoId.isNotEmpty) {
        candidatos.add((estudoId: item.estudoId, data: data));
      }
    }
    for (final item in resultados.values) {
      final data = item.dataReferencia;
      if (data != null && item.estudoId.isNotEmpty) {
        candidatos.add((estudoId: item.estudoId, data: data));
      }
    }
    for (final item in tentativas) {
      final data = item.dataReferencia;
      if (data != null && item.estudoId.isNotEmpty) {
        candidatos.add((estudoId: item.estudoId, data: data));
      }
    }
    candidatos.sort((a, b) => b.data.compareTo(a.data));
    return candidatos.isEmpty ? '' : candidatos.first.estudoId;
  }
}

class EstudosAcompanhamentoGeral {
  final EstudosAcompanhamentoBase base;
  final List<AlunoEstudosResumo> alunos;

  const EstudosAcompanhamentoGeral({required this.base, required this.alunos});

  int get totalVinculados => alunos.length;
  int get iniciaram => alunos.where((a) => a.iniciados > 0).length;
  int get semIniciar => alunos.where((a) => a.iniciados == 0).length;
  int get totalTentativas =>
      alunos.fold(0, (total, a) => total + (a.tentativas ?? 0));
  bool get temTentativasDesconhecidas =>
      alunos.any((a) => a.tentativas == null);
  int get totalConcluidos => alunos.fold(0, (total, a) => total + a.concluidos);
  int get mediaProgresso => alunos.isEmpty
      ? 0
      : (alunos.fold(0, (total, a) => total + a.percentual) / alunos.length)
            .round();
}

class EstudosAcompanhamentoBase {
  final List<EstudoCicloModel> ciclos;
  final List<EstudoModel> estudosPublicados;

  const EstudosAcompanhamentoBase({
    required this.ciclos,
    required this.estudosPublicados,
  });

  Map<String, EstudoCicloModel> get cicloPorId => {
    for (final ciclo in ciclos) ciclo.id: ciclo,
  };

  Map<String, EstudoModel> get estudoPorId => {
    for (final estudo in estudosPublicados) estudo.id: estudo,
  };

  Set<String> get estudoIdsPublicados => {
    for (final estudo in estudosPublicados) estudo.id,
  };
}

class AlunoVinculadoEstudos {
  final String id;
  final String nome;
  final String fotoUrl;
  final String turma;
  final String academia;
  final String graduacao;
  final String contaEmail;
  final String contaNome;
  final String contaUid;
  final String metodoVinculo;
  final bool contaVinculadaFlag;
  final DateTime? vinculadoEm;
  final DateTime? ultimoAcesso;

  const AlunoVinculadoEstudos({
    required this.id,
    required this.nome,
    required this.fotoUrl,
    required this.turma,
    required this.academia,
    required this.graduacao,
    required this.contaEmail,
    required this.contaNome,
    required this.contaUid,
    required this.metodoVinculo,
    required this.contaVinculadaFlag,
    this.vinculadoEm,
    this.ultimoAcesso,
  });

  static AlunoVinculadoEstudos? tryFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    Map<String, dynamic>? data;
    try {
      data = doc.data();
    } catch (e) {
      debugPrint(
        'Aluno ignorado no acompanhamento (${doc.id}): dados inválidos.',
      );
      return null;
    }

    if (data == null) return null;

    try {
      return AlunoVinculadoEstudos._fromData(doc.id, data);
    } catch (e) {
      debugPrint(
        'Aluno ignorado no acompanhamento (${doc.id}): parser inválido.',
      );
      return null;
    }
  }

  factory AlunoVinculadoEstudos._fromData(
    String id,
    Map<String, dynamic> data,
  ) {
    final contaUaiUid = _asString(data['conta_uai_uid']);
    final googleUid = _asString(data['areaAlunoGoogleUid']);
    final contaUid = contaUaiUid.isNotEmpty ? contaUaiUid : googleUid;
    final contaEmail = _firstText(data, [
      'email_conta_uai',
      'areaAlunoGoogleEmail',
    ]);
    final contaNome = _firstText(data, [
      'areaAlunoGoogleNome',
      'nome_responsavel',
    ]);
    final metodoVinculo = contaUaiUid.isNotEmpty
        ? 'Conta UAI'
        : (googleUid.isNotEmpty || data['areaAlunoGoogleVinculado'] == true)
            ? 'Google'
            : '';

    return AlunoVinculadoEstudos(
      id: id,
      nome: _asString(data['nome'], fallback: 'Aluno sem nome'),
      fotoUrl: _asString(data['foto_perfil_aluno']),
      turma: _firstText(data, ['turma', 'turma_nome', 'nome_turma']),
      academia: _firstText(data, [
        'academia',
        'academia_nome',
        'nome_academia',
      ]),
      graduacao: _firstText(data, [
        'graduacao_nome',
        'graduacao_atual',
        'graduacao',
        'graduacao_id',
      ]),
      contaEmail: contaEmail,
      contaNome: contaNome,
      contaUid: contaUid,
      metodoVinculo: metodoVinculo,
      contaVinculadaFlag:
          data['areaAlunoGoogleVinculado'] == true || contaUaiUid.isNotEmpty,
      vinculadoEm: _asDate(
        data['areaAlunoVinculadoEm'] ?? data['areaAlunoGoogleVinculadoEm'],
      ),
      ultimoAcesso: _asDate(
        data['areaAlunoUltimoAcessoEm'] ??
            data['areaAlunoUltimoAcessoGoogleEm'],
      ),
    );
  }

  bool get vinculadoConta =>
      contaVinculadaFlag || contaUid.isNotEmpty || contaEmail.isNotEmpty;

  // Getters legados preservados para não quebrar widgets/relatórios antigos.
  String get googleEmail => contaEmail;
  String get googleNome => contaNome;
  String get googleUid => contaUid;
  bool get vinculadoGoogle => vinculadoConta;

  String get busca => [
    nome,
    turma,
    academia,
    graduacao,
    contaEmail,
    contaNome,
    metodoVinculo,
  ].join(' ').toLowerCase();
}

class AlunoEstudosResumo {
  final AlunoVinculadoEstudos aluno;
  final int totalEstudos;
  final int iniciados;
  final int concluidos;
  final int aprovados;
  final int percentual;
  final int? tentativas;
  final double? notaMedia;
  final double? melhorNota;
  final DateTime? ultimoAcesso;
  final String ultimoEstudoTitulo;
  final DateTime? ultimaTentativa;
  final int registrosAntigos;

  const AlunoEstudosResumo({
    required this.aluno,
    required this.totalEstudos,
    required this.iniciados,
    required this.concluidos,
    required this.aprovados,
    required this.percentual,
    required this.tentativas,
    required this.notaMedia,
    required this.melhorNota,
    required this.ultimoAcesso,
    required this.ultimoEstudoTitulo,
    required this.ultimaTentativa,
    required this.registrosAntigos,
  });

  int get pendentes => (totalEstudos - concluidos).clamp(0, totalEstudos);

  String get statusLabel {
    if (totalEstudos > 0 && concluidos >= totalEstudos) return 'Concluiu tudo';
    if (iniciados == 0 && tentativas == 0) return 'Não iniciou';
    if (percentual >= 50 || (tentativas != null && tentativas! >= 3)) {
      return 'Avançando';
    }
    if (precisaAtencao) return 'Precisa atenção';
    return 'Em andamento';
  }

  bool get precisaAtencao {
    final parado =
        ultimoAcesso != null &&
        DateTime.now().difference(ultimoAcesso!).inDays >= 30;
    return (tentativas != null && tentativas! >= 3 && aprovados == 0) || parado;
  }
}

class AlunoEstudosDashboard {
  final AlunoVinculadoEstudos aluno;
  final EstudosAcompanhamentoBase base;
  final AlunoEstudosResumo resumo;
  final List<EstudoProgressoAdmin> estudos;
  final List<TentativaEstudoAdmin> tentativas;
  final int registrosAntigos;

  const AlunoEstudosDashboard({
    required this.aluno,
    required this.base,
    required this.resumo,
    required this.estudos,
    required this.tentativas,
    required this.registrosAntigos,
  });

  Map<String, List<EstudoProgressoAdmin>> get estudosPorCiclo {
    final map = <String, List<EstudoProgressoAdmin>>{};
    for (final estudo in estudos) {
      map.putIfAbsent(estudo.estudo.cicloId, () => []).add(estudo);
    }
    return map;
  }
}

class EstudoProgressoAdmin {
  final EstudoModel estudo;
  final EstudoCicloModel? ciclo;
  final ProgressoEstudoAdmin? progresso;
  final ResultadoEstudoAdmin? resultado;
  final List<TentativaEstudoAdmin> tentativas;
  const EstudoProgressoAdmin({
    required this.estudo,
    required this.ciclo,
    required this.progresso,
    required this.resultado,
    required this.tentativas,
  });

  bool get iniciado =>
      progresso?.iniciado == true || tentativas.isNotEmpty || resultado != null;
  bool get concluido =>
      progresso?.concluido == true || resultado?.aprovado == true;
  String get statusLabel {
    if (resultado?.aprovado == true) return 'Aprovado';
    if (resultado != null && resultado?.aprovado == false) return 'Reprovado';
    if (concluido) return 'Concluído';
    if (iniciado) return 'Iniciado';
    return 'Não iniciado';
  }
}

class ProgressoEstudoAdmin {
  final String estudoId;
  final String cicloId;
  final String status;
  final int percentual;
  final DateTime? iniciadoEm;
  final DateTime? concluidoEm;
  final DateTime? atualizadoEm;
  final DateTime? ultimoAcessoEm;

  const ProgressoEstudoAdmin({
    required this.estudoId,
    required this.cicloId,
    required this.status,
    required this.percentual,
    this.iniciadoEm,
    this.concluidoEm,
    this.atualizadoEm,
    this.ultimoAcessoEm,
  });

  factory ProgressoEstudoAdmin.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    String fallbackEstudoId = '',
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ProgressoEstudoAdmin(
      estudoId: _asString(data['estudoId'], fallback: fallbackEstudoId),
      cicloId: _asString(data['cicloId']),
      status: _asString(data['status']),
      percentual: _asInt(data['percentualLeitura'] ?? data['percentual']),
      iniciadoEm: _asDate(data['iniciadoEm']),
      concluidoEm: _asDate(data['concluidoEm'] ?? data['concluídoEm']),
      atualizadoEm: _asDate(data['atualizadoEm']),
      ultimoAcessoEm: _asDate(
        data['ultimaVisualizacaoEm'] ?? data['ultimoAcessoEm'],
      ),
    );
  }

  bool get concluido => status == 'concluido' || percentual >= 100;
  bool get iniciado => status.isNotEmpty || percentual > 0;
  DateTime? get dataReferencia =>
      ultimoAcessoEm ?? atualizadoEm ?? concluidoEm ?? iniciadoEm;
}

class ResultadoEstudoAdmin {
  final String estudoId;
  final String cicloId;
  final double? nota;
  final bool aprovado;
  final int acertos;
  final int total;
  final DateTime? dataReferencia;
  final Map<String, dynamic> raw;

  const ResultadoEstudoAdmin({
    required this.estudoId,
    required this.cicloId,
    required this.nota,
    required this.aprovado,
    required this.acertos,
    required this.total,
    required this.dataReferencia,
    required this.raw,
  });

  factory ResultadoEstudoAdmin.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    String fallbackEstudoId = '',
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ResultadoEstudoAdmin(
      estudoId: _asString(data['estudoId'], fallback: fallbackEstudoId),
      cicloId: _asString(data['cicloId']),
      nota: _asDoubleOrNull(data['nota'] ?? data['percentual']),
      aprovado: _asBool(data['aprovado']),
      acertos: _asInt(data['acertos']),
      total: _asInt(data['totalQuestoes'] ?? data['total']),
      dataReferencia: _asDate(
        data['atualizadoEm'] ?? data['criadoEm'] ?? data['concluidoEm'],
      ),
      raw: data,
    );
  }
}

class TentativaEstudoAdmin {
  final String id;
  final String alunoId;
  final String estudoId;
  final String cicloId;
  final double? nota;
  final bool aprovado;
  final int acertos;
  final int total;
  final String status;
  final String origem;
  final DateTime? criadoEm;
  final DateTime? finalizadoEm;
  final List<dynamic> respostas;
  final Map<String, dynamic> raw;

  const TentativaEstudoAdmin({
    required this.id,
    required this.alunoId,
    required this.estudoId,
    required this.cicloId,
    required this.nota,
    required this.aprovado,
    required this.acertos,
    required this.total,
    required this.status,
    required this.origem,
    required this.criadoEm,
    required this.finalizadoEm,
    required this.respostas,
    required this.raw,
  });

  factory TentativaEstudoAdmin.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool incluirRespostas = true,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TentativaEstudoAdmin(
      id: doc.id,
      alunoId: _asString(data['alunoId']),
      estudoId: _asString(data['estudoId']),
      cicloId: _asString(data['cicloId']),
      nota: _asDoubleOrNull(data['nota'] ?? data['percentual']),
      aprovado: _asBool(data['aprovado']),
      acertos: _asInt(data['acertos']),
      total: _asInt(data['totalQuestoes'] ?? data['total']),
      status: _asString(data['status']),
      origem: _asString(data['origem']),
      criadoEm: _asDate(data['criadoEm']),
      finalizadoEm: _asDate(data['finalizadoEm'] ?? data['concluidoEm']),
      respostas: incluirRespostas && data['respostas'] is List
          ? List<dynamic>.from(data['respostas'] as List)
          : const [],
      raw: data,
    );
  }

  DateTime? get dataReferencia => finalizadoEm ?? criadoEm;
}

void _ordenarTentativasMaisRecentes(List<TentativaEstudoAdmin> tentativas) {
  tentativas.sort((a, b) {
    final ad = a.dataReferencia;
    final bd = b.dataReferencia;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
}

String _firstText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = _asString(data[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _asString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

double? _asDoubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return [
      'true',
      'sim',
      '1',
      'aprovado',
    ].contains(value.trim().toLowerCase());
  }
  return false;
}

DateTime? _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String formatarDataCurta(DateTime? value) {
  if (value == null) return '--';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String formatarNota(double? value) {
  if (value == null) return '--';
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(1);
}
