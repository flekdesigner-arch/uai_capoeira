import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditarAcademiaScreen extends StatefulWidget {
  final String? academiaId;

  const EditarAcademiaScreen({super.key, this.academiaId});

  @override
  State<EditarAcademiaScreen> createState() => _EditarAcademiaScreenState();
}

class _EditarAcademiaScreenState extends State<EditarAcademiaScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool get _isEditing => widget.academiaId != null;
  bool _isLoading = false;
  bool _usuariosCarregando = false;

  // 🔥 VARIÁVEL LOCAL PARA GUARDAR O ID DA ACADEMIA
  String? _academiaId;

  // Listas de usuários
  List<Map<String, dynamic>> _todosUsuarios = [];
  List<Map<String, dynamic>> _usuariosDisponiveis = []; // Somente peso_permissao >= 50
  List<Map<String, dynamic>> _professoresDisponiveis = [];

  // Controllers
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _cidadeController = TextEditingController();
  final TextEditingController _enderecoController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _logoUrlController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  // Valores selecionados
  String _modalidadeSelecionada = 'CAPOEIRA';
  String _statusSelecionado = 'ativa';
  String? _responsavelSelecionadoId;
  String _responsavelNome = '';
  List<String> _professoresSelecionadosIds = [];
  List<String> _professoresSelecionadosNomes = [];

  // 🔥 ARMAZENAR VALORES ANTERIORES PARA COMPARAÇÃO
  List<String> _professoresAnterioresIds = [];
  String? _responsavelAnteriorId;

  // Opções para dropdowns
  final List<String> _modalidades = [
    'CAPOEIRA',
    'JIU-JITSU',
    'MUAY THAI',
    'KARATÊ',
    'JUDÔ',
    'TAEKWONDO',
    'BOXING',
    'MMA',
    'OUTROS'
  ];

  final List<String> _statusOptions = ['ativa', 'inativa'];

  @override
  void initState() {
    super.initState();
    _academiaId = widget.academiaId;
    _carregarUsuarios();
    if (_isEditing) {
      _carregarAcademia();
    }
  }

  Future<void> _carregarUsuarios() async {
    setState(() => _usuariosCarregando = true);
    try {
      final snapshot = await _firestore.collection('usuarios').get();
      debugPrint('📊 Total de usuários carregados: ${snapshot.docs.length}');

      setState(() {
        _todosUsuarios = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'nome': data['nome_completo'] ?? data['name'] ?? 'Sem nome',
            'email': data['email'] ?? 'Sem email',
            'tipo': data['tipo'] ?? 'aluno',
            'peso_permissao': data['peso_permissao'] ?? 0,
            'status_conta': data['status_conta'] ?? 'pendente',
            'contato': data['contato'] ?? '',
            'foto_url': data['foto_url'] as String?,
          };
        }).toList();

        // Filtrar usuários com peso_permissao >= 50 E status_conta = 'ativa'
        _usuariosDisponiveis = _todosUsuarios.where((user) {
          final peso = user['peso_permissao'] ?? 0;
          final status = user['status_conta']?.toString().toLowerCase() ?? '';
          return peso >= 50 && status == 'ativa';
        }).toList();
        debugPrint('👥 Usuários disponíveis (peso >= 50): ${_usuariosDisponiveis.length}');

        // Filtrar professores (tipo professor ou admin) com peso >= 50
        _professoresDisponiveis = _todosUsuarios.where((user) {
          final tipo = user['tipo']?.toString().toLowerCase() ?? '';
          final peso = user['peso_permissao'] ?? 0;
          final status = user['status_conta']?.toString().toLowerCase() ?? '';
          final isProfessorOuAdmin = tipo == 'professor' || tipo == 'administrador' || tipo == 'admin';
          return isProfessorOuAdmin && peso >= 50 && status == 'ativa';
        }).toList();
        debugPrint('👨‍🏫 Professores disponíveis: ${_professoresDisponiveis.length}');
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar usuários: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar usuários: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _usuariosCarregando = false);
    }
  }

  Future<void> _carregarAcademia() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('📥 Carregando academia ID: $_academiaId');
      final doc = await _firestore
          .collection('academias')
          .doc(_academiaId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _nomeController.text = data['nome'] ?? '';
        _cidadeController.text = data['cidade'] ?? '';
        _enderecoController.text = data['endereco'] ?? '';
        _telefoneController.text = data['telefone'] ?? '';
        _emailController.text = data['email'] ?? '';
        _whatsappController.text = data['whatsapp'] ?? data['whatsapp_url'] ?? '';
        _logoUrlController.text = data['logo_url'] ?? '';
        _observacoesController.text = data['observacoes'] ?? '';
        _modalidadeSelecionada = data['modalidade'] ?? 'CAPOEIRA';
        _statusSelecionado = data['status'] ?? 'ativa';

        // Carregar responsável
        final responsavelId = data['responsavel_id'] as String?;
        if (responsavelId != null && responsavelId.isNotEmpty) {
          _responsavelSelecionadoId = responsavelId;
          _responsavelAnteriorId = responsavelId;
          debugPrint('👤 Responsável ID: $responsavelId');

          // Buscar nome do responsável
          final responsavelNaLista = _todosUsuarios.firstWhere(
                (user) => user['id'] == responsavelId,
            orElse: () => {},
          );

          if (responsavelNaLista.isNotEmpty) {
            _responsavelNome = responsavelNaLista['nome'] ?? 'Responsável';
          } else {
            try {
              final responsavelDoc = await _firestore
                  .collection('usuarios')
                  .doc(responsavelId)
                  .get();
              if (responsavelDoc.exists) {
                final responsavelData = responsavelDoc.data()!;
                _responsavelNome = responsavelData['nome_completo'] ??
                    responsavelData['name'] ??
                    'Responsável';
              } else {
                _responsavelNome = 'Usuário não encontrado';
              }
            } catch (e) {
              _responsavelNome = 'Erro ao carregar';
              debugPrint('❌ Erro ao carregar responsável: $e');
            }
          }
        }

        // Carregar professores com acesso
        final professoresIds = data['professores_ids'] as List<dynamic>? ?? [];
        final professoresNomes = data['professores_nomes'] as List<dynamic>? ?? [];

        setState(() {
          _professoresSelecionadosIds = professoresIds.map((id) => id.toString()).toList();
          _professoresAnterioresIds = List.from(_professoresSelecionadosIds);
          _professoresSelecionadosNomes = professoresNomes.map((nome) => nome.toString()).toList();
        });

        debugPrint('👨‍🏫 Professores carregados: ${_professoresSelecionadosIds.length}');
        for (var id in _professoresSelecionadosIds) {
          debugPrint('   - Professor ID: $id');
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar academia: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 🔥 FUNÇÃO PARA VINCULAR/DESVINCULAR ACADEMIA NO USUÁRIO
  Future<void> _atualizarVinculoUsuario(String usuarioId, bool adicionar) async {
    if (_academiaId == null) {
      debugPrint('❌ _academiaId é null, não é possível vincular');
      return;
    }

    debugPrint('🔧 ===== VINCULANDO USUÁRIO =====');
    debugPrint('🔧 usuarioId: $usuarioId');
    debugPrint('🔧 adicionar: $adicionar');
    debugPrint('🔧 academiaId: $_academiaId');

    try {
      final userRef = _firestore.collection('usuarios').doc(usuarioId);

      // Verificar se o documento existe
      final userDoc = await userRef.get();
      if (!userDoc.exists) {
        debugPrint('❌ Usuário $usuarioId não existe!');
        return;
      }

      if (adicionar) {
        debugPrint('🔗 Adicionando vínculo: Usuário $usuarioId -> Academia $_academiaId');
        await userRef.update({
          'academias': FieldValue.arrayUnion([_academiaId])
        });
        debugPrint('✅ Vínculo adicionado com sucesso!');
      } else {
        debugPrint('🔗 Removendo vínculo: Usuário $usuarioId -> Academia $_academiaId');
        await userRef.update({
          'academias': FieldValue.arrayRemove([_academiaId])
        });
        debugPrint('✅ Vínculo removido com sucesso!');
      }

      // Verificar se funcionou
      final updatedDoc = await userRef.get();
      final dadosAtualizados = updatedDoc.data() ?? {};
      debugPrint('📄 academias após operação: ${dadosAtualizados['academias']}');

    } catch (e) {
      debugPrint('❌ ERRO ao atualizar vínculo: $e');
    }
  }

  // 🔥 NOVO: DIALOG BONITO PARA GERENCIAR PROFESSORES
  Future<void> _mostrarDialogProfessores() async {
    // Criar cópia temporária das seleções
    List<String> selecaoTemporaria = List.from(_professoresSelecionadosIds);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                  maxWidth: 500,
                ),
                child: Column(
                  children: [
                    // CABEÇALHO DO DIALOG
                    Container(
                      padding: const EdgeInsets.all(20),
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
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.people,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gerenciar Professores',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Selecione os professores que terão acesso',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // CONTEÚDO DO DIALOG
                    Expanded(
                      child: _usuariosCarregando
                          ? const Center(child: CircularProgressIndicator())
                          : _professoresDisponiveis.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off,
                              size: 60,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhum professor disponível',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Não há professores com peso_permissao ≥ 50',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                          : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _professoresDisponiveis.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final professor = _professoresDisponiveis[index];
                          final isSelecionado = selecaoTemporaria.contains(professor['id']);

                          return InkWell(
                            onTap: () {
                              setStateDialog(() {
                                if (isSelecionado) {
                                  selecaoTemporaria.remove(professor['id']);
                                } else {
                                  selecaoTemporaria.add(professor['id']);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: isSelecionado ? Colors.red.shade50 : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  // Avatar do professor
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelecionado
                                            ? Colors.red.shade400
                                            : Colors.grey.shade300,
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: professor['foto_url'] != null
                                          ? Image.network(
                                        professor['foto_url'],
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey.shade200,
                                            child: Icon(
                                              Icons.person,
                                              color: Colors.grey.shade400,
                                              size: 30,
                                            ),
                                          );
                                        },
                                      )
                                          : Container(
                                        color: Colors.grey.shade200,
                                        child: Icon(
                                          Icons.person,
                                          color: Colors.grey.shade400,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Informações do professor
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          professor['nome'],
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: isSelecionado
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isSelecionado
                                                ? Colors.red.shade900
                                                : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          professor['email'],
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                professor['tipo']?.toUpperCase() ?? 'PROFESSOR',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.blue.shade700,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Peso ${professor['peso_permissao']}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.green.shade700,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Checkbox customizado
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelecionado
                                          ? Colors.red.shade900
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelecionado
                                            ? Colors.red.shade900
                                            : Colors.grey.shade400,
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelecionado
                                        ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // RODAPÉ DO DIALOG
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Resumo das seleções
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${selecaoTemporaria.length} professor(es) selecionado(s)',
                                    style: TextStyle(
                                      color: Colors.blue.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Botões de ação
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey.shade700,
                                    side: BorderSide(color: Colors.grey.shade300),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('CANCELAR'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _professoresSelecionadosIds = selecaoTemporaria;
                                    });
                                    Navigator.pop(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade900,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('CONFIRMAR'),
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
            );
          },
        );
      },
    );
  }

  Future<void> _salvarAcademia() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar responsável
    if (_responsavelSelecionadoId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione um responsável para a academia'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Obter nome do responsável
      String responsavelNome = _responsavelNome;
      if (responsavelNome.isEmpty ||
          responsavelNome == 'Erro ao carregar' ||
          responsavelNome == 'Usuário não encontrado') {
        final responsavel = _usuariosDisponiveis.firstWhere(
              (user) => user['id'] == _responsavelSelecionadoId,
          orElse: () => {'nome': 'Responsável não encontrado'},
        );
        responsavelNome = responsavel['nome'];
      }

      // Obter nomes dos professores selecionados
      final professoresNomes = _professoresSelecionadosIds.map((id) {
        final professor = _professoresDisponiveis.firstWhere(
              (p) => p['id'] == id,
          orElse: () => _usuariosDisponiveis.firstWhere(
                (u) => u['id'] == id,
            orElse: () => {'nome': 'Professor não encontrado'},
          ),
        );
        return professor['nome'];
      }).toList();

      final data = {
        'nome': _nomeController.text.trim().toUpperCase(),
        'cidade': _cidadeController.text.trim().toUpperCase(),
        'endereco': _enderecoController.text.trim(),
        'responsavel_id': _responsavelSelecionadoId,
        'responsavel': responsavelNome,
        'responsavel_nome': responsavelNome,
        'telefone': _telefoneController.text.trim(),
        'email': _emailController.text.trim(),
        'whatsapp': _whatsappController.text.trim(),
        'whatsapp_url': _whatsappController.text.trim(),
        'logo_url': _logoUrlController.text.trim(),
        'observacoes': _observacoesController.text.trim(),
        'modalidade': _modalidadeSelecionada,
        'status': _statusSelecionado,
        'professores_ids': _professoresSelecionadosIds,
        'professores_nomes': professoresNomes,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      };

      if (_isEditing) {
        debugPrint('📝 ===== EDITANDO ACADEMIA =====');
        debugPrint('📝 academia ID: $_academiaId');
        debugPrint('📝 Professores atuais na academia: $_professoresSelecionadosIds');

        await _firestore.runTransaction((transaction) async {
          // 1. Atualiza a academia (lista de professores_ids)
          transaction.update(
            _firestore.collection('academias').doc(_academiaId),
            data,
          );

          // 2. GERENCIAR RESPONSÁVEL (sempre atualiza)
          if (_responsavelAnteriorId != null) {
            debugPrint('🔄 Removendo vínculo antigo do responsável $_responsavelAnteriorId');
            await _atualizarVinculoUsuario(_responsavelAnteriorId!, false);
          }

          debugPrint('🔄 Adicionando vínculo do novo responsável $_responsavelSelecionadoId');
          await _atualizarVinculoUsuario(_responsavelSelecionadoId!, true);

          // 3. GERENCIAR TODOS OS PROFESSORES - FORÇAR ATUALIZAÇÃO
          debugPrint('🔄 ===== ATUALIZANDO VÍNCULOS DE TODOS OS PROFESSORES =====');

          // Lista de todos os professores que devem estar vinculados
          final todosProfessores = _professoresSelecionadosIds.toSet();

          // Adicionar responsável também na lista (se não estiver)
          if (_responsavelSelecionadoId != null) {
            todosProfessores.add(_responsavelSelecionadoId!);
          }

          debugPrint('🔄 Total de professores para vincular: ${todosProfessores.length}');
          debugPrint('🔄 IDs: $todosProfessores');

          // Para cada professor, garantir que o vínculo existe
          for (var professorId in todosProfessores) {
            debugPrint('🔄 Vinculando professor $professorId');
            await _atualizarVinculoUsuario(professorId, true);
          }

          // 4. Remover vínculos de professores que não estão mais na lista
          final todosProfessoresAnteriores = _professoresAnterioresIds.toSet();
          if (_responsavelAnteriorId != null) {
            todosProfessoresAnteriores.add(_responsavelAnteriorId!);
          }

          final removidos = todosProfessoresAnteriores.difference(todosProfessores);

          if (removidos.isNotEmpty) {
            debugPrint('🔄 Removendo vínculos de professores que saíram: $removidos');
            for (var id in removidos) {
              await _atualizarVinculoUsuario(id, false);
            }
          }
        });

        debugPrint('✅ Transação concluída com sucesso!');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Academia atualizada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        debugPrint('➕ ===== CRIANDO NOVA ACADEMIA =====');

        // Criando nova academia
        data['data_cadastro'] = FieldValue.serverTimestamp();
        data['turmas_count'] = 0;

        final docRef = await _firestore.collection('academias').add(data);
        _academiaId = docRef.id;
        debugPrint('✅ Academia criada com ID: $_academiaId');

        // 🔥 VINCULA RESPONSÁVEL E TODOS OS PROFESSORES
        final todosParaVincular = <String>{};

        if (_responsavelSelecionadoId != null) {
          todosParaVincular.add(_responsavelSelecionadoId!);
        }

        for (var id in _professoresSelecionadosIds) {
          todosParaVincular.add(id);
        }

        debugPrint('🔗 Vinculando ${todosParaVincular.length} usuários: $todosParaVincular');

        for (var usuarioId in todosParaVincular) {
          debugPrint('🔗 Vinculando usuário $usuarioId');
          await _atualizarVinculoUsuario(usuarioId, true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Academia criada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Erro ao salvar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _excluirAcademia() async {
    // Verificar se tem turmas ativas
    final turmasSnapshot = await _firestore
        .collection('turmas')
        .where('academia_id', isEqualTo: _academiaId)
        .get();

    final temTurmasAtivas = turmasSnapshot.docs.isNotEmpty;
    final nomeAcademia = _nomeController.text.trim().toUpperCase();

    // Controller para o campo de confirmação
    final confirmacaoController = TextEditingController();
    bool nomeConfere = false;

    await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirmar Exclusão'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temTurmasAtivas
                        ? 'Esta academia possui ${turmasSnapshot.docs.length} turma(s) ativa(s).\n\nTodas as turmas também serão excluídas.'
                        : 'Tem certeza que deseja excluir esta academia?\n\nEsta ação não pode ser desfeita.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Para confirmar, digite o nome da academia:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Center(
                      child: Text(
                        '"$nomeAcademia"',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmacaoController,
                    decoration: InputDecoration(
                      labelText: 'Digite o nome da academia',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.warning),
                      suffixIcon: confirmacaoController.text.isNotEmpty
                          ? Icon(
                        confirmacaoController.text.trim().toUpperCase() == nomeAcademia
                            ? Icons.check_circle
                            : Icons.error,
                        color: confirmacaoController.text.trim().toUpperCase() == nomeAcademia
                            ? Colors.green
                            : Colors.red,
                      )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        nomeConfere = value.trim().toUpperCase() == nomeAcademia;
                      });
                    },
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: nomeConfere
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    backgroundColor: nomeConfere ? Colors.red.shade50 : Colors.grey.shade100,
                  ),
                  child: const Text('Excluir Academia'),
                ),
              ],
            );
          },
        );
      },
    ).then((confirmado) async {
      if (confirmado == true) {
        await _realizarExclusaoAcademia(turmasSnapshot);
      }
    });
  }

  Future<void> _realizarExclusaoAcademia(QuerySnapshot turmasSnapshot) async {
    setState(() => _isLoading = true);
    try {
      debugPrint('🗑️ ===== EXCLUINDO ACADEMIA =====');
      debugPrint('🗑️ academia ID: $_academiaId');

      // 🔥 REMOVER VÍNCULOS DE TODOS OS USUÁRIOS
      final todosUsuarios = <String>{};

      if (_responsavelSelecionadoId != null) {
        todosUsuarios.add(_responsavelSelecionadoId!);
      }

      for (var id in _professoresSelecionadosIds) {
        todosUsuarios.add(id);
      }

      debugPrint('🔗 Removendo vínculos de ${todosUsuarios.length} usuários: $todosUsuarios');

      for (var usuarioId in todosUsuarios) {
        await _atualizarVinculoUsuario(usuarioId, false);
      }

      // Excluir turmas vinculadas primeiro
      debugPrint('🗑️ Excluindo ${turmasSnapshot.docs.length} turmas');
      for (var turma in turmasSnapshot.docs) {
        await turma.reference.delete();
      }

      // Excluir academia
      debugPrint('🗑️ Excluindo academia');
      await _firestore
          .collection('academias')
          .doc(_academiaId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Academia excluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Erro ao excluir: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obrigatorio = false,
    TextInputType? keyboardType,
    int? maxLines,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label + (obrigatorio ? ' *' : ''),
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines ?? 1,
        validator: validator ?? (obrigatorio
            ? (value) {
          if (value == null || value.isEmpty) {
            return 'Campo obrigatório';
          }
          return null;
        }
            : null),
      ),
    );
  }

  Widget _buildDropdownField({
    required String value,
    required List<String> items,
    required String label,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildSelecaoResponsavel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Responsável *',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Somente usuários com peso_permissao ≥ 50 e status_conta = ativa',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),

          if (_usuariosCarregando)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_usuariosDisponiveis.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Nenhum usuário disponível como responsável',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _responsavelSelecionadoId,
                  hint: const Text('Selecione um responsável'),
                  isExpanded: true,
                  items: _usuariosDisponiveis.map((usuario) {
                    return DropdownMenuItem<String>(
                      value: usuario['id'],
                      child: Text(
                        usuario['email'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (String? novoId) {
                    if (novoId != null) {
                      final usuario = _usuariosDisponiveis.firstWhere(
                            (u) => u['id'] == novoId,
                        orElse: () => {'nome': '', 'email': ''},
                      );
                      setState(() {
                        _responsavelSelecionadoId = novoId;
                        _responsavelNome = usuario['nome'];
                      });
                    }
                  },
                ),
              ),
            ),

          if (_responsavelSelecionadoId != null && _responsavelNome.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Responsável: $_responsavelNome',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  // NOVA SEÇÃO DE PROFESSORES COM BOTÃO ESTILOSO
  Widget _buildSelecaoProfessores() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Professores com Acesso',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gerencie os professores que podem acessar esta academia',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          // BOTÃO PRINCIPAL
          InkWell(
            onTap: _usuariosCarregando ? null : _mostrarDialogProfessores,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade400,
                    Colors.blue.shade700,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.people,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GERENCIAR PROFESSORES',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _professoresSelecionadosIds.isEmpty
                              ? 'Nenhum professor selecionado'
                              : '${_professoresSelecionadosIds.length} professor(es) selecionado(s)',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // LISTA DE PROFESSORES SELECIONADOS (CHIPS)
          if (_professoresSelecionadosIds.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.school,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Professores vinculados:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _professoresSelecionadosIds.map((id) {
                      final professor = _professoresDisponiveis.firstWhere(
                            (p) => p['id'] == id,
                        orElse: () => {'nome': 'Professor', 'email': ''},
                      );
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person,
                              size: 14,
                              color: Colors.blue.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              professor['nome'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Academia' : 'Nova Academia'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _excluirAcademia,
              tooltip: 'Excluir Academia',
            ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading || _usuariosCarregando ? null : _salvarAcademia,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Nome da Academia
              _buildFormField(
                controller: _nomeController,
                label: 'Nome da Academia/Núcleo',
                icon: Icons.business,
                obrigatorio: true,
              ),

              // Modalidade
              _buildDropdownField(
                value: _modalidadeSelecionada,
                items: _modalidades,
                label: 'Modalidade',
                icon: Icons.sports_martial_arts,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _modalidadeSelecionada = value);
                  }
                },
              ),

              // Status
              _buildDropdownField(
                value: _statusSelecionado,
                items: _statusOptions,
                label: 'Status',
                icon: Icons.circle,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _statusSelecionado = value);
                  }
                },
              ),

              // Responsável (SOMENTE 1)
              _buildSelecaoResponsavel(),

              // Professores com Acesso (MÚLTIPLOS)
              _buildSelecaoProfessores(),

              // Cidade
              _buildFormField(
                controller: _cidadeController,
                label: 'Cidade',
                icon: Icons.location_city,
                obrigatorio: true,
              ),

              // Endereço
              _buildFormField(
                controller: _enderecoController,
                label: 'Endereço Completo',
                icon: Icons.location_on,
                maxLines: 2,
              ),

              // Telefone
              _buildFormField(
                controller: _telefoneController,
                label: 'Telefone de Contato',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),

              // Email
              _buildFormField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),

              // WhatsApp URL
              _buildFormField(
                controller: _whatsappController,
                label: 'Link do Grupo WhatsApp',
                icon: Icons.chat,
                keyboardType: TextInputType.url,
              ),

              // Logo URL
              _buildFormField(
                controller: _logoUrlController,
                label: 'URL da Logo',
                icon: Icons.image,
                keyboardType: TextInputType.url,
              ),

              // Observações
              _buildFormField(
                controller: _observacoesController,
                label: 'Observações',
                icon: Icons.note,
                maxLines: 4,
              ),

              const SizedBox(height: 24),

              // Botão Salvar
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading || _usuariosCarregando ? null : _salvarAcademia,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  )
                      : Text(
                    _isEditing ? 'ATUALIZAR ACADEMIA' : 'CRIAR ACADEMIA',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}