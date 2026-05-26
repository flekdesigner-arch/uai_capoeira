import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'editar_usuario_screen.dart';

class UsuarioDetalheScreen extends StatefulWidget {
  final String userId;

  const UsuarioDetalheScreen({super.key, required this.userId});

  @override
  State<UsuarioDetalheScreen> createState() => _UsuarioDetalheScreenState();
}

class _UsuarioDetalheScreenState extends State<UsuarioDetalheScreen> {
  // 🔥 LOGS PARA ACOMPANHAR
  void _log(String mensagem, {dynamic dados}) {
    debugPrint('🔍 [UsuarioDetalhe] $mensagem');
    if (dados != null) {
      debugPrint('📦 Dados: $dados');
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Não informado';
    final date = timestamp.toDate();
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  String _formatStatus(String? status) {
    if (status == null) return 'Não informado';
    switch (status.toLowerCase()) {
      case 'pendente':
        return 'Pendente';
      case 'ativa':
        return 'Ativa';
      case 'bloqueada':
      case 'inativa':
        return 'Bloqueada';
      default:
        return status;
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    switch (status.toLowerCase()) {
      case 'ativa':
        return Colors.green;
      case 'pendente':
        return Colors.orange;
      case 'bloqueada':
      case 'inativa':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getTipoColor(String? tipo) {
    if (tipo == null) return Colors.grey;
    switch (tipo.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return Colors.red;
      case 'professor':
        return Colors.orange;
      case 'monitor':
        return Colors.blue;
      case 'aluno':
        return Colors.green;
      case 'visitante':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getTipoIcon(String? tipo) {
    if (tipo == null) return Icons.person;
    switch (tipo.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return Icons.admin_panel_settings;
      case 'professor':
        return Icons.school;
      case 'monitor':
        return Icons.supervised_user_circle;
      case 'aluno':
        return Icons.person;
      case 'visitante':
        return Icons.person_outline;
      default:
        return Icons.person;
    }
  }

  // 🔥 MÉTODO DE DIAGNÓSTICO COMPLETO
  Future<void> _diagnosticarPermissoesCompleto(BuildContext context) async {
    _log('INICIANDO DIAGNÓSTICO COMPLETO');

    try {
      final user = FirebaseAuth.instance.currentUser;
      _log('Usuário logado:', dados: user?.uid ?? 'Ninguém logado');

      if (user == null) {
        _log('❌ ERRO: Ninguém logado!');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Você precisa estar logado!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final caminho = 'usuarios/${widget.userId}/permissoes_usuario/configuracoes';
      _log('Caminho completo:', dados: caminho);

      final docRef = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.userId)
          .collection('permissoes_usuario')
          .doc('configuracoes');

      _log('Tentando ler documento...');
      final doc = await docRef.get();
      _log('Documento existe:', dados: doc.exists);

      if (doc.exists) {
        final dados = doc.data();
        _log('Dados encontrados:', dados: dados);

        dados?.forEach((key, value) {
          debugPrint('   • $key: $value');
        });

        if (context.mounted) {
          _mostrarDialogDiagnostico(context, doc, dados);
        }
      } else {
        _log('⚠️ Documento NÃO existe!');
        if (context.mounted) {
          _mostrarDialogDocumentoNaoEncontrado(context, caminho);
        }
      }

      _log('Testando permissão de escrita...');
      try {
        await docRef.set({'diagnostico_timestamp': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        _log('✅ Permissão de escrita OK!');
        await docRef.update({'diagnostico_timestamp': FieldValue.delete()});
      } catch (e) {
        _log('❌ Erro ao testar escrita:', dados: e.toString());
      }
    } catch (e) {
      _log('❌ ERRO NO DIAGNÓSTICO:', dados: e.toString());
    }
  }

  // 🔥 MÉTODO DE SALVAR PERMISSÕES
  Future<void> _salvarPermissoes(BuildContext context, Map<String, bool> permissoes) async {
    _log('SALVANDO PERMISSÕES');
    _log('Permissões a salvar:', dados: permissoes);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não está logado');

      final docRef = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.userId)
          .collection('permissoes_usuario')
          .doc('configuracoes');

      await docRef.set(permissoes, SetOptions(merge: true));
      _log('✅ Comando set executado com sucesso!');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Permissões salvas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _log('❌ ERRO AO SALVAR:', dados: e.toString());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔥 MÉTODO DE CARREGAR PERMISSÕES
  Future<Map<String, bool>> _carregarPermissoes() async {
    _log('CARREGANDO PERMISSÕES');

    try {
      final docRef = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.userId)
          .collection('permissoes_usuario')
          .doc('configuracoes');

      final doc = await docRef.get();

      if (doc.exists) {
        final dados = doc.data()!;
        _log('✅ Documento encontrado!');
        return dados.map((key, value) => MapEntry(key, value as bool? ?? false));
      } else {
        _log('⚠️ Documento NÃO encontrado - retornando mapa vazio');
        return {};
      }
    } catch (e) {
      _log('❌ ERRO AO CARREGAR:', dados: e.toString());
      return {};
    }
  }

  // 🔥 LISTA COMPLETA DE PERMISSÕES (COM UNIFORMES)
  final List<Map<String, dynamic>> _permissoesList = [
    // ===== AÇÕES - ALUNOS =====
    {
      'titulo': 'Adicionar aluno',
      'descricao': 'Permite adicionar novos alunos',
      'chave': 'pode_adicionar_aluno',
      'icone': Icons.person_add,
      'categoria': 'AÇÕES - ALUNOS',
      'cor': Colors.blue.shade900,
    },
    {
      'titulo': 'Visualizar alunos',
      'descricao': 'Permite ver lista de alunos',
      'chave': 'pode_visualizar_alunos',
      'icone': Icons.visibility,
      'categoria': 'AÇÕES - ALUNOS',
      'cor': Colors.blue.shade900,
    },
    {
      'titulo': 'Editar aluno',
      'descricao': 'Permite editar informações',
      'chave': 'pode_editar_aluno',
      'icone': Icons.edit,
      'categoria': 'AÇÕES - ALUNOS',
      'cor': Colors.blue.shade900,
    },
    {
      'titulo': 'Excluir aluno',
      'descricao': 'Permite remover alunos',
      'chave': 'pode_excluir_aluno',
      'icone': Icons.delete,
      'categoria': 'AÇÕES - ALUNOS',
      'cor': Colors.blue.shade900,
    },
    {
      'titulo': 'Desativar aluno',
      'descricao': 'Tornar alunos inativos',
      'chave': 'pode_desativar_aluno',
      'icone': Icons.person_off,
      'categoria': 'AÇÕES - ALUNOS',
      'cor': Colors.blue.shade900,
    },
    {
      'titulo': 'Ativar alunos',
      'descricao': 'Reativar alunos inativos',
      'chave': 'pode_ativar_alunos',
      'icone': Icons.person_add_alt_1,
      'categoria': 'AÇÕES - ALUNOS',
      'cor': Colors.blue.shade900,
    },
    {
      'titulo': 'Mudar turma',
      'descricao': 'Transferir entre turmas',
      'chave': 'pode_mudar_turma',
      'icone': Icons.switch_account,
      'categoria': 'AÇÕES - ALUNOS',
      'cor': Colors.blue.shade900,
    },

    // ===== AÇÕES - CHAMADA =====
    {
      'titulo': 'Fazer chamada',
      'descricao': 'Registrar chamada',
      'chave': 'pode_fazer_chamada',
      'icone': Icons.checklist,
      'categoria': 'AÇÕES - CHAMADA',
      'cor': Colors.green.shade900,
    },
    {
      'titulo': 'Editar chamada',
      'descricao': 'Editar chamadas',
      'chave': 'pode_editar_chamada',
      'icone': Icons.edit_calendar,
      'categoria': 'AÇÕES - CHAMADA',
      'cor': Colors.green.shade900,
    },
    {
      'titulo': 'Ver lista',
      'descricao': 'Histórico de chamadas',
      'chave': 'pode_ver_lista_de_chamada',
      'icone': Icons.list_alt,
      'categoria': 'AÇÕES - CHAMADA',
      'cor': Colors.green.shade900,
    },

    // ===== AÇÕES - RELATÓRIOS =====
    {
      'titulo': 'Ver relatórios',
      'descricao': 'Visualizar relatórios',
      'chave': 'pode_visualizar_relatorios',
      'icone': Icons.assessment,
      'categoria': 'AÇÕES - RELATÓRIOS',
      'cor': Colors.orange.shade900,
    },

    {
      'titulo': 'Avaliar aluno',
      'descricao': 'Permite avaliar comportamento, disciplina e evolução dos alunos',
      'chave': 'pode_avaliar_aluno',
      'icone': Icons.star_rate_rounded,
      'categoria': 'AVALIAÇÕES',
      'cor': Colors.deepPurple.shade900,
    },

    // ===== AÇÕES - USUÁRIOS =====
    {
      'titulo': 'Gerenciar usuários',
      'descricao': 'Gerenciar usuários',
      'chave': 'pode_gerenciar_usuarios',
      'icone': Icons.people,
      'categoria': 'AÇÕES - USUÁRIOS',
      'cor': Colors.red.shade900,
    },

    // ===== EVENTOS =====
    {
      'titulo': 'Ver eventos',
      'descricao': 'Visualizar lista de eventos',
      'chave': 'pode_ver_eventos',
      'icone': Icons.event,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Criar evento',
      'descricao': 'Criar novos eventos',
      'chave': 'pode_criar_evento',
      'icone': Icons.add_circle,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Editar evento',
      'descricao': 'Editar eventos existentes',
      'chave': 'pode_editar_evento',
      'icone': Icons.edit_calendar,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Excluir evento',
      'descricao': 'Excluir eventos',
      'chave': 'pode_excluir_evento',
      'icone': Icons.delete_forever,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Ver andamento',
      'descricao': 'Ver eventos em andamento',
      'chave': 'pode_ver_eventos_andamento',
      'icone': Icons.pending_actions,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Gerenciar taxas',
      'descricao': 'Gerenciar taxas do evento',
      'chave': 'pode_gerenciar_taxas',
      'icone': Icons.attach_money,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Finalizar evento',
      'descricao': 'Finalizar evento',
      'chave': 'pode_finalizar_evento',
      'icone': Icons.check_circle,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Gerar certificados',
      'descricao': 'Gerar certificados',
      'chave': 'pode_gerar_certificados',
      'icone': Icons.card_membership,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Adicionar aluno eventos',
      'descricao': 'Permite adicionar alunos a eventos',
      'chave': 'pode_adcionar_aluno_a_eventos',
      'icone': Icons.person_add,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },
    {
      'titulo': 'Remover alunos eventos',
      'descricao': 'Permite remover alunos de eventos',
      'chave': 'pode_remover_alunos_de_eventos',
      'icone': Icons.person_remove,
      'categoria': 'EVENTOS',
      'cor': Colors.teal.shade900,
    },

    // ===== VISIBILIDADE =====
    {
      'titulo': 'Associação',
      'descricao': 'Acessar tela de Associação',
      'chave': 'podeAcessarAssociacao',
      'icone': Icons.people_outline,
      'categoria': 'VISIBILIDADE',
      'cor': Colors.purple.shade900,
    },
    {
      'titulo': 'Rifas',
      'descricao': 'Acessar tela de Rifas',
      'chave': 'podeAcessarRifas',
      'icone': Icons.confirmation_number,
      'categoria': 'VISIBILIDADE',
      'cor': Colors.purple.shade900,
    },
    {
      'titulo': 'Eventos',
      'descricao': 'Acessar tela de Eventos',
      'chave': 'podeAcessarEventos',
      'icone': Icons.event,
      'categoria': 'VISIBILIDADE',
      'cor': Colors.purple.shade900,
    },
    {
      'titulo': 'Uniformes',
      'descricao': 'Acessar tela de Uniformes',
      'chave': 'podeAcessarUniformes',
      'icone': Icons.shopping_bag,
      'categoria': 'VISIBILIDADE',
      'cor': Colors.purple.shade900,
    },
    {
      'titulo': 'Inscrições',
      'descricao': 'Acessar tela de Inscrições',
      'chave': 'podeAcessarInscricoes',
      'icone': Icons.app_registration,
      'categoria': 'VISIBILIDADE',
      'cor': Colors.purple.shade900,
    },

    // ===== 🆕 UNIFORMES - AÇÕES ESPECÍFICAS =====
    {
      'titulo': 'Editar vendas',
      'descricao': 'Permite editar vendas de uniformes',
      'chave': 'pode_editar_venda',
      'icone': Icons.edit,
      'categoria': 'UNIFORMES',
      'cor': Colors.green.shade900,
    },
    {
      'titulo': 'Excluir vendas',
      'descricao': 'Permite excluir vendas de uniformes',
      'chave': 'pode_excluir_venda',
      'icone': Icons.delete_forever,
      'categoria': 'UNIFORMES',
      'cor': Colors.green.shade900,
    },
    {
      'titulo': 'Editar pedidos',
      'descricao': 'Permite editar pedidos',
      'chave': 'pode_editar_pedido',
      'icone': Icons.edit_note,
      'categoria': 'UNIFORMES',
      'cor': Colors.green.shade900,
    },
    {
      'titulo': 'Excluir pedidos',
      'descricao': 'Permite excluir pedidos',
      'chave': 'pode_excluir_pedido',
      'icone': Icons.delete_sweep,
      'categoria': 'UNIFORMES',
      'cor': Colors.green.shade900,
    },
    {
      'titulo': 'Gerenciar estoque',
      'descricao': 'Permite gerenciar estoque',
      'chave': 'pode_gerenciar_estoque',
      'icone': Icons.inventory,
      'categoria': 'UNIFORMES',
      'cor': Colors.green.shade900,
    },
  ];

  // 🔥 MÉTODO PARA MOSTRAR DIÁLOGO DE PERMISSÕES
  Future<void> _mostrarDialogPermissoes(BuildContext context) async {
    _log('ABRINDO DIÁLOGO DE PERMISSÕES');

    final permissoesAtuais = await _carregarPermissoes();
    _log('Permissões atuais carregadas:', dados: permissoesAtuais);

    // Agrupa permissões por categoria
    final Map<String, List<Map<String, dynamic>>> permissoesPorCategoria = {};
    for (var permissao in _permissoesList) {
      final categoria = permissao['categoria'] as String;
      if (!permissoesPorCategoria.containsKey(categoria)) {
        permissoesPorCategoria[categoria] = [];
      }
      permissoesPorCategoria[categoria]!.add(permissao);
    }

    // Lista de categorias ordenadas
    final List<String> categorias = [
      'AÇÕES - ALUNOS',
      'AÇÕES - CHAMADA',
      'AÇÕES - RELATÓRIOS',
      'AVALIAÇÕES',
      'AÇÕES - USUÁRIOS',
      'EVENTOS',
      'VISIBILIDADE',
      'UNIFORMES',
    ];

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        Map<String, bool> permissoesTemp = {
          for (var p in _permissoesList)
            p['chave']: permissoesAtuais[p['chave']] ?? false,
        };

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: Column(
                  children: [
                    // Header do Dialog
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Permissões Individuais',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // Grid de Permissões
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.9,
                          ),
                          itemCount: categorias.length,
                          itemBuilder: (context, index) {
                            final categoria = categorias[index];
                            final permissoesDaCategoria = permissoesPorCategoria[categoria] ?? [];

                            return _buildCategoriaCard(
                              categoria: categoria,
                              permissoes: permissoesDaCategoria,
                              permissoesTemp: permissoesTemp,
                              onChanged: (chave, valor) {
                                setState(() {
                                  permissoesTemp[chave] = valor;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // Botão Salvar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _salvarPermissoes(context, permissoesTemp);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Salvar Permissões'),
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

  // 🎨 Widget para o Card de Categoria
  Widget _buildCategoriaCard({
    required String categoria,
    required List<Map<String, dynamic>> permissoes,
    required Map<String, bool> permissoesTemp,
    required Function(String, bool) onChanged,
  }) {
    Color getCorCategoria(String categoria) {
      if (categoria.contains('ALUNOS')) return Colors.blue.shade900;
      if (categoria.contains('CHAMADA')) return Colors.green.shade900;
      if (categoria.contains('RELATÓRIOS')) return Colors.orange.shade900;
      if (categoria.contains('USUÁRIOS')) return Colors.red.shade900;
      if (categoria.contains('EVENTOS')) return Colors.teal.shade900;
      if (categoria.contains('VISIBILIDADE')) return Colors.purple.shade900;
      if (categoria.contains('UNIFORMES')) return Colors.green.shade900; // 🆕
      return Colors.grey.shade900;
    }

    IconData getIconCategoria(String categoria) {
      if (categoria.contains('ALUNOS')) return Icons.people;
      if (categoria.contains('CHAMADA')) return Icons.checklist;
      if (categoria.contains('RELATÓRIOS')) return Icons.assessment;
      if (categoria.contains('USUÁRIOS')) return Icons.admin_panel_settings;
      if (categoria.contains('EVENTOS')) return Icons.event;
      if (categoria.contains('VISIBILIDADE')) return Icons.visibility;
      if (categoria.contains('UNIFORMES')) return Icons.shopping_bag; // 🆕
      return Icons.category;
    }

    final corCategoria = getCorCategoria(categoria);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho da Categoria
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: corCategoria.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    getIconCategoria(categoria),
                    size: 16,
                    color: corCategoria,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getNomeCategoriaAmigavel(categoria),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: corCategoria,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Lista de Permissões
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: permissoes.map((permissao) {
                    final chave = permissao['chave'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => onChanged(chave, !permissoesTemp[chave]!),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: permissoesTemp[chave]!
                                ? corCategoria.withOpacity(0.1)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: permissoesTemp[chave]!
                                  ? corCategoria.withOpacity(0.3)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                permissoesTemp[chave]! ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 16,
                                color: permissoesTemp[chave]! ? corCategoria : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  permissao['titulo'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: permissoesTemp[chave]!
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: permissoesTemp[chave]! ? corCategoria : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNomeCategoriaAmigavel(String categoria) {
    if (categoria == 'VISIBILIDADE') return 'Telas';
    if (categoria == 'UNIFORMES') return 'Uniformes';
    return categoria.replaceAll('AÇÕES - ', '');
  }

  void _mostrarDialogDocumentoNaoEncontrado(BuildContext context, String caminho) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔍 Diagnóstico'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DOCUMENTO NÃO ENCONTRADO!',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 16),
            Text('Caminho: $caminho'),
            const SizedBox(height: 8),
            const Text('Possíveis causas:'),
            const Text('• Nunca salvou permissões para este usuário'),
            const Text('• Erro ao salvar (verifique regras do Firestore)'),
            const Text('• Usuário sem permissões configuradas'),
            const SizedBox(height: 16),
            const Text('Solução: Tente salvar as permissões primeiro!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _mostrarDialogPermissoes(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
            ),
            child: const Text('Configurar Agora'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogDiagnostico(BuildContext context, DocumentSnapshot doc, Map<String, dynamic>? dados) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔍 Diagnóstico de Permissões'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('DOCUMENTO ENCONTRADO!',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 16),
              Text('Caminho: usuarios/${widget.userId}/permissoes_usuario/configuracoes'),
              const SizedBox(height: 8),
              Text('Existe: ${doc.exists}'),
              const SizedBox(height: 16),
              const Text('DADOS SALVOS:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...?dados?.entries.map((e) =>
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${e.key}:',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: e.value == true ? Colors.green.shade100 : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            e.value.toString(),
                            style: TextStyle(
                              color: e.value == true ? Colors.green.shade900 : Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
              ).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _mostrarDialogPermissoes(context);
            },
            child: const Text('Editar Permissões'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Detalhes do Usuário',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_rounded),
            onPressed: () => _diagnosticarPermissoesCompleto(context),
            tooltip: 'Diagnosticar permissões',
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditarUsuarioScreen(userId: widget.userId),
                ),
              );
            },
            tooltip: 'Editar usuário',
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(widget.userId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState('Carregando usuário...');
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildEmptyState();
          }

          final data = snapshot.data!.data()!;
          final fotoUrl = data['foto_url'] as String?;
          final nomeCompleto =
              data['nome_completo'] ?? data['name'] ?? 'Nome não informado';
          final email = data['email'] ?? 'Email não informado';
          final tipo = data['tipo'] ?? 'Tipo não informado';
          final pesoPermissao = data['peso_permissao'] ?? 0;
          final statusConta = data['status_conta'] ?? 'pendente';
          final contato = data['contato'] ?? 'Contato não informado';
          final dataCadastro = data['data_cadastro'] as Timestamp?;
          final ultimaAtualizacao = data['ultima_atualizacao'] as Timestamp?;
          final aprovadoEm = data['aprovado_em'] as Timestamp?;
          final aprovadoPor = data['aprovado_por'] as String?;
          final aprovadoPorNome = data['aprovado_por_nome'] as String?;

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final wide = constraints.maxWidth >= 960;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 20,
                  compact ? 12 : 18,
                  compact ? 12 : 20,
                  28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildUserHero(
                          fotoUrl: fotoUrl,
                          nome: nomeCompleto.toString(),
                          email: email.toString(),
                          tipo: tipo.toString(),
                          status: statusConta.toString(),
                          peso: pesoPermissao,
                          compact: compact,
                        ),
                        const SizedBox(height: 14),
                        _buildActionStrip(compact),
                        const SizedBox(height: 14),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    _buildAccessCard(
                                      tipo: tipo.toString(),
                                      peso: pesoPermissao,
                                    ),
                                    const SizedBox(height: 14),
                                    _buildContactCard(
                                      contato: contato.toString(),
                                      email: email.toString(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    _buildStatusCard(statusConta.toString()),
                                    const SizedBox(height: 14),
                                    _buildDatesCard(
                                      dataCadastro: dataCadastro,
                                      ultimaAtualizacao: ultimaAtualizacao,
                                      aprovadoEm: aprovadoEm,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _buildStatusCard(statusConta.toString()),
                          const SizedBox(height: 14),
                          _buildAccessCard(
                            tipo: tipo.toString(),
                            peso: pesoPermissao,
                          ),
                          const SizedBox(height: 14),
                          _buildContactCard(
                            contato: contato.toString(),
                            email: email.toString(),
                          ),
                          const SizedBox(height: 14),
                          _buildDatesCard(
                            dataCadastro: dataCadastro,
                            ultimaAtualizacao: ultimaAtualizacao,
                            aprovadoEm: aprovadoEm,
                          ),
                        ],
                        if (aprovadoPor != null || aprovadoPorNome != null) ...[
                          const SizedBox(height: 14),
                          _buildApprovalCard(
                            aprovadoPor: aprovadoPor,
                            aprovadoPorNome: aprovadoPorNome,
                          ),
                        ],
                        const SizedBox(height: 14),
                        _buildIdCard(),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildUserHero({
    required String? fotoUrl,
    required String nome,
    required String email,
    required String tipo,
    required String status,
    required int peso,
    required bool compact,
  }) {
    final tipoColor = _getTipoColor(tipo);
    final statusColor = _getStatusColor(status);
    final inicial = nome.trim().isNotEmpty ? nome.trim().substring(0, 1).toUpperCase() : '?';

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 26 : 32),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;

          final avatar = Container(
            width: compact ? 94 : 118,
            height: compact ? 94 : 118,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(compact ? 32 : 40),
              border: Border.all(color: Colors.white.withOpacity(0.20), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 30 : 38),
              child: fotoUrl != null && fotoUrl.isNotEmpty
                  ? CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Text(
                    inicial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
                  : Center(
                child: Text(
                  inicial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );

          final info = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                nome,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 24 : 33,
                  height: 1.04,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                email,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: compact ? 12.5 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(_getTipoIcon(tipo), tipo.toUpperCase()),
                  _whiteChip(Icons.security_rounded, 'PESO $peso'),
                  _whiteChip(Icons.circle, _formatStatus(status).toUpperCase()),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [avatar, const SizedBox(height: 14), info],
            );
          }

          return Row(
            children: [
              avatar,
              const SizedBox(width: 18),
              Expanded(child: info),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tipoColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.22)),
                ),
                child: Icon(_getTipoIcon(tipo), color: Colors.white, size: 30),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _whiteChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStrip(bool compact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 420;

        final permissions = ElevatedButton.icon(
          onPressed: () => _mostrarDialogPermissoes(context),
          icon: const Icon(Icons.security_rounded),
          label: const Text('PERMISSÕES'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade900,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

        final edit = OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EditarUsuarioScreen(userId: widget.userId),
              ),
            );
          },
          icon: const Icon(Icons.edit_rounded),
          label: const Text('EDITAR'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey.shade800,
            side: BorderSide(color: Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

        final diagnostic = OutlinedButton.icon(
          onPressed: () => _diagnosticarPermissoesCompleto(context),
          icon: const Icon(Icons.bug_report_rounded),
          label: const Text('DIAGNÓSTICO'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blue.shade800,
            side: BorderSide(color: Colors.blue.shade100),
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );

        if (tiny) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: permissions),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: edit),
                  const SizedBox(width: 8),
                  Expanded(child: diagnostic),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 2, child: permissions),
            const SizedBox(width: 8),
            Expanded(child: edit),
            const SizedBox(width: 8),
            Expanded(child: diagnostic),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(String status) {
    final color = _getStatusColor(status);

    return _premiumCard(
      title: 'Status da conta',
      icon: Icons.account_circle_rounded,
      color: color,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.09),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withOpacity(0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: color, size: 13),
              const SizedBox(width: 7),
              Text(
                _formatStatus(status).toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessCard({
    required String tipo,
    required int peso,
  }) {
    final isAdmin = peso >= 90;
    final color = isAdmin ? Colors.red : Colors.blue;

    return _premiumCard(
      title: 'Acesso e permissões',
      icon: Icons.admin_panel_settings_rounded,
      color: color,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.08),
                  color.withOpacity(0.14),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                Icon(
                  isAdmin ? Icons.stars_rounded : Icons.security_rounded,
                  color: color,
                  size: 38,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAdmin ? 'Acesso administrativo' : 'Permissão personalizada',
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tipo: ${tipo.toUpperCase()} • Peso $peso/100',
                        style: TextStyle(
                          color: color,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isAdmin) ...[
            const SizedBox(height: 10),
            Text(
              'Configure permissões específicas no botão “Permissões”.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required String contato,
    required String email,
  }) {
    return _premiumCard(
      title: 'Contato',
      icon: Icons.contact_phone_rounded,
      color: Colors.green,
      child: Column(
        children: [
          _infoLine(Icons.phone_rounded, 'Telefone/WhatsApp', contato),
          const Divider(height: 20),
          _infoLine(Icons.email_rounded, 'E-mail', email),
        ],
      ),
    );
  }

  Widget _buildDatesCard({
    required Timestamp? dataCadastro,
    required Timestamp? ultimaAtualizacao,
    required Timestamp? aprovadoEm,
  }) {
    return _premiumCard(
      title: 'Registros',
      icon: Icons.event_note_rounded,
      color: Colors.orange,
      child: Column(
        children: [
          _infoLine(Icons.calendar_today_rounded, 'Data de cadastro', _formatTimestamp(dataCadastro)),
          const Divider(height: 20),
          _infoLine(Icons.update_rounded, 'Última atualização', _formatTimestamp(ultimaAtualizacao)),
          if (aprovadoEm != null) ...[
            const Divider(height: 20),
            _infoLine(Icons.verified_rounded, 'Aprovado em', _formatTimestamp(aprovadoEm)),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalCard({
    required String? aprovadoPor,
    required String? aprovadoPorNome,
  }) {
    return _premiumCard(
      title: 'Aprovação',
      icon: Icons.verified_user_rounded,
      color: Colors.purple,
      child: Column(
        children: [
          if (aprovadoPorNome != null)
            _infoLine(Icons.person_rounded, 'Aprovado por', aprovadoPorNome),
          if (aprovadoPor != null) ...[
            if (aprovadoPorNome != null) const Divider(height: 20),
            _infoLine(Icons.fingerprint_rounded, 'ID do aprovador', '${aprovadoPor.substring(0, aprovadoPor.length > 8 ? 8 : aprovadoPor.length)}...'),
          ],
        ],
      ),
    );
  }

  Widget _buildIdCard() {
    return _premiumCard(
      title: 'Identificação',
      icon: Icons.fingerprint_rounded,
      color: Colors.grey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            'ID: ${widget.userId}',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use este ID para referenciar o usuário em outros sistemas.',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.032),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(title: title, icon: icon, color: color),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _cardHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoLine(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: Colors.grey.shade900,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.red.shade900),
            const SizedBox(height: 14),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_rounded, size: 62, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'Usuário não encontrado',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusInfo(String title, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateInfo(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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