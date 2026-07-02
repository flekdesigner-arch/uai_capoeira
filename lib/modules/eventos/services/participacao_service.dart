import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ParticipacaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 DUAS COLEÇÕES DIFERENTES!
  final String _emAndamentoCollection = 'participacoes_eventos_em_andamento';
  final String _finalizadasCollection = 'participacoes_eventos';

  // ───────────────────── PADRÕES DE CAMISA ─────────────────────
  static const String modelagemNormal = 'NORMAL';
  static const String modelagemBabyLook = 'BABY_LOOK';

  static const String tipoManga = 'MANGA';
  static const String tipoMangaLonga = 'MANGA_LONGA';
  static const String tipoRegata = 'REGATA';

  String _normalizarModelagem(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'BABYLOOK' ||
        clean == 'BABY_LOOK' ||
        clean == 'BABY_LOOK_FEMININA' ||
        clean == 'FEMININA') {
      return modelagemBabyLook;
    }

    return modelagemNormal;
  }

  String _normalizarTipoCamisa(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';

    final clean = raw
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .replaceAll('__', '_');

    if (clean == 'MANGA_LONGA' ||
        clean == 'LONGA' ||
        clean == 'MANGA_COMPRIDA') {
      return tipoMangaLonga;
    }

    if (clean == 'REGATA') {
      return tipoRegata;
    }

    return tipoManga;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 0;

    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  /// Adiciona um participante ao evento (SEMPRE na coleção EM ANDAMENTO)
  Future<Map<String, dynamic>> adicionarParticipante({
    required String alunoId,
    required String alunoNome,
    String? alunoFoto,
    required String eventoId,
    required String eventoNome,
    required DateTime dataEvento,
    required String tipoEvento,
    String? graduacao,
    String? graduacaoId,
    String? tamanhoCamisa,
    bool presente = false,
    String status = 'pendente',

    // 🔥 CAMPOS PARA GRADUAÇÃO
    String? graduacaoNova,
    String? graduacaoNovaId,

    // 🔥 CAMPOS PARA FINANCEIRO / CAMISA
    double valorInscricao = 0,
    double valorCamisa = 0,
    bool camisaEntregue = false,

    // 🔥 NOVOS CAMPOS PARA CONFECÇÃO
    String? modelagemCamisa,
    String? tipoCamisa,
  }) async {
    try {
      // Verifica se já está participando (busca nas duas coleções)
      final existeEmAndamento = await _buscarParticipacao(
        alunoId,
        eventoId,
        _emAndamentoCollection,
      );

      final existeFinalizada = await _buscarParticipacao(
        alunoId,
        eventoId,
        _finalizadasCollection,
      );

      if (existeEmAndamento != null || existeFinalizada != null) {
        throw Exception('Aluno já está participando deste evento');
      }

      final modelagemFinal = _normalizarModelagem(modelagemCamisa);
      final tipoFinal = _normalizarTipoCamisa(tipoCamisa);

      final participacao = <String, dynamic>{
        'aluno_id': alunoId,
        'aluno_nome': alunoNome,
        'aluno_foto': alunoFoto,
        'evento_id': eventoId,
        'evento_nome': eventoNome,
        'data_evento': Timestamp.fromDate(dataEvento),
        'tipo_evento': tipoEvento,
        'graduacao': graduacao,
        'graduacao_id': graduacaoId,
        'tamanho_camisa': tamanhoCamisa,
        'modelagem_camisa': modelagemFinal,
        'tipo_camisa': tipoFinal,
        'presente': presente,
        'status': status,
        'valor_inscricao': valorInscricao,
        'valor_camisa': valorCamisa,
        'camisa_entregue': camisaEntregue,
        'total_pago': 0,
        'criado_em': FieldValue.serverTimestamp(),
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      // 🔥 Adiciona campos de graduação nova se existirem
      if (graduacaoNova != null) {
        participacao['graduacao_nova'] = graduacaoNova;
      }

      if (graduacaoNovaId != null) {
        participacao['graduacao_nova_id'] = graduacaoNovaId;
      }

      // Indica que está aguardando finalização (para batizados)
      if (graduacaoNova != null) {
        participacao['aguardando_finalizacao'] = true;
      }

      debugPrint('📝 Salvando participação:');
      debugPrint('   - valorInscricao: $valorInscricao');
      debugPrint('   - valorCamisa: $valorCamisa');
      debugPrint('   - total: ${valorInscricao + valorCamisa}');
      debugPrint('   - tamanhoCamisa: $tamanhoCamisa');
      debugPrint('   - modelagemCamisa: $modelagemFinal');
      debugPrint('   - tipoCamisa: $tipoFinal');

      // 🔥 SALVA NA COLEÇÃO EM ANDAMENTO
      final docRef = await _firestore
          .collection(_emAndamentoCollection)
          .add(participacao);

      // 🔥 TAMBÉM SALVA UMA REFERÊNCIA NA COLEÇÃO DO EVENTO
      await _firestore
          .collection('eventos')
          .doc(eventoId)
          .collection('participacoes')
          .doc(docRef.id)
          .set({
            'participacao_id': docRef.id,
            'aluno_id': alunoId,
            'aluno_nome': alunoNome,
            'status': status,
            'total_pago': 0,
            'valor_total': valorInscricao + valorCamisa,
            'tamanho_camisa': tamanhoCamisa,
            'modelagem_camisa': modelagemFinal,
            'tipo_camisa': tipoFinal,
            'criado_em': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      return {'id': docRef.id, ...participacao};
    } catch (e) {
      debugPrint('Erro ao adicionar participante: $e');
      rethrow;
    }
  }

  /// 🔥 Método auxiliar para buscar participação em uma coleção específica
  Future<Map<String, dynamic>?> _buscarParticipacao(
    String alunoId,
    String eventoId,
    String collection,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .where('aluno_id', isEqualTo: alunoId)
          .where('evento_id', isEqualTo: eventoId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      return {'id': doc.id, ...doc.data()};
    } catch (e) {
      debugPrint('Erro ao buscar participação em $collection: $e');
      return null;
    }
  }

  /// Remove um participante do evento (da coleção EM ANDAMENTO)
  Future<void> removerParticipante(String participacaoId) async {
    try {
      // Primeiro, busca a participação para saber o eventoId
      final participacaoDoc = await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .get();

      if (!participacaoDoc.exists) return;

      final eventoId = participacaoDoc.data()?['evento_id'] as String?;

      // 1️⃣ Remove da coleção EM ANDAMENTO
      await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .delete();

      // 2️⃣ Remove também da subcoleção do evento (se existir eventoId)
      if (eventoId != null) {
        await _firestore
            .collection('eventos')
            .doc(eventoId)
            .collection('participacoes')
            .doc(participacaoId)
            .delete();
      }

      debugPrint('✅ Participação $participacaoId removida de todos os lugares');
    } catch (e) {
      debugPrint('❌ Erro ao remover participante: $e');
      rethrow;
    }
  }

  /// Lista todos os participantes EM ANDAMENTO de um evento
  Future<List<Map<String, dynamic>>> listarParticipantesEmAndamento(
    String eventoId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_emAndamentoCollection)
          .where('evento_id', isEqualTo: eventoId)
          .orderBy('aluno_nome')
          .get();

      return snapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();
    } catch (e) {
      debugPrint('Erro ao listar participantes em andamento: $e');
      return [];
    }
  }

  /// Lista todos os participantes FINALIZADOS de um evento
  Future<List<Map<String, dynamic>>> listarParticipantesFinalizados(
    String eventoId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_finalizadasCollection)
          .where('evento_id', isEqualTo: eventoId)
          .orderBy('aluno_nome')
          .get();

      return snapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();
    } catch (e) {
      debugPrint('Erro ao listar participantes finalizados: $e');
      return [];
    }
  }

  /// 🔥 Lista TODOS os participantes (em andamento + finalizados)
  Future<List<Map<String, dynamic>>> listarTodosParticipantes(
    String eventoId,
  ) async {
    try {
      final emAndamento = await listarParticipantesEmAndamento(eventoId);
      final finalizados = await listarParticipantesFinalizados(eventoId);

      return [...emAndamento, ...finalizados];
    } catch (e) {
      debugPrint('Erro ao listar todos participantes: $e');
      return [];
    }
  }

  /// Lista todos os eventos que um aluno participou (busca nas duas coleções)
  Future<List<Map<String, dynamic>>> listarParticipantesPorAluno(
    String alunoId,
  ) async {
    try {
      final emAndamento = await _firestore
          .collection(_emAndamentoCollection)
          .where('aluno_id', isEqualTo: alunoId)
          .orderBy('data_evento', descending: true)
          .get();

      final finalizados = await _firestore
          .collection(_finalizadasCollection)
          .where('aluno_id', isEqualTo: alunoId)
          .orderBy('data_evento', descending: true)
          .get();

      final resultados = [
        ...emAndamento.docs.map((doc) => {'id': doc.id, ...doc.data()}),
        ...finalizados.docs.map((doc) => {'id': doc.id, ...doc.data()}),
      ];

      return resultados;
    } catch (e) {
      debugPrint('Erro ao listar participações do aluno: $e');
      return [];
    }
  }

  /// Busca uma participação específica (nas duas coleções)
  Future<Map<String, dynamic>?> buscarParticipacao(
    String alunoId,
    String eventoId,
  ) async {
    try {
      // Tenta na coleção em andamento
      final emAndamento = await _buscarParticipacao(
        alunoId,
        eventoId,
        _emAndamentoCollection,
      );

      if (emAndamento != null) return emAndamento;

      // Tenta na coleção finalizada
      final finalizada = await _buscarParticipacao(
        alunoId,
        eventoId,
        _finalizadasCollection,
      );

      return finalizada;
    } catch (e) {
      debugPrint('Erro ao buscar participação: $e');
      return null;
    }
  }

  /// Marca presença do participante (apenas em andamento)
  Future<void> marcarPresenca(String participacaoId, bool presente) async {
    try {
      await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .update({
            'presente': presente,
            'atualizado_em': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Erro ao marcar presença: $e');
      rethrow;
    }
  }

  /// Atualiza status da participação
  Future<void> atualizarStatus(String participacaoId, String novoStatus) async {
    try {
      await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .update({
            'status': novoStatus,
            'atualizado_em': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Erro ao atualizar status: $e');
      rethrow;
    }
  }

  /// Atualiza dados da camisa.
  ///
  /// Compatibilidade:
  /// - Se modelagem não for informada, NÃO altera o campo.
  /// - Se tipo não for informado, NÃO altera o campo.
  /// - Nas leituras/relatórios, ausência deve ser tratada como NORMAL/MANGA.
  /// - Se valorCamisa for informado, atualiza também o financeiro da camisa.
  Future<void> atualizarCamisa({
    required String participacaoId,
    String? tamanho,
    bool? entregue,
    String? modelagemCamisa,
    String? tipoCamisa,

    // Quando o tipo muda, a tela pode enviar o novo valor calculado
    // pelo evento: Manga, Manga Longa ou Regata.
    double? valorCamisa,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      if (tamanho != null) {
        updates['tamanho_camisa'] = tamanho;
      }

      if (entregue != null) {
        updates['camisa_entregue'] = entregue;
      }

      if (modelagemCamisa != null) {
        updates['modelagem_camisa'] = _normalizarModelagem(modelagemCamisa);
      }

      if (tipoCamisa != null) {
        updates['tipo_camisa'] = _normalizarTipoCamisa(tipoCamisa);
      }

      if (valorCamisa != null) {
        updates['valor_camisa'] = valorCamisa;
      }

      await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .update(updates);

      // 🔥 Mantém a referência da subcoleção do evento sincronizada quando possível.
      // Não é crítico para certificado/graduação, mas ajuda relatórios e buscas leves.
      try {
        final doc = await _firestore
            .collection(_emAndamentoCollection)
            .doc(participacaoId)
            .get();

        final data = doc.data();
        final eventoId = data?['evento_id']?.toString();

        if (eventoId != null && eventoId.trim().isNotEmpty) {
          final refUpdates = <String, dynamic>{
            'atualizado_em': FieldValue.serverTimestamp(),
          };

          if (updates.containsKey('tamanho_camisa')) {
            refUpdates['tamanho_camisa'] = updates['tamanho_camisa'];
          }
          if (updates.containsKey('modelagem_camisa')) {
            refUpdates['modelagem_camisa'] = updates['modelagem_camisa'];
          }
          if (updates.containsKey('tipo_camisa')) {
            refUpdates['tipo_camisa'] = updates['tipo_camisa'];
          }
          if (updates.containsKey('valor_camisa')) {
            refUpdates['valor_camisa'] = updates['valor_camisa'];

            final valorInscricao = _asDouble(data?['valor_inscricao']);
            final valorCamisaAtualizado = _asDouble(
              data?['valor_camisa'] ?? updates['valor_camisa'],
            );

            refUpdates['valor_total'] = valorInscricao + valorCamisaAtualizado;
          }

          await _firestore
              .collection('eventos')
              .doc(eventoId)
              .collection('participacoes')
              .doc(participacaoId)
              .set(refUpdates, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint(
          '⚠️ Camisa atualizada, mas erro ao sincronizar referência do evento: $e',
        );
      }
    } catch (e) {
      debugPrint('Erro ao atualizar camisa: $e');
      rethrow;
    }
  }

  /// Atualiza graduação nova
  Future<void> atualizarGraduacaoNova({
    required String participacaoId,
    String? graduacaoNovaId,
    String? graduacaoNovaNome,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      if (graduacaoNovaId != null) {
        updates['graduacao_nova_id'] = graduacaoNovaId;
      }

      if (graduacaoNovaNome != null) {
        updates['graduacao_nova'] = graduacaoNovaNome;
      }

      updates['aguardando_finalizacao'] = true;

      await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .update(updates);
    } catch (e) {
      debugPrint('Erro ao atualizar graduação nova: $e');
      rethrow;
    }
  }

  /// Finaliza a participação (MOVE da EM ANDAMENTO para FINALIZADAS)
  ///
  /// REGRAS IMPORTANTES:
  /// - NÃO mexe nos documentos antigos já existentes em participacoes_eventos.
  /// - Copia TODOS os dados atuais da participação em andamento.
  /// - Preserva o link_certificado real já salvo no documento.
  /// - Nunca substitui o certificado por link fake/null.
  /// - Mantém o mesmo ID do documento, para facilitar rastreio.
  Future<void> finalizarParticipacao({
    required String participacaoId,
    String? linkCertificado,
    String? novaGraduacao,
    String? novaGraduacaoId,
  }) async {
    try {
      final emAndamentoRef = _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId);

      final finalizadaRef = _firestore
          .collection(_finalizadasCollection)
          .doc(participacaoId);

      await _firestore.runTransaction((transaction) async {
        // 1️⃣ PEGA OS DADOS DA PARTICIPAÇÃO EM ANDAMENTO
        final doc = await transaction.get(emAndamentoRef);

        if (!doc.exists) {
          throw Exception('Participação não encontrada em andamento');
        }

        final data = doc.data() ?? {};

        final linkAtualFirestore =
            data['link_certificado']?.toString().trim() ?? '';
        final linkRecebidoTela = linkCertificado?.trim() ?? '';

        // 🔥 PRIORIDADE:
        // 1. Link enviado pela tela, se existir.
        // 2. Link já salvo no documento em andamento.
        // 3. Não salva campo vazio.
        final linkFinal = linkRecebidoTela.isNotEmpty
            ? linkRecebidoTela
            : linkAtualFirestore;

        final graduacaoNovaFinal = (novaGraduacao?.trim().isNotEmpty ?? false)
            ? novaGraduacao
            : data['graduacao_nova']?.toString();

        final graduacaoNovaIdFinal =
            (novaGraduacaoId?.trim().isNotEmpty ?? false)
            ? novaGraduacaoId
            : data['graduacao_nova_id']?.toString();

        // 2️⃣ COPIA TODOS OS DADOS PARA FINALIZADA
        final Map<String, dynamic> dadosFinalizada = {
          ...data,

          // 🔥 Campos oficiais de finalização
          'status': 'finalizado',
          'finalizado': true,
          'aguardando_finalizacao': false,
          'data_finalizacao': FieldValue.serverTimestamp(),
          'finalizado_em': FieldValue.serverTimestamp(),
          'atualizado_em': FieldValue.serverTimestamp(),
          'origem_finalizacao': 'flutter',

          // 🔥 Mantém compatibilidade com telas antigas e novas
          'graduacao_final': graduacaoNovaFinal,
          'graduacao_final_id': graduacaoNovaIdFinal,
        };

        // 🔥 Só grava link_certificado se realmente existir.
        // Isso impede apagar link antigo/real com null ou vazio.
        if (linkFinal.isNotEmpty) {
          dadosFinalizada['link_certificado'] = linkFinal;
        } else {
          dadosFinalizada.remove('link_certificado');
        }

        // 3️⃣ SALVA NA COLEÇÃO DE FINALIZADAS COM O MESMO ID
        transaction.set(
          finalizadaRef,
          dadosFinalizada,
          SetOptions(merge: true),
        );

        // 4️⃣ REMOVE DA COLEÇÃO EM ANDAMENTO
        transaction.delete(emAndamentoRef);
      });

      // 5️⃣ ATUALIZA A REFERÊNCIA NA SUBCOLEÇÃO DO EVENTO, SEM APAGAR HISTÓRICO
      try {
        final finalizadaDoc = await finalizadaRef.get();
        final dadosFinalizados = finalizadaDoc.data();

        if (dadosFinalizados != null) {
          final eventoId = dadosFinalizados['evento_id']?.toString();

          if (eventoId != null && eventoId.isNotEmpty) {
            await _firestore
                .collection('eventos')
                .doc(eventoId)
                .collection('participacoes')
                .doc(participacaoId)
                .set({
                  'participacao_id': participacaoId,
                  'aluno_id': dadosFinalizados['aluno_id'],
                  'aluno_nome': dadosFinalizados['aluno_nome'],
                  'status': 'finalizado',
                  'total_pago': dadosFinalizados['total_pago'] ?? 0,
                  'valor_total':
                      _asDouble(dadosFinalizados['valor_inscricao']) +
                      _asDouble(dadosFinalizados['valor_camisa']),
                  'tamanho_camisa': dadosFinalizados['tamanho_camisa'],
                  'modelagem_camisa':
                      dadosFinalizados['modelagem_camisa'] ?? modelagemNormal,
                  'tipo_camisa': dadosFinalizados['tipo_camisa'] ?? tipoManga,
                  'link_certificado': dadosFinalizados['link_certificado'],
                  'finalizado_em': FieldValue.serverTimestamp(),
                  'atualizado_em': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
          }
        }
      } catch (e) {
        debugPrint(
          '⚠️ Participação finalizada, mas erro ao atualizar referência do evento: $e',
        );
      }

      debugPrint('✅ Participação finalizada preservando certificado real');
    } catch (e) {
      debugPrint('Erro ao finalizar participação: $e');
      rethrow;
    }
  }

  /// Obtém estatísticas de participação por evento (considerando EM ANDAMENTO)
  Future<Map<String, dynamic>> getEstatisticasPorEvento(String eventoId) async {
    try {
      final participantes = await listarParticipantesEmAndamento(eventoId);

      int total = participantes.length;
      int presentes = participantes.where((p) => p['presente'] == true).length;
      int pendentes = participantes
          .where((p) => p['status'] == 'pendente')
          .length;
      int finalizados = participantes
          .where((p) => p['status'] == 'finalizado')
          .length;
      int quitados = participantes
          .where((p) => p['status'] == 'quitado')
          .length;

      // Contagem de aguardando graduação
      int aguardandoGraduacao = participantes
          .where((p) => p['aguardando_finalizacao'] == true)
          .length;

      // Contagem por tamanho de camisa
      Map<String, int> camisas = {};
      int camisasEntregues = 0;
      int camisasPendentes = 0;

      // 🔥 Nova contagem detalhada para relatórios futuros
      Map<String, int> camisasDetalhadas = {};

      // Cálculo de valores financeiros
      double totalPrevisto = 0;
      double totalArrecadado = 0;

      for (var p in participantes) {
        // Contagem de camisas
        if (p['tamanho_camisa'] != null) {
          final tamanho = p['tamanho_camisa'].toString().trim();

          if (tamanho.isNotEmpty) {
            camisas[tamanho] = (camisas[tamanho] ?? 0) + 1;

            final modelagem = _normalizarModelagem(p['modelagem_camisa']);
            final tipo = _normalizarTipoCamisa(p['tipo_camisa']);
            final chaveDetalhada = '$modelagem|$tipo|$tamanho';

            camisasDetalhadas[chaveDetalhada] =
                (camisasDetalhadas[chaveDetalhada] ?? 0) + 1;
          }
        }

        if (p['camisa_entregue'] == true) {
          camisasEntregues++;
        } else if (p['tamanho_camisa'] != null) {
          camisasPendentes++;
        }

        // Cálculo financeiro
        final valorInscricao = _asDouble(p['valor_inscricao']);
        final valorCamisa = _asDouble(p['valor_camisa']);
        final totalPago = _asDouble(p['total_pago']);

        totalPrevisto += valorInscricao + valorCamisa;
        totalArrecadado += totalPago;
      }

      return {
        'total': total,
        'presentes': presentes,
        'pendentes': pendentes,
        'finalizados': finalizados,
        'quitados': quitados,
        'aguardando_graduacao': aguardandoGraduacao,
        'camisas': camisas,
        'camisas_detalhadas': camisasDetalhadas,
        'camisas_entregues': camisasEntregues,
        'camisas_pendentes': camisasPendentes,
        'total_previsto': totalPrevisto,
        'total_arrecadado': totalArrecadado,
        'inadimplencia': totalPrevisto - totalArrecadado,
      };
    } catch (e) {
      debugPrint('Erro ao calcular estatísticas: $e');
      return {
        'total': 0,
        'presentes': 0,
        'pendentes': 0,
        'finalizados': 0,
        'quitados': 0,
        'aguardando_graduacao': 0,
        'camisas': {},
        'camisas_detalhadas': {},
        'camisas_entregues': 0,
        'camisas_pendentes': 0,
        'total_previsto': 0,
        'total_arrecadado': 0,
        'inadimplencia': 0,
      };
    }
  }

  /// Verifica se aluno pode participar (não está em outro evento no mesmo dia)
  Future<bool> podeParticipar(String alunoId, DateTime dataEvento) async {
    try {
      final inicioDia = DateTime(
        dataEvento.year,
        dataEvento.month,
        dataEvento.day,
      );

      final fimDia = inicioDia.add(const Duration(days: 1));

      // Verifica nas duas coleções
      final snapshotEmAndamento = await _firestore
          .collection(_emAndamentoCollection)
          .where('aluno_id', isEqualTo: alunoId)
          .where(
            'data_evento',
            isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia),
          )
          .where('data_evento', isLessThan: Timestamp.fromDate(fimDia))
          .get();

      final snapshotFinalizadas = await _firestore
          .collection(_finalizadasCollection)
          .where('aluno_id', isEqualTo: alunoId)
          .where(
            'data_evento',
            isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia),
          )
          .where('data_evento', isLessThan: Timestamp.fromDate(fimDia))
          .get();

      return snapshotEmAndamento.docs.isEmpty &&
          snapshotFinalizadas.docs.isEmpty;
    } catch (e) {
      debugPrint('Erro ao verificar disponibilidade: $e');
      return false;
    }
  }

  /// Atualiza dados de uma participação (apenas em andamento)
  Future<void> atualizarParticipacao(
    String participacaoId,
    Map<String, dynamic> dados,
  ) async {
    try {
      dados['atualizado_em'] = FieldValue.serverTimestamp();

      if (dados.containsKey('modelagem_camisa')) {
        dados['modelagem_camisa'] = _normalizarModelagem(
          dados['modelagem_camisa'],
        );
      }

      if (dados.containsKey('tipo_camisa')) {
        dados['tipo_camisa'] = _normalizarTipoCamisa(dados['tipo_camisa']);
      }

      await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .update(dados);
    } catch (e) {
      debugPrint('Erro ao atualizar participação: $e');
      rethrow;
    }
  }

  /// Busca participantes que aguardam graduação (apenas em andamento)
  Future<List<Map<String, dynamic>>> listarAguardandoGraduacao(
    String eventoId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_emAndamentoCollection)
          .where('evento_id', isEqualTo: eventoId)
          .where('aguardando_finalizacao', isEqualTo: true)
          .orderBy('aluno_nome')
          .get();

      return snapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();
    } catch (e) {
      debugPrint('Erro ao listar aguardando graduação: $e');
      return [];
    }
  }

  /// Busca participantes com saldo pendente (apenas em andamento)
  Future<List<Map<String, dynamic>>> listarInadimplentes(
    String eventoId,
  ) async {
    try {
      final participantes = await listarParticipantesEmAndamento(eventoId);

      return participantes.where((p) {
        final valorInscricao = _asDouble(p['valor_inscricao']);
        final valorCamisa = _asDouble(p['valor_camisa']);
        final totalPago = _asDouble(p['total_pago']);
        final valorTotal = valorInscricao + valorCamisa;

        return valorTotal > totalPago && p['status'] != 'finalizado';
      }).toList();
    } catch (e) {
      debugPrint('Erro ao listar inadimplentes: $e');
      return [];
    }
  }

  /// Atualiza o total pago de uma participação
  Future<void> atualizarTotalPago(
    String participacaoId,
    double novoTotalPago,
  ) async {
    try {
      // Atualiza na coleção EM ANDAMENTO
      await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .update({
            'total_pago': novoTotalPago,
            'atualizado_em': FieldValue.serverTimestamp(),
          });

      debugPrint('💰 Total pago atualizado na EM ANDAMENTO: $novoTotalPago');
    } catch (e) {
      debugPrint('Erro ao atualizar total pago: $e');
      rethrow;
    }
  }

  /// Busca participação por ID (em qualquer coleção)
  Future<Map<String, dynamic>?> buscarPorId(String participacaoId) async {
    try {
      // Tenta na coleção em andamento
      final docEmAndamento = await _firestore
          .collection(_emAndamentoCollection)
          .doc(participacaoId)
          .get();

      if (docEmAndamento.exists) {
        final data = docEmAndamento.data()!;
        debugPrint('📊 Participação EM ANDAMENTO encontrada:');
        debugPrint('   - valorInscricao: ${data['valor_inscricao']}');
        debugPrint('   - valorCamisa: ${data['valor_camisa']}');
        debugPrint('   - total_pago: ${data['total_pago']}');
        debugPrint(
          '   - modelagem_camisa: ${data['modelagem_camisa'] ?? modelagemNormal}',
        );
        debugPrint('   - tipo_camisa: ${data['tipo_camisa'] ?? tipoManga}');
        return {'id': docEmAndamento.id, ...data};
      }

      // Tenta na coleção finalizada
      final docFinalizada = await _firestore
          .collection(_finalizadasCollection)
          .doc(participacaoId)
          .get();

      if (docFinalizada.exists) {
        final data = docFinalizada.data()!;
        debugPrint('📊 Participação FINALIZADA encontrada:');
        debugPrint('   - valorInscricao: ${data['valor_inscricao']}');
        debugPrint('   - valorCamisa: ${data['valor_camisa']}');
        debugPrint('   - total_pago: ${data['total_pago']}');
        debugPrint(
          '   - modelagem_camisa: ${data['modelagem_camisa'] ?? modelagemNormal}',
        );
        debugPrint('   - tipo_camisa: ${data['tipo_camisa'] ?? tipoManga}');
        return {'id': docFinalizada.id, ...data};
      }

      return null;
    } catch (e) {
      debugPrint('Erro ao buscar participação por ID: $e');
      return null;
    }
  }

  /// Busca o valor total de uma participação
  Future<double> buscarValorTotal(String participacaoId) async {
    try {
      final participacao = await buscarPorId(participacaoId);
      if (participacao == null) return 0;

      final valorInscricao = _asDouble(participacao['valor_inscricao']);
      final valorCamisa = _asDouble(participacao['valor_camisa']);

      return valorInscricao + valorCamisa;
    } catch (e) {
      debugPrint('Erro ao buscar valor total: $e');
      return 0;
    }
  }

  /// Busca o total pago de uma participação
  Future<double> buscarTotalPago(String participacaoId) async {
    try {
      final participacao = await buscarPorId(participacaoId);
      if (participacao == null) return 0;

      return _asDouble(participacao['total_pago']);
    } catch (e) {
      debugPrint('Erro ao buscar total pago: $e');
      return 0;
    }
  }

  /// Calcula o saldo devedor de uma participação
  Future<double> calcularSaldoDevedor(String participacaoId) async {
    try {
      final valorTotal = await buscarValorTotal(participacaoId);
      final totalPago = await buscarTotalPago(participacaoId);

      final saldo = valorTotal - totalPago;
      debugPrint(
        '💰 Saldo devedor calculado: $saldo (Total: $valorTotal - Pago: $totalPago)',
      );

      return saldo;
    } catch (e) {
      debugPrint('Erro ao calcular saldo devedor: $e');
      return 0;
    }
  }
}
