import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint

class MigracaoChamadasService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 CALCULAR ESTATÍSTICAS DO JSON
  Map<String, dynamic> calcularEstatisticas(List<Map<String, dynamic>> dados) {
    final alunosUnicos = <String>{};
    final datasUnicas = <String>{};
    final turmasUnicas = <String>{};
    int totalPresentes = 0;
    int totalAusencias = 0;

    for (var registro in dados) {
      final alunoNome = registro['aluno_nome']?.toString() ?? '';
      final dataFormatada = registro['data_formatada']?.toString() ?? '';
      final turmaId = registro['turma_id']?.toString() ?? '';
      final presente = registro['presente']?.toString().toUpperCase() == 'TRUE';

      if (alunoNome.isNotEmpty) alunosUnicos.add(alunoNome);
      if (dataFormatada.isNotEmpty) datasUnicas.add(dataFormatada);
      if (turmaId.isNotEmpty) turmasUnicas.add(turmaId);

      if (presente) {
        totalPresentes++;
      } else {
        totalAusencias++;
      }
    }

    return {
      'totalRegistros': dados.length,
      'alunosUnicos': alunosUnicos.length,
      'datasUnicas': datasUnicas.length,
      'turmasUnicas': turmasUnicas.length,
      'totalPresentes': totalPresentes,
      'totalAusencias': totalAusencias,
    };
  }

  // 🔥 MIGRAÇÃO PRINCIPAL
  Future<Map<String, dynamic>> migrarChamadas({
    required List<Map<String, dynamic>> dados,
    required String professorId,
    required String professorNome,
    required Function(int progress, String message) onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    int logsCriados = 0;
    int contadoresAtualizados = 0;
    int chamadasCriadas = 0;
    final List<String> erros = [];

    // MAPA: data + turma_id -> lista de registros (SÓ QUEM TEM TURMA)
    final Map<String, List<Map<String, dynamic>>> chamadasPorDataTurma = {};

    // MAPA: aluno_id -> contador
    final Map<String, Map<String, dynamic>> contadoresAlunos = {};

    // MAPA PARA ESTATÍSTICAS
    final Map<String, Set<String>> alunosPorDataTurma = {};
    final Map<String, int> presentesPorDataTurma = {};
    final Map<String, int> ausentesPorDataTurma = {};

    onProgress(5, 'Organizando dados...');
    debugPrint('📊 Organizando ${dados.length} registros...');

    // 1️⃣ ORGANIZAR DADOS
    int registrosComTurma = 0;
    int registrosSemTurma = 0;

    for (var registro in dados) {
      try {
        // Converter presente para boolean
        bool presente = registro['presente']?.toString().toUpperCase() == 'TRUE';

        // Extrair campos necessários (já devem vir do enriquecimento!)
        final alunoId = registro['aluno_id']?.toString();
        final alunoNome = registro['aluno_nome']?.toString() ?? '';
        final turmaId = registro['turma_id']?.toString() ?? '';
        final turmaNome = registro['turma_nome']?.toString() ?? '';
        final academiaId = registro['academia_id']?.toString() ?? '';
        final academiaNome = registro['academia_nome']?.toString() ?? '';
        final dataFormatada = registro['data_formatada']?.toString() ?? '';
        final diaSemana = registro['dia_semana']?.toString() ?? '';
        final diaSemanaAbrev = registro['dia_semana_abrev']?.toString().toLowerCase() ?? '';
        final tipoAula = registro['tipo_aula']?.toString() ?? 'OBJETIVA';

        if (alunoId == null || alunoId.isEmpty) {
          erros.add('❌ Aluno sem ID: $alunoNome');
          continue;
        }

        // Adicionar ao registro
        registro['aluno_id'] = alunoId;
        registro['presente'] = presente;

        // 🔥 SEPARAR QUEM TEM TURMA DE QUEM NÃO TEM
        if (turmaId.isNotEmpty) {
          registrosComTurma++;

          // Criar chave única: data + turma
          final keyChamada = '${dataFormatada}_$turmaId';

          if (!chamadasPorDataTurma.containsKey(keyChamada)) {
            chamadasPorDataTurma[keyChamada] = [];
            alunosPorDataTurma[keyChamada] = {};
            presentesPorDataTurma[keyChamada] = 0;
            ausentesPorDataTurma[keyChamada] = 0;
          }

          chamadasPorDataTurma[keyChamada]!.add(registro);
          alunosPorDataTurma[keyChamada]!.add(alunoId);

          if (presente) {
            presentesPorDataTurma[keyChamada] = (presentesPorDataTurma[keyChamada] ?? 0) + 1;
          } else {
            ausentesPorDataTurma[keyChamada] = (ausentesPorDataTurma[keyChamada] ?? 0) + 1;
          }
        } else {
          registrosSemTurma++;
        }

        // 🔥 CONTADORES (SEMPRE!)
        final keyContador = alunoId;
        if (!contadoresAlunos.containsKey(keyContador)) {
          contadoresAlunos[keyContador] = {
            'aluno_id': alunoId,
            'aluno_nome': alunoNome,
            'academia_id': academiaId,
            'academia_nome': academiaNome,
            'turma_id': turmaId,
            'seg': 0,
            'ter': 0,
            'qua': 0,
            'qui': 0,
            'sex': 0,
            'sab': 0,
            'dom': 0,
            'ultimo_dia_presente': null,
            'ultima_chamada': null,
            'ultima_chamada_por': professorNome,
            'ultima_chamada_por_id': professorId,
          };
        }

        // Atualizar contador
        if (presente && diaSemanaAbrev.isNotEmpty) {
          contadoresAlunos[keyContador]![diaSemanaAbrev] =
              (contadoresAlunos[keyContador]![diaSemanaAbrev] ?? 0) + 1;

          // 🔥 CORREÇÃO: Criar Timestamp diretamente
          final dataObj = _parseData(dataFormatada);
          final ultimoPresente = contadoresAlunos[keyContador]!['ultimo_dia_presente'];

          if (ultimoPresente == null) {
            contadoresAlunos[keyContador]!['ultimo_dia_presente'] = dataObj;
          } else {
            // 🔥 CORREÇÃO: Comparar Timestamps corretamente
            if ((ultimoPresente as Timestamp).compareTo(dataObj) < 0) {
              contadoresAlunos[keyContador]!['ultimo_dia_presente'] = dataObj;
            }
          }
        }

      } catch (e) {
        erros.add('❌ Erro ao processar registro: $e');
      }
    }

    debugPrint('📊 Registros COM turma: $registrosComTurma');
    debugPrint('📊 Registros SEM turma: $registrosSemTurma');
    debugPrint('📦 Total de combinações data+turma: ${chamadasPorDataTurma.length}');

    onProgress(20, 'Preparando batches...');

    // 2️⃣ EXECUTAR MIGRAÇÃO EM BATCHES
    int totalBatches = (dados.length / 400).ceil() +
        (contadoresAlunos.length / 400).ceil() +
        (chamadasPorDataTurma.length / 400).ceil();
    int batchesCompletos = 0;

    // ============================================
    // BATCH 1: LOGS INDIVIDUAIS (SEMPRE!)
    // ============================================
    debugPrint('\n📝 ===== CRIANDO LOGS INDIVIDUAIS =====');
    for (int i = 0; i < dados.length; i += 400) {
      final batch = _firestore.batch();
      final lote = dados.skip(i).take(400).toList();
      int loteLogs = 0;

      for (var registro in lote) {
        try {
          if (registro['aluno_id'] == null) continue;

          final docRef = _firestore
              .collection('log_presenca_alunos')
              .doc(registro['log_id'] ?? _gerarId());

          batch.set(docRef, {
            'academia_id': registro['academia_id'] ?? '',
            'academia_nome': registro['academia_nome'] ?? '',
            'aluno_id': registro['aluno_id'],
            'aluno_nome': registro['aluno_nome'],
            'data_aula': _parseData(registro['data_formatada']),
            'data_formatada': registro['data_formatada'],
            'dia_semana': registro['dia_semana'],
            'dia_semana_abrev': registro['dia_semana_abrev'],
            'log_id': registro['log_id'],
            'observacao': registro['observacao'] ?? '',
            'presente': registro['presente'],
            'professor_id': professorId,
            'professor_nome': professorNome,
            'registrado_em': Timestamp.now(),
            'sincronizado': true,
            'tipo_aula': registro['tipo_aula'] ?? 'OBJETIVA',
            'tipo_registro': 'chamada_turma',
            'turma_id': registro['turma_id'] ?? '',
            'turma_nome': registro['turma_nome'] ?? '',
          });

          logsCriados++;
          loteLogs++;
        } catch (e) {
          erros.add('❌ Erro ao criar log: $e');
        }
      }

      await batch.commit();
      batchesCompletos++;
      debugPrint('   ✅ Lote ${i ~/ 400 + 1}: $loteLogs logs criados');
      onProgress(
        20 + (30 * batchesCompletos / totalBatches).round(),
        'Criando logs individuais...',
      );
    }
    debugPrint('✅ Total de logs criados: $logsCriados');

    // ============================================
    // BATCH 2: CONTADORES (SEMPRE!)
    // ============================================
    onProgress(50, 'Atualizando contadores dos alunos...');
    debugPrint('\n📊 ===== ATUALIZANDO CONTADORES =====');

    final List<Map<String, dynamic>> contadoresList = contadoresAlunos.values.toList();
    for (int i = 0; i < contadoresList.length; i += 400) {
      final batch = _firestore.batch();
      final lote = contadoresList.skip(i).take(400).toList();
      int loteContadores = 0;

      for (var contador in lote) {
        try {
          final docRef = _firestore
              .collection('contador_presencas_alunos')
              .doc(contador['aluno_id']);

          batch.set(docRef, {
            'academia_id': contador['academia_id'],
            'aluno_id': contador['aluno_id'],
            'aluno_nome': contador['aluno_nome'],
            'atualizado_em': Timestamp.now(),
            'dom': contador['dom'],
            'professor_atualizacao': professorNome,
            'professor_id_atualizacao': professorId,
            'qua': contador['qua'],
            'qui': contador['qui'],
            'sab': contador['sab'],
            'seg': contador['seg'],
            'sex': contador['sex'],
            'ter': contador['ter'],
            'turma_id': contador['turma_id'],
            'ultima_chamada': Timestamp.now(),
            'ultima_chamada_por': professorNome,
            'ultima_chamada_por_id': professorId,
            'ultimo_dia_presente': contador['ultimo_dia_presente'],
          }, SetOptions(merge: true));

          contadoresAtualizados++;
          loteContadores++;
        } catch (e) {
          erros.add('❌ Erro ao atualizar contador: $e');
        }
      }

      await batch.commit();
      batchesCompletos++;
      debugPrint('   ✅ Lote ${i ~/ 400 + 1}: $loteContadores contadores atualizados');
      onProgress(
        50 + (30 * batchesCompletos / totalBatches).round(),
        'Atualizando contadores...',
      );
    }
    debugPrint('✅ Total de contadores atualizados: $contadoresAtualizados');

    // ============================================
    // BATCH 3: CHAMADAS DE TURMA (SÓ QUEM TEM TURMA!)
    // ============================================
    onProgress(80, 'Criando chamadas de turma...');
    debugPrint('\n📋 ===== CRIANDO CHAMADAS DE TURMA =====');

    final chamadasList = chamadasPorDataTurma.entries.toList();
    int chamadasEsperadas = chamadasList.length;

    for (int i = 0; i < chamadasList.length; i += 400) {
      final batch = _firestore.batch();
      final lote = chamadasList.skip(i).take(400).toList();
      int loteChamadas = 0;

      for (var entry in lote) {
        try {
          final partes = entry.key.split('_');
          if (partes.length != 2) continue;

          final dataFormatada = partes[0];
          final turmaId = partes[1];
          final registros = entry.value;

          if (registros.isEmpty) continue;

          final primeiroRegistro = registros.first;
          final totalAlunos = registros.length;
          final presentes = registros.where((r) => r['presente'] == true).length;
          final ausentes = totalAlunos - presentes;

          final docId = _gerarId();
          final docRef = _firestore
              .collection('chamadas')
              .doc(docId);

          // 🔥 CRIAR ARRAY DE ALUNOS SÓ COM QUEM TEM TURMA!
          final alunosArray = registros.map((r) {
            final dataRegistro = _parseData(r['data_formatada']);
            return {
              'aluno_id': r['aluno_id'],
              'aluno_nome': r['aluno_nome'],
              'data_registro': dataRegistro,
              'observacao': r['observacao'] ?? '',
              'presente': r['presente'],
            };
          }).toList();

          batch.set(docRef, {
            'academia_id': primeiroRegistro['academia_id'] ?? '',
            'academia_nome': primeiroRegistro['academia_nome'] ?? '',
            'alunos': alunosArray,
            'atualizado_em': Timestamp.now(),
            'ausentes': ausentes,
            'criado_em': Timestamp.now(),
            'data_chamada': _parseData(dataFormatada),
            'data_formatada': dataFormatada,
            'dia_semana': primeiroRegistro['dia_semana'],
            'dia_semana_abrev': primeiroRegistro['dia_semana_abrev'],
            'porcentagem_frequencia':
            totalAlunos > 0 ? ((presentes / totalAlunos) * 100).round() : 0,
            'presentes': presentes,
            'professor_id': professorId,
            'professor_nome': professorNome,
            'tipo_aula': primeiroRegistro['tipo_aula'] ?? 'OBJETIVA',
            'total_alunos': totalAlunos,
            'turma_id': turmaId,
            'turma_nome': primeiroRegistro['turma_nome'] ?? '',
          });

          chamadasCriadas++;
          loteChamadas++;

        } catch (e) {
          erros.add('❌ Erro ao criar chamada de turma: $e');
        }
      }

      await batch.commit();
      batchesCompletos++;
      debugPrint('   ✅ Lote ${i ~/ 400 + 1}: $loteChamadas chamadas criadas');
      onProgress(
        80 + (20 * batchesCompletos / totalBatches).round(),
        'Finalizando...',
      );
    }
    debugPrint('✅ Total de chamadas criadas: $chamadasCriadas/$chamadasEsperadas');

    stopwatch.stop();

    // ============================================
    // RELATÓRIO FINAL (CORRIGIDO - SEM repeat!)
    // ============================================
    debugPrint('\n' + ('=' * 60));  // 🔥 CORRIGIDO: usa * em vez de repeat()
    debugPrint('📊 RELATÓRIO FINAL DA MIGRAÇÃO');
    debugPrint('=' * 60);  // 🔥 CORRIGIDO
    debugPrint('📝 Logs criados: $logsCriados/${dados.length}');
    debugPrint('📊 Contadores atualizados: $contadoresAtualizados/${contadoresAlunos.length}');
    debugPrint('📋 Chamadas criadas: $chamadasCriadas/$chamadasEsperadas');
    debugPrint('⏱️ Tempo: ${_formatarTempo(stopwatch.elapsed)}');
    debugPrint('❌ Erros: ${erros.length}');
    if (erros.isNotEmpty) {
      debugPrint('📋 Primeiros 5 erros:');
      for (int i = 0; i < (erros.length > 5 ? 5 : erros.length); i++) {
        debugPrint('   $i. ${erros[i]}');
      }
    }
    debugPrint('=' * 60);  // 🔥 CORRIGIDO

    return {
      'sucesso': erros.isEmpty,
      'totalRegistros': dados.length,
      'logsCriados': logsCriados,
      'alunosUnicos': contadoresAlunos.length,
      'contadoresAtualizados': contadoresAtualizados,
      'chamadasEsperadas': chamadasEsperadas,
      'chamadasCriadas': chamadasCriadas,
      'tempoExecucao': _formatarTempo(stopwatch.elapsed),
      'erros': erros,
    };
  }

  // 🔥 FUNÇÕES AUXILIARES
  Timestamp _parseData(String? dataFormatada) {
    if (dataFormatada == null || dataFormatada.isEmpty) {
      return Timestamp.now();
    }
    try {
      final partes = dataFormatada.split('-');
      if (partes.length == 3) {
        final ano = int.parse(partes[0]);
        final mes = int.parse(partes[1]);
        final dia = int.parse(partes[2]);
        return Timestamp.fromDate(DateTime.utc(ano, mes, dia, 12));
      }
    } catch (e) {
      debugPrint('❌ Erro ao parsear data: $e');
    }
    return Timestamp.now();
  }

  String _gerarId() {
    return _firestore.collection('_').doc().id;
  }

  String _formatarTempo(Duration duracao) {
    String doisDigitos(int n) => n.toString().padLeft(2, '0');
    final minutos = doisDigitos(duracao.inMinutes.remainder(60));
    final segundos = doisDigitos(duracao.inSeconds.remainder(60));
    final horas = duracao.inHours;

    if (horas > 0) {
      return '${doisDigitos(horas)}:$minutos:$segundos';
    }
    return '$minutos:$segundos';
  }
}