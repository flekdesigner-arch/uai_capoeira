import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:confetti/confetti.dart'; // 👈 NOVO PACOTE
import 'aluno_detalhe_screen.dart';
import 'package:uai_capoeira/services/mensagem_aniversario_service.dart';
import 'package:uai_capoeira/models/mensagem_aniversario_model.dart';
import 'arte_aniversario_screen.dart';

class AniversariantesPage extends StatefulWidget {
  const AniversariantesPage({super.key});

  @override
  State<AniversariantesPage> createState() => _AniversariantesPageState();
}

class _AniversariantesPageState extends State<AniversariantesPage> with SingleTickerProviderStateMixin {
  int? _selectedMonth;
  late DateTime _today;
  late DateTime _nextWeek;

  // 🎉 CONTROLE DE CONFETES
  late ConfettiController _confettiController;
  Timer? _confettiTimer;
  bool _mostrarConfetes = false;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _nextWeek = _today.add(const Duration(days: 7));

    // 🎉 INICIALIZA CONTROLADOR DE CONFETES
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _confettiTimer?.cancel();
    super.dispose();
  }

  // 🎉 MÉTODO PARA EXPLODIR CONFETES
  void _explodirConfetes() {
    setState(() {
      _mostrarConfetes = true;
    });

    // Inicia a animação
    _confettiController.play();

    // Para os confetes após 3 segundos
    _confettiTimer?.cancel();
    _confettiTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _mostrarConfetes = false;
        });
      }
    });
  }

  // ==================== MÉTODOS AUXILIARES PARA DATAS ====================

  /// 🔥 CORREÇÃO 1: Normalizar data (remover horas, minutos, segundos)
  DateTime _normalizarData(DateTime data) {
    return DateTime(data.year, data.month, data.day);
  }

  /// 🔥 CORREÇÃO 2: Verificar se é aniversário hoje (ignorando fuso horário)
  bool _isAniversarioHoje(DateTime dataNascimento) {
    final hoje = DateTime.now();

    // Normalizar ambas as datas para ignorar horas
    final dataNascimentoNormalizada = DateTime(
      dataNascimento.year,
      dataNascimento.month,
      dataNascimento.day,
    );

    final hojeNormalizada = DateTime(
      hoje.year,
      hoje.month,
      hoje.day,
    );

    // Comparar apenas mês e dia
    return dataNascimentoNormalizada.month == hojeNormalizada.month &&
        dataNascimentoNormalizada.day == hojeNormalizada.day;
  }

  /// 🔥 CORREÇÃO 3: Calcular idade corretamente considerando data normalizada
  int _calcularIdade(DateTime dataNascimento) {
    final hoje = DateTime.now();
    final hojeNormalizada = DateTime(hoje.year, hoje.month, hoje.day);
    final nascimentoNormalizada = DateTime(
      dataNascimento.year,
      dataNascimento.month,
      dataNascimento.day,
    );

    int idade = hojeNormalizada.year - nascimentoNormalizada.year;

    // Ajustar se ainda não fez aniversário esse ano
    if (hojeNormalizada.month < nascimentoNormalizada.month ||
        (hojeNormalizada.month == nascimentoNormalizada.month &&
            hojeNormalizada.day < nascimentoNormalizada.day)) {
      idade--;
    }

    return idade;
  }

  /// 🔥 CORREÇÃO 4: Calcular dias até o próximo aniversário
  int _calcularDiasAteAniversario(DateTime dataNascimento) {
    final hoje = DateTime.now();
    final hojeNormalizada = DateTime(hoje.year, hoje.month, hoje.day);

    // Próximo aniversário no ano atual
    DateTime proximoAniversario = DateTime(
      hoje.year,
      dataNascimento.month,
      dataNascimento.day,
    );

    // Se já passou esse ano, considerar ano que vem
    if (proximoAniversario.isBefore(hojeNormalizada) ||
        _isAniversarioHoje(dataNascimento)) {
      proximoAniversario = DateTime(
        hoje.year + 1,
        dataNascimento.month,
        dataNascimento.day,
      );
    }

    return proximoAniversario.difference(hojeNormalizada).inDays;
  }

  // ==================== STREAMS E FILTROS ====================

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _getAlunosAtivosStream() {
    return FirebaseFirestore.instance
        .collection('alunos')
        .where('status_atividade', isEqualTo: 'ATIVO(A)')
        .where('data_nascimento', isNotEqualTo: null)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  /// 🔥 CORREÇÃO 5: Filtrar aniversariantes de hoje (CORRIGIDO)
  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _filterTodayBirthdays(List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos) {
    return alunos.where((doc) {
      final birthData = doc.data();
      if (birthData['data_nascimento'] == null) return false;

      final birthDate = (birthData['data_nascimento'] as Timestamp).toDate();
      return _isAniversarioHoje(birthDate);
    }).toList();
  }

  /// 🔥 CORREÇÃO 6: Filtrar próximos aniversários (7 dias)
  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _filterWeekBirthdays(List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos) {
    final hoje = DateTime.now();
    final hojeNormalizada = DateTime(hoje.year, hoje.month, hoje.day);

    return alunos.where((doc) {
      final birthData = doc.data();
      if (birthData['data_nascimento'] == null) return false;

      final birthDate = (birthData['data_nascimento'] as Timestamp).toDate();

      // Ignorar aniversariantes de hoje
      if (_isAniversarioHoje(birthDate)) return false;

      // Calcular dias até o próximo aniversário
      final diasAteAniversario = _calcularDiasAteAniversario(birthDate);

      return diasAteAniversario > 0 && diasAteAniversario <= 7;
    }).toList()
      ..sort((a, b) {
        final dateA = (a.data()['data_nascimento'] as Timestamp).toDate();
        final dateB = (b.data()['data_nascimento'] as Timestamp).toDate();

        final diasA = _calcularDiasAteAniversario(dateA);
        final diasB = _calcularDiasAteAniversario(dateB);

        return diasA.compareTo(diasB);
      });
  }

  /// Filtrar por mês
  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _filterMonthBirthdays(List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos, int month) {
    return alunos.where((doc) {
      final birthData = doc.data();
      if (birthData['data_nascimento'] == null) return false;
      final birthDate = (birthData['data_nascimento'] as Timestamp).toDate();
      return birthDate.month == month;
    }).toList()
      ..sort((a, b) {
        final dateA = (a.data()['data_nascimento'] as Timestamp).toDate();
        final dateB = (b.data()['data_nascimento'] as Timestamp).toDate();
        return dateA.day.compareTo(dateB.day);
      });
  }

  // ==================== MÉTODOS DE PERMISSÃO ====================

  /// 🔥 CORREÇÃO 7: Método corrigido - AGORA SÓ ESPERA 2 PARÂMETROS
  Future<void> _verificarPermissaoEAbrirPerfil(BuildContext context, String alunoId) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _mostrarSnackBarSemPermissao(context, 'Usuário não autenticado');
      return;
    }

    try {
      // Verifica permissão no Firestore
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser.uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      final permissoes = doc.data() ?? {};
      final podeVisualizarAlunos = permissoes['pode_visualizar_alunos'] ?? false;

      // Verifica também se é admin pelo peso_permissao
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser.uid)
          .get();

      final pesoPermissao = userDoc.data()?['peso_permissao'] as int? ?? 0;
      final isAdmin = pesoPermissao >= 90;

      if (!podeVisualizarAlunos && !isAdmin) {
        _mostrarDialogoSemPermissao(context, 'visualizar alunos');
        return;
      }

      // Se tiver permissão, abre o perfil
      if (context.mounted) {
        print('🎯 Abrindo perfil do aluno: $alunoId');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlunoDetalheScreen(
              alunoId: alunoId,
            ),
          ),
        );
      }
    } catch (e) {
      print('Erro ao verificar permissão: $e');
      _mostrarSnackBarSemPermissao(context, 'Erro ao verificar permissão');
    }
  }

  void _mostrarDialogoSemPermissao(BuildContext context, String acao) {
    showDialog(
      context: context,
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

  void _mostrarSnackBarSemPermissao(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== DIALOG DE ANIVERSÁRIO ====================

  void _mostrarDialogAniversario(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final aluno = doc.data();
    final alunoId = doc.id;
    final nome = aluno['nome'] ?? 'Aniversariante';
    final fotoUrl = aluno['foto_perfil_aluno'] as String?;
    final birthDate = (aluno['data_nascimento'] as Timestamp).toDate();
    final idade = _calcularIdade(birthDate);

    // 🎉 EXPLODE CONFETES QUANDO ABRE O DIALOG
    _explodirConfetes();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => Stack(
        children: [
          // 🎉 CONFETES POR CIMA DE TUDO
          if (_mostrarConfetes)
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive, // Explode em todas direções
              shouldLoop: false,
              colors: const [
                Colors.red,
                Colors.blue,
                Colors.green,
                Colors.yellow,
                Colors.purple,
                Colors.orange,
                Colors.pink,
              ], // Cores variadas
              numberOfParticles: 50, // Quantidade de partículas
              gravity: 0.1, // Queda suave
              emissionFrequency: 0.05,
              minimumSize: const Size(10, 10),
              maximumSize: const Size(20, 20),
              particleDrag: 0.05,
            ),
          // Dialog normal
          Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 8,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.red.shade50,
                    Colors.white,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cabeçalho comemorativo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.red.shade900,
                          Colors.red.shade700,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (index) =>
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  Icons.star,
                                  color: Colors.amber.shade300,
                                  size: 20 + index * 4,
                                ),
                              ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '🎉 FELIZ ANIVERSÁRIO! 🎉',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$idade anos',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Corpo do dialog
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Foto do aluno
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.red.shade800,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.shade200,
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: fotoUrl != null && fotoUrl.isNotEmpty
                                ? CachedNetworkImage(
                              imageUrl: fotoUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade200,
                                child: Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            )
                                : Container(
                              color: Colors.grey.shade200,
                              child: Icon(
                                Icons.person,
                                size: 50,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Nome do aluno
                        Text(
                          nome,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Hoje é um dia especial! 🎂',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 24),

                        // Botões
                        Row(
                          children: [
                            // Botão Ver Perfil
                            Expanded(
                              child: _buildDialogButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  Future.delayed(Duration.zero, () {
                                    if (context.mounted) {
                                      _verificarPermissaoEAbrirPerfil(context, alunoId);
                                    }
                                  });
                                },
                                icon: Icons.person,
                                label: 'VER PERFIL',
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Botão Criar Arte
                            Expanded(
                              child: _buildDialogButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  Future.delayed(Duration.zero, () {
                                    if (context.mounted) {
                                      _abrirArteAniversario(context, aluno, alunoId);
                                    }
                                  });
                                },
                                icon: Icons.brush,
                                label: 'CRIAR ARTE',
                                color: Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Botão Fechar
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade600,
                          ),
                          child: const Text('FECHAR'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget auxiliar para botões do dialog
  Widget _buildDialogButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color,
            color.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== MÉTODO DE ARTE ====================

  void _abrirArteAniversario(BuildContext context, Map<String, dynamic> aluno, String alunoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArteAniversarioScreen(
          alunoId: alunoId,
          nomeAluno: aluno['nome'] ?? 'Aluno',
          fotoUrl: aluno['foto_perfil_aluno'],
        ),
      ),
    );
  }

  // ==================== BUILD PRINCIPAL ====================

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedMonth != null) {
          setState(() => _selectedMonth = null);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: _selectedMonth != null
            ? AppBar(
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selectedMonth = null),
          ),
        )
            : null,
        body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: _getAlunosAtivosStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoading();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState();
            }

            final alunos = snapshot.data!;

            if (_selectedMonth != null) {
              final monthlyBirthdays = _filterMonthBirthdays(alunos, _selectedMonth!);
              return _buildMonthView(monthlyBirthdays, _selectedMonth!);
            }

            return _buildMainView(alunos);
          },
        ),
      ),
    );
  }

  Widget _buildMainView(List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos) {
    final todayBirthdays = _filterTodayBirthdays(alunos);
    final weeklyBirthdays = _filterWeekBirthdays(alunos);

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _today = DateTime.now();
          _nextWeek = _today.add(const Duration(days: 7));
        });
      },
      child: CustomScrollView(
        slivers: [
          // Cabeçalho
          SliverAppBar(
            backgroundColor: Colors.red.shade900,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            pinned: true,
            floating: true,
            expandedHeight: 100,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cake, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Aniversariantes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.shade900,
                      Colors.red.shade700,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Seção: Aniversariantes de Hoje
          if (todayBirthdays.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildBirthdaySection(
                title: '🎂 Aniversariantes de Hoje',
                count: todayBirthdays.length,
                icon: Icons.celebration,
                isToday: true,
              ),
            ),
          if (todayBirthdays.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final doc = todayBirthdays[index];
                  final birthDate = (doc.data()['data_nascimento'] as Timestamp).toDate();
                  return _buildBirthdayCard(doc, birthDate, isHoje: true);
                },
                childCount: todayBirthdays.length,
              ),
            ),

          // Seção: Próximos Aniversários
          if (weeklyBirthdays.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildBirthdaySection(
                title: '📅 Próximos Aniversários',
                count: weeklyBirthdays.length,
                icon: Icons.upcoming,
                isToday: false,
              ),
            ),
          if (weeklyBirthdays.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final doc = weeklyBirthdays[index];
                  final birthDate = (doc.data()['data_nascimento'] as Timestamp).toDate();
                  return _buildBirthdayCard(doc, birthDate, isHoje: false);
                },
                childCount: weeklyBirthdays.length,
              ),
            ),

          // Seção: Buscar por Mês
          SliverToBoxAdapter(
            child: _buildMonthGridSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthView(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> monthlyBirthdays,
      int month,
      ) {
    return Column(
      children: [
        // Faixinha com nome do mês
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _getMonthName(month),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${monthlyBirthdays.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Lista de aniversariantes
        Expanded(
          child: monthlyBirthdays.isEmpty
              ? _buildEmptyMonthState(month)
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: monthlyBirthdays.length,
            itemBuilder: (context, index) {
              final doc = monthlyBirthdays[index];
              final birthDate = (doc.data()['data_nascimento'] as Timestamp).toDate();
              return _buildBirthdayCard(doc, birthDate, isMonthView: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBirthdaySection({
    required String title,
    required int count,
    required IconData icon,
    required bool isToday,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isToday ? Colors.red.shade100 : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isToday ? Colors.red.shade800 : Colors.orange.shade800,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isToday ? Colors.red.shade800 : Colors.black87,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isToday ? Colors.red.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isToday ? Colors.red.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isToday ? Colors.red.shade800 : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🔥 CORREÇÃO 9: Card com verificação correta de aniversário
  Widget _buildBirthdayCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      DateTime birthDate, {
        bool isMonthView = false,
        bool isHoje = false,
      }) {
    final aluno = doc.data();
    final alunoId = doc.id;
    final idade = _calcularIdade(birthDate);
    final diasAteAniversario = _calcularDiasAteAniversario(birthDate);

    // 🔥 DEBUG para verificar datas
    debugPrint('''
      📅 Verificando ${aluno['nome']}:
        Data nascimento (Firestore): $birthDate
        Data hoje: ${DateTime.now()}
        Data hoje normalizada: ${_normalizarData(DateTime.now())}
        Data nascimento normalizada: ${_normalizarData(birthDate)}
        É aniversário hoje? ${_isAniversarioHoje(birthDate)}
        Idade: $idade
        Dias até aniversário: $diasAteAniversario
    ''');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isHoje ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: isHoje ? Border.all(color: Colors.red.shade300, width: 2) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (isHoje) {
              // Se for hoje, mostra diálogo especial com CONFETES!
              _mostrarDialogAniversario(context, doc);
            } else {
              // 🔥 CORREÇÃO 10: Chamada corrigida - sem o nome
              _verificarPermissaoEAbrirPerfil(context, alunoId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Foto do aluno
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isHoje ? Colors.red.shade500 : Colors.grey.shade300,
                      width: isHoje ? 3 : 2,
                    ),
                  ),
                  child: ClipOval(
                    child: aluno['foto_perfil_aluno'] != null
                        ? CachedNetworkImage(
                      imageUrl: aluno['foto_perfil_aluno'],
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade100,
                        child: Icon(
                          Icons.person,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade100,
                        child: const Icon(
                          Icons.error,
                          color: Colors.red,
                        ),
                      ),
                    )
                        : Container(
                      color: Colors.grey.shade100,
                      child: Icon(
                        Icons.person,
                        color: Colors.grey.shade400,
                        size: 30,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Informações do aluno
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        aluno['nome'] ?? 'Nome não informado',
                        style: TextStyle(
                          fontWeight: isHoje ? FontWeight.bold : FontWeight.w600,
                          fontSize: 16,
                          color: isHoje ? Colors.red.shade900 : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 4),

                      Text(
                        DateFormat('dd/MM/yyyy').format(birthDate),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          // Idade
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$idade ano${idade != 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          // Dias restantes (se não for hoje)
                          if (!isHoje && diasAteAniversario > 0 && diasAteAniversario <= 30)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Faltam $diasAteAniversario dia${diasAteAniversario != 1 ? 's' : ''}',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Ícone indicador
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isHoje ? Colors.red.shade100 : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isHoje ? Icons.cake : Icons.chevron_right,
                    color: isHoje ? Colors.red.shade800 : Colors.grey.shade400,
                    size: isHoje ? 28 : 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthGridSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 16),
            child: Text(
              "📆 Escolha um mês",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              return _buildMonthCard(month);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCard(int month) {
    final isCurrentMonth = month == DateTime.now().month;

    return Material(
      borderRadius: BorderRadius.circular(12),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedMonth = month),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isCurrentMonth
                  ? [Colors.red.shade800, Colors.red.shade600]
                  : [Colors.red.shade700, Colors.red.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade300.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _getMonthAbbreviation(month).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  month.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyMonthState(int month) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cake_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum aniversariante em ${_getMonthName(month)}',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Não há alunos ativos que façam aniversário neste mês',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => setState(() => _selectedMonth = null),
            child: Text(
              'Voltar',
              style: TextStyle(
                color: Colors.red.shade800,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Colors.red.shade800,
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          const Text(
            'Carregando...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Título centralizado
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.red.shade900,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cake, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Aniversariantes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.celebration_outlined,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Nenhum aniversariante',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Não há alunos ativos com aniversário próximo',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getMonthName(int month) {
    final date = DateTime(2024, month);
    final name = DateFormat.MMMM('pt_BR').format(date);
    return name.substring(0, 1).toUpperCase() + name.substring(1);
  }

  String _getMonthAbbreviation(int month) {
    final date = DateTime(2024, month);
    final name = DateFormat.MMM('pt_BR').format(date);
    return name.substring(0, 1).toUpperCase() + name.substring(1);
  }
}