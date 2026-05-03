import 'package:cloud_firestore/cloud_firestore.dart';

class RastreioSiteService {
  static final RastreioSiteService _instance = RastreioSiteService._internal();

  factory RastreioSiteService() => _instance;

  RastreioSiteService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _documentoAcessoId;
  DateTime? _inicioSessao;

  void iniciarSessaoComDocumento(String documentoId) {
    _documentoAcessoId = documentoId;
    _inicioSessao = DateTime.now();
    print('✅ Sessão iniciada para documento: $documentoId');
  }

  Future<void> registrarEvento({
    required String tipo,
    required String nome,
    String? origem,
    String? paginaOrigem,
    Map<String, dynamic>? metadata,
  }) async {
    if (_documentoAcessoId == null) {
      print('⚠️ Nenhum documento de acesso ativo. Ignorando evento: $tipo | $nome');
      return;
    }

    print('📝 Tentando registrar evento "$tipo|$nome" no documento $_documentoAcessoId');

    try {
      final agora = DateTime.now();
      final evento = {
        'tipo': tipo,
        'nome': nome,
        'origem': origem,
        'pagina_origem': paginaOrigem,
        'timestamp': agora.millisecondsSinceEpoch, // 🔥 Número inteiro (compatível com timestamp)
        'data_hora': agora.toIso8601String(),
        'metadata': metadata ?? {},
      };

      await _firestore
          .collection('estatisticas_acessos')
          .doc(_documentoAcessoId!)
          .update({
        'eventos': FieldValue.arrayUnion([evento]),
        'ultima_atividade': FieldValue.serverTimestamp(),
        'total_eventos': FieldValue.increment(1),
      });

      print('✅ Evento registrado com sucesso: $tipo | $nome | $origem');
    } catch (e) {
      print('❌ Erro ao registrar evento: $e');
      if (e is FirebaseException) {
        print('   Código: ${e.code}');
        print('   Mensagem: ${e.message}');
      }
    }
  }

  Future<void> registrarPaginaVista(String pagina, String? origem) async {
    await registrarEvento(
      tipo: 'pagina',
      nome: pagina,
      origem: origem,
      metadata: {'tempo_carregamento': DateTime.now().millisecondsSinceEpoch},
    );
  }

  Future<void> finalizarSessao() async {
    if (_documentoAcessoId != null && _inicioSessao != null) {
      final duracao = DateTime.now().difference(_inicioSessao!).inSeconds;
      try {
        await _firestore
            .collection('estatisticas_acessos')
            .doc(_documentoAcessoId)
            .update({
          'fim_sessao': FieldValue.serverTimestamp(),
          'duracao_segundos': duracao,
        });
        print('✅ Sessão finalizada. Duração: ${duracao}s');
      } catch (e) {
        print('❌ Erro ao finalizar sessão: $e');
      }
    }
  }

  Future<Map<String, dynamic>> buscarRastroSessao(String documentoId) async {
    try {
      final doc = await _firestore
          .collection('estatisticas_acessos')
          .doc(documentoId)
          .get();

      if (!doc.exists) {
        return {'erro': 'Documento não encontrado'};
      }

      final data = doc.data()!;
      final eventosRaw = data['eventos'] as List? ?? [];
      final List<Map<String, dynamic>> eventosMap = eventosRaw
          .map((e) => e as Map<String, dynamic>)
          .toList();

      return {
        'sessao': {
          'id': documentoId,
          'ip': data['ip'],
          'cidade': data['cidade'],
          'estado': data['estado'],
          'pais': data['pais'],
          'latitude': data['latitude'],
          'longitude': data['longitude'],
          'isp': data['isp'],
          'inicio_sessao': (data['data_acesso'] as Timestamp?)?.toDate(),
          'fim_sessao': (data['fim_sessao'] as Timestamp?)?.toDate(),
          'total_eventos': data['total_eventos'] ?? 0,
          'user_agent': data['user_agent'] ?? 'Desconhecido',
        },
        'eventos': eventosMap,
        'resumo': {
          'total_eventos': eventosMap.length,
          'menus_clicados': eventosMap.where((e) => e['tipo'] == 'menu').length,
          'botoes_clicados': eventosMap.where((e) => e['tipo'] == 'botao_social').length,
          'cards_clicados': eventosMap.where((e) => e['tipo'] == 'card').length,
          'paginas_vistas': eventosMap.where((e) => e['tipo'] == 'pagina').length,
        },
      };
    } catch (e) {
      print('❌ Erro ao buscar rastro: $e');
      return {'erro': e.toString()};
    }
  }

  String? get documentoAcessoId => _documentoAcessoId;
}