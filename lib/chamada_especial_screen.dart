// chamada_especial_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ============================================
// ENUM PARA MODO DE VISUALIZAÇÃO
// ============================================
enum ViewMode { list, grid }

// ============================================
// SELETOR DE VISUALIZAÇÃO
// ============================================
class ViewModeSelector extends StatelessWidget {
  final ViewMode currentMode;
  final ValueChanged<ViewMode> onChanged;

  const ViewModeSelector({
    super.key,
    required this.currentMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            icon: Icons.view_list,
            label: 'Lista',
            mode: ViewMode.list,
          ),
          const SizedBox(width: 8),
          _buildButton(
            icon: Icons.grid_view,
            label: 'Grade',
            mode: ViewMode.grid,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required ViewMode mode,
  }) {
    final isSelected = currentMode == mode;
    return GestureDetector(
      onTap: () => onChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red.shade900 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChamadaEspecialScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;
  final String usuarioId;
  final DateTime dataSelecionada;

  const ChamadaEspecialScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
    required this.usuarioId,
    required this.dataSelecionada,
  });

  @override
  State<ChamadaEspecialScreen> createState() => _ChamadaEspecialScreenState();
}

class _ChamadaEspecialScreenState extends State<ChamadaEspecialScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _alunos = [];
  Map<String, bool> _presencas = {};
  Map<String, String> _observacoes = {};
  final TextEditingController _observacaoController = TextEditingController();

  String _professorNome = 'Carregando...';
  String _professorId = '';
  String _tipoAula = 'CARREGANDO...';
  String _diaSemana = '';
  String _diaSemanaAbrev = '';

  // 🔥 CONTROLE DA ANIMAÇÃO DE SALVAMENTO
  bool _mostrarProgresso = false;
  String _statusMensagem = '';

  // Modo de visualização
  ViewMode _viewMode = ViewMode.grid;

  final Map<String, String> _diasAbreviados = {
    'SEGUNDA': 'seg', 'TERÇA': 'ter', 'TERCA': 'ter',
    'QUARTA': 'qua', 'QUINTA': 'qui', 'SEXTA': 'sex',
    'SÁBADO': 'sab', 'SABADO': 'sab', 'DOMINGO': 'dom',
  };

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      // Formatar o dia da semana
      final diaSemanaOriginal = DateFormat('EEEE', 'pt_BR')
          .format(widget.dataSelecionada).toLowerCase();

      String diaSemanaFormatado = diaSemanaOriginal;

      if (diaSemanaOriginal.contains('segunda')) {
        diaSemanaFormatado = 'SEGUNDA';
      } else if (diaSemanaOriginal.contains('terça') || diaSemanaOriginal.contains('terca')) {
        diaSemanaFormatado = 'TERCA';
      } else if (diaSemanaOriginal.contains('quarta')) {
        diaSemanaFormatado = 'QUARTA';
      } else if (diaSemanaOriginal.contains('quinta')) {
        diaSemanaFormatado = 'QUINTA';
      } else if (diaSemanaOriginal.contains('sexta')) {
        diaSemanaFormatado = 'SEXTA';
      } else if (diaSemanaOriginal.contains('sábado') || diaSemanaOriginal.contains('sabado')) {
        diaSemanaFormatado = 'SABADO';
      } else if (diaSemanaOriginal.contains('domingo')) {
        diaSemanaFormatado = 'DOMINGO';
      }

      _diaSemana = diaSemanaFormatado;
      _diaSemanaAbrev = _getDiaAbreviado(diaSemanaFormatado);

      debugPrint('📅 Data selecionada: ${widget.dataSelecionada}');
      debugPrint('📅 Dia formatado: $_diaSemana');

      // Carregar tipo de aula da configuração da turma
      final turmaDoc = await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .get();

      if (turmaDoc.exists) {
        final turmaData = turmaDoc.data()!;
        final diasConfiguracao = turmaData['dias_configuracao'] as Map<String, dynamic>?;

        if (diasConfiguracao != null) {
          final configuracaoDia = diasConfiguracao[_diaSemana];
          if (configuracaoDia != null) {
            _tipoAula = configuracaoDia['tipoAula'] ?? 'OBJETIVA';
            debugPrint('✅ Tipo de aula: $_tipoAula para $_diaSemana');
          } else {
            _tipoAula = 'OBJETIVA';
          }
        } else {
          _tipoAula = 'OBJETIVA';
        }
      }

      // Carregar dados do professor
      final userDoc = await _firestore
          .collection('usuarios')
          .doc(widget.usuarioId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _professorId = widget.usuarioId;
        _professorNome = userData['nome_completo']?.toString() ??
            userData['nome']?.toString() ?? 'Professor';
      }

      // Carregar alunos da turma
      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', whereIn: ['ATIVO(A)', 'ATIVO(A) '])
          .get();

      final alunosList = alunosSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'foto': data['foto_perfil_aluno'] as String?,
        };
      }).toList();

      alunosList.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

      final presencasIniciais = <String, bool>{};
      for (var aluno in alunosList) {
        presencasIniciais[aluno['id'] as String] = false;
      }

      setState(() {
        _alunos = alunosList;
        _presencas = presencasIniciais;
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar dados: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isLoading = false;
        _tipoAula = 'OBJETIVA';
      });
    }
  }

  String _getDiaAbreviado(String diaCompleto) {
    final diaUpper = diaCompleto.toUpperCase().trim();
    if (_diasAbreviados.containsKey(diaUpper)) {
      return _diasAbreviados[diaUpper]!;
    }
    for (var entry in _diasAbreviados.entries) {
      if (diaUpper.contains(entry.key) || entry.key.contains(diaUpper)) {
        return entry.value;
      }
    }
    return diaUpper.length >= 3 ? diaUpper.substring(0, 3).toLowerCase() : diaUpper.toLowerCase();
  }

  void _togglePresenca(String alunoId) {
    setState(() {
      _presencas[alunoId] = !(_presencas[alunoId] ?? false);
    });
  }

  void _adicionarObservacao(String alunoId, String nomeAluno) {
    _observacaoController.text = _observacoes[alunoId] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Observação para $nomeAluno'),
          content: TextField(
            controller: _observacaoController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Digite uma observação...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_observacaoController.text.isNotEmpty) {
                  setState(() {
                    _observacoes[alunoId] = _observacaoController.text;
                  });
                  _observacaoController.clear();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Observação salva!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  // ============================================
  // FUNÇÃO PRINCIPAL DE SALVAR CHAMADA (COM CLOUD FUNCTION)
  // ============================================
  Future<void> _salvarChamada() async {
    if (_alunos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Não há alunos para salvar chamada'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final presentes = _presencas.values.where((v) => v).length;

    if (presentes == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('❌ Nenhum aluno presente'),
          content: const Text('Deseja salvar a chamada mesmo sem nenhum aluno presente?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Salvar mesmo assim'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    // Preparar dados para a Cloud Function
    final dadosChamada = {
      'turmaId': widget.turmaId,
      'turmaNome': widget.turmaNome,
      'academiaId': widget.academiaId,
      'academiaNome': widget.academiaNome,
      'dataChamada': widget.dataSelecionada.toIso8601String(),
      'tipoAula': _tipoAula,
      'professorId': _professorId,
      'professorNome': _professorNome,
      'alunos': _alunos.map((aluno) => {
        'id': aluno['id'],
        'nome': aluno['nome'],
        'presente': _presencas[aluno['id']] ?? false,
        'observacao': _observacoes[aluno['id']] ?? '',
      }).toList(),
    };

    setState(() {
      _isSaving = true;
      _mostrarProgresso = true;
      _statusMensagem = 'Enviando para processamento...';
    });

    try {
      setState(() {
        _statusMensagem = 'Processando chamada especial na nuvem...';
      });

      final HttpsCallable callable = _functions.httpsCallable('processarChamada');
      final result = await callable.call(dadosChamada);

      setState(() {
        _statusMensagem = '✅ Chamada salva com sucesso!';
      });
      await Future.delayed(const Duration(milliseconds: 500));

      if (result.data['success']) {
        if (mounted) {
          _mostrarTelaConclusao({
            'presentes': result.data['presentes'],
            'ausentes': result.data['ausentes'],
            'total_alunos': result.data['processados'],
            'porcentagem_frequencia': (result.data['presentes'] / result.data['processados'] * 100).round(),
          });
        }
      }

    } catch (e) {
      debugPrint('❌ Erro ao processar chamada especial: $e');
      setState(() {
        _isSaving = false;
        _mostrarProgresso = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _mostrarProgresso = false;
        });
      }
    }
  }

  // ============================================
  // TELA DE CONCLUSÃO DA CHAMADA
  // ============================================
  void _mostrarTelaConclusao(Map<String, dynamic> dados) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green.shade700, Colors.green.shade500],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 1),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: const Icon(Icons.celebration, size: 80, color: Colors.white),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                '🎉 CHAMADA ESPECIAL CONCLUÍDA!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                DateFormat("dd/MM/yyyy", 'pt_BR').format(widget.dataSelecionada),
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem('${dados['presentes']}', 'Presentes', Icons.check_circle),
                    _buildResumoItem('${dados['ausentes']}', 'Ausentes', Icons.cancel),
                    _buildResumoItem('${dados['porcentagem_frequencia']}%', 'Frequência', Icons.trending_up),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Professor: $_professorNome',
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                'Tipo de aula: $_tipoAula',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 25),
              TweenAnimationBuilder<Duration>(
                duration: const Duration(seconds: 5),
                tween: Tween(begin: const Duration(seconds: 5), end: Duration.zero),
                onEnd: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                builder: (context, value, child) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: value.inSeconds / 5,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fechando em ${value.inSeconds} segundos...',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text(
                  'FECHAR AGORA',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumoItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }

  // ============================================
  // TELA DE PROGRESSO
  // ============================================
  Widget _buildTelaProgresso() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.red.shade900, Colors.red.shade700],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.cloud_upload, size: 60, color: Colors.white),
                const SizedBox(height: 20),
                const Text(
                  'PROCESSANDO CHAMADA ESPECIAL',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusMensagem,
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // WIDGETS DE LISTA E GRADE
  // ============================================
  Widget _buildAlunoListTile(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final estaPresente = _presencas[alunoId] ?? false;
    final observacao = _observacoes[alunoId];
    final fotoUrl = aluno['foto'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        margin: const EdgeInsets.all(0),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: estaPresente ? Colors.green.shade50 : Colors.grey.shade200,
            backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
            child: fotoUrl == null || fotoUrl.isEmpty
                ? Icon(Icons.person, size: 18, color: Colors.grey.shade500)
                : null,
          ),
          title: Text(
            nomeAluno,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: estaPresente ? Colors.black : Colors.grey.shade700,
            ),
          ),
          subtitle: observacao != null
              ? Text(
            observacao,
            style: const TextStyle(fontSize: 10, color: Colors.orange, fontStyle: FontStyle.italic),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
              : null,
          trailing: SizedBox(
            width: 72,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    icon: Icon(
                      Icons.note_add,
                      size: 14,
                      color: observacao != null ? Colors.orange : Colors.blue.shade600,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _adicionarObservacao(alunoId, nomeAluno),
                    splashRadius: 14,
                  ),
                ),
                const SizedBox(width: 2),
                Transform.scale(
                  scale: 0.55,
                  child: Switch(
                    value: estaPresente,
                    activeColor: Colors.green,
                    inactiveTrackColor: Colors.grey.shade400,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) => _togglePresenca(alunoId),
                  ),
                ),
              ],
            ),
          ),
          tileColor: estaPresente ? Colors.green.shade50.withOpacity(0.3) : null,
          onTap: () => _togglePresenca(alunoId),
        ),
      ),
    );
  }

  Widget _buildAlunoGridItem(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final estaPresente = _presencas[alunoId] ?? false;
    final fotoUrl = aluno['foto'] as String?;

    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: estaPresente ? Colors.green : Colors.transparent, width: estaPresente ? 2 : 0),
      ),
      child: InkWell(
        onTap: () => _togglePresenca(alunoId),
        child: Container(
          decoration: BoxDecoration(
            color: estaPresente ? Colors.green.shade50.withOpacity(0.3) : Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      color: Colors.grey[200],
                      child: fotoUrl != null && fotoUrl.isNotEmpty
                          ? CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorWidget: (c, u, e) => _placeholderIcon(size: 80),
                      )
                          : _placeholderIcon(size: 80),
                    ),
                    if (estaPresente)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 14, color: Colors.white),
                        ),
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _adicionarObservacao(alunoId, nomeAluno),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.note_add, size: 16, color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeAluno.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        height: 1.2,
                        color: estaPresente ? Colors.green.shade800 : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.center,
                      child: Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: estaPresente,
                          activeColor: Colors.green,
                          inactiveTrackColor: Colors.grey.shade400,
                          onChanged: (_) => _togglePresenca(alunoId),
                        ),
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
  }

  Widget _placeholderIcon({double size = 50}) {
    return Center(child: Icon(Icons.person, size: size, color: Colors.white));
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final porcentagem = total > 0 ? (presentes / total * 100).round() : 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CHAMADA ESPECIAL', style: TextStyle(fontSize: 14)),
            Text(
              '${widget.turmaNome} - ${DateFormat('dd/MM/yyyy').format(widget.dataSelecionada)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (!_isSaving)
            ViewModeSelector(
              currentMode: _viewMode,
              onChanged: (mode) {
                setState(() {
                  _viewMode = mode;
                });
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isSaving && _mostrarProgresso
          ? _buildTelaProgresso()
          : Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _diaSemana,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade900,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'TIPO: $_tipoAula',
                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _professorNome.split(' ').first,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(
                      value: '$presentes',
                      label: 'Presentes',
                      color: Colors.green,
                      icon: Icons.check_circle,
                    ),
                    _buildStatItem(
                      value: '${total - presentes}',
                      label: 'Ausentes',
                      color: Colors.red,
                      icon: Icons.cancel,
                    ),
                    _buildStatItem(
                      value: '$porcentagem%',
                      label: 'Frequência',
                      color: Colors.blue,
                      icon: Icons.trending_up,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: total > 0 ? presentes / total : 0,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    presentes == 0
                        ? Colors.red
                        : presentes == total
                        ? Colors.green
                        : Colors.orange,
                  ),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          ),
          // Lista de alunos
          Expanded(
            child: _viewMode == ViewMode.list
                ? ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _alunos.length,
              itemBuilder: (context, index) {
                return _buildAlunoListTile(_alunos[index]);
              },
            )
                : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: _alunos.length,
              itemBuilder: (context, index) {
                return _buildAlunoGridItem(_alunos[index]);
              },
            ),
          ),
          // Botão salvar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _salvarChamada,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSaving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.save, size: 24),
              label: _isSaving
                  ? const Text('SALVANDO...')
                  : const Text(
                '✅ SALVAR CHAMADA ESPECIAL',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _observacaoController.dispose();
    super.dispose();
  }
}