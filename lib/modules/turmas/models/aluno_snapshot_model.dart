import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo que representa o snapshot visual de um aluno para a Dashboard V2.
/// 
/// Este modelo centraliza os dados processados pelo backend em `functions/index.js`
/// (reconstruirDashboardTurmaCacheInterno) para exibição rápida e tipada na Dashboard.
class AlunoSnapshotModel {
  final String alunoId;
  final String turmaId;
  final String nome;
  final String nomeBusca;
  final String fotoUrl;
  final String sexo;
  final String sexoNormalizado;
  final DateTime? dataNascimento;
  final int? idade;
  final String faixaIdade;
  final bool ativo;

  // Graduação
  final String? graduacaoId;
  final String graduacaoNome;
  final int graduacaoNivel;
  final String hexCor1;
  final String hexCor2;
  final String hexPonta1;
  final String hexPonta2;

  // Frequência Agregada
  final int freqTotal;
  final int freqSemana;
  final int freqMes;
  final int freqAno; // No Firestore pode estar ausente se deletado no JS, mas calculamos.

  // Frequência Histórica (Séries Temporais)
  final Map<String, int> freqPorAno;
  final Map<String, int> freqPorMes;
  final Map<String, int> freqPorSemana;
  final Map<String, int> freqPorDiaSemana;

  // Período de referência no momento da geração
  final String mesKeyAtual;
  final String semanaKeyAtual;
  final String anoKeyAtual;
  final String? semanaDashboardInicio;
  final String? semanaRegra;

  // Metadados Frequência
  final String frequenciaOrigem;
  final DateTime? frequenciaRecalculadaEm;

  // Avaliação Técnica
  final double avaliacaoNota;
  final String avaliacaoConceito;

  // Destaque & Rankings (Calculados 60/40)
  final double destaqueScoreTotal;
  final double destaqueScoreSemana;
  final double destaqueScoreMes;
  final double destaqueScorePorAno;
  final int rankingTotal;
  final int rankingSemana;
  final int rankingMes;
  final int rankingPorAno;

  // Controle de Versão e Sync
  final int cacheVersao;
  final DateTime? atualizadoEm;

  AlunoSnapshotModel({
    required this.alunoId,
    required this.turmaId,
    required this.nome,
    required this.nomeBusca,
    required this.fotoUrl,
    required this.sexo,
    required this.sexoNormalizado,
    this.dataNascimento,
    this.idade,
    required this.faixaIdade,
    required this.ativo,
    this.graduacaoId,
    required this.graduacaoNome,
    required this.graduacaoNivel,
    required this.hexCor1,
    required this.hexCor2,
    required this.hexPonta1,
    required this.hexPonta2,
    required this.freqTotal,
    required this.freqSemana,
    required this.freqMes,
    required this.freqAno,
    required this.freqPorAno,
    required this.freqPorMes,
    required this.freqPorSemana,
    required this.freqPorDiaSemana,
    required this.mesKeyAtual,
    required this.semanaKeyAtual,
    required this.anoKeyAtual,
    this.semanaDashboardInicio,
    this.semanaRegra,
    required this.frequenciaOrigem,
    this.frequenciaRecalculadaEm,
    required this.avaliacaoNota,
    required this.avaliacaoConceito,
    required this.destaqueScoreTotal,
    required this.destaqueScoreSemana,
    required this.destaqueScoreMes,
    required this.destaqueScorePorAno,
    required this.rankingTotal,
    required this.rankingSemana,
    required this.rankingMes,
    required this.rankingPorAno,
    required this.cacheVersao,
    this.atualizadoEm,
  });

  /// Construtor a partir de um Mapa (Firestore ou Cache local).
  factory AlunoSnapshotModel.fromMap(Map<String, dynamic> map, {String? id}) {
    final freqTotal = _toInt(map['freq_total']);
    final freqPorAno = _toMapStringInt(map['freq_por_ano']);
    final anoKey = map['ano_key_atual']?.toString() ?? DateTime.now().year.toString();

    return AlunoSnapshotModel(
      alunoId: id ?? map['aluno_id']?.toString() ?? '',
      turmaId: map['turma_id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      nomeBusca: map['nome_busca']?.toString() ?? '',
      fotoUrl: map['foto_url']?.toString() ?? '',
      sexo: map['sexo']?.toString() ?? '',
      sexoNormalizado: map['sexo_normalizado']?.toString() ?? 'NAO_INFORMADO',
      dataNascimento: _toDateTime(map['data_nascimento']),
      idade: _toInt(map['idade']),
      faixaIdade: map['faixa_idade']?.toString() ?? 'NAO_INFORMADA',
      ativo: map['ativo'] == true,
      graduacaoId: map['graduacao_id']?.toString(),
      graduacaoNome: map['graduacao_nome']?.toString() ?? 'SEM GRADUAÇÃO',
      graduacaoNivel: _toInt(map['graduacao_nivel']),
      hexCor1: map['hex_cor1']?.toString() ?? '#FFFFFF',
      hexCor2: map['hex_cor2']?.toString() ?? '#FFFFFF',
      hexPonta1: map['hex_ponta1']?.toString() ?? '#FFFFFF',
      hexPonta2: map['hex_ponta2']?.toString() ?? '#FFFFFF',
      freqTotal: freqTotal,
      freqSemana: _toInt(map['freq_semana']),
      freqMes: _toInt(map['freq_mes']),
      freqAno: _toInt(map['freq_ano'] ?? freqPorAno[anoKey]),
      freqPorAno: freqPorAno,
      freqPorMes: _toMapStringInt(map['freq_por_mes']),
      freqPorSemana: _toMapStringInt(map['freq_por_semana']),
      freqPorDiaSemana: _toMapStringInt(map['freq_por_dia_semana']),
      mesKeyAtual: map['mes_key_atual']?.toString() ?? '',
      semanaKeyAtual: map['semana_key_atual']?.toString() ?? '',
      anoKeyAtual: anoKey,
      semanaDashboardInicio: map['semana_dashboard_inicio']?.toString(),
      semanaRegra: map['semana_regra']?.toString(),
      frequenciaOrigem: map['frequencia_origem']?.toString() ?? '',
      frequenciaRecalculadaEm: _toDateTime(map['frequencia_recalculada_em']),
      avaliacaoNota: _toDouble(map['avaliacao_nota']),
      avaliacaoConceito: map['avaliacao_conceito']?.toString() ?? '',
      destaqueScoreTotal: _toDouble(map['destaque_score_total']),
      destaqueScoreSemana: _toDouble(map['destaque_score_semana']),
      destaqueScoreMes: _toDouble(map['destaque_score_mes']),
      destaqueScorePorAno: _toDouble(map['destaque_score_por_ano']),
      rankingTotal: _toInt(map['ranking_total']),
      rankingSemana: _toInt(map['ranking_semana']),
      rankingMes: _toInt(map['ranking_mes']),
      rankingPorAno: _toInt(map['ranking_por_ano']),
      cacheVersao: _toInt(map['cache_versao']),
      atualizadoEm: _toDateTime(map['atualizado_em']),
    );
  }

  /// Construtor a partir de um DocumentSnapshot do Firestore.
  factory AlunoSnapshotModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AlunoSnapshotModel.fromMap(doc.data() ?? {}, id: doc.id);
  }

  /// Converte o modelo de volta para um Mapa.
  Map<String, dynamic> toMap() {
    return {
      'aluno_id': alunoId,
      'turma_id': turmaId,
      'nome': nome,
      'nome_busca': nomeBusca,
      'foto_url': fotoUrl,
      'sexo': sexo,
      'sexo_normalizado': sexoNormalizado,
      'data_nascimento': dataNascimento != null ? Timestamp.fromDate(dataNascimento!) : null,
      'idade': idade,
      'faixa_idade': faixaIdade,
      'ativo': ativo,
      'graduacao_id': graduacaoId,
      'graduacao_nome': graduacaoNome,
      'graduacao_nivel': graduacaoNivel,
      'hex_cor1': hexCor1,
      'hex_cor2': hexCor2,
      'hex_ponta1': hexPonta1,
      'hex_ponta2': hexPonta2,
      'freq_total': freqTotal,
      'freq_semana': freqSemana,
      'freq_mes': freqMes,
      'freq_ano': freqAno,
      'freq_por_ano': freqPorAno,
      'freq_por_mes': freqPorMes,
      'freq_por_semana': freqPorSemana,
      'freq_por_dia_semana': freqPorDiaSemana,
      'mes_key_atual': mesKeyAtual,
      'semana_key_atual': semanaKeyAtual,
      'ano_key_atual': anoKeyAtual,
      'semana_dashboard_inicio': semanaDashboardInicio,
      'semana_regra': semanaRegra,
      'frequencia_origem': frequenciaOrigem,
      'frequencia_recalculada_em': frequenciaRecalculadaEm != null ? Timestamp.fromDate(frequenciaRecalculadaEm!) : null,
      'avaliacao_nota': avaliacaoNota,
      'avaliacao_conceito': avaliacaoConceito,
      'destaque_score_total': destaqueScoreTotal,
      'destaque_score_semana': destaqueScoreSemana,
      'destaque_score_mes': destaqueScoreMes,
      'destaque_score_por_ano': destaqueScorePorAno,
      'ranking_total': rankingTotal,
      'ranking_semana': rankingSemana,
      'ranking_mes': rankingMes,
      'ranking_por_ano': rankingPorAno,
      'cache_versao': cacheVersao,
      'atualizado_em': atualizadoEm != null ? Timestamp.fromDate(atualizadoEm!) : null,
    };
  }

  /// Converte para o formato de Mapa "Legado" esperado pelos componentes atuais da Dashboard.
  /// 
  /// Este método é vital para a Etapa 8/9 de refatoração gradual, permitindo que a
  /// fonte de dados seja tipada, mas os Widgets ainda consumam o Map antigo.
  Map<String, dynamic> toLegacyMap() {
    final temporal = {
      'total': freqTotal,
      'semana': freqSemana,
      'mes': freqMes,
      ...freqPorAno,
      ...freqPorMes,
    };

    final diaSemanaPadrao = {
      'seg': freqPorDiaSemana['seg'] ?? 0,
      'ter': freqPorDiaSemana['ter'] ?? 0,
      'qua': freqPorDiaSemana['qua'] ?? 0,
      'qui': freqPorDiaSemana['qui'] ?? 0,
      'sex': freqPorDiaSemana['sex'] ?? 0,
      'sab': freqPorDiaSemana['sab'] ?? 0,
      'dom': freqPorDiaSemana['dom'] ?? 0,
    };

    return {
      'id': alunoId,
      'nome': nome,
      'sexo': sexoNormalizado,
      'foto_perfil_aluno': fotoUrl,
      'foto_url': fotoUrl,
      'aluno_foto': fotoUrl,
      'graduacao_id': graduacaoId,
      'graduacao_nome': graduacaoNome,
      'graduacao_atual': graduacaoNome,
      'data_nascimento': dataNascimento != null ? Timestamp.fromDate(dataNascimento!) : null,
      'total_presencas': freqTotal,
      'idade_calculada': idade,
      'frequencia_temporal': temporal,
      'freq_por_mes': freqPorMes,
      'freq_por_semana': freqPorSemana,
      'freq_por_ano': freqPorAno,
      'porDiaSemana': diaSemanaPadrao,
      ...diaSemanaPadrao,
      'avaliacao_nota': avaliacaoNota,
      'avaliacao_conceito': avaliacaoConceito,
      'destaque_score_total': destaqueScoreTotal,
      'destaque_score_semana': destaqueScoreSemana,
      'destaque_score_mes': destaqueScoreMes,
      'destaque_score_por_ano': destaqueScorePorAno,
      'ranking_total': rankingTotal,
      'ranking_semana': rankingSemana,
      'ranking_mes': rankingMes,
      'ranking_por_ano': rankingPorAno,
    };
  }

  // Métodos auxiliares de parsing seguro (replicando lógica da DashboardPage)
  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  static Map<String, int> _toMapStringInt(dynamic v) {
    if (v is Map) {
      return Map<String, int>.from(v.map((key, value) => MapEntry(key.toString(), _toInt(value))));
    }
    return {};
  }
}
