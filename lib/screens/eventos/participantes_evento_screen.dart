import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/evento_model.dart';
import '../../services/participacao_service.dart';
import '../../services/permissao_service.dart';
import '../../services/graduacao_service.dart';
import '../../services/certificado_service.dart';
import '../../models/participacao_model.dart';
import 'detalhe_participacao_screen.dart';
import 'adicionar_participante_modal.dart';
import 'selecionar_participantes_csv_screen.dart';

class ParticipantesEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;
  final EventoModel? evento;

  const ParticipantesEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
    this.evento,
  });

  @override
  State<ParticipantesEventoScreen> createState() => _ParticipantesEventoScreenState();
}

class _ParticipantesEventoScreenState extends State<ParticipantesEventoScreen> {
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final PermissaoService _permissaoService = PermissaoService();
  final GraduacaoService _graduacaoService = GraduacaoService();
  final CertificadoService _certificadoService = CertificadoService();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _alunosDisponiveis = [];
  List<String> _alunosParticipantesIds = [];
  bool _isLoadingAlunos = false;
  EventoModel? _eventoCarregado;

  // Controles de UI
  bool _isGridView = true;
  String _filtroStatus = 'todos';
  bool _isLoadingCertificados = false;

  // Dados do dashboard (só para modo grade)
  double _totalArrecadado = 0;
  double _totalInscricoes = 0;
  int _totalParticipantes = 0;
  int _participantesPagos = 0;
  Map<String, int> _camisasPorTamanho = {};

  // Controle para evitar loop
  int _ultimoTotalParticipantes = -1;

  // Cache para dados dos alunos
  final Map<String, Map<String, dynamic>> _cacheAlunos = {};

  // Permissões
  bool _podeAdicionar = false;
  bool _podeRemover = false;
  bool _podeMarcarPresenca = false;
  bool _podeGerarCertificados = false;

  bool get _isBatizado {
    if (widget.evento != null) {
      final String tipo = widget.evento!.tipo.toUpperCase();
      return tipo.contains('BATIZADO');
    }
    if (_eventoCarregado != null) {
      final String tipo = _eventoCarregado!.tipo.toUpperCase();
      return tipo.contains('BATIZADO');
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    if (widget.evento == null) {
      _buscarEventoDoFirestore();
    }

    _carregarParticipantesExistentes().then((_) {
      _carregarAlunos();
    });

    _verificarPermissoes();
  }

  Future<void> _buscarEventoDoFirestore() async {
    try {
      debugPrint('🔍 Buscando evento do Firestore: ${widget.eventoId}');
      final doc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      if (doc.exists) {
        final evento = EventoModel.fromFirestore(doc);
        setState(() {
          _eventoCarregado = evento;
        });
        debugPrint('✅ Evento carregado: ${evento.nome} - Tipo: ${evento.tipo}');
      }
    } catch (e) {
      debugPrint('❌ Erro ao buscar evento: $e');
    }
  }

  Future<void> _verificarPermissoes() async {
    debugPrint('🔍 Verificando permissões...');

    final permissoes = await _permissaoService.getTodasPermissoes();

    _podeAdicionar = permissoes['pode_adcionar_aluno_a_eventos'] ?? false;
    _podeRemover = permissoes['pode_remover_alunos_de_eventos'] ?? false;
    _podeMarcarPresenca = permissoes['pode_gerenciar_participantes'] ?? false;
    _podeGerarCertificados = permissoes['pode_gerar_certificados'] ?? false;

    debugPrint('📊 Permissões carregadas: $permissoes');
    debugPrint('   - pode_remover_alunos_de_eventos: $_podeRemover');

    if (mounted) setState(() {});
  }

  Future<void> _carregarParticipantesExistentes() async {
    try {
      final participantes = await _participacaoService.listarParticipantesEmAndamento(widget.eventoId);
      setState(() {
        _alunosParticipantesIds = participantes.map((p) => p['aluno_id'] as String).toList();
      });
      debugPrint('👥 Participantes existentes: ${_alunosParticipantesIds.length}');
    } catch (e) {
      debugPrint('Erro ao carregar participantes existentes: $e');
    }
  }

  // 🔥 NOVO MÉTODO: Buscar dados atualizados do aluno com cache
  Future<Map<String, dynamic>> _buscarDadosAluno(String alunoId) async {
    // Verifica se já está no cache
    if (_cacheAlunos.containsKey(alunoId)) {
      return _cacheAlunos[alunoId]!;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('alunos')
          .doc(alunoId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final dadosAluno = {
          'nome': data['nome'] ?? '',
          'foto': data['foto_perfil_aluno'] as String?,
          'graduacao': data['graduacao_atual'] ?? '',
          'turma': data['turma'] as String?,
          'data_nascimento': data['data_nascimento'],
        };

        // Armazena no cache
        _cacheAlunos[alunoId] = dadosAluno;
        return dadosAluno;
      }
    } catch (e) {
      debugPrint('Erro ao buscar dados do aluno $alunoId: $e');
    }

    return {
      'nome': '',
      'foto': null,
      'graduacao': '',
      'turma': null,
      'data_nascimento': null,
    };
  }

  void _calcularEstatisticas(List<ParticipacaoModel> participantes) {
    if (_ultimoTotalParticipantes == participantes.length) {
      return;
    }

    double arrecadado = 0;
    double inscricoes = 0;
    int pagos = 0;
    Map<String, int> camisasPorTamanho = {};

    for (var p in participantes) {
      arrecadado += p.totalPago;
      inscricoes += p.valorTotal;

      if (p.estaQuitado) {
        pagos++;
      }

      if (p.tamanhoCamisa != null && p.tamanhoCamisa!.isNotEmpty) {
        camisasPorTamanho[p.tamanhoCamisa!] = (camisasPorTamanho[p.tamanhoCamisa!] ?? 0) + 1;
      }
    }

    setState(() {
      _totalArrecadado = arrecadado;
      _totalInscricoes = inscricoes;
      _totalParticipantes = participantes.length;
      _participantesPagos = pagos;
      _camisasPorTamanho = Map.from(camisasPorTamanho);
      _ultimoTotalParticipantes = participantes.length;
    });
  }

  Widget _buildDashboard() {
    final saldoDevedor = _totalInscricoes - _totalArrecadado;
    final percentualPago = _totalParticipantes > 0
        ? (_participantesPagos / _totalParticipantes * 100).toStringAsFixed(1)
        : '0';
    final evento = widget.evento ?? _eventoCarregado;
    final temCamisa = evento?.temCamisa ?? false;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.red.shade900,
            Colors.red.shade700,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade200,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDashboardItem(
                  icon: Icons.people,
                  value: '$_totalParticipantes',
                  label: 'Participantes',
                  color: Colors.white,
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildDashboardItem(
                  icon: Icons.paid,
                  value: '$_participantesPagos',
                  label: 'Pagos',
                  color: Colors.white,
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildDashboardItem(
                  icon: Icons.percent,
                  value: '$percentualPago%',
                  label: 'Taxa',
                  color: Colors.white,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.3), height: 1),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildDashboardItem(
                  icon: Icons.attach_money,
                  value: 'R\$ ${_totalArrecadado.toStringAsFixed(2)}',
                  label: 'Arrecadado',
                  color: Colors.white,
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildDashboardItem(
                  icon: Icons.warning,
                  value: 'R\$ ${saldoDevedor.toStringAsFixed(2)}',
                  label: 'A Receber',
                  color: Colors.white,
                ),
              ),
            ],
          ),

          if (temCamisa && _camisasPorTamanho.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: Colors.white.withOpacity(0.3), height: 1),
            const SizedBox(height: 12),

            Row(
              children: [
                Icon(Icons.shopping_bag, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Camisas:',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _camisasPorTamanho.entries.map((entry) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDashboardItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color.withOpacity(0.9), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Future<void> _carregarAlunos() async {
    setState(() => _isLoadingAlunos = true);
    try {
      final todasGraduacoes = await _graduacaoService.buscarTodasGraduacoes();
      final Map<String, Map<String, dynamic>> mapaGraduacoes = {};
      for (var grad in todasGraduacoes) {
        mapaGraduacoes[grad['id']] = grad;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final alunosFiltrados = snapshot.docs.where((doc) {
        return !_alunosParticipantesIds.contains(doc.id);
      }).toList();

      setState(() {
        _alunosDisponiveis = alunosFiltrados.map((doc) {
          final data = doc.data();

          final String graduacaoId = data['graduacao_atual_id'] ?? '';
          final Map<String, dynamic>? graduacaoAtual = mapaGraduacoes[graduacaoId];

          String tipoPublico = 'ADULTO';
          int nivelCorreto = data['nivel_graduacao'] ?? 0;

          if (graduacaoAtual != null) {
            tipoPublico = graduacaoAtual['tipo_publico'] ?? 'ADULTO';
            if (graduacaoAtual['nivel_graduacao'] != null) {
              nivelCorreto = graduacaoAtual['nivel_graduacao'];
            }
          } else {
            final String graduacaoTexto = data['graduacao_atual'] ?? '';
            if (graduacaoTexto.contains('INFANTIL')) {
              tipoPublico = 'INFANTIL';
            }
          }

          return {
            'id': doc.id,
            'nome': data['nome'] ?? '',
            'foto': data['foto_perfil_aluno'] as String?,
            'graduacao': data['graduacao_atual'] ?? '',
            'graduacao_id': graduacaoId,
            'nivel_graduacao': nivelCorreto,
            'tipo_publico': tipoPublico,
            'turma': data['turma'] as String?,
            'data_nascimento': data['data_nascimento'],
          };
        }).toList();

        _alunosDisponiveis.sort((a, b) => a['nome'].compareTo(b['nome']));
      });

      debugPrint('✅ Alunos disponíveis: ${_alunosDisponiveis.length}');

    } catch (e) {
      debugPrint('❌ Erro ao carregar alunos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar alunos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAlunos = false);
    }
  }

  Future<void> _mostrarModalAdicionar(Map<String, dynamic> aluno) async {
    final evento = widget.evento ?? _eventoCarregado;
    if (evento == null) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => AdicionarParticipanteModal(
        aluno: aluno,
        evento: evento,
        isBatizado: _isBatizado,
      ),
    );

    if (result != null) {
      await _adicionarParticipante(
        aluno,
        tamanhoCamisa: result['tamanhoCamisa'],
        novaGraduacao: result['graduacao']?['nome_graduacao'],
        novaGraduacaoId: result['graduacaoId'],
      );
    }
  }

  Future<void> _adicionarParticipante(
      Map<String, dynamic> aluno, {
        String? tamanhoCamisa,
        String? novaGraduacao,
        String? novaGraduacaoId,
      }) async {
    if (!_podeAdicionar) {
      _mostrarSemPermissao();
      return;
    }

    try {
      final evento = widget.evento ?? _eventoCarregado;

      await _participacaoService.adicionarParticipante(
        alunoId: aluno['id'],
        alunoNome: aluno['nome'],
        alunoFoto: aluno['foto'],
        eventoId: widget.eventoId,
        eventoNome: widget.eventoNome,
        dataEvento: evento?.data ?? DateTime.now(),
        tipoEvento: evento?.tipo ?? 'EVENTO',
        graduacao: aluno['graduacao'],
        graduacaoId: aluno['nivel_graduacao'].toString(),
        tamanhoCamisa: tamanhoCamisa,
        status: 'pendente',
        graduacaoNova: novaGraduacao,
        graduacaoNovaId: novaGraduacaoId,
        valorInscricao: evento?.valorInscricao ?? 0,
        valorCamisa: evento?.temCamisa == true ? (evento?.valorCamisa ?? 0) : 0,
      );

      // Limpa o cache do aluno adicionado
      _cacheAlunos.remove(aluno['id']);

      setState(() {
        _alunosParticipantesIds.add(aluno['id']);
        _alunosDisponiveis.removeWhere((a) => a['id'] == aluno['id']);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isBatizado && novaGraduacao != null
                  ? '✅ ${aluno['nome']} será graduado para $novaGraduacao!'
                  : '✅ ${aluno['nome']} adicionado ao evento!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao adicionar participante: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removerParticipante(String participacaoId, String nomeAluno, String alunoId) async {
    if (!_podeRemover) {
      _mostrarSemPermissao();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Participante'),
        content: Text('Remover $nomeAluno do evento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('REMOVER'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _participacaoService.removerParticipante(participacaoId);

        // Limpa o cache do aluno removido
        _cacheAlunos.remove(alunoId);

        setState(() {
          _alunosParticipantesIds.remove(alunoId);
          _carregarAlunos();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ $nomeAluno removido do evento!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        debugPrint('Erro ao remover participante: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao remover: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _marcarPresenca(String participacaoId, bool presente) async {
    if (!_podeMarcarPresenca) {
      _mostrarSemPermissao();
      return;
    }

    try {
      await _participacaoService.marcarPresenca(participacaoId, presente);
    } catch (e) {
      debugPrint('Erro ao marcar presença: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao marcar presença: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _mostrarSemPermissao() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Você não tem permissão para esta ação'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _abrirDetalheParticipacao(ParticipacaoModel participacao) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalheParticipacaoScreen(
          participacao: participacao.toMap(),
          participacaoId: participacao.id!,
          eventoId: widget.eventoId,
        ),
      ),
    );
  }

  String _formatarValorResumido(double valor) {
    if (valor >= 100) {
      return 'R\$${valor.toStringAsFixed(0)}';
    }
    return 'R\$${valor.toStringAsFixed(2)}';
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red.shade900 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.grey.shade600,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildFiltroChip(String label, String valor) {
    bool isSelected = _filtroStatus == valor;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filtroStatus = selected ? valor : 'todos';
        });
      },
      backgroundColor: Colors.grey.shade100,
      selectedColor: Colors.red.shade100,
      checkmarkColor: Colors.red.shade900,
      labelStyle: TextStyle(
        color: isSelected ? Colors.red.shade900 : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  // 🔥 CARD DO MODO GRADE COM FOTO DINÂMICA
  Widget _buildParticipantCardGrade(ParticipacaoModel participacao) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarDadosAluno(participacao.alunoId),
      builder: (context, snapshot) {
        final dadosAluno = snapshot.data;
        final fotoUrl = dadosAluno?['foto'];
        final nomeAluno = dadosAluno?['nome'] ?? participacao.alunoNome;
        final graduacaoAtual = dadosAluno?['graduacao'] ?? participacao.graduacao;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () => _abrirDetalheParticipacao(participacao),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.grey.shade100,
                        backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
                            ? NetworkImage(fotoUrl)
                            : null,
                        child: fotoUrl == null || fotoUrl.isEmpty
                            ? const Icon(Icons.person, size: 32, color: Colors.grey)
                            : null,
                      ),
                      if (participacao.aguardandoFinalizacao)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.access_time,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Text(
                    nomeAluno.split(' ').first,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      participacao.graduacaoNova != null
                          ? participacao.graduacaoNova!.split(' ').take(2).join(' ')
                          : (graduacaoAtual ?? '').split(' ').take(2).join(' '),
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: participacao.estaQuitado ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          participacao.estaQuitado ? Icons.check_circle : Icons.hourglass_empty,
                          size: 10,
                          color: participacao.estaQuitado ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          participacao.estaQuitado ? 'Pago' : 'R\$ ${participacao.saldoDevedor.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 8,
                            color: participacao.estaQuitado ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 🔥 CARD DO MODO LISTA COM FOTO DINÂMICA
  Widget _buildParticipantCardLista(ParticipacaoModel p) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarDadosAluno(p.alunoId),
      builder: (context, snapshot) {
        final dadosAluno = snapshot.data;
        final fotoUrl = dadosAluno?['foto'];
        final nomeAluno = dadosAluno?['nome'] ?? p.alunoNome;
        final graduacaoAtual = dadosAluno?['graduacao'] ?? p.graduacao;
        final turma = dadosAluno?['turma'];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _abrirDetalheParticipacao(p),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.grey.shade50,
                        backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
                            ? NetworkImage(fotoUrl)
                            : null,
                        child: fotoUrl == null || fotoUrl.isEmpty
                            ? Icon(Icons.person, size: 32, color: Colors.grey)
                            : null,
                      ),
                      if (p.aguardandoFinalizacao)
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.access_time, color: Colors.white, size: 12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nomeAluno, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                                child: Text(
                                  graduacaoAtual ?? 'Sem graduação',
                                  style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                                ),
                              ),
                              if (p.graduacaoNova != null) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward, size: 12, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                                  child: Text(
                                    p.graduacaoNova!,
                                    style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: p.estaQuitado ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      p.estaQuitado ? Icons.check_circle : Icons.hourglass_empty,
                                      size: 12,
                                      color: p.estaQuitado ? Colors.green : Colors.orange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      p.estaQuitado ? 'Pago' : 'Dev ${_formatarValorResumido(p.saldoDevedor)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.estaQuitado ? Colors.green : Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (turma != null && turma.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.class_, size: 12, color: Colors.purple),
                                      const SizedBox(width: 4),
                                      Text(
                                        turma,
                                        style: TextStyle(fontSize: 11, color: Colors.purple.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (p.tamanhoCamisa != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.shopping_bag, size: 12, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text(
                                        p.tamanhoCamisa!,
                                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_podeRemover)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                          child: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () => _removerParticipante(p.id!, p.alunoNome, p.alunoId),
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                        child: IconButton(
                          icon: Icon(Icons.chevron_right, color: Colors.red.shade900, size: 20),
                          onPressed: () => _abrirDetalheParticipacao(p),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridView(List<ParticipacaoModel> participantes) {
    List<ParticipacaoModel> participantesFiltrados = participantes.where((p) {
      if (_filtroStatus == 'todos') return true;
      if (_filtroStatus == 'pagos') return p.estaQuitado;
      if (_filtroStatus == 'pendentes') return !p.estaQuitado;
      return true;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildDashboard()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.info, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  '${participantesFiltrados.length} participantes (filtrados)',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildParticipantCardGrade(participantesFiltrados[index]),
              childCount: participantesFiltrados.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListView(List<ParticipacaoModel> participantes) {
    List<ParticipacaoModel> participantesFiltrados = participantes.where((p) {
      if (_filtroStatus == 'todos') return true;
      if (_filtroStatus == 'pagos') return p.estaQuitado;
      if (_filtroStatus == 'pendentes') return !p.estaQuitado;
      return true;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(Icons.info, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  '${participantesFiltrados.length} participantes (filtrados)',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                if (index == participantesFiltrados.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          '🔹 MAIS PARTICIPANTES...',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return _buildParticipantCardLista(participantesFiltrados[index]);
              },
              childCount: participantesFiltrados.length + 1,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.eventoNome} - Participantes', style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          actions: [
            if (_podeGerarCertificados)
              IconButton(
                icon: const Icon(Icons.table_chart),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SelecionarParticipantesCsvScreen(
                        eventoId: widget.eventoId,
                        eventoNome: widget.eventoNome,
                      ),
                    ),
                  );
                },
                tooltip: 'Selecionar para CSV',
              ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'PARTICIPANTES', icon: Icon(Icons.people)),
              Tab(text: 'ADICIONAR', icon: Icon(Icons.person_add)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildParticipantesList(),
            _buildAdicionarParticipantes(),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('participacoes_eventos_em_andamento')
          .where('evento_id', isEqualTo: widget.eventoId)
          .orderBy('aluno_nome')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text('Erro: ${snapshot.error}'),
            ],
          ));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 60, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text('Nenhum participante ainda', style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 8),
              Text('Adicione participantes na aba "ADICIONAR"', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            ],
          ));
        }

        final participantes = docs.map((doc) =>
            ParticipacaoModel.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>)
        ).toList();

        if (_isGridView && _ultimoTotalParticipantes != participantes.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _calcularEstatisticas(participantes);
            }
          });
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFiltroChip('TODOS', 'todos'),
                    const SizedBox(width: 8),
                    _buildFiltroChip('💰 PAGOS', 'pagos'),
                    const SizedBox(width: 8),
                    _buildFiltroChip('⏳ PENDENTES', 'pendentes'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${participantes.length} participantes', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  Container(
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        _buildViewModeButton(icon: Icons.grid_view, isSelected: _isGridView, onTap: () => setState(() => _isGridView = true)),
                        _buildViewModeButton(icon: Icons.list, isSelected: !_isGridView, onTap: () => setState(() => _isGridView = false)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isGridView
                  ? _buildGridView(participantes)
                  : _buildListView(participantes),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAdicionarParticipantes() {
    if (!_podeAdicionar) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('Você não tem permissão para adicionar participantes', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar alunos...',
              prefixIcon: Icon(Icons.search, color: Colors.red),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: Icon(Icons.clear, color: Colors.red), onPressed: () => _searchController.clear())
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _isLoadingAlunos
              ? const Center(child: CircularProgressIndicator())
              : _alunosDisponiveis.isEmpty
              ? Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 60, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text('Nenhum aluno disponível', style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 8),
              Text('Todos os alunos já estão participando!', style: TextStyle(fontSize: 14, color: Colors.grey.shade500), textAlign: TextAlign.center),
            ],
          ))
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _alunosDisponiveis.length,
            itemBuilder: (context, index) {
              final aluno = _alunosDisponiveis[index];
              if (_searchQuery.isNotEmpty && !aluno['nome'].toLowerCase().contains(_searchQuery)) {
                return const SizedBox.shrink();
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () => _mostrarModalAdicionar(aluno),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.red.shade50,
                          backgroundImage: aluno['foto'] != null && aluno['foto'].toString().isNotEmpty
                              ? NetworkImage(aluno['foto'])
                              : null,
                          child: aluno['foto'] == null || aluno['foto'].toString().isEmpty
                              ? Icon(Icons.person, color: Colors.red, size: 28)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(aluno['nome'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                                      child: Text(aluno['graduacao'], style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                                    ),
                                    if (aluno['turma'] != null && aluno['turma'].toString().isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                                        child: Text(aluno['turma'], style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          child: ElevatedButton(
                            onPressed: () => _mostrarModalAdicionar(aluno),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.add, size: 18),
                                SizedBox(width: 4),
                                Text('ADICIONAR'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cacheAlunos.clear();
    super.dispose();
  }
}