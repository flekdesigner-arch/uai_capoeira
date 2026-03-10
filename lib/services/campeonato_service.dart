import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'dart:developer' as developer;
import '../models/campeonato_model.dart';
import '../models/grupo_model.dart';
import '../models/categoria_model.dart';
import '../models/inscricao_model.dart';
import '../models/inscricao_campeonato_model.dart';

class CampeonatoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ==================== CONFIGURAÇÕES ====================

  /// 🔥 NOVO MÉTODO: Carregar configurações do campeonato
  Future<Map<String, dynamic>> carregarConfiguracoes() async {
    try {
      developer.log('📥 Carregando configurações do campeonato...');

      final doc = await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .get();

      if (!doc.exists) {
        developer.log('⚠️ Documento "campeonato" não encontrado');
        return {};
      }

      developer.log('✅ Configurações carregadas com sucesso');
      return doc.data()!;
    } catch (e) {
      developer.log('❌ Erro ao carregar configurações: $e');
      return {};
    }
  }

  /// Salvar configurações do campeonato
  Future<void> salvarConfiguracoes(Map<String, dynamic> config) async {
    try {
      await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .set(config, SetOptions(merge: true));

      developer.log('✅ Configurações salvas com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao salvar configurações: $e');
      rethrow;
    }
  }

  // ==================== GRUPOS CONVIDADOS ====================

  /// Carrega todos os grupos convidados ativos
  Future<List<GrupoModel>> carregarGruposConvidados() async {
    try {
      developer.log('🔍 Carregando grupos convidados...');

      final campeonatoDoc = await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .get();

      if (!campeonatoDoc.exists) {
        developer.log('❌ Documento "campeonato" não existe');
        return [];
      }

      final querySnapshot = await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .collection('grupos_convidados')
          .get();

      developer.log('📦 Total de documentos: ${querySnapshot.docs.length}');

      List<GrupoModel> grupos = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final ativo = data['ativo'] ?? true;

        if (ativo && data['nome'] != null && data['nome'].toString().trim().isNotEmpty) {
          grupos.add(GrupoModel.fromFirestore(data, doc.id));
        }
      }

      grupos.sort((a, b) => a.nome.compareTo(b.nome));

      // Adiciona grupo UAI como primeira opção
      grupos.insert(0, GrupoModel(
        id: 'GRUPO_UAI',
        nome: 'GRUPO UAI CAPOEIRA',
        ativo: true,
      ));

      developer.log('✅ Grupos carregados: ${grupos.length} (incluindo UAI)');
      return grupos;
    } catch (e) {
      developer.log('❌ Erro ao carregar grupos: $e');
      rethrow;
    }
  }

  /// Adicionar um novo grupo convidado
  Future<void> adicionarGrupoConvidado(GrupoModel grupo) async {
    try {
      await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .collection('grupos_convidados')
          .add(grupo.toFirestore());

      developer.log('✅ Grupo adicionado com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao adicionar grupo: $e');
      rethrow;
    }
  }

  /// Atualizar um grupo convidado
  Future<void> atualizarGrupoConvidado(String grupoId, GrupoModel grupo) async {
    try {
      await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .collection('grupos_convidados')
          .doc(grupoId)
          .update(grupo.toFirestore());

      developer.log('✅ Grupo atualizado com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao atualizar grupo: $e');
      rethrow;
    }
  }

  /// Excluir um grupo convidado
  Future<void> excluirGrupoConvidado(String grupoId) async {
    try {
      await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .collection('grupos_convidados')
          .doc(grupoId)
          .delete();

      developer.log('✅ Grupo excluído com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao excluir grupo: $e');
      rethrow;
    }
  }

  // ==================== GRADUAÇÕES ====================

  /// Carrega todas as graduações UAI
  Future<List<Map<String, dynamic>>> carregarGraduacoesUai() async {
    try {
      final snapshot = await _firestore
          .collection('graduacoes')
          .where('nivel_graduacao', isLessThanOrEqualTo: 14)
          .orderBy('nivel_graduacao')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      developer.log('❌ Erro ao carregar graduações: $e');
      rethrow;
    }
  }

  // ==================== CAMPEONATOS ====================

  /// Buscar campeonato por ID
  Future<CampeonatoModel?> getCampeonato(String campeonatoId) async {
    try {
      developer.log('🔍 Buscando campeonato com ID: $campeonatoId');

      DocumentSnapshot doc;

      if (campeonatoId == 'campeonato') {
        doc = await _firestore.collection('configuracoes').doc('campeonato').get();
      } else {
        doc = await _firestore.collection('eventos').doc(campeonatoId).get();
      }

      if (!doc.exists) {
        developer.log('❌ Documento não encontrado');
        return null;
      }

      developer.log('✅ Documento encontrado: ${doc.id}');
      return CampeonatoModel.fromFirestore(doc);
    } catch (e) {
      developer.log('❌ Erro ao buscar campeonato: $e');
      return null;
    }
  }

  /// Stream de campeonato (para atualizações em tempo real)
  Stream<DocumentSnapshot> streamCampeonato(String campeonatoId) {
    return _firestore.collection('configuracoes').doc('campeonato').snapshots();
  }

  // ==================== INSCRIÇÕES ====================

  /// Buscar todas as inscrições do campeonato
  Stream<QuerySnapshot> getInscricoesStream(String campeonatoId) {
    return _firestore
        .collection('campeonato_inscricoes')
        .orderBy('data_inscricao', descending: true)
        .snapshots();
  }

  /// Buscar inscrições por status
  Stream<QuerySnapshot> getInscricoesPorStatusStream(String campeonatoId, String status) {
    return _firestore
        .collection('campeonato_inscricoes')
        .where('status', isEqualTo: status)
        .orderBy('data_inscricao', descending: true)
        .snapshots();
  }

  /// Buscar uma inscrição específica
  Future<InscricaoCampeonatoModel?> getInscricao(String inscricaoId) async {
    try {
      developer.log('🔍 Buscando inscrição com ID: $inscricaoId');

      final doc = await _firestore.collection('campeonato_inscricoes').doc(inscricaoId).get();

      if (!doc.exists) {
        developer.log('❌ Documento não encontrado');
        return null;
      }

      return InscricaoCampeonatoModel.fromFirestore(doc);
    } catch (e) {
      developer.log('❌ Erro ao buscar inscrição: $e');
      return null;
    }
  }

  /// Salvar nova inscrição
  Future<String> salvarInscricao(InscricaoModel inscricao) async {
    try {
      final docRef = await _firestore
          .collection('campeonato_inscricoes')
          .add(inscricao.toFirestore());

      // Atualizar contador
      await _firestore.collection('configuracoes').doc('campeonato').set({
        'total_inscricoes': FieldValue.increment(1),
      }, SetOptions(merge: true));

      developer.log('✅ Inscrição salva com ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      developer.log('❌ Erro ao salvar inscrição: $e');
      rethrow;
    }
  }

  /// Atualizar status da inscrição
  Future<void> atualizarStatusInscricao(String inscricaoId, String status) async {
    try {
      await _firestore
          .collection('campeonato_inscricoes')
          .doc(inscricaoId)
          .update({'status': status});

      developer.log('✅ Status atualizado para: $status');
    } catch (e) {
      developer.log('❌ Erro ao atualizar status: $e');
      rethrow;
    }
  }

  /// Confirmar pagamento da inscrição
  Future<void> confirmarPagamento(String inscricaoId) async {
    try {
      await _firestore
          .collection('campeonato_inscricoes')
          .doc(inscricaoId)
          .update({
        'taxa_paga': true,
        'status': 'confirmado',
        'data_confirmacao': FieldValue.serverTimestamp(),
      });

      developer.log('✅ Pagamento confirmado');
    } catch (e) {
      developer.log('❌ Erro ao confirmar pagamento: $e');
      rethrow;
    }
  }

  /// Adicionar observação na inscrição
  Future<void> adicionarObservacao(String inscricaoId, String observacao) async {
    try {
      await _firestore
          .collection('campeonato_inscricoes')
          .doc(inscricaoId)
          .update({
        'observacoes': FieldValue.arrayUnion([observacao]),
        'ultima_observacao': observacao,
        'data_observacao': FieldValue.serverTimestamp(),
      });

      developer.log('✅ Observação adicionada');
    } catch (e) {
      developer.log('❌ Erro ao adicionar observação: $e');
      rethrow;
    }
  }

  /// Excluir inscrição
  Future<void> excluirInscricao(String inscricaoId) async {
    try {
      developer.log('🗑️ Excluindo inscrição: $inscricaoId');
      await _firestore
          .collection('campeonato_inscricoes')
          .doc(inscricaoId)
          .delete();
      developer.log('✅ Inscrição excluída com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao excluir inscrição: $e');
      rethrow;
    }
  }

  /// Contar inscrições ativas
  Future<int> contarInscricoesAtivas() async {
    try {
      final snapshot = await _firestore
          .collection('campeonato_inscricoes')
          .where('status', whereIn: ['pendente', 'confirmado'])
          .get();

      return snapshot.docs.length;
    } catch (e) {
      developer.log('❌ Erro ao contar inscrições: $e');
      return 0;
    }
  }

  /// Verificar vagas disponíveis
  Future<bool> verificarVagasDisponiveis(int vagasTotais) async {
    if (vagasTotais <= 0) return true;
    final inscricoesAtivas = await contarInscricoesAtivas();
    return inscricoesAtivas < vagasTotais;
  }

  // ==================== CATEGORIAS ====================

  /// Processar categorias do Firestore
  List<CategoriaModel> processarCategorias(List<dynamic> categoriasData) {
    return categoriasData
        .where((cat) => cat['ativo'] == true)
        .map((cat) => CategoriaModel.fromFirestore(cat as Map<String, dynamic>, id: cat['id']))
        .toList();
  }

  /// Buscar competidores por categoria
  Future<List<InscricaoCampeonatoModel>> getCompetidoresPorCategoria(String categoriaNome) async {
    try {
      developer.log('🔍 Buscando competidores para categoria: $categoriaNome');

      final snapshot = await _firestore
          .collection('campeonato_inscricoes')
          .where('categoria_nome', isEqualTo: categoriaNome)
          .where('status', isEqualTo: 'confirmado')
          .orderBy('nome')
          .get();

      developer.log('📦 Competidores encontrados: ${snapshot.docs.length}');

      return snapshot.docs
          .map((doc) => InscricaoCampeonatoModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      developer.log('❌ Erro ao buscar competidores: $e');
      return [];
    }
  }

  // ==================== ESTATÍSTICAS ====================

  /// Buscar estatísticas gerais do campeonato
  Future<Map<String, dynamic>> getEstatisticas(String campeonatoId) async {
    try {
      developer.log('📊 Buscando estatísticas...');

      // 🔥 BUSCAR TAXA ATUAL DAS CONFIGURAÇÕES
      final configDoc = await _firestore
          .collection('configuracoes')
          .doc('campeonato')
          .get();

      double taxaAtual = 30.0; // valor padrão
      if (configDoc.exists) {
        final configData = configDoc.data();
        if (configData != null && configData.containsKey('taxa_inscricao')) {
          taxaAtual = (configData['taxa_inscricao'] as num).toDouble();
          developer.log('💰 Taxa atual das configurações: R\$ $taxaAtual');
        }
      }

      final inscricoes = await _firestore
          .collection('campeonato_inscricoes')
          .get();

      int total = inscricoes.docs.length;
      int pendentes = inscricoes.docs.where((doc) => doc['status'] == 'pendente').length;
      int confirmados = inscricoes.docs.where((doc) => doc['status'] == 'confirmado').length;
      int cancelados = inscricoes.docs.where((doc) => doc['status'] == 'cancelado').length;
      int pagos = inscricoes.docs.where((doc) => doc['taxa_paga'] == true).length;

      // Agrupar por categoria
      Map<String, int> porCategoria = {};
      Map<String, int> pagosPorCategoria = {};

      for (var doc in inscricoes.docs) {
        String categoria = doc['categoria_nome'] ?? 'Sem categoria';
        porCategoria[categoria] = (porCategoria[categoria] ?? 0) + 1;

        if (doc['taxa_paga'] == true) {
          pagosPorCategoria[categoria] = (pagosPorCategoria[categoria] ?? 0) + 1;
        }
      }

      // Agrupar por grupo
      Map<String, int> porGrupo = {};
      for (var doc in inscricoes.docs) {
        String grupo = doc['grupo'] ?? 'Sem grupo';
        porGrupo[grupo] = (porGrupo[grupo] ?? 0) + 1;
      }

      // 🔥 CALCULAR TOTAL ARRECADADO COM A TAXA ATUAL
      double totalArrecadado = pagos * taxaAtual;

      developer.log('💰 Total arrecadado: R\$ $totalArrecadado ($pagos pagos x R\$ $taxaAtual)');

      return {
        'total': total,
        'pendentes': pendentes,
        'confirmados': confirmados,
        'cancelados': cancelados,
        'pagos': pagos,
        'nao_pagos': total - pagos,
        'por_categoria': porCategoria,
        'pagos_por_categoria': pagosPorCategoria,
        'por_grupo': porGrupo,
        'total_arrecadado': totalArrecadado,
        'taxa_base': taxaAtual,
      };
    } catch (e) {
      developer.log('❌ Erro ao buscar estatísticas: $e');
      return {
        'total': 0,
        'pendentes': 0,
        'confirmados': 0,
        'cancelados': 0,
        'pagos': 0,
        'nao_pagos': 0,
        'por_categoria': {},
        'pagos_por_categoria': {},
        'por_grupo': {},
        'total_arrecadado': 0,
        'taxa_base': 0,
      };
    }
  }

  // ==================== UPLOAD DE ARQUIVOS ====================

  /// Fazer upload de arquivo para o Storage
  Future<String?> uploadArquivo(Uint8List bytes, String pasta, String nomeArquivo) async {
    try {
      final ref = _storage.ref().child('$pasta/$nomeArquivo');
      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: _getContentType(nomeArquivo)),
      );
      final url = await uploadTask.ref.getDownloadURL();

      developer.log('✅ Upload concluído: $url');
      return url;
    } catch (e) {
      developer.log('❌ Erro no upload: $e');
      return null;
    }
  }

  /// Determinar content type baseado na extensão
  String _getContentType(String nomeArquivo) {
    final ext = nomeArquivo.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  // ==================== PRESENÇA ====================

  /// Marcar presença do competidor
  Future<void> marcarPresenca(String inscricaoId, bool presente) async {
    try {
      await _firestore
          .collection('campeonato_inscricoes')
          .doc(inscricaoId)
          .update({'presente': presente});

      developer.log('✅ Presença marcada: $presente');
    } catch (e) {
      developer.log('❌ Erro ao marcar presença: $e');
      rethrow;
    }
  }

  // ==================== CHAVEAMENTO ====================

  /// Gerar chaves para uma categoria
  Future<void> gerarChaves(String categoriaId, List<String> competidoresIds) async {
    try {
      // Embaralhar competidores
      List<String> shuffled = List.from(competidoresIds)..shuffle();

      // Criar chaves (mata-mata)
      List<Map<String, dynamic>> chaves = [];

      for (int i = 0; i < shuffled.length; i += 2) {
        if (i + 1 < shuffled.length) {
          chaves.add({
            'competidor1': shuffled[i],
            'competidor2': shuffled[i + 1],
            'vencedor': null,
            'status': 'pendente',
          });
        } else {
          // Competidor com "bye" (passa direto)
          chaves.add({
            'competidor1': shuffled[i],
            'competidor2': null,
            'vencedor': shuffled[i],
            'status': 'bye',
          });
        }
      }

      // Salvar chaves
      await _firestore
          .collection('campeonato_chaves')
          .doc(categoriaId)
          .set({
        'categoria_id': categoriaId,
        'chaves': chaves,
        'rodada': 1,
        'total_rodadas': _calcularTotalRodadas(competidoresIds.length),
        'status': 'ativo',
      });

      developer.log('✅ Chaves geradas para categoria: $categoriaId');
    } catch (e) {
      developer.log('❌ Erro ao gerar chaves: $e');
      rethrow;
    }
  }

  /// Atualizar chaves (para edição manual)
  Future<void> atualizarChaves(String categoriaId, List<dynamic> novasChaves) async {
    try {
      developer.log('🔄 Atualizando chaves para categoria: $categoriaId');

      await _firestore
          .collection('campeonato_chaves')
          .doc(categoriaId)
          .update({
        'chaves': novasChaves,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      developer.log('✅ Chaves atualizadas com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao atualizar chaves: $e');
      rethrow;
    }
  }

  /// Registrar resultado de um confronto
  Future<void> registrarResultado(
      String categoriaId,
      int chaveIndex,
      String vencedorId,
      ) async {
    try {
      final docRef = _firestore.collection('campeonato_chaves').doc(categoriaId);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        List<dynamic> chaves = List.from(snapshot['chaves']);

        if (chaves.length > chaveIndex) {
          chaves[chaveIndex]['vencedor'] = vencedorId;
          chaves[chaveIndex]['status'] = 'finalizado';

          transaction.update(docRef, {'chaves': chaves});
        }
      });

      developer.log('✅ Resultado registrado');
    } catch (e) {
      developer.log('❌ Erro ao registrar resultado: $e');
      rethrow;
    }
  }

  /// Avançar para próxima rodada
  Future<void> avancarRodada(String categoriaId) async {
    try {
      final doc = await _firestore.collection('campeonato_chaves').doc(categoriaId).get();

      if (!doc.exists) return;

      List<dynamic> chavesAtuais = doc['chaves'];
      int rodadaAtual = doc['rodada'];

      // Pegar vencedores
      List<String> vencedores = [];
      for (var chave in chavesAtuais) {
        if (chave['vencedor'] != null) {
          vencedores.add(chave['vencedor']);
        }
      }

      // Criar novas chaves
      List<Map<String, dynamic>> novasChaves = [];
      for (int i = 0; i < vencedores.length; i += 2) {
        if (i + 1 < vencedores.length) {
          novasChaves.add({
            'competidor1': vencedores[i],
            'competidor2': vencedores[i + 1],
            'vencedor': null,
            'status': 'pendente',
          });
        } else {
          novasChaves.add({
            'competidor1': vencedores[i],
            'competidor2': null,
            'vencedor': vencedores[i],
            'status': 'bye',
          });
        }
      }

      // Atualizar
      await doc.reference.update({
        'chaves': novasChaves,
        'rodada': rodadaAtual + 1,
      });

      developer.log('✅ Rodada avançada para: ${rodadaAtual + 1}');
    } catch (e) {
      developer.log('❌ Erro ao avançar rodada: $e');
      rethrow;
    }
  }

  /// Calcular total de rodadas
  int _calcularTotalRodadas(int numCompetidores) {
    int rodadas = 0;
    int n = numCompetidores;
    while (n > 1) {
      n = (n / 2).ceil();
      rodadas++;
    }
    return rodadas;
  }

  /// Buscar chaves de uma categoria
  Future<Map<String, dynamic>?> getChaves(String categoriaId) async {
    try {
      final doc = await _firestore.collection('campeonato_chaves').doc(categoriaId).get();
      return doc.data();
    } catch (e) {
      developer.log('❌ Erro ao buscar chaves: $e');
      return null;
    }
  }
}