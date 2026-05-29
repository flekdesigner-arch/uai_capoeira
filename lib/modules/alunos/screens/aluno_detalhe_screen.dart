import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:xml/xml.dart' as xml;
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'editar_aluno_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/cadastro_aluno_turma_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/public/visualizar_termo_screen.dart';

// 🔥 IMPORTS DO SISTEMA DE FREQUÊNCIA
import 'package:uai_capoeira/modules/chamadas/models/frequencia_model.dart';
import 'package:uai_capoeira/modules/chamadas/services/frequencia_service.dart';
import 'package:uai_capoeira/shared/widgets/indicador_frequencia.dart';
import 'historico_frequencia_screen.dart';
import 'package:uai_capoeira/modules/alunos/screens/detalhe_participacao_screen.dart';

// ============================================
// 🔥 SERVIÇO DE CACHE INTELIGENTE (30 MINUTOS)
// ============================================
Color _readableOn(Color background) {
  return background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}

Color _onCard(BuildContext context) => _readableOn(context.uai.card);
Color _onCardMuted(BuildContext context) => _onCard(context).withOpacity(0.68);
Color _onPrimary(BuildContext context) => _readableOn(context.uai.primary);

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, CacheEntry> _memoryCache = {};
  final Duration cacheValidity = Duration(minutes: 30);

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
          .get(GetOptions(source: Source.cache));

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
            .get(GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(GetOptions(source: Source.server));
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
            .get(GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .get(GetOptions(source: Source.server));
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

  AlunoDetalheScreen({super.key, required this.alunoId});

  @override
  State<AlunoDetalheScreen> createState() => _AlunoDetalheScreenState();
}

class _AlunoDetalheScreenState extends State<AlunoDetalheScreen> {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard([BuildContext? c]) => _readableOn((c ?? context).uai.card);
  Color _onCardMuted([BuildContext? c]) => _onCard(c ?? context).withOpacity(0.68);
  Color _onPrimary([BuildContext? c]) => _readableOn((c ?? context).uai.primary);


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
          backgroundColor: context.uai.warning,
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
          SnackBar(content: Text('Termo não encontrado'), backgroundColor: context.uai.error),
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
        SnackBar(content: Text('Erro ao carregar termo: $e'), backgroundColor: context.uai.error),
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
            GetOptions(source: Source.server)
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
              SnackBar(
                content: Text('⚠️ Modo offline - usando dados salvos'),
                backgroundColor: context.uai.warning,
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
              SnackBar(
                content: Text('Usuário não autenticado. Faça login novamente.'),
                backgroundColor: context.uai.error,
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
        SnackBar(
          content: Text('Carregando permissões...'),
          backgroundColor: context.uai.info,
          duration: Duration(seconds: 1),
        ),
      );
      return false;
    }

    // VERIFICA INTERNET (OBRIGATÓRIO PARA AÇÕES ESCRITA)
    final bool isOnline = await _temInternet();
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🌐 Você precisa estar conectado à internet para realizar esta ação.'),
          backgroundColor: context.uai.warning,
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
                color: context.uai.primary,
                size: 28,
              ),
              SizedBox(width: 12),
              Text(
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
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.uai.error.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.uai.error.withOpacity(0.16)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: context.uai.primary,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Entre em contato com um administrador para solicitar acesso.',
                        style: TextStyle(
                          fontSize: 14,
                          color: _onCard(context),
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
                foregroundColor: context.uai.primary,
              ),
              child: Text('Entendi'),
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
            backgroundColor: context.uai.error,
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
          SnackBar(
            content: Text('Não foi possível abrir o WhatsApp.'),
            backgroundColor: context.uai.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _convidarParaGrupo(BuildContext context, String? linkGrupo, String contatoAluno, String? contatoResponsavel) async {
    if (linkGrupo == null || linkGrupo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link do grupo não disponível'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    try {
      final alunoDoc = await _firestore.collection('alunos').doc(widget.alunoId).get();
      if (!alunoDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aluno não encontrado'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      final alunoData = alunoDoc.data() as Map<String, dynamic>;
      final nomeAluno = alunoData['nome'] ?? 'Aluno';
      final turmaId = alunoData['turma_id'] as String?;

      String mensagemConvite = 'Olá! Aqui está o link para entrar no nosso grupo:';

      if (turmaId != null && turmaId.isNotEmpty) {
        final turmaDoc = await _firestore.collection('turmas').doc(turmaId).get();
        if (turmaDoc.exists) {
          final turmaData = turmaDoc.data() as Map<String, dynamic>?;
          String msgConvite = turmaData?['msg_convite_grupo_whatsapp'] as String? ?? '';

          if (msgConvite.isNotEmpty) {
            // 🔥 SUBSTITUI O {nome_aluno} PELO NOME REAL DO ALUNO
            mensagemConvite = msgConvite.replaceAll('{nome_aluno}', nomeAluno);
          }
        }
      }

      final mensagem = '$mensagemConvite\n\n👇 ENTRE NO GRUPO PELO LINK ABAIXO:\n$linkGrupo';

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Convidar para Grupo'),
          content: Text('Enviar convite para o grupo para:'),
          actions: [
            if (contatoAluno.isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _abrirWhatsApp(contatoAluno, mensagem: mensagem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                  foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                ),
                child: Text('Aluno'),
              ),
            if (contatoResponsavel != null && contatoResponsavel.isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _abrirWhatsApp(contatoResponsavel, mensagem: mensagem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                  foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                ),
                child: Text('Responsável'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar', style: TextStyle(color: context.uai.textMuted)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar mensagem de convite: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }


  String _iniciaisAreaAluno(String nomeCompleto) {
    final ignorar = {'DE', 'DA', 'DO', 'DAS', 'DOS', 'E'};

    final partes = nomeCompleto
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty && !ignorar.contains(p.trim()))
        .toList();

    if (partes.isEmpty) return '';

    return partes
        .map((p) => p.characters.first)
        .join()
        .replaceAll(RegExp(r'[^A-ZÀ-Ú0-9]'), '');
  }

  String _formatarDataNascimentoAreaAluno(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String) {
      final raw = value.trim();

      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(raw)) {
        return raw;
      }

      date = DateTime.tryParse(raw);
    }

    if (date == null) return '';

    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _ultimosQuatroDigitos(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');

    if (digits.length <= 4) return digits;

    return digits.substring(digits.length - 4);
  }

  Future<Map<String, dynamic>> _configAreaAlunoAtual() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_site')
          .doc('area_aluno')
          .get(GetOptions(source: Source.server));

      return doc.data() ?? {};
    } catch (_) {
      try {
        final doc = await _firestore
            .collection('configuracoes_site')
            .doc('area_aluno')
            .get(GetOptions(source: Source.cache));

        return doc.data() ?? {};
      } catch (_) {
        return {};
      }
    }
  }

  bool _areaAlunoVisivel(Map<String, dynamic> config) {
    final value = config['visivel_site'];
    return value == true;
  }

  Future<void> _enviarAcessoAreaAlunoWhatsApp({
    required String nomeAluno,
    required String contatoAluno,
    required String? contatoResponsavel,
    required String nomeResponsavel,
  }) async {
    try {
      final config = await _configAreaAlunoAtual();

      if (!_areaAlunoVisivel(config)) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A Área do Aluno não está ativa no site.'),
            backgroundColor: context.uai.warning,
          ),
        );
        return;
      }

      final alunoDoc = await _firestore.collection('alunos').doc(widget.alunoId).get();

      if (!alunoDoc.exists) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aluno não encontrado.'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      final alunoData = alunoDoc.data() ?? {};
      final nome = alunoData['nome']?.toString() ?? nomeAluno;
      final dataNascimento = _formatarDataNascimentoAreaAluno(alunoData['data_nascimento']);
      final iniciais = _iniciaisAreaAluno(nome);
      final exigeTelefone = config['exigir_telefone_confirmacao'] != false;

      final contatoAlunoAtual = alunoData['contato_aluno']?.toString() ?? contatoAluno;
      final contatoResponsavelAtual = alunoData['contato_responsavel']?.toString() ?? contatoResponsavel;

      final telefoneBase = _temContatoValido(contatoAlunoAtual)
          ? contatoAlunoAtual
          : (contatoResponsavelAtual ?? '');
      final telefoneFinal = _ultimosQuatroDigitos(telefoneBase);

      if (dataNascimento.isEmpty || iniciais.isEmpty || (exigeTelefone && telefoneFinal.length != 4)) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dados insuficientes para montar o acesso da Área do Aluno.'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      final linhas = <String>[
        '🥋 *ÁREA DO ALUNO - UAI CAPOEIRA* 🥋',
        '',
        'Olá! Seguem as instruções para acessar a Área do Aluno de *$nome*.',
        '',
        '🌐 Acesse o site:',
        'http://uaicapoeira.com.br',
        '',
        'No site, toque em *Área do Aluno* e preencha:',
        '',
        '📅 *Data de nascimento:* $dataNascimento',
        '🔤 *Iniciais do nome:* $iniciais',
      ];

      if (exigeTelefone) {
        linhas.add('📱 *Últimos 4 dígitos do telefone:* $telefoneFinal');
      }

      linhas.addAll([
        '',
        '✅ Depois de entrar, o aluno poderá consultar dados, turma, frequência, eventos e certificados.',
        '',
        '⚠️ Não compartilhe esses dados com outras pessoas.',
      ]);

      final mensagem = linhas.join('\n');

      final destinos = <Map<String, String>>[];

      if (_temContatoValido(contatoAlunoAtual)) {
        destinos.add({
          'label': 'Aluno',
          'numero': contatoAlunoAtual,
        });
      }

      if (_temContatoValido(contatoResponsavelAtual) &&
          _limparNumeroContato(contatoResponsavelAtual) != _limparNumeroContato(contatoAlunoAtual)) {
        destinos.add({
          'label': nomeResponsavel.trim().isNotEmpty ? nomeResponsavel : 'Responsável',
          'numero': contatoResponsavelAtual!,
        });
      }

      if (destinos.isEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nenhum WhatsApp válido cadastrado para o aluno ou responsável.'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.school_rounded, color: context.uai.associacao),
                SizedBox(width: 8),
                Expanded(child: Text('Enviar acesso da Área do Aluno')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Escolha para quem enviar as instruções de acesso:',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.uai.associacao.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.uai.associacao.withOpacity(0.16)),
                  ),
                  child: Text(
                    'Iniciais: $iniciais\nData: $dataNascimento${exigeTelefone ? '\nFinal do telefone: $telefoneFinal' : ''}',
                    style: TextStyle(
                      color: context.uai.associacao,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CANCELAR'),
              ),
              ...destinos.map((destino) {
                return ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _abrirWhatsApp(destino['numero']!, mensagem: mensagem);
                  },
                  icon: Icon(Icons.send_rounded, size: 18),
                  label: Text(destino['label']!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: destino['label'] == 'Aluno'
                        ? context.uai.success
                        : context.uai.info,
                    foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                  ),
                );
              }),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar acesso da Área do Aluno: $e'),
          backgroundColor: context.uai.error,
        ),
      );
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
            .get(GetOptions(source: Source.cache));

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
            .get(GetOptions(source: Source.cache));

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
            backgroundColor: context.uai.warning,
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
        title: Text('Desativar Aluno'),
        content: Text('Tem certeza que deseja desativar este aluno?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.warning,
            ),
            child: Text('Desativar', style: TextStyle(color: context.uai.card)),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final turmasQuery = await _firestore
            .collection('turmas')
            .where('alunos', arrayContains: alunoId)
            .get(GetOptions(source: Source.server));

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
            SnackBar(
              content: Text('Aluno desativado com sucesso!'),
              backgroundColor: context.uai.success,
            ),
          );
        }

        _carregarDadosAluno();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao desativar aluno: $e'),
              backgroundColor: context.uai.error,
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
        SnackBar(
          content: Text('Este aluno não está vinculado a uma academia.'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    final turmasSnapshot = await _firestore
        .collection('turmas')
        .where('academia_id', isEqualTo: academiaId)
        .get(GetOptions(source: Source.server));

    final turmasAtivas = turmasSnapshot.docs.where((doc) {
      final status = doc['status'] as String?;
      return status != null && status.toUpperCase() == 'ATIVA';
    }).toList();

    if (turmasAtivas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não há turmas ativas disponíveis nesta academia.'),
            backgroundColor: context.uai.error,
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
            title: Text('Ativar Aluno'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Selecione a turma para vincular o aluno:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    ...turmas.map((turma) {
                      final isSelected = selectedTurmaId == turma['id'];
                      final temVaga = turma['tem_vaga'] as bool;
                      final capacidadeMaxima = turma['capacidade_maxima'] as int;
                      final totalAlunos = turma['total_alunos'] as int;

                      return Card(
                        margin: EdgeInsets.only(bottom: 8),
                        color: isSelected ? context.uai.error.withOpacity(0.10) :
                        !temVaga ? context.uai.cardAlt : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? context.uai.error :
                            !temVaga ? context.uai.textMuted : context.uai.border,
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
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? context.uai.primary :
                                    !temVaga ? context.uai.textMuted : context.uai.textMuted,
                                  ),
                                ),
                                SizedBox(width: 12),
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
                                                color: isSelected ? context.uai.primary :
                                                !temVaga ? context.uai.textSecondary : Colors.black,
                                              ),
                                            ),
                                          ),
                                          if (!temVaga)
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.uai.error.withOpacity(0.16),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'LOTADA',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.uai.error,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        turma['horario']!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: !temVaga ? context.uai.textMuted : context.uai.textMuted,
                                        ),
                                      ),
                                      Text(
                                        turma['dias']!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: !temVaga ? context.uai.textMuted : context.uai.textMuted,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _buildTurmaChip(
                                            label: turma['nivel']!,
                                            color: context.uai.info.withOpacity(0.16),
                                            textColor: context.uai.info,
                                          ),
                                          SizedBox(width: 6),
                                          _buildTurmaChip(
                                            label: turma['faixa_etaria']!,
                                            color: context.uai.success.withOpacity(0.16),
                                            textColor: context.uai.success,
                                          ),
                                          SizedBox(width: 6),
                                          _buildTurmaChip(
                                            label: '$totalAlunos/$capacidadeMaxima alunos',
                                            color: temVaga ? context.uai.warning.withOpacity(0.16) : context.uai.error.withOpacity(0.16),
                                            textColor: temVaga ? context.uai.warning : context.uai.error,
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
                child: Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: selectedTurmaId != null
                    ? () async {
                  final temVaga = await _verificarCapacidadeTurma(selectedTurmaId!);

                  if (!temVaga) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Esta turma não tem mais vagas disponíveis.'),
                          backgroundColor: context.uai.error,
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
                      SnackBar(
                        content: Text('Aluno ativado com sucesso!'),
                        backgroundColor: context.uai.success,
                      ),
                    );
                  }

                  Navigator.pop(context);
                  _carregarDadosAluno();
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.success,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Ativar', style: TextStyle(color: context.uai.card)),
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
          GetOptions(source: Source.server)
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
          SnackBar(
            content: Text('Este aluno não está vinculado a uma academia.'),
            backgroundColor: context.uai.error,
          ),
        );
      }
      return;
    }

    final turmasSnapshot = await _firestore
        .collection('turmas')
        .where('academia_id', isEqualTo: academiaId)
        .get(GetOptions(source: Source.server));

    final turmasAtivas = turmasSnapshot.docs.where((doc) {
      final status = doc['status'] as String?;
      return status != null && status.toUpperCase() == 'ATIVA';
    }).toList();

    if (turmasAtivas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não há turmas ativas disponíveis nesta academia.'),
            backgroundColor: context.uai.error,
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
            title: Text('Mudar de Turma'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Selecione a nova turma para o aluno:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    ...turmas.map((turma) {
                      final isSelected = selectedTurmaId == turma['id'];
                      final isTurmaAtual = turma['isTurmaAtual'] == true;
                      final temVaga = turma['tem_vaga'] as bool;
                      final capacidadeMaxima = turma['capacidade_maxima'] as int;
                      final totalAlunos = turma['total_alunos'] as int;

                      return Card(
                        margin: EdgeInsets.only(bottom: 8),
                        color: isSelected ? context.uai.error.withOpacity(0.10) :
                        isTurmaAtual ? context.uai.cardAlt :
                        !temVaga ? context.uai.cardAlt : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? context.uai.error :
                            isTurmaAtual ? context.uai.textMuted :
                            !temVaga ? context.uai.textMuted : context.uai.border,
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
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? context.uai.primary :
                                    isTurmaAtual ? context.uai.textSecondary :
                                    !temVaga ? context.uai.textMuted : context.uai.textMuted,
                                  ),
                                ),
                                SizedBox(width: 12),
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
                                                color: isSelected ? context.uai.primary :
                                                isTurmaAtual ? context.uai.textPrimary :
                                                !temVaga ? context.uai.textSecondary : Colors.black,
                                              ),
                                            ),
                                          ),
                                          if (isTurmaAtual)
                                            Container(
                                              margin: EdgeInsets.only(left: 8),
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.uai.border,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'ATUAL',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _onCardMuted(context),
                                                ),
                                              ),
                                            ),
                                          if (!temVaga && !isTurmaAtual)
                                            Container(
                                              margin: EdgeInsets.only(left: 8),
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.uai.error.withOpacity(0.16),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'LOTADA',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.uai.error,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        turma['horario']!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isTurmaAtual ? context.uai.textSecondary :
                                          !temVaga ? context.uai.textMuted : context.uai.textMuted,
                                        ),
                                      ),
                                      Text(
                                        turma['dias']!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isTurmaAtual ? context.uai.textSecondary :
                                          !temVaga ? context.uai.textMuted : context.uai.textMuted,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label: turma['nivel']!,
                                              color: context.uai.info.withOpacity(0.16),
                                              textColor: context.uai.info,
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label: turma['faixa_etaria']!,
                                              color: context.uai.success.withOpacity(0.16),
                                              textColor: context.uai.success,
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label: '$totalAlunos/$capacidadeMaxima alunos',
                                              color: isTurmaAtual ? context.uai.border :
                                              temVaga ? context.uai.warning.withOpacity(0.16) : context.uai.error.withOpacity(0.16),
                                              textColor: isTurmaAtual ? context.uai.textSecondary :
                                              temVaga ? context.uai.warning : context.uai.error,
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
                child: Text('Cancelar'),
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
                          SnackBar(
                            content: Text('Esta turma não tem mais vagas disponíveis.'),
                            backgroundColor: context.uai.error,
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
                        SnackBar(
                          content: Text('Aluno transferido para nova turma com sucesso!'),
                          backgroundColor: context.uai.success,
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
                          backgroundColor: context.uai.error,
                        ),
                      );
                    }
                  }
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Confirmar', style: TextStyle(color: context.uai.card)),
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
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      color: enabled ? color : context.uai.textMuted,
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
        color: context.uai.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
                    color: onPressed != null ? color : context.uai.textMuted,
                    size: 20,
                  ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onPressed != null ? context.uai.textPrimary : context.uai.textMuted,
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



  // ============================================
  // 🚨 CONTATOS DE EMERGÊNCIA - UI PREMIUM
  // ============================================
  String _limparNumeroContato(String? numero) {
    if (numero == null) return '';
    return numero.replaceAll(RegExp(r'[^0-9+]'), '').trim();
  }

  bool _temContatoValido(String? numero) {
    final limpo = _limparNumeroContato(numero);
    return limpo.length >= 8;
  }

  String _formatarTelefoneVisual(String? numero) {
    final limpo = _limparNumeroContato(numero).replaceAll('+55', '').replaceAll('+', '');

    if (limpo.length == 11) {
      return '(${limpo.substring(0, 2)}) ${limpo.substring(2, 7)}-${limpo.substring(7)}';
    }

    if (limpo.length == 10) {
      return '(${limpo.substring(0, 2)}) ${limpo.substring(2, 6)}-${limpo.substring(6)}';
    }

    return numero?.trim().isNotEmpty == true ? numero!.trim() : 'Não cadastrado';
  }

  Future<void> _mostrarOpcoesContatoEmergencia({
    required String nomeAluno,
    required String contatoAluno,
    required String nomeResponsavel,
    required String? contatoResponsavel,
    required String nomeContatoEmergencia,
    required String contatoEmergencia,
  }) async {
    final contatos = <Map<String, dynamic>>[];

    if (_temContatoValido(contatoResponsavel)) {
      contatos.add({
        'titulo': nomeResponsavel,
        'subtitulo': 'Responsável principal',
        'numero': contatoResponsavel!,
        'cor': context.uai.error,
        'icone': Icons.family_restroom_rounded,
        'prioridade': 'PRIORIDADE 1',
      });
    }

    if (_temContatoValido(contatoEmergencia) &&
        _limparNumeroContato(contatoEmergencia) != _limparNumeroContato(contatoResponsavel)) {
      contatos.add({
        'titulo': nomeContatoEmergencia,
        'subtitulo': 'Contato de emergência',
        'numero': contatoEmergencia,
        'cor': context.uai.warning,
        'icone': Icons.emergency_share_rounded,
        'prioridade': 'EMERGÊNCIA',
      });
    }

    if (_temContatoValido(contatoAluno) &&
        _limparNumeroContato(contatoAluno) != _limparNumeroContato(contatoResponsavel) &&
        _limparNumeroContato(contatoAluno) != _limparNumeroContato(contatoEmergencia)) {
      contatos.add({
        'titulo': nomeAluno,
        'subtitulo': 'Contato do aluno',
        'numero': contatoAluno,
        'cor': context.uai.info,
        'icone': Icons.person_rounded,
        'prioridade': 'ALUNO',
      });
    }

    if (contatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nenhum contato válido cadastrado para emergência.'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: EdgeInsets.all(12),
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.uai.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.uai.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.uai.error.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.sos_rounded, color: context.uai.primary, size: 30),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contatos de emergência',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _onCard(context),
                            ),
                          ),
                          Text(
                            nomeAluno,
                            style: TextStyle(fontSize: 13, color: context.uai.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                ...contatos.map((contato) {
                  final color = contato['cor'] as Color;
                  final numero = contato['numero'] as String;

                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: color.withOpacity(0.18)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                              child: Icon(contato['icone'] as IconData, color: _readableOn(color), size: 20),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          contato['titulo'] as String,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: _onCard(context),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          contato['prioridade'] as String,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '${contato['subtitulo']} • ${_formatarTelefoneVisual(numero)}',
                                    style: TextStyle(fontSize: 12, color: context.uai.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _launchPhone(numero);
                                },
                                icon: Icon(Icons.call_rounded, size: 20),
                                label: Text('LIGAR AGORA'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: color,
                                  foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                                  padding: EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            SizedBox(
                              width: 54,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _abrirWhatsApp(numero, mensagem: 'Olá, preciso falar sobre $nomeAluno.');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                                  foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: _buildWhatsAppIcon(enabled: true, color: context.uai.card),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergencyContactsSection({
    required String nomeAluno,
    required String contatoAluno,
    required String nomeResponsavel,
    required String? contatoResponsavel,
    required String nomeContatoEmergencia,
    required String contatoEmergencia,
    required String? turmaId,
  }) {
    final contatoPrincipal = _temContatoValido(contatoResponsavel)
        ? contatoResponsavel!
        : _temContatoValido(contatoEmergencia)
        ? contatoEmergencia
        : contatoAluno;

    final nomePrincipal = _temContatoValido(contatoResponsavel)
        ? nomeResponsavel
        : _temContatoValido(contatoEmergencia)
        ? nomeContatoEmergencia
        : nomeAluno;

    final tipoPrincipal = _temContatoValido(contatoResponsavel)
        ? 'Responsável principal'
        : _temContatoValido(contatoEmergencia)
        ? 'Contato de emergência'
        : 'Aluno';

    final temPrincipal = _temContatoValido(contatoPrincipal);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.13),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: context.uai.card,
            border: Border.all(color: context.uai.error.withOpacity(0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: context.uai.primaryGradient,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.uai.card.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.health_and_safety_rounded, color: _onPrimary(context), size: 28),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emergência e contatos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _onCard(context),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Acesso rápido para ligar ou chamar no WhatsApp',
                            style: TextStyle(fontSize: 12, color: context.uai.card.withOpacity(0.70)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: temPrincipal ? () => _launchPhone(contatoPrincipal) : null,
                        icon: Icon(temPrincipal ? Icons.sos_rounded : Icons.phone_disabled_rounded, size: 26),
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              temPrincipal ? 'LIGAR EMERGÊNCIA AGORA' : 'SEM CONTATO DE EMERGÊNCIA',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            if (temPrincipal)
                              Text(
                                '$nomePrincipal • $tipoPrincipal',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.uai.error,
                          disabledBackgroundColor: context.uai.border,
                          foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                          disabledForegroundColor: context.uai.textSecondary,
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          elevation: temPrincipal ? 3 : 0,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    if (temPrincipal)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.uai.error.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.uai.error.withOpacity(0.16)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.priority_high_rounded, color: context.uai.error, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Contato principal: $nomePrincipal • ${_formatarTelefoneVisual(contatoPrincipal)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.uai.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildContactPersonCard(
                            titulo: 'Responsável',
                            nome: nomeResponsavel,
                            numero: contatoResponsavel,
                            color: context.uai.primaryDark,
                            icon: Icons.family_restroom_rounded,
                            mensagemWhatsApp: 'Olá, preciso falar sobre $nomeAluno.',
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: _buildContactPersonCard(
                            titulo: 'Aluno',
                            nome: nomeAluno,
                            numero: contatoAluno,
                            color: context.uai.info,
                            icon: Icons.person_rounded,
                            mensagemWhatsApp: 'Olá, $nomeAluno. Tudo bem?',
                          ),
                        ),
                      ],
                    ),
                    if (_temContatoValido(contatoEmergencia)) ...[
                      SizedBox(height: 10),
                      _buildContactPersonCard(
                        titulo: 'Contato extra de emergência',
                        nome: nomeContatoEmergencia,
                        numero: contatoEmergencia,
                        color: context.uai.warning,
                        icon: Icons.emergency_share_rounded,
                        fullWidth: true,
                        mensagemWhatsApp: 'Olá, preciso falar sobre $nomeAluno.',
                      ),
                    ],
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: temPrincipal
                                ? () => _mostrarOpcoesContatoEmergencia(
                              nomeAluno: nomeAluno,
                              contatoAluno: contatoAluno,
                              nomeResponsavel: nomeResponsavel,
                              contatoResponsavel: contatoResponsavel,
                              nomeContatoEmergencia: nomeContatoEmergencia,
                              contatoEmergencia: contatoEmergencia,
                            )
                                : null,
                            icon: Icon(Icons.contact_phone_rounded, size: 18),
                            label: Text('Ver opções'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.uai.primary,
                              side: BorderSide(color: context.uai.error.withOpacity(0.28)),
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: turmaId != null && turmaId.isNotEmpty
                                ? _firestore.collection('turmas').doc(turmaId).get()
                                : null,
                            builder: (context, snapshot) {
                              String? whatsappUrl;
                              if (snapshot.hasData && snapshot.data!.exists) {
                                final turmaData = snapshot.data!.data() as Map<String, dynamic>?;
                                whatsappUrl = turmaData?['whatsapp_url'] as String?;
                              }

                              return OutlinedButton.icon(
                                onPressed: whatsappUrl != null && whatsappUrl.isNotEmpty
                                    ? () => _convidarParaGrupo(
                                  context,
                                  whatsappUrl,
                                  contatoAluno,
                                  contatoResponsavel,
                                )
                                    : null,
                                icon: Icon(Icons.group_add_rounded, size: 18),
                                label: Text('Grupo'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: context.uai.warning,
                                  side: BorderSide(color: context.uai.warning.withOpacity(0.28)),
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    _buildAreaAlunoAcessoButton(
                      nomeAluno: nomeAluno,
                      contatoAluno: contatoAluno,
                      contatoResponsavel: contatoResponsavel,
                      nomeResponsavel: nomeResponsavel,
                    ),
                    if (!temPrincipal) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.uai.warning.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.uai.warning.withOpacity(0.28)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: context.uai.warning, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cadastre pelo menos um telefone para emergências.',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildAreaAlunoAcessoButton({
    required String nomeAluno,
    required String contatoAluno,
    required String? contatoResponsavel,
    required String nomeResponsavel,
  }) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _firestore
          .collection('configuracoes_site')
          .doc('area_aluno')
          .get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final visivel = data['visivel_site'] == true;

        if (!visivel) return SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(top: 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _enviarAcessoAreaAlunoWhatsApp(
                nomeAluno: nomeAluno,
                contatoAluno: contatoAluno,
                contatoResponsavel: contatoResponsavel,
                nomeResponsavel: nomeResponsavel,
              ),
              icon: Icon(Icons.school_rounded, size: 18),
              label: Text('Enviar acesso da Área do Aluno'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.uai.associacao,
                side: BorderSide(color: context.uai.associacao.withOpacity(0.35)),
                padding: EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactPersonCard({
    required String titulo,
    required String nome,
    required String? numero,
    required Color color,
    required IconData icon,
    required String mensagemWhatsApp,
    bool fullWidth = false,
  }) {
    final temNumero = _temContatoValido(numero);

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: temNumero ? color.withOpacity(0.07) : context.uai.cardAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: temNumero ? color.withOpacity(0.18) : context.uai.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: temNumero ? color : context.uai.textMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _readableOn(temNumero ? color : context.uai.textMuted), size: 18),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 11,
                        color: temNumero ? color : context.uai.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      nome.trim().isNotEmpty ? nome : titulo,
                      style: TextStyle(
                        fontSize: 13,
                        color: _onCard(context),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            _formatarTelefoneVisual(numero),
            style: TextStyle(
              fontSize: 12,
              color: temNumero ? context.uai.textPrimary : context.uai.textMuted,
              fontWeight: temNumero ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: temNumero ? () => _launchPhone(numero!) : null,
                  icon: Icon(Icons.call_rounded, size: 16),
                  label: Text(fullWidth ? 'Ligar' : 'Ligar', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    disabledBackgroundColor: context.uai.border,
                    foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                    disabledForegroundColor: context.uai.textSecondary,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 40,
                child: ElevatedButton(
                  onPressed: temNumero
                      ? () => _abrirWhatsApp(numero!, mensagem: mensagemWhatsApp)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.uai.success,
                    disabledBackgroundColor: context.uai.border,
                    foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _buildWhatsAppIcon(enabled: temNumero, color: context.uai.card),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getMonitorColor(String monitor) {
    final lowerMonitor = monitor.toLowerCase();
    if (lowerMonitor.contains('azul')) return context.uai.info;
    if (lowerMonitor.contains('roxo') || lowerMonitor.contains('roxa')) return context.uai.associacao;
    if (lowerMonitor.contains('vermelho') || lowerMonitor.contains('vermelha')) return context.uai.error;
    if (lowerMonitor.contains('verde')) return context.uai.success;
    if (lowerMonitor.contains('amarelo') || lowerMonitor.contains('amarela')) return context.uai.warning;
    if (lowerMonitor.contains('branco') || lowerMonitor.contains('branca')) return context.uai.border;
    if (lowerMonitor.contains('marrom')) return context.uai.warning;
    return context.uai.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    if (_carregandoAluno || _carregandoPermissoes || !_permissoesCarregadas) {
      return Scaffold(
        backgroundColor: context.uai.background,
        appBar: AppBar(
          title: Text('Perfil do Aluno'),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: context.uai.error),
              SizedBox(height: 20),
              Text('Carregando informações...'),
            ],
          ),
        ),
      );
    }

    if (_alunoData == null) {
      return Scaffold(
        backgroundColor: context.uai.background,
        appBar: AppBar(
          title: Text('Perfil do Aluno'),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 60, color: context.uai.error),
              SizedBox(height: 20),
              Text('Aluno não encontrado', style: TextStyle(fontSize: 18)),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.primary,
                ),
                child: Text('Voltar', style: TextStyle(color: context.uai.card)),
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
    final nomeResponsavel = data['nome_responsavel']?.toString() ??
        data['responsavel']?.toString() ??
        data['responsavel_nome']?.toString() ??
        'Responsável';
    final contatoEmergencia = data['contato_emergencia']?.toString() ??
        data['telefone_emergencia']?.toString() ??
        data['emergencia_contato']?.toString() ??
        '';
    final nomeContatoEmergencia = data['nome_contato_emergencia']?.toString() ??
        data['responsavel_emergencia']?.toString() ??
        'Contato de emergência';
    final monitor = data['monitor'] as String?;
    final idade = data['idade'] as String?;
    final nome = data['nome'] as String? ?? 'N/A';
    final apelido = data['apelido'] as String?;
    final statusAtividade = data['status_atividade'] as String?;
    final turma = data['turma'] as String?;
    final turmaId = data['turma_id'] as String?;

    final isAtivo = _isAlunoAtivo(statusAtividade);

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text('Perfil do Aluno'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) {
              final List<PopupMenuItem<String>> menuItems = [];

              menuItems.add(
                PopupMenuItem(
                  value: 'editar',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: context.uai.info),
                      SizedBox(width: 8),
                      Text('Editar Perfil'),
                    ],
                  ),
                ),
              );

              // 👇 BOTÃO VER TERMO (sempre aparece)
              menuItems.add(
                PopupMenuItem(
                  value: 'ver_termo',
                  child: Row(
                    children: [
                      Icon(Icons.description, color: context.uai.success),
                      SizedBox(width: 8),
                      Text('Ver Termo'),
                    ],
                  ),
                ),
              );

              if (isAtivo) {
                menuItems.add(
                  PopupMenuItem(
                    value: 'desativar',
                    child: Row(
                      children: [
                        Icon(Icons.pause_circle, color: context.uai.warning),
                        SizedBox(width: 8),
                        Text('Desativar Aluno'),
                      ],
                    ),
                  ),
                );
              } else {
                menuItems.add(
                  PopupMenuItem(
                    value: 'ativar',
                    child: Row(
                      children: [
                        Icon(Icons.play_circle, color: context.uai.success),
                        SizedBox(width: 8),
                        Text('Ativar Aluno'),
                      ],
                    ),
                  ),
                );
              }

              if (isAtivo) {
                menuItems.add(
                  PopupMenuItem(
                    value: 'mudar_turma',
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz, color: context.uai.associacao),
                        SizedBox(width: 8),
                        Text('Mudar de Turma'),
                      ],
                    ),
                  ),
                );
              }

              menuItems.add(
                PopupMenuItem(
                  value: 'historico',
                  child: Row(
                    children: [
                      Icon(Icons.history, color: context.uai.info),
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
            icon: Icon(Icons.more_vert),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cabeçalho do Perfil
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.uai.card,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.uai.textMuted.withOpacity(0.15),
                    blurRadius: 15,
                    offset: Offset(0, 5),
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
                            color: context.uai.border,
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
                                CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.uai.error,
                                ),
                            errorWidget: (context, url, error) =>
                                Icon(Icons.person,
                                    size: 50, color: context.uai.textMuted),
                          )
                              : Container(
                            color: context.uai.cardAlt,
                            child: Icon(Icons.person,
                                size: 50, color: context.uai.textMuted),
                          ),
                        ),
                      ),
                      // Badge de status
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isAtivo ? context.uai.success : context.uai.warning,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _onCard(context),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          isAtivo ? 'ATIVO' : 'INATIVO',
                          style: TextStyle(
                            color: _readableOn(isAtivo ? context.uai.success : context.uai.warning),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 16),

                  // Nome e apelido
                  Column(
                    children: [
                      Text(
                        nome,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _onCard(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (apelido != null && apelido.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '"$apelido"',
                            style: TextStyle(
                              fontSize: 16,
                              color: _onCardMuted(context),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),

                  SizedBox(height: 12),

                  // Informações básicas
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (idade != null && idade.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.cake,
                                size: 16,
                                color: context.uai.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '$idade anos',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _onCardMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (turma != null)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.group,
                                size: 16,
                                color: context.uai.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                turma,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _onCardMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  SizedBox(height: 16),

                  // Monitor (se houver)
                  if (monitor != null && monitor.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getMonitorColor(monitor),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'MONITOR $monitor'.toUpperCase(),
                        style: TextStyle(
                          color: _readableOn(_getMonitorColor(monitor)),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 🚨 SEÇÃO DE EMERGÊNCIA E CONTATOS RÁPIDOS
            _buildEmergencyContactsSection(
              nomeAluno: nome,
              contatoAluno: contatoAluno,
              nomeResponsavel: nomeResponsavel,
              contatoResponsavel: contatoResponsavel,
              nomeContatoEmergencia: nomeContatoEmergencia,
              contatoEmergencia: contatoEmergencia,
              turmaId: turmaId,
            ),

            // 🔥 CARD DE FREQUÊNCIA COM CACHE INTELIGENTE
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CardFrequenciaModerno(
                key: ValueKey(_frequenciaKey),
                alunoId: widget.alunoId,
                filtroTemporal: 'Ano',
                anoSelecionado: '2026',
              ),
            ),

            // Card de Informações Completas
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: CardInformacoesModerno(alunoId: widget.alunoId),
            ),

            SizedBox(height: 12),

            // 🔥 CARD DE EVENTOS PARTICIPADOS
            CardEventosParticipados(
              alunoId: widget.alunoId,
              alunoData: data,
            ),

            SizedBox(height: 20),
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

  CardFrequenciaModerno({
    super.key,
    required this.alunoId,
    this.filtroTemporal,
    this.anoSelecionado,
  });

  @override
  State<CardFrequenciaModerno> createState() => _CardFrequenciaModernoState();
}

class _CardFrequenciaModernoState extends State<CardFrequenciaModerno> {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

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
          SnackBar(
            content: Text('✅ Dados atualizados com sucesso!'),
            backgroundColor: context.uai.success,
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
            backgroundColor: context.uai.error,
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
          .get(GetOptions(source: Source.server));

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
            SnackBar(
              content: Text('⚠️ Usando dados offline'),
              backgroundColor: context.uai.warning,
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
            final umaSemanaAtras = now.subtract(Duration(days: 7));
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

      final snapshot = await query.get(GetOptions(source: Source.server));

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
      backgroundColor: context.uai.border,
      backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
          ? NetworkImage(fotoUrl)
          : null,
      child: fotoUrl == null || fotoUrl.isEmpty
          ? Text(
        _dadosAluno?['nome']?.toString().substring(0, 1).toUpperCase() ?? '?',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: _onCardMuted(context),
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
          padding: EdgeInsets.all(10),
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
        SizedBox(height: 8),
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
          style: TextStyle(
            fontSize: 11,
            color: _onCardMuted(context),
          ),
        ),
      ],
    );
  }

  Widget _buildDiaCardCompacto(String dia, int quantidade) {
    return Container(
      width: 38,
      padding: EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: quantidade > 0 ? context.uai.error.withOpacity(0.10) : context.uai.cardAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: quantidade > 0 ? context.uai.error.withOpacity(0.24) : context.uai.border,
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
              color: quantidade > 0 ? context.uai.primary : context.uai.textMuted,
            ),
          ),
          SizedBox(height: 2),
          Text(
            quantidade.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: quantidade > 0 ? context.uai.primary : context.uai.textMuted,
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
      margin: EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildFiltroChip('Semana', Icons.calendar_view_week),
            SizedBox(width: 8),
            _buildFiltroChip('Mês', Icons.calendar_month),
            SizedBox(width: 8),
            _buildFiltroChip('Ano', Icons.calendar_today),
            SizedBox(width: 8),
            _buildFiltroChip('Total', Icons.history),
          ],
        ),
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
        color: isSelected ? Colors.white : context.uai.textSecondary,
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
      selectedColor: context.uai.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : context.uai.textPrimary,
        fontSize: 12,
      ),
      backgroundColor: context.uai.cardAlt,
      elevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Future<void> _mostrarSeletorAno() async {
    final anoAtual = DateTime.now().year;
    final anos = List.generate(10, (index) => (anoAtual - index).toString());

    final anoSelecionado = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Selecione o ano'),
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
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: context.uai.error)),
      );
    }

    if (_frequencia == null || _dadosAluno == null) {
      return Container(
        height: 200,
        padding: EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: context.uai.error),
              SizedBox(height: 12),
              Text(
                'Erro ao carregar dados de frequência',
                style: TextStyle(color: context.uai.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _forcarAtualizacao,
                icon: Icon(Icons.refresh),
                label: Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.primary,
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
        margin: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho com nome, foto e indicador offline
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: frequencia.corIndicador.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildAlunoAvatar(),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    nome,
                                    style: TextStyle(
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
                                    margin: EdgeInsets.only(right: 8),
                                    padding: EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: context.uai.warning.withOpacity(0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.wifi_off,
                                      size: 16,
                                      color: context.uai.warning,
                                    ),
                                  ),
                                // 🔥 BOTÃO DE ATUALIZAÇÃO
                                if (!_isAtualizando)
                                  IconButton(
                                    icon: Icon(Icons.refresh, size: 20),
                                    onPressed: _forcarAtualizacao,
                                    color: context.uai.primary,
                                    tooltip: 'Atualizar dados',
                                  ),
                                if (_isAtualizando)
                                  Container(
                                    width: 30,
                                    height: 30,
                                    padding: EdgeInsets.all(4),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: context.uai.error,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
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
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _getTituloFiltro(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _onCardMuted(context),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (_filtroAtual != null) ...[
                              SizedBox(height: 2),
                              Text(
                                _getSubtituloFiltro(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.uai.textMuted,
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
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  // Métricas principais
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricCard(
                        value: '$_totalPresencas',
                        label: 'Presenças',
                        color: context.uai.info,
                        icon: Icons.event_available,
                      ),
                      _buildMetricCard(
                        value: '$_totalAusencias',
                        label: 'Faltas',
                        color: context.uai.error,
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

                  SizedBox(height: 20),

                  // Última presença
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.uai.cardAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.uai.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: frequencia.corIndicador,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Última presença',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _onCardMuted(context),
                                ),
                              ),
                              Text(
                                _formatarData(_ultimaPresenca),
                                style: TextStyle(
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

                  SizedBox(height: 20),

                  // Dias da semana
                  Text(
                    'Presenças por dia',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12),

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
                    SizedBox(height: 20),

                    // Lista dos últimos logs
                    Container(
                      constraints: BoxConstraints(maxHeight: 200),
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
                              color: presente ? context.uai.success : context.uai.error,
                              size: 18,
                            ),
                            title: Text(
                              _formatarData(data),
                              style: TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              log['tipo_aula']?.toString() ?? 'N/A',
                              style: TextStyle(
                                fontSize: 11,
                                color: _onCardMuted(context),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    SizedBox(height: 20),

                    // Botão de ver histórico
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: Icon(Icons.history, size: 18),
                      label: Text('FECHAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                        minimumSize: Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: 8),

                  // Botão de expandir/recolher
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: context.uai.primary,
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

  CardEventosParticipados({
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
          .get(GetOptions(source: Source.server));

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
              .get(GetOptions(source: Source.server));

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
            .get(GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('graduacoes')
            .doc(graduacaoId)
            .get(GetOptions(source: Source.server));
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
        if (hexColor == null || hexColor.length < 7) return context.uai.textMuted;
        try {
          return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
        } catch (e) {
          return context.uai.textMuted;
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
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                context.uai.warning.withOpacity(0.10),
                context.uai.cardAlt,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.uai.warning.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.emoji_events,
                    color: context.uai.warning,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Eventos Participados',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _readableOn(context.uai.card),
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
                          color: _erro != null
                              ? context.uai.error
                              : _readableOn(context.uai.card).withOpacity(0.68),
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
                            placeholderBuilder: (context) => SizedBox(),
                          ),
                        );
                      }
                      return SizedBox(
                        width: 50,
                        height: 50,
                        child: Icon(Icons.emoji_events, color: context.uai.warning),
                      );
                    },
                  ),
              ],
            ),
          ),

          // Conteúdo
          if (_isLoading)
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: context.uai.warning)),
            )
          else if (_erro != null)
            Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: context.uai.error,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Erro ao carregar eventos',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.uai.primaryDark,
                    ),
                  ),
                  Text(
                    _erro!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _onCardMuted(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_participacoes.isEmpty)
              Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_busy,
                      size: 48,
                      color: context.uai.border,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Nenhum evento participado',
                      style: TextStyle(
                        fontSize: 14,
                        color: _onCardMuted(context),
                      ),
                    ),
                    Text(
                      'Este aluno ainda não participou de eventos',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.uai.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: EdgeInsets.all(16),
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
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.uai.cardAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.uai.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: context.uai.warning.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.event,
                                  color: context.uai.warning,
                                  size: 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nomeEvento,
                                      style: TextStyle(
                                        color: _readableOn(context.uai.cardAlt),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today, size: 10, color: context.uai.textSecondary),
                                        SizedBox(width: 4),
                                        Text(
                                          dataEvento,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _onCardMuted(context),
                                          ),
                                        ),
                                        if (tipoEvento.isNotEmpty) ...[
                                          SizedBox(width: 8),
                                          Container(
                                            width: 4,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: context.uai.textMuted,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              tipoEvento,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: _onCardMuted(context),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (graduacaoEvento != null && graduacaoEvento.isNotEmpty) ...[
                                      SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.emoji_events, size: 10, color: context.uai.warning),
                                          SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              graduacaoEvento,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: context.uai.warning,
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
                                    color: context.uai.success,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _abrirLinkCertificado(certificado);
                                  },
                                  tooltip: 'Ver certificado',
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    if (_participacoes.length > 3)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _expanded = !_expanded;
                            });
                          },
                          icon: Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            color: context.uai.warning,
                          ),
                          label: Text(
                            _expanded ? 'Ver menos' : 'Ver todos (${_participacoes.length})',
                            style: TextStyle(
                              color: context.uai.warning,
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

  CardInformacoesModerno({super.key, required this.alunoId});

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
            GetOptions(source: Source.cache)
        );
      } catch (e) {
        alunoDoc = await _firestore.collection('alunos').doc(widget.alunoId).get(
            GetOptions(source: Source.server)
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
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Icon(
              icon,
              size: 16,
              color: iconColor ?? context.uai.primary,
            ),
          SizedBox(width: icon != null ? 12 : 0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: _onCardMuted(context),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _readableOn(context.uai.card),
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
        margin: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(color: context.uai.primary)),
      );
    }

    if (_dadosAluno == null) {
      return SizedBox.shrink();
    }

    final dados = _dadosAluno!;

    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                context.uai.info.withOpacity(0.10),
                context.uai.cardAlt,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info,
                  color: context.uai.info,
                  size: 24,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Informações do Aluno',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _readableOn(context.uai.card),
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
                    color: context.uai.info,
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Conteúdo
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoItem(
                  label: 'Nome completo',
                  value: dados['nome']?.toString() ?? 'Não informado',
                  icon: Icons.person,
                  iconColor: context.uai.primary,
                ),

                _buildInfoItem(
                  label: 'Apelido',
                  value: dados['apelido']?.toString() ?? 'Sem apelido',
                  icon: Icons.emoji_emotions,
                  iconColor: context.uai.warning,
                ),

                _buildInfoItem(
                  label: 'Data de nascimento',
                  value: _formatarData(dados['data_nascimento']),
                  icon: Icons.cake,
                  iconColor: context.uai.error,
                ),

                if (_expanded) ...[
                  Divider(color: context.uai.border),
                  SizedBox(height: 12),

                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Contato',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _readableOn(context.uai.card),
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Telefone',
                    value: dados['contato_aluno']?.toString() ?? 'Não informado',
                    icon: Icons.phone,
                    iconColor: context.uai.success,
                  ),

                  _buildInfoItem(
                    label: 'Endereço',
                    value: dados['endereco']?.toString() ?? 'Não informado',
                    icon: Icons.home,
                    iconColor: context.uai.info,
                  ),

                  SizedBox(height: 12),

                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Responsável',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _readableOn(context.uai.card),
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Nome do responsável',
                    value: dados['nome_responsavel']?.toString() ?? 'Não informado',
                    icon: Icons.person_outline,
                    iconColor: context.uai.associacao,
                  ),

                  _buildInfoItem(
                    label: 'Contato do responsável',
                    value: dados['contato_responsavel']?.toString() ?? 'Não informado',
                    icon: Icons.phone_android,
                    iconColor: context.uai.inscricoes,
                  ),

                  SizedBox(height: 12),

                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Cadastro',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _readableOn(context.uai.card),
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Data do cadastro',
                    value: _formatarData(dados['data_do_cadastro']),
                    icon: Icons.calendar_today,
                    iconColor: context.uai.textMuted,
                  ),

                  _buildInfoItem(
                    label: 'Cadastrado por',
                    value: dados['cadastro_realizado_por']?.toString() ?? 'Sistema',
                    icon: Icons.person_add,
                    iconColor: context.uai.textMuted,
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
