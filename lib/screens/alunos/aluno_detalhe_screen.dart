import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:xml/xml.dart' as xml;
import 'editar_aluno_screen.dart';
import 'cadastro_aluno_turma_screen.dart';
import 'package:uai_capoeira/screens/inscricao/visualizar_termo_screen.dart';

// 🔥 IMPORTS DO SISTEMA DE FREQUÊNCIA
import '../../models/frequencia_model.dart';
import '../../services/frequencia_service.dart';
import '../../widgets/indicador_frequencia.dart';
import 'historico_frequencia_screen.dart';
import 'package:uai_capoeira/screens/alunos/detalhe_participacao_screen.dart';

// ============================================
// 🔥 SERVIÇO DE CACHE INTELIGENTE (30 MINUTOS)
// ============================================
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, CacheEntry> _memoryCache = {};
  final Duration cacheValidity = const Duration(minutes: 30);

  // Verifica se o cache é válido (menos de 30 minutos)
  bool isCacheValid(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return false;

    final age = DateTime.now().difference(entry.timestamp);
    return age < cacheValidity;
  }

  // Salva no cache (memória + Firestore)
  Future<void> saveToCache(String key, Map<String, dynamic> data) async {
    // Cache em memória
    _memoryCache[key] = CacheEntry(
      data: data,
      timestamp: DateTime.now(),
    );

    // Cache no Firestore (para persistência)
    try {
      await _firestore
          .collection('cache_alunos')
          .doc(key)
          .set({
        'dados': data,
        'timestamp': FieldValue.serverTimestamp(),
        'valido_ate': DateTime.now().add(cacheValidity).toIso8601String(),
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao salvar cache no Firestore: $e');
    }
  }

  // Carrega do cache (memória > Firestore)
  Future<Map<String, dynamic>?> loadFromCache(String key) async {
    // 1️⃣ Tenta memória primeiro
    if (_memoryCache.containsKey(key) && isCacheValid(key)) {
      debugPrint('✅ Cache válido encontrado na MEMÓRIA para $key');
      return _memoryCache[key]!.data;
    }

    // 2️⃣ Tenta Firestore cache
    try {
      final doc = await _firestore
          .collection('cache_alunos')
          .doc(key)
          .get(const GetOptions(source: Source.cache));

      if (doc.exists) {
        final data = doc.data()!;
        final timestampStr = data['valido_ate'] as String?;

        if (timestampStr != null) {
          final validoAte = DateTime.parse(timestampStr);
          if (DateTime.now().isBefore(validoAte)) {
            debugPrint('✅ Cache válido encontrado no FIRESTORE para $key');

            // Salva também em memória
            _memoryCache[key] = CacheEntry(
              data: Map<String, dynamic>.from(data['dados']),
              timestamp: DateTime.now(),
            );

            return data['dados'] as Map<String, dynamic>;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao ler cache do Firestore: $e');
    }

    return null;
  }

  // Limpa cache antigo
  void limparCacheExpirado() {
    final agora = DateTime.now();
    _memoryCache.removeWhere((key, entry) {
      return agora.difference(entry.timestamp) >= cacheValidity;
    });
  }
}

class CacheEntry {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  CacheEntry({required this.data, required this.timestamp});
}

// ============================================
// 🔐 SERVIÇO DE PERMISSÕES
// ============================================
class PermissaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CacheService _cache = CacheService();

  // Singleton
  static final PermissaoService _instance = PermissaoService._internal();
  factory PermissaoService() => _instance;
  PermissaoService._internal();

  Future<Map<String, bool>> carregarPermissoes(String userId) async {
    final cacheKey = 'permissoes_$userId';

    // Tenta cache primeiro
    final cached = await _cache.loadFromCache(cacheKey);
    if (cached != null) {
      return cached.map((key, value) => MapEntry(key, value as bool));
    }

    try {
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(const GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(const GetOptions(source: Source.server));
      }

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data is Map<String, dynamic>) {
          final permissoes = data.map((key, value) =>
              MapEntry(key, value as bool? ?? false));

          // Salva no cache
          await _cache.saveToCache(cacheKey, permissoes);

          return permissoes;
        }
      }
    } catch (e) {
      print('Erro ao carregar permissões: $e');
    }

    return {};
  }

  Future<bool> temPermissao(String userId, String permissao) async {
    final permissoes = await carregarPermissoes(userId);
    return permissoes[permissao] ?? false;
  }

  Future<bool> isAdmin(String userId) async {
    final cacheKey = 'isAdmin_$userId';

    // Tenta cache primeiro
    final cached = await _cache.loadFromCache(cacheKey);
    if (cached != null) {
      return cached['isAdmin'] as bool;
    }

    try {
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .get(const GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .get(const GetOptions(source: Source.server));
      }

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data is Map<String, dynamic>) {
          final peso = data['peso_permissao'] as int? ?? 0;
          final isAdmin = peso >= 90;

          // Salva no cache
          await _cache.saveToCache(cacheKey, {'isAdmin': isAdmin});

          return isAdmin;
        }
      }
    } catch (e) {
      print('Erro ao verificar admin: $e');
    }
    return false;
  }

  void limparCache(String userId) {
    _cache._memoryCache.remove('permissoes_$userId');
    _cache._memoryCache.remove('isAdmin_$userId');
  }
}

class AlunoDetalheScreen extends StatefulWidget {
  final String alunoId;

  const AlunoDetalheScreen({super.key, required this.alunoId});

  @override
  State<AlunoDetalheScreen> createState() => _AlunoDetalheScreenState();
}

class _AlunoDetalheScreenState extends State<AlunoDetalheScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PermissaoService _permissaoService = PermissaoService();
  final FrequenciaService _frequenciaService = FrequenciaService();
  final Connectivity _connectivity = Connectivity();
  final CacheService _cache = CacheService();

  // ID do usuário logado
  String? _currentUserId;

  // Cache das permissões
  Map<String, bool> _permissoes = {};
  bool _isAdmin = false;
  bool _carregandoPermissoes = true;
  bool _permissoesCarregadas = false;

  // Dados do aluno
  Map<String, dynamic>? _alunoData;
  bool _carregandoAluno = true;

  // 🔥 CONTROLE PARA RECARREGAR FREQUÊNCIA QUANDO VOLTAR DA EDIÇÃO
  int _frequenciaKey = 0;

  @override
  void initState() {
    super.initState();
    _carregarUsuarioLogado();
    _carregarDadosAluno();
  }
  Future<void> _verTermoAluno(BuildContext context, String alunoId, Map<String, dynamic> alunoData) async {
    final inscricaoId = alunoData['inscricao_id'];

    if (inscricaoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Este aluno não possui termo de inscrição'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('inscricoes_aprovadas')
          .doc(inscricaoId)
          .get();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Termo não encontrado'), backgroundColor: Colors.red),
        );
        return;
      }

      final dados = doc.data()!;
      dados['aluno_id'] = alunoId;
      dados['aluno_nome'] = alunoData['nome'];
      dados['aluno_apelido'] = alunoData['apelido'];

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VisualizarTermoScreen(
            dados: dados,
            inscricaoId: inscricaoId,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar termo: $e'), backgroundColor: Colors.red),
      );
    }
  }
  // 👇 VERIFICAR CONEXÃO COM INTERNET
  Future<bool> _temInternet() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Erro ao verificar internet: $e');
      return false;
    }
  }

  // 🔐 CARREGAR DADOS DO ALUNO COM CACHE INTELIGENTE
  Future<void> _carregarDadosAluno() async {
    try {
      final cacheKey = 'aluno_${widget.alunoId}';

      // 🔥 1️⃣ Tenta cache primeiro (se válido)
      final cachedData = await _cache.loadFromCache(cacheKey);
      if (cachedData != null) {
        setState(() {
          _alunoData = cachedData;
          _carregandoAluno = false;
          _frequenciaKey++;
        });
        debugPrint('✅ Dados do aluno carregados do CACHE');
        return;
      }

      // 🔥 2️⃣ Sem cache válido, busca do Firestore
      debugPrint('📡 Buscando dados do aluno do servidor...');

      DocumentSnapshot doc;
      try {
        doc = await _firestore.collection('alunos').doc(widget.alunoId).get(
            const GetOptions(source: Source.server)
        );
      } catch (e) {
        // Se falhou servidor, tenta cache como fallback (mesmo expirado)
        final fallbackCache = await _cache.loadFromCache(cacheKey);
        if (fallbackCache != null) {
          setState(() {
            _alunoData = fallbackCache;
            _carregandoAluno = false;
            _frequenciaKey++;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Modo offline - usando dados salvos'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        throw e;
      }

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        // 🔥 3️⃣ Salva no cache
        await _cache.saveToCache(cacheKey, data);

        setState(() {
          _alunoData = data;
          _carregandoAluno = false;
          _frequenciaKey++;
        });
      } else {
        setState(() {
          _carregandoAluno = false;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar aluno: $e');
      setState(() {
        _carregandoAluno = false;
      });
    }
  }

  // 🔐 CARREGAR USUÁRIO LOGADO E SUAS PERMISSÕES
  Future<void> _carregarUsuarioLogado() async {
    try {
      await FirebaseAuth.instance.authStateChanges().first;
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        _currentUserId = user.uid;
        print('✅ Usuário logado ID: $_currentUserId');
        await _carregarPermissoes();
      } else {
        print('❌ Nenhum usuário logado');
        setState(() {
          _carregandoPermissoes = false;
          _permissoesCarregadas = true;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Usuário não autenticado. Faça login novamente.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar usuário logado: $e');
      setState(() {
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });
    }
  }

  // 🔐 CARREGAR PERMISSÕES DO USUÁRIO
  Future<void> _carregarPermissoes() async {
    if (_currentUserId == null) {
      setState(() {
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });
      return;
    }

    try {
      final permissoes = await _permissaoService.carregarPermissoes(_currentUserId!);
      final isAdmin = await _permissaoService.isAdmin(_currentUserId!);

      setState(() {
        _permissoes = permissoes;
        _isAdmin = isAdmin;
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });

    } catch (e) {
      print('❌ Erro ao carregar permissões: $e');
      setState(() {
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });
    }
  }

  // 🔐 VERIFICAR PERMISSÃO E INTERNET PARA AÇÕES ESCRITA
  Future<bool> _verificarPermissaoEOnline(String permissao, {String? acao}) async {
    if (_carregandoPermissoes || !_permissoesCarregadas) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Carregando permissões...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );
      return false;
    }

    // VERIFICA INTERNET (OBRIGATÓRIO PARA AÇÕES ESCRITA)
    final bool isOnline = await _temInternet();
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌐 Você precisa estar conectado à internet para realizar esta ação.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return false;
    }

    if (_isAdmin) {
      return true;
    }

    final temPermissao = _permissoes[permissao] ?? false;

    if (!temPermissao) {
      await _mostrarDialogoSemPermissao(acao ?? permissao);
    }

    return temPermissao;
  }

  // 🔐 DIÁLOGO DE SEM PERMISSÃO
  Future<void> _mostrarDialogoSemPermissao(String acao) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.no_accounts,
                color: Colors.red.shade900,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Sem Permissão',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você não tem permissão para $acao.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.red.shade900,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Entre em contato com um administrador para solicitar acesso.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade900,
              ),
              child: const Text('Entendi'),
            ),
          ],
        );
      },
    );
  }

  // 📞 FUNÇÕES DE CONTATO (FUNCIONAM OFFLINE)
  Future<void> _launchPhone(String phone) async {
    try {
      String cleanedPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');

      if (!cleanedPhone.startsWith('+')) {
        if (cleanedPhone.startsWith('0')) {
          cleanedPhone = cleanedPhone.substring(1);
        }
        cleanedPhone = '+55$cleanedPhone';
      }

      final url = Uri.parse('tel:$cleanedPhone');

      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        throw Exception('Não foi possível abrir o aplicativo de telefone');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao realizar chamada: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatarNumeroWhatsApp(String numero) {
    String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanedPhone.startsWith('0')) {
      cleanedPhone = cleanedPhone.substring(1);
    }
    if (!cleanedPhone.startsWith('55')) {
      cleanedPhone = '55$cleanedPhone';
    }
    return cleanedPhone;
  }

  Future<void> _abrirWhatsApp(String numero, {String? mensagem, bool isApp = true}) async {
    try {
      String cleanedPhone = _formatarNumeroWhatsApp(numero);
      String url = 'https://wa.me/$cleanedPhone';

      if (mensagem != null && mensagem.isNotEmpty) {
        final encodedMessage = Uri.encodeComponent(mensagem);
        url += '?text=$encodedMessage';
      }

      final uri = Uri.parse(url);

      if (isApp) {
        try {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );

          if (!launched) {
            throw Exception('Não foi possível abrir o app do WhatsApp');
          }
        } catch (appError) {
          final webUrl = Uri.parse('https://web.whatsapp.com/send?phone=$cleanedPhone' +
              (mensagem != null && mensagem.isNotEmpty ? '&text=${Uri.encodeComponent(mensagem)}' : ''));

          await launchUrl(
            webUrl,
            mode: LaunchMode.externalApplication,
          );
        }
      } else {
        final webUrl = Uri.parse('https://web.whatsapp.com/send?phone=$cleanedPhone' +
            (mensagem != null && mensagem.isNotEmpty ? '&text=${Uri.encodeComponent(mensagem)}' : ''));

        await launchUrl(
          webUrl,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o WhatsApp.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _convidarParaGrupo(BuildContext context, String? linkGrupo, String contatoAluno, String? contatoResponsavel) async {
    if (linkGrupo == null || linkGrupo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link do grupo não disponível'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final alunoDoc = await _firestore.collection('alunos').doc(widget.alunoId).get();
      if (!alunoDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aluno não encontrado'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final alunoData = alunoDoc.data() as Map<String, dynamic>;
      final turmaId = alunoData['turma_id'] as String?;

      String mensagemConvite = 'Olá! Aqui está o link para entrar no nosso grupo:';

      if (turmaId != null && turmaId.isNotEmpty) {
        final turmaDoc = await _firestore.collection('turmas').doc(turmaId).get();
        if (turmaDoc.exists) {
          final turmaData = turmaDoc.data() as Map<String, dynamic>?;
          final msgConvite = turmaData?['msg_convite_grupo_whatsapp'] as String?;

          if (msgConvite != null && msgConvite.isNotEmpty) {
            mensagemConvite = msgConvite;
          }
        }
      }

      final mensagem = '$mensagemConvite $linkGrupo';

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Convidar para Grupo'),
          content: const Text('Enviar convite para o grupo para:'),
          actions: [
            if (contatoAluno.isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _abrirWhatsApp(contatoAluno, mensagem: mensagem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Aluno'),
              ),
            if (contatoResponsavel != null && contatoResponsavel.isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _abrirWhatsApp(contatoResponsavel, mensagem: mensagem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Responsável'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar mensagem de convite: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔐 FUNÇÕES DE GERENCIAMENTO COM VALIDAÇÃO DE PERMISSÃO E INTERNET
  Future<void> _editarAluno(BuildContext context) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_editar_aluno',
      acao: 'editar informações do aluno',
    );

    if (!temPermissao || !mounted) return;

    // 🔥 VERIFICAR O PESO_PERMISSAO DO USUÁRIO
    int pesoPermissao = 0;

    try {
      if (_currentUserId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(_currentUserId)
            .get(const GetOptions(source: Source.cache));

        if (userDoc.exists) {
          pesoPermissao = userDoc.data()?['peso_permissao'] as int? ?? 0;
        }
      }
    } catch (e) {
      print('❌ Erro ao verificar peso_permissao: $e');
    }

    // ✅ REDIRECIONAMENTO BASEADO NO PESO
    if (pesoPermissao >= 100) {
      print('✅ Redirecionando para EditarAlunoScreen (peso: $pesoPermissao)');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditarAlunoScreen(
            alunoId: widget.alunoId,
          ),
        ),
      ).then((_) {
        _carregarDadosAluno();
      });

    } else {
      print('🟡 Redirecionando para CadastroAlunoTurmaScreen (peso: $pesoPermissao)');

      try {
        final alunoDoc = await FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId)
            .get(const GetOptions(source: Source.cache));

        if (alunoDoc.exists) {
          final alunoData = alunoDoc.data()!;
          final academiaId = alunoData['academia_id'] as String? ?? '';
          final academiaNome = alunoData['academia'] as String? ?? '';
          final turmaId = alunoData['turma_id'] as String? ?? '';
          final turmaNome = alunoData['turma'] as String? ?? '';

          if (academiaId.isEmpty) {
            print('⚠️ Academia não encontrada, redirecionando para EditarAlunoScreen');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EditarAlunoScreen(
                  alunoId: widget.alunoId,
                ),
              ),
            ).then((_) {
              _carregarDadosAluno();
            });
            return;
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CadastroAlunoTurmaScreen(
                alunoId: widget.alunoId,
                turmaId: turmaId,
                turmaNome: turmaNome,
                academiaId: academiaId,
                academiaNome: academiaNome,
              ),
            ),
          ).then((_) {
            _carregarDadosAluno();
          });
        } else {
          print('⚠️ Aluno não encontrado, redirecionando para EditarAlunoScreen');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditarAlunoScreen(
                alunoId: widget.alunoId,
              ),
            ),
          ).then((_) {
            _carregarDadosAluno();
          });
        }
      } catch (e) {
        print('❌ Erro ao buscar dados do aluno: $e');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados. Usando editor completo.'),
            backgroundColor: Colors.orange,
          ),
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditarAlunoScreen(
              alunoId: widget.alunoId,
            ),
          ),
        ).then((_) {
          _carregarDadosAluno();
        });
      }
    }
  }

  Future<void> _desativarAluno(BuildContext context, String alunoId) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_desativar_aluno',
      acao: 'desativar aluno',
    );

    if (!temPermissao || !mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desativar Aluno'),
        content: const Text('Tem certeza que deseja desativar este aluno?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Desativar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final turmasQuery = await _firestore
            .collection('turmas')
            .where('alunos', arrayContains: alunoId)
            .get(const GetOptions(source: Source.server));

        for (var turmaDoc in turmasQuery.docs) {
          await _firestore
              .collection('turmas')
              .doc(turmaDoc.id)
              .update({
            'alunos': FieldValue.arrayRemove([alunoId])
          });
        }

        await _firestore
            .collection('alunos')
            .doc(alunoId)
            .update({
          'status_atividade': 'INATIVO(A)',
          'data_desativacao': FieldValue.serverTimestamp(),
          'turma': null,
          'turma_id': null,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aluno desativado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }

        _carregarDadosAluno();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao desativar aluno: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _ativarAluno(BuildContext context, String alunoId, Map<String, dynamic> alunoData) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_ativar_alunos',
      acao: 'ativar aluno',
    );

    if (!temPermissao || !mounted) return;

    final academiaId = alunoData['academia_id'] as String?;
    if (academiaId == null || academiaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este aluno não está vinculado a uma academia.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final turmasSnapshot = await _firestore
        .collection('turmas')
        .where('academia_id', isEqualTo: academiaId)
        .get(const GetOptions(source: Source.server));

    final turmasAtivas = turmasSnapshot.docs.where((doc) {
      final status = doc['status'] as String?;
      return status != null && status.toUpperCase() == 'ATIVA';
    }).toList();

    if (turmasAtivas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não há turmas ativas disponíveis nesta academia.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    turmasAtivas.sort((a, b) {
      final nomeA = a['nome'] as String? ?? '';
      final nomeB = b['nome'] as String? ?? '';
      return nomeA.compareTo(nomeB);
    });

    final turmas = await Future.wait(turmasAtivas.map((doc) async {
      final dados = doc.data() as Map<String, dynamic>;
      final capacidadeMaxima = dados['capacidade_maxima'] as int? ?? 0;
      final alunos = (dados['alunos'] as List? ?? []).length;
      final alunosCount = dados['alunos_count'] as int? ?? 0;
      final totalAlunos = alunos > alunosCount ? alunos : alunosCount;
      final temVaga = totalAlunos < capacidadeMaxima;

      return {
        'id': doc.id,
        'nome': dados['nome'] ?? 'Sem nome',
        'horario': dados['horario_display'] ?? dados['horario_inicio'] ?? 'Sem horário',
        'dias': (dados['dias_semana_display'] as List?)?.join(', ') ??
            (dados['dias_semana'] as List?)?.join(', ') ?? 'Sem dias definidos',
        'nivel': dados['nivel'] ?? 'Não especificado',
        'faixa_etaria': dados['faixa_etaria'] ?? 'Não especificada',
        'capacidade_maxima': capacidadeMaxima,
        'total_alunos': totalAlunos,
        'tem_vaga': temVaga,
      };
    }));

    String? selectedTurmaId;
    String? selectedTurmaNome;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Ativar Aluno'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Selecione a turma para vincular o aluno:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ...turmas.map((turma) {
                      final isSelected = selectedTurmaId == turma['id'];
                      final temVaga = turma['tem_vaga'] as bool;
                      final capacidadeMaxima = turma['capacidade_maxima'] as int;
                      final totalAlunos = turma['total_alunos'] as int;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isSelected ? Colors.red.shade50 :
                        !temVaga ? Colors.grey.shade100 : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? Colors.red.shade300 :
                            !temVaga ? Colors.grey.shade400 : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: temVaga ? () {
                            setState(() {
                              selectedTurmaId = turma['id'];
                              selectedTurmaNome = turma['nome'];
                            });
                          } : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? Colors.red.shade900 :
                                    !temVaga ? Colors.grey.shade500 : Colors.grey.shade400,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              turma['nome']!,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? Colors.red.shade900 :
                                                !temVaga ? Colors.grey.shade600 : Colors.black,
                                              ),
                                            ),
                                          ),
                                          if (!temVaga)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade100,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'LOTADA',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red.shade800,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        turma['horario']!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: !temVaga ? Colors.grey.shade500 : Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        turma['dias']!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: !temVaga ? Colors.grey.shade500 : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _buildTurmaChip(
                                            label: turma['nivel']!,
                                            color: Colors.blue.shade100,
                                            textColor: Colors.blue.shade800,
                                          ),
                                          const SizedBox(width: 6),
                                          _buildTurmaChip(
                                            label: turma['faixa_etaria']!,
                                            color: Colors.green.shade100,
                                            textColor: Colors.green.shade800,
                                          ),
                                          const SizedBox(width: 6),
                                          _buildTurmaChip(
                                            label: '$totalAlunos/$capacidadeMaxima alunos',
                                            color: temVaga ? Colors.amber.shade100 : Colors.red.shade100,
                                            textColor: temVaga ? Colors.amber.shade800 : Colors.red.shade800,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: selectedTurmaId != null
                    ? () async {
                  final temVaga = await _verificarCapacidadeTurma(selectedTurmaId!);

                  if (!temVaga) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Esta turma não tem mais vagas disponíveis.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  await _firestore
                      .collection('turmas')
                      .doc(selectedTurmaId!)
                      .update({
                    'alunos': FieldValue.arrayUnion([widget.alunoId])
                  });

                  await _firestore
                      .collection('alunos')
                      .doc(widget.alunoId)
                      .update({
                    'status_atividade': 'ATIVO(A)',
                    'turma_id': selectedTurmaId,
                    'turma': selectedTurmaNome,
                    'data_ativacao': FieldValue.serverTimestamp(),
                    'data_desativacao': null,
                  });

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Aluno ativado com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }

                  Navigator.pop(context);
                  _carregarDadosAluno();
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Ativar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _verificarCapacidadeTurma(String turmaId) async {
    try {
      final turmaDoc = await _firestore.collection('turmas').doc(turmaId).get(
          const GetOptions(source: Source.server)
      );

      if (!turmaDoc.exists) {
        return false;
      }

      final dadosTurma = turmaDoc.data()!;
      final capacidadeMaxima = dadosTurma['capacidade_maxima'] as int? ?? 0;
      final alunos = (dadosTurma['alunos'] as List? ?? []).length;
      final alunosCount = dadosTurma['alunos_count'] as int? ?? 0;

      final totalAlunos = alunos > alunosCount ? alunos : alunosCount;

      return totalAlunos < capacidadeMaxima;
    } catch (e) {
      print('Erro ao verificar capacidade da turma: $e');
      return false;
    }
  }

  Future<void> _mudarTurma(BuildContext context, String alunoId, Map<String, dynamic> alunoData) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_mudar_turma',
      acao: 'mudar aluno de turma',
    );

    if (!temPermissao || !mounted) return;

    final academiaId = alunoData['academia_id'] as String?;
    final turmaAtualId = alunoData['turma_id'] as String?;
    final turmaAtualNome = alunoData['turma'] as String?;

    if (academiaId == null || academiaId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este aluno não está vinculado a uma academia.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final turmasSnapshot = await _firestore
        .collection('turmas')
        .where('academia_id', isEqualTo: academiaId)
        .get(const GetOptions(source: Source.server));

    final turmasAtivas = turmasSnapshot.docs.where((doc) {
      final status = doc['status'] as String?;
      return status != null && status.toUpperCase() == 'ATIVA';
    }).toList();

    if (turmasAtivas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não há turmas ativas disponíveis nesta academia.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    turmasAtivas.sort((a, b) {
      final nomeA = a['nome'] as String? ?? '';
      final nomeB = b['nome'] as String? ?? '';
      return nomeA.compareTo(nomeB);
    });

    final turmas = await Future.wait(turmasAtivas.map((doc) async {
      final dados = doc.data() as Map<String, dynamic>;
      final isTurmaAtual = doc.id == turmaAtualId;
      final capacidadeMaxima = dados['capacidade_maxima'] as int? ?? 0;
      final alunos = (dados['alunos'] as List? ?? []).length;
      final alunosCount = dados['alunos_count'] as int? ?? 0;
      final totalAlunos = alunos > alunosCount ? alunos : alunosCount;
      final temVaga = totalAlunos < capacidadeMaxima || isTurmaAtual;

      return {
        'id': doc.id,
        'nome': dados['nome'] ?? 'Sem nome',
        'horario': dados['horario_display'] ?? dados['horario_inicio'] ?? 'Sem horário',
        'dias': (dados['dias_semana_display'] as List?)?.join(', ') ??
            (dados['dias_semana'] as List?)?.join(', ') ?? 'Sem dias definidos',
        'nivel': dados['nivel'] ?? 'Não especificado',
        'faixa_etaria': dados['faixa_etaria'] ?? 'Não especificada',
        'capacidade_maxima': capacidadeMaxima,
        'total_alunos': totalAlunos,
        'tem_vaga': temVaga,
        'isTurmaAtual': isTurmaAtual,
      };
    }));

    String? selectedTurmaId = turmaAtualId;
    String? selectedTurmaNome = turmaAtualNome;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Mudar de Turma'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Selecione a nova turma para o aluno:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ...turmas.map((turma) {
                      final isSelected = selectedTurmaId == turma['id'];
                      final isTurmaAtual = turma['isTurmaAtual'] == true;
                      final temVaga = turma['tem_vaga'] as bool;
                      final capacidadeMaxima = turma['capacidade_maxima'] as int;
                      final totalAlunos = turma['total_alunos'] as int;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isSelected ? Colors.red.shade50 :
                        isTurmaAtual ? Colors.grey.shade50 :
                        !temVaga ? Colors.grey.shade100 : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? Colors.red.shade300 :
                            isTurmaAtual ? Colors.grey.shade400 :
                            !temVaga ? Colors.grey.shade400 : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: temVaga || isTurmaAtual ? () {
                            setState(() {
                              selectedTurmaId = turma['id'];
                              selectedTurmaNome = turma['nome'];
                            });
                          } : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? Colors.red.shade900 :
                                    isTurmaAtual ? Colors.grey.shade700 :
                                    !temVaga ? Colors.grey.shade500 : Colors.grey.shade400,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              turma['nome']!,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? Colors.red.shade900 :
                                                isTurmaAtual ? Colors.grey.shade800 :
                                                !temVaga ? Colors.grey.shade600 : Colors.black,
                                              ),
                                            ),
                                          ),
                                          if (isTurmaAtual)
                                            Container(
                                              margin: const EdgeInsets.only(left: 8),
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade300,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'ATUAL',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          if (!temVaga && !isTurmaAtual)
                                            Container(
                                              margin: const EdgeInsets.only(left: 8),
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade100,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'LOTADA',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red.shade800,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        turma['horario']!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isTurmaAtual ? Colors.grey.shade600 :
                                          !temVaga ? Colors.grey.shade500 : Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        turma['dias']!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isTurmaAtual ? Colors.grey.shade600 :
                                          !temVaga ? Colors.grey.shade500 : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label: turma['nivel']!,
                                              color: Colors.blue.shade100,
                                              textColor: Colors.blue.shade800,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label: turma['faixa_etaria']!,
                                              color: Colors.green.shade100,
                                              textColor: Colors.green.shade800,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label: '$totalAlunos/$capacidadeMaxima alunos',
                                              color: isTurmaAtual ? Colors.grey.shade200 :
                                              temVaga ? Colors.amber.shade100 : Colors.red.shade100,
                                              textColor: isTurmaAtual ? Colors.grey.shade700 :
                                              temVaga ? Colors.amber.shade800 : Colors.red.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: selectedTurmaId != null
                    ? () async {
                  if (selectedTurmaId == turmaAtualId) {
                    Navigator.pop(context);
                    return;
                  }

                  try {
                    final temVaga = await _verificarCapacidadeTurma(selectedTurmaId!);

                    if (!temVaga) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Esta turma não tem mais vagas disponíveis.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }

                    if (turmaAtualId != null && turmaAtualId.isNotEmpty) {
                      await _firestore
                          .collection('turmas')
                          .doc(turmaAtualId)
                          .update({
                        'alunos': FieldValue.arrayRemove([alunoId])
                      });
                    }

                    await _firestore
                        .collection('turmas')
                        .doc(selectedTurmaId!)
                        .update({
                      'alunos': FieldValue.arrayUnion([alunoId])
                    });

                    await _firestore
                        .collection('alunos')
                        .doc(alunoId)
                        .update({
                      'turma_id': selectedTurmaId,
                      'turma': selectedTurmaNome,
                      'data_mudanca_turma': FieldValue.serverTimestamp(),
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Aluno transferido para nova turma com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }

                    Navigator.pop(context);
                    _carregarDadosAluno();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao mudar turma: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTurmaChip({
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  bool _isAlunoAtivo(String? statusAtividade) {
    return statusAtividade == 'ATIVO(A)' || statusAtividade == 'ATIVO';
  }

  Widget _buildWhatsAppIcon({required bool enabled, required Color color}) {
    return SvgPicture.asset(
      'assets/images/whatsapp.svg',
      width: 20,
      height: 20,
      color: enabled ? color : Colors.grey.shade400,
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (label.contains('WhatsApp'))
                  _buildWhatsAppIcon(
                    enabled: onPressed != null,
                    color: color,
                  )
                else
                  Icon(
                    icon,
                    color: onPressed != null ? color : Colors.grey.shade400,
                    size: 20,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onPressed != null ? Colors.black87 : Colors.grey.shade400,
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getMonitorColor(String monitor) {
    final lowerMonitor = monitor.toLowerCase();
    if (lowerMonitor.contains('azul')) return Colors.blue;
    if (lowerMonitor.contains('roxo') || lowerMonitor.contains('roxa')) return Colors.purple;
    if (lowerMonitor.contains('vermelho') || lowerMonitor.contains('vermelha')) return Colors.red;
    if (lowerMonitor.contains('verde')) return Colors.green;
    if (lowerMonitor.contains('amarelo') || lowerMonitor.contains('amarela')) return Colors.yellow.shade700;
    if (lowerMonitor.contains('branco') || lowerMonitor.contains('branca')) return Colors.grey.shade300;
    if (lowerMonitor.contains('marrom')) return Colors.brown;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    if (_carregandoAluno || _carregandoPermissoes || !_permissoesCarregadas) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Perfil do Aluno'),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 20),
              Text('Carregando informações...'),
            ],
          ),
        ),
      );
    }

    if (_alunoData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Perfil do Aluno'),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 20),
              const Text('Aluno não encontrado', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                ),
                child: const Text('Voltar', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final data = _alunoData!;
    final fotoUrl = data['foto_perfil_aluno'] as String?;
    final contatoAluno = data['contato_aluno'] as String? ?? '';
    final contatoResponsavel = data['contato_responsavel'] as String?;
    final monitor = data['monitor'] as String?;
    final idade = data['idade'] as String?;
    final nome = data['nome'] as String? ?? 'N/A';
    final apelido = data['apelido'] as String?;
    final statusAtividade = data['status_atividade'] as String?;
    final turma = data['turma'] as String?;
    final turmaId = data['turma_id'] as String?;

    final isAtivo = _isAlunoAtivo(statusAtividade);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil do Aluno'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) {
              final List<PopupMenuItem<String>> menuItems = [];

              menuItems.add(
                const PopupMenuItem(
                  value: 'editar',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Editar Perfil'),
                    ],
                  ),
                ),
              );

              // 👇 BOTÃO VER TERMO (sempre aparece)
              menuItems.add(
                const PopupMenuItem(
                  value: 'ver_termo',
                  child: Row(
                    children: [
                      Icon(Icons.description, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Ver Termo'),
                    ],
                  ),
                ),
              );

              if (isAtivo) {
                menuItems.add(
                  const PopupMenuItem(
                    value: 'desativar',
                    child: Row(
                      children: [
                        Icon(Icons.pause_circle, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Desativar Aluno'),
                      ],
                    ),
                  ),
                );
              } else {
                menuItems.add(
                  const PopupMenuItem(
                    value: 'ativar',
                    child: Row(
                      children: [
                        Icon(Icons.play_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Ativar Aluno'),
                      ],
                    ),
                  ),
                );
              }

              if (isAtivo) {
                menuItems.add(
                  const PopupMenuItem(
                    value: 'mudar_turma',
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('Mudar de Turma'),
                      ],
                    ),
                  ),
                );
              }

              menuItems.add(
                const PopupMenuItem(
                  value: 'historico',
                  child: Row(
                    children: [
                      Icon(Icons.history, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Histórico de Frequência'),
                    ],
                  ),
                ),
              );

              return menuItems;
            },
            onSelected: (value) async {
              switch (value) {
                case 'editar':
                  await _editarAluno(context);
                  break;
                case 'ver_termo':  // 👇 NOVO CASE
                  await _verTermoAluno(context, widget.alunoId, data);
                  break;
                case 'desativar':
                  await _desativarAluno(context, widget.alunoId);
                  break;
                case 'ativar':
                  await _ativarAluno(context, widget.alunoId, data);
                  break;
                case 'mudar_turma':
                  await _mudarTurma(context, widget.alunoId, data);
                  break;
                case 'historico':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoricoFrequenciaScreen(
                        alunoId: widget.alunoId,
                        alunoNome: nome,
                      ),
                    ),
                  );
                  break;
              }
            },
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cabeçalho do Perfil
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Foto do aluno
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 3,
                          ),
                        ),
                        child: ClipOval(
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? CachedNetworkImage(
                            imageUrl: fotoUrl,
                            fit: BoxFit.cover,
                            width: 114,
                            height: 114,
                            placeholder: (context, url) =>
                            const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                            errorWidget: (context, url, error) =>
                            const Icon(Icons.person,
                                size: 50, color: Colors.grey),
                          )
                              : Container(
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.person,
                                size: 50, color: Colors.grey),
                          ),
                        ),
                      ),
                      // Badge de status
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isAtivo ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          isAtivo ? 'ATIVO' : 'INATIVO',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Nome e apelido
                  Column(
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (apelido != null && apelido.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '"$apelido"',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Informações básicas
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (idade != null && idade.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.cake,
                                size: 16,
                                color: Colors.red.shade900,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$idade anos',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (turma != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.group,
                                size: 16,
                                color: Colors.red.shade900,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                turma,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Monitor (se houver)
                  if (monitor != null && monitor.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getMonitorColor(monitor),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'MONITOR $monitor'.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Seção de Ações Rápidas
            Container(
              margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.red.shade100,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Contatos Rápidos',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[900],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Linha 1 - Contato Aluno
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickActionButton(
                          icon: Icons.phone,
                          label: 'Ligar para Aluno',
                          onPressed: contatoAluno.isNotEmpty
                              ? () => _launchPhone(contatoAluno)
                              : null,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickActionButton(
                          icon: Icons.chat,
                          label: 'WhatsApp Aluno',
                          onPressed: contatoAluno.isNotEmpty
                              ? () => _abrirWhatsApp(contatoAluno)
                              : null,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Linha 2 - Contato Responsável
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickActionButton(
                          icon: Icons.phone,
                          label: 'Ligar para Responsável',
                          onPressed: contatoResponsavel != null &&
                              contatoResponsavel.isNotEmpty
                              ? () => _launchPhone(contatoResponsavel!)
                              : null,
                          color: Colors.purple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickActionButton(
                          icon: Icons.chat,
                          label: 'WhatsApp Responsável',
                          onPressed: contatoResponsavel != null &&
                              contatoResponsavel.isNotEmpty
                              ? () => _abrirWhatsApp(contatoResponsavel!)
                              : null,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Botão de convidar para grupo
                  FutureBuilder<DocumentSnapshot>(
                    future: _firestore.collection('turmas').doc(turmaId).get(),
                    builder: (context, snapshot) {
                      String? whatsappUrl;
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final turmaData = snapshot.data!.data() as Map<String, dynamic>?;
                        whatsappUrl = turmaData?['whatsapp_url'] as String?;
                      }

                      return _buildQuickActionButton(
                        icon: Icons.group_add,
                        label: 'Convidar para Grupo',
                        onPressed: whatsappUrl != null && whatsappUrl.isNotEmpty
                            ? () => _convidarParaGrupo(context, whatsappUrl, contatoAluno, contatoResponsavel)
                            : null,
                        color: Colors.orange,
                      );
                    },
                  ),
                ],
              ),
            ),

            // 🔥 CARD DE FREQUÊNCIA COM CACHE INTELIGENTE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CardFrequenciaModerno(
                key: ValueKey(_frequenciaKey),
                alunoId: widget.alunoId,
                filtroTemporal: 'Ano',
                anoSelecionado: '2026',
              ),
            ),

            // Card de Informações Completas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: CardInformacoesModerno(alunoId: widget.alunoId),
            ),

            const SizedBox(height: 12),

            // 🔥 CARD DE EVENTOS PARTICIPADOS
            CardEventosParticipados(
              alunoId: widget.alunoId,
              alunoData: data,
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================
// ✅ CARD DE FREQUÊNCIA - CACHE INTELIGENTE (30 MINUTOS)
// ============================================
class CardFrequenciaModerno extends StatefulWidget {
  final String alunoId;
  final String? filtroTemporal;
  final String? anoSelecionado;

  const CardFrequenciaModerno({
    super.key,
    required this.alunoId,
    this.filtroTemporal,
    this.anoSelecionado,
  });

  @override
  State<CardFrequenciaModerno> createState() => _CardFrequenciaModernoState();
}

class _CardFrequenciaModernoState extends State<CardFrequenciaModerno> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FrequenciaService _frequenciaService = FrequenciaService();
  final CacheService _cache = CacheService();
  final Connectivity _connectivity = Connectivity();

  Map<String, dynamic>? _dadosAluno;
  FrequenciaModel? _frequencia;
  List<Map<String, dynamic>> _logsFrequencia = [];
  bool _isLoading = true;
  bool _expanded = false;
  bool _isAtualizando = false;
  bool _isOffline = false;

  // 🔥 FILTROS INTERNOS
  String? _filtroAtual;
  String? _anoAtual;

  // Contadores calculados dos logs
  int _totalPresencas = 0;
  int _totalAusencias = 0;
  late Map<String, int> _presencasPorDia;
  Timestamp? _ultimaPresenca;

  @override
  void initState() {
    super.initState();

    _filtroAtual = widget.filtroTemporal;
    _anoAtual = widget.anoSelecionado;

    _resetContadores();
    _carregarDados();
  }

  void _resetContadores() {
    _presencasPorDia = {
      'seg': 0, 'ter': 0, 'qua': 0, 'qui': 0, 'sex': 0, 'sab': 0, 'dom': 0
    };
    _totalPresencas = 0;
    _totalAusencias = 0;
    _ultimaPresenca = null;
  }

  // 🔥 VERIFICAR INTERNET
  Future<bool> _temInternet() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  // 🔥 FUNÇÃO PARA MUDAR O FILTRO
  void _aplicarFiltro(String? filtro, {String? ano}) {
    setState(() {
      _filtroAtual = filtro;
      if (filtro == 'Ano' && ano != null) {
        _anoAtual = ano;
      } else if (filtro != 'Ano') {
        _anoAtual = null;
      }
    });
    _carregarDados();
  }

  // 🔥 FUNÇÃO PARA FORÇAR ATUALIZAÇÃO DO SERVIDOR
  Future<void> _forcarAtualizacao() async {
    setState(() {
      _isAtualizando = true;
    });

    try {
      debugPrint('🔄 FORÇANDO ATUALIZAÇÃO DO SERVIDOR PARA ALUNO ${widget.alunoId}');
      await _carregarDados(forcarServidor: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dados atualizados com sucesso!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao forçar atualização: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAtualizando = false;
        });
      }
    }
  }

  // 🔥 CARREGAR DADOS COM CACHE INTELIGENTE
  Future<void> _carregarDados({bool forcarServidor = false}) async {
    setState(() {
      _isLoading = true;
      _resetContadores();
      _isOffline = false;
    });

    try {
      final cacheKey = 'frequencia_${widget.alunoId}_${_filtroAtual ?? 'total'}_${_anoAtual ?? ''}';
      final temInternet = await _temInternet();

      // 🔥 1️⃣ Se NÃO forçar servidor e tiver cache válido, usa cache
      if (!forcarServidor && temInternet) {
        final cachedData = await _cache.loadFromCache(cacheKey);
        if (cachedData != null) {
          _logsFrequencia = List<Map<String, dynamic>>.from(cachedData['logs'] ?? []);
          _dadosAluno = cachedData['dados_aluno'] as Map<String, dynamic>?;
          _calcularFrequenciaDosLogs();

          setState(() => _isLoading = false);
          debugPrint('✅ Frequência carregada do CACHE (válido)');
          return;
        }
      }

      // 🔥 2️⃣ Se estiver offline e sem cache, tenta cache mesmo expirado
      if (!temInternet) {
        final fallbackCache = await _cache.loadFromCache(cacheKey);
        if (fallbackCache != null) {
          _logsFrequencia = List<Map<String, dynamic>>.from(fallbackCache['logs'] ?? []);
          _dadosAluno = fallbackCache['dados_aluno'] as Map<String, dynamic>?;
          _calcularFrequenciaDosLogs();

          setState(() {
            _isLoading = false;
            _isOffline = true;
          });

          debugPrint('⚠️ Modo offline - usando cache expirado');
          return;
        }
      }

      // 🔥 3️⃣ Busca do servidor
      debugPrint('📡 Buscando frequência do servidor...');

      // Buscar dados do aluno
      final alunoDoc = await _firestore
          .collection('alunos')
          .doc(widget.alunoId)
          .get(const GetOptions(source: Source.server));

      if (!alunoDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      _dadosAluno = alunoDoc.data();

      // Buscar logs
      await _carregarLogsComFiltro();

      // Calcular frequência
      _calcularFrequenciaDosLogs();

      // 🔥 4️⃣ Salvar no cache
      if (_logsFrequencia.isNotEmpty) {
        await _cache.saveToCache(cacheKey, {
          'logs': _logsFrequencia,
          'dados_aluno': _dadosAluno,
        });
      }

    } catch (e) {
      debugPrint('❌ Erro ao carregar frequência: $e');

      // 🔥 Fallback: tenta cache em caso de erro
      final fallbackCache = await _cache.loadFromCache('frequencia_${widget.alunoId}');
      if (fallbackCache != null) {
        _logsFrequencia = List<Map<String, dynamic>>.from(fallbackCache['logs'] ?? []);
        _dadosAluno = fallbackCache['dados_aluno'] as Map<String, dynamic>?;
        _calcularFrequenciaDosLogs();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Usando dados offline'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Carrega logs aplicando o filtro
  Future<void> _carregarLogsComFiltro() async {
    try {
      Query query = _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: widget.alunoId)
          .orderBy('data_aula', descending: true);

      // Aplica filtro temporal
      if (_filtroAtual != null) {
        final now = DateTime.now();

        switch (_filtroAtual) {
          case 'Semana':
            final umaSemanaAtras = now.subtract(const Duration(days: 7));
            query = query.where('data_aula', isGreaterThanOrEqualTo: Timestamp.fromDate(umaSemanaAtras));
            break;
          case 'Mês':
            final umMesAtras = DateTime(now.year, now.month - 1, now.day);
            query = query.where('data_aula', isGreaterThanOrEqualTo: Timestamp.fromDate(umMesAtras));
            break;
          case 'Ano':
            if (_anoAtual != null) {
              final inicioAno = DateTime(int.parse(_anoAtual!), 1, 1);
              final fimAno = DateTime(int.parse(_anoAtual!), 12, 31, 23, 59, 59);
              query = query
                  .where('data_aula', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioAno))
                  .where('data_aula', isLessThanOrEqualTo: Timestamp.fromDate(fimAno));
            }
            break;
        }
      }

      final snapshot = await query.get(const GetOptions(source: Source.server));

      _logsFrequencia = snapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      debugPrint('📊 Logs carregados do servidor: ${_logsFrequencia.length}');

    } catch (e) {
      debugPrint('❌ Erro ao carregar logs: $e');
      _logsFrequencia = [];
    }
  }

  // Calcula estatísticas dos logs
  void _calcularFrequenciaDosLogs() {
    for (var log in _logsFrequencia) {
      final presente = log['presente'] as bool? ?? false;
      final dataLog = log['data_aula'] as Timestamp?;
      final diaSemana = log['dia_semana_abrev'] as String?;

      if (presente) {
        _totalPresencas++;

        if (dataLog != null) {
          if (_ultimaPresenca == null || dataLog.toDate().isAfter(_ultimaPresenca!.toDate())) {
            _ultimaPresenca = dataLog;
          }
        }

        if (diaSemana != null && _presencasPorDia.containsKey(diaSemana)) {
          _presencasPorDia[diaSemana] = _presencasPorDia[diaSemana]! + 1;
        }
      } else {
        _totalAusencias++;
      }
    }

    final dadosCompletos = <String, dynamic>{
      if (_dadosAluno != null) ..._dadosAluno!,
      'seg': _presencasPorDia['seg'],
      'ter': _presencasPorDia['ter'],
      'qua': _presencasPorDia['qua'],
      'qui': _presencasPorDia['qui'],
      'sex': _presencasPorDia['sex'],
      'sab': _presencasPorDia['sab'],
      'dom': _presencasPorDia['dom'],
      'total_presencas': _totalPresencas,
      'total_ausencias': _totalAusencias,
      'ultimo_dia_presente': _ultimaPresenca,
    };

    _frequencia = _frequenciaService.calcularFrequencia(dadosCompletos);

    if (mounted) {
      setState(() {});
    }

    debugPrint('📊 Frequência calculada - Total: $_totalPresencas');
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return "Nunca";
    return DateFormat("dd/MM/yyyy").format(timestamp.toDate());
  }

  Widget _buildAlunoAvatar() {
    final fotoUrl = _dadosAluno?['foto_perfil_aluno'] as String?;

    return CircleAvatar(
      radius: 40,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
          ? NetworkImage(fotoUrl)
          : null,
      child: fotoUrl == null || fotoUrl.isEmpty
          ? Text(
        _dadosAluno?['nome']?.toString().substring(0, 1).toUpperCase() ?? '?',
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      )
          : null,
    );
  }

  Widget _buildMetricCard({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildDiaCardCompacto(String dia, int quantidade) {
    return Container(
      width: 38,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: quantidade > 0 ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: quantidade > 0 ? Colors.red.shade200 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            dia,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: quantidade > 0 ? Colors.red.shade900 : Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quantidade.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: quantidade > 0 ? Colors.red.shade900 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _getTituloFiltro() {
    if (_filtroAtual == null) return '';

    if (_filtroAtual == 'Ano' && _anoAtual != null) {
      return ' • $_anoAtual';
    }
    return ' • $_filtroAtual';
  }

  String _getSubtituloFiltro() {
    if (_filtroAtual == null) return '';

    switch (_filtroAtual) {
      case 'Semana':
        return 'Últimos 7 dias';
      case 'Mês':
        return 'Últimos 30 dias';
      case 'Ano':
        return _anoAtual ?? 'Ano selecionado';
      case 'Total':
        return 'Todo histórico';
      default:
        return '';
    }
  }

  Widget _buildFiltrosRow() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFiltroChip('Semana', Icons.calendar_view_week),
          _buildFiltroChip('Mês', Icons.calendar_month),
          _buildFiltroChip('Ano', Icons.calendar_today),
          _buildFiltroChip('Total', Icons.history),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String label, IconData icon) {
    final isSelected = _filtroAtual == label;

    return FilterChip(
      label: Text(label),
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : Colors.grey.shade600,
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          if (label == 'Ano') {
            _mostrarSeletorAno();
          } else {
            _aplicarFiltro(label);
          }
        } else {
          _aplicarFiltro(null);
        }
      },
      selectedColor: Colors.red.shade900,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 12,
      ),
      backgroundColor: Colors.grey.shade100,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Future<void> _mostrarSeletorAno() async {
    final anoAtual = DateTime.now().year;
    final anos = List.generate(10, (index) => (anoAtual - index).toString());

    final anoSelecionado = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Selecione o ano'),
        children: anos.map((ano) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ano),
            child: Text(ano),
          );
        }).toList(),
      ),
    );

    if (anoSelecionado != null) {
      _aplicarFiltro('Ano', ano: anoSelecionado);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    if (_frequencia == null || _dadosAluno == null) {
      return Container(
        height: 200,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar dados de frequência',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _forcarAtualizacao,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final frequencia = _frequencia!;
    final nome = _dadosAluno!['nome'] ?? 'Aluno';

    return GestureDetector(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho com nome, foto e indicador offline
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: frequencia.corIndicador.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildAlunoAvatar(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    nome,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // 🔥 INDICADOR OFFLINE
                                if (_isOffline)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.wifi_off,
                                      size: 16,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                // 🔥 BOTÃO DE ATUALIZAÇÃO
                                if (!_isAtualizando)
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 20),
                                    onPressed: _forcarAtualizacao,
                                    color: Colors.red.shade900,
                                    tooltip: 'Atualizar dados',
                                  ),
                                if (_isAtualizando)
                                  Container(
                                    width: 30,
                                    height: 30,
                                    padding: const EdgeInsets.all(4),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: frequencia.corIndicador.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    frequencia.nivel,
                                    style: TextStyle(
                                      color: frequencia.corIndicador,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (_filtroAtual != null) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _getTituloFiltro(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (_filtroAtual != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                _getSubtituloFiltro(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  _buildFiltrosRow(),
                ],
              ),
            ),

            // Conteúdo
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Métricas principais
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricCard(
                        value: '$_totalPresencas',
                        label: 'Presenças',
                        color: Colors.blue,
                        icon: Icons.event_available,
                      ),
                      _buildMetricCard(
                        value: '$_totalAusencias',
                        label: 'Faltas',
                        color: Colors.red,
                        icon: Icons.event_busy,
                      ),
                      _buildMetricCard(
                        value: '${frequencia.diasSemTreinar}',
                        label: 'Dias sem',
                        color: frequencia.corIndicador,
                        icon: Icons.calendar_today,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Última presença
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: frequencia.corIndicador,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Última presença',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                _formatarData(_ultimaPresenca),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                frequencia.statusTexto,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: frequencia.corIndicador,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Dias da semana
                  const Text(
                    'Presenças por dia',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDiaCardCompacto('S', _presencasPorDia['seg']!),
                      _buildDiaCardCompacto('T', _presencasPorDia['ter']!),
                      _buildDiaCardCompacto('Q', _presencasPorDia['qua']!),
                      _buildDiaCardCompacto('Q', _presencasPorDia['qui']!),
                      _buildDiaCardCompacto('S', _presencasPorDia['sex']!),
                      _buildDiaCardCompacto('S', _presencasPorDia['sab']!),
                      _buildDiaCardCompacto('D', _presencasPorDia['dom']!),
                    ],
                  ),

                  if (_expanded) ...[
                    const SizedBox(height: 20),

                    // Lista dos últimos logs
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _logsFrequencia.length > 10 ? 10 : _logsFrequencia.length,
                        itemBuilder: (context, index) {
                          final log = _logsFrequencia[index];
                          final presente = log['presente'] as bool? ?? false;
                          final data = log['data_aula'] as Timestamp?;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              presente ? Icons.check_circle : Icons.cancel,
                              color: presente ? Colors.green : Colors.red,
                              size: 18,
                            ),
                            title: Text(
                              _formatarData(data),
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              log['tipo_aula']?.toString() ?? 'N/A',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Botão de ver histórico
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('FECHAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Botão de expandir/recolher
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.red.shade900,
                    ),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// ✅ CARD DE EVENTOS PARTICIPADOS
// ============================================
class CardEventosParticipados extends StatefulWidget {
  final String alunoId;
  final Map<String, dynamic> alunoData;

  const CardEventosParticipados({
    super.key,
    required this.alunoId,
    required this.alunoData,
  });

  @override
  State<CardEventosParticipados> createState() => _CardEventosParticipadosState();
}

class _CardEventosParticipadosState extends State<CardEventosParticipados> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CacheService _cache = CacheService();

  List<Map<String, dynamic>> _participacoes = [];
  bool _isLoading = true;
  bool _expanded = false;
  String? _erro;

  // Cache para as cores das graduações
  final Map<String, Map<String, dynamic>> _graduacoesCache = {};

  // Cache para o SVG
  String? _svgContent;
  final Map<String, String?> _svgCache = {};

  @override
  void initState() {
    super.initState();
    _carregarSvg();
    _carregarParticipacoes();
  }

  Future<void> _carregarSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() {
          _svgContent = content;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar SVG: $e');
    }
  }

  // 🔥 CARREGAR PARTICIPAÇÕES COM CACHE INTELIGENTE
  Future<void> _carregarParticipacoes() async {
    try {
      final cacheKey = 'eventos_${widget.alunoId}';

      // Tenta cache primeiro
      final cachedData = await _cache.loadFromCache(cacheKey);
      if (cachedData != null) {
        _participacoes = List<Map<String, dynamic>>.from(cachedData['participacoes'] ?? []);
        setState(() {
          _isLoading = false;
          _erro = null;
        });
        return;
      }

      // Busca do servidor
      final participacoesSnapshot = await _firestore
          .collection('participacoes_eventos')
          .where('aluno_id', isEqualTo: widget.alunoId)
          .orderBy('data_evento', descending: true)
          .get(const GetOptions(source: Source.server));

      if (participacoesSnapshot.docs.isEmpty) {
        setState(() {
          _participacoes = [];
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> participacoesCompletas = [];

      for (var doc in participacoesSnapshot.docs) {
        final participacao = doc.data();
        final eventoId = participacao['evento_id'] as String?;

        if (eventoId != null) {
          final eventoDoc = await _firestore
              .collection('eventos')
              .doc(eventoId)
              .get(const GetOptions(source: Source.server));

          if (eventoDoc.exists) {
            final eventoData = eventoDoc.data()!;
            participacoesCompletas.add({
              'id': doc.id,
              ...participacao,
              'evento_detalhes': eventoData,
            });
          } else {
            participacoesCompletas.add({
              'id': doc.id,
              ...participacao,
            });
          }
        } else {
          participacoesCompletas.add({
            'id': doc.id,
            ...participacao,
          });
        }
      }

      // Salva no cache
      await _cache.saveToCache(cacheKey, {
        'participacoes': participacoesCompletas,
      });

      setState(() {
        _participacoes = participacoesCompletas;
        _isLoading = false;
        _erro = null;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar participações: $e');
      setState(() {
        _isLoading = false;
        _erro = e.toString();
      });
    }
  }

  Future<Map<String, dynamic>?> _getCoresGraduacao(String? graduacaoId) async {
    if (graduacaoId == null || graduacaoId.isEmpty) return null;

    if (_graduacoesCache.containsKey(graduacaoId)) {
      return _graduacoesCache[graduacaoId];
    }

    try {
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection('graduacoes')
            .doc(graduacaoId)
            .get(const GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('graduacoes')
            .doc(graduacaoId)
            .get(const GetOptions(source: Source.server));
      }

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;

        if (data != null) {
          _graduacoesCache[graduacaoId] = {
            'hex_cor1': data['hex_cor1'],
            'hex_cor2': data['hex_cor2'],
            'hex_ponta1': data['hex_ponta1'],
            'hex_ponta2': data['hex_ponta2'],
            'nome_graduacao': data['nome_graduacao'],
          };
          return _graduacoesCache[graduacaoId];
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar graduação: $e');
    }
    return null;
  }

  Future<String?> _getSvgColorido(String? graduacaoId) async {
    if (graduacaoId == null || _svgContent == null) return null;

    final cacheKey = 'svg_$graduacaoId';
    if (_svgCache.containsKey(cacheKey)) {
      return _svgCache[cacheKey];
    }

    final cores = await _getCoresGraduacao(graduacaoId);
    if (cores == null) return null;

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.length < 7) return Colors.grey;
        try {
          return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
        } catch (e) {
          return Colors.grey;
        }
      }

      void changeColor(String id, Color color) {
        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );
        if (element.name.local.isNotEmpty) {
          final style = element.getAttribute('style') ?? '';
          final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
          final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
          element.setAttribute('style', 'fill:$hex;$newStyle');
        }
      }

      changeColor('cor1', colorFromHex(cores['hex_cor1']));
      changeColor('cor2', colorFromHex(cores['hex_cor2']));
      changeColor('corponta1', colorFromHex(cores['hex_ponta1']));
      changeColor('corponta2', colorFromHex(cores['hex_ponta2']));

      final svgString = document.toXmlString();
      _svgCache[cacheKey] = svgString;
      return svgString;

    } catch (e) {
      debugPrint('Erro ao colorir SVG: $e');
      return null;
    }
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';
    if (data is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(data.toDate());
    }
    return data.toString();
  }

  Future<void> _abrirDetalhesParticipacao(Map<String, dynamic> participacao, String id) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalheParticipacaoScreen(
          participacao: participacao,
          participacaoId: id,
        ),
      ),
    );
  }

  void _abrirLinkCertificado(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir certificado: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final graduacaoId = widget.alunoData['graduacao_id']?.toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: Colors.amber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Eventos Participados',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        _isLoading
                            ? 'Carregando...'
                            : _erro != null
                            ? 'Erro ao carregar'
                            : '${_participacoes.length} ${_participacoes.length == 1 ? 'evento' : 'eventos'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _erro != null ? Colors.red : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (graduacaoId != null)
                  FutureBuilder<String?>(
                    future: _getSvgColorido(graduacaoId),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return SizedBox(
                          width: 50,
                          height: 50,
                          child: SvgPicture.string(
                            snapshot.data!,
                            placeholderBuilder: (context) => const SizedBox(),
                          ),
                        );
                      }
                      return const SizedBox(
                        width: 50,
                        height: 50,
                        child: Icon(Icons.emoji_events, color: Colors.amber),
                      );
                    },
                  ),
              ],
            ),
          ),

          // Conteúdo
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: Colors.amber)),
            )
          else if (_erro != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Erro ao carregar eventos',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Text(
                    _erro!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_participacoes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_busy,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum evento participado',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      'Este aluno ainda não participou de eventos',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ..._participacoes.take(_expanded ? _participacoes.length : 3).map((participacao) {
                      final eventoDetalhes = participacao['evento_detalhes'] as Map<String, dynamic>?;
                      final nomeEvento = eventoDetalhes?['nome'] ?? participacao['evento_nome'] ?? 'Evento';
                      final dataEvento = _formatarData(eventoDetalhes?['data'] ?? participacao['data_evento']);
                      final tipoEvento = eventoDetalhes?['tipo_evento'] ?? participacao['tipo_evento'] ?? '';
                      final certificado = participacao['link_certificado'] as String?;
                      final graduacaoEvento = participacao['graduacao'] as String?;

                      return InkWell(
                        onTap: () => _abrirDetalhesParticipacao(participacao, participacao['id']),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.event,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nomeEvento,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today, size: 10, color: Colors.grey.shade600),
                                        const SizedBox(width: 4),
                                        Text(
                                          dataEvento,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        if (tipoEvento.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 4,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade400,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              tipoEvento,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (graduacaoEvento != null && graduacaoEvento.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.emoji_events, size: 10, color: Colors.amber.shade700),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              graduacaoEvento,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.amber.shade700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (certificado != null && certificado.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    Icons.verified,
                                    color: Colors.green.shade600,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _abrirLinkCertificado(certificado);
                                  },
                                  tooltip: 'Ver certificado',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    if (_participacoes.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _expanded = !_expanded;
                            });
                          },
                          icon: Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.amber.shade700,
                          ),
                          label: Text(
                            _expanded ? 'Ver menos' : 'Ver todos (${_participacoes.length})',
                            style: TextStyle(
                              color: Colors.amber.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// CARD DE INFORMAÇÕES COM DESIGN MODERNO
class CardInformacoesModerno extends StatefulWidget {
  final String alunoId;

  const CardInformacoesModerno({super.key, required this.alunoId});

  @override
  State<CardInformacoesModerno> createState() => _CardInformacoesModernoState();
}

class _CardInformacoesModernoState extends State<CardInformacoesModerno> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _dadosAluno;
  bool _isLoading = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _carregarDadosAluno();
  }

  Future<void> _carregarDadosAluno() async {
    try {
      DocumentSnapshot alunoDoc;
      try {
        alunoDoc = await _firestore.collection('alunos').doc(widget.alunoId).get(
            const GetOptions(source: Source.cache)
        );
      } catch (e) {
        alunoDoc = await _firestore.collection('alunos').doc(widget.alunoId).get(
            const GetOptions(source: Source.server)
        );
      }

      if (!alunoDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() {
        _dadosAluno = alunoDoc.data() as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar dados do aluno: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatarData(dynamic data) {
    if (data == null) return "Não informado";

    if (data is Timestamp) {
      return DateFormat("dd/MM/yyyy").format(data.toDate());
    }

    if (data is String) {
      try {
        final date = DateTime.parse(data);
        return DateFormat("dd/MM/yyyy").format(date);
      } catch (e) {
        return data;
      }
    }

    return data.toString();
  }

  Widget _buildInfoItem({
    required String label,
    required String value,
    IconData? icon,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Icon(
              icon,
              size: 16,
              color: iconColor ?? Colors.red.shade900,
            ),
          SizedBox(width: icon != null ? 12 : 0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: const Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    if (_dadosAluno == null) {
      return const SizedBox.shrink();
    }

    final dados = _dadosAluno!;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info,
                  color: Colors.blue.shade900,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Informações do Aluno',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.blue.shade900,
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Conteúdo
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoItem(
                  label: 'Nome completo',
                  value: dados['nome']?.toString() ?? 'Não informado',
                  icon: Icons.person,
                  iconColor: Colors.red.shade900,
                ),

                _buildInfoItem(
                  label: 'Apelido',
                  value: dados['apelido']?.toString() ?? 'Sem apelido',
                  icon: Icons.emoji_emotions,
                  iconColor: Colors.orange,
                ),

                _buildInfoItem(
                  label: 'Data de nascimento',
                  value: _formatarData(dados['data_nascimento']),
                  icon: Icons.cake,
                  iconColor: Colors.pink,
                ),

                if (_expanded) ...[
                  const Divider(),
                  const SizedBox(height: 12),

                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Contato',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Telefone',
                    value: dados['contato_aluno']?.toString() ?? 'Não informado',
                    icon: Icons.phone,
                    iconColor: Colors.green,
                  ),

                  _buildInfoItem(
                    label: 'Endereço',
                    value: dados['endereco']?.toString() ?? 'Não informado',
                    icon: Icons.home,
                    iconColor: Colors.blue,
                  ),

                  const SizedBox(height: 12),

                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Responsável',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Nome do responsável',
                    value: dados['nome_responsavel']?.toString() ?? 'Não informado',
                    icon: Icons.person_outline,
                    iconColor: Colors.purple,
                  ),

                  _buildInfoItem(
                    label: 'Contato do responsável',
                    value: dados['contato_responsavel']?.toString() ?? 'Não informado',
                    icon: Icons.phone_android,
                    iconColor: Colors.teal,
                  ),

                  const SizedBox(height: 12),

                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Cadastro',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Data do cadastro',
                    value: _formatarData(dados['data_do_cadastro']),
                    icon: Icons.calendar_today,
                    iconColor: Colors.grey,
                  ),

                  _buildInfoItem(
                    label: 'Cadastrado por',
                    value: dados['cadastro_realizado_por']?.toString() ?? 'Sistema',
                    icon: Icons.person_add,
                    iconColor: Colors.grey,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}