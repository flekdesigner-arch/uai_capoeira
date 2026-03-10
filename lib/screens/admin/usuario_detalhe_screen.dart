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
      'AÇÕES - USUÁRIOS',
      'EVENTOS',
      'VISIBILIDADE',
      'UNIFORMES',  // 🆕 NOVA CATEGORIA
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
      appBar: AppBar(
        title: const Text('Detalhes do Usuário'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => _diagnosticarPermissoesCompleto(context),
            tooltip: 'Diagnosticar Permissões',
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditarUsuarioScreen(userId: widget.userId),
                ),
              );
            },
          )
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('usuarios').doc(widget.userId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Usuário não encontrado."));
          }

          final data = snapshot.data!.data()!;
          final fotoUrl = data['foto_url'] as String?;
          final nomeCompleto = data['nome_completo'] ?? data['name'] ?? 'Nome não informado';
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabeçalho com foto e informações básicas
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey.shade300,
                        child: ClipOval(
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? CachedNetworkImage(
                            imageUrl: fotoUrl,
                            fit: BoxFit.cover,
                            width: 120,
                            height: 120,
                            placeholder: (context, url) => const CircularProgressIndicator(),
                            errorWidget: (context, url, error) => const Icon(Icons.person, size: 60, color: Colors.white),
                          )
                              : const Icon(Icons.person, size: 60, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        nomeCompleto,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getTipoColor(tipo).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getTipoIcon(tipo), size: 16, color: _getTipoColor(tipo)),
                            const SizedBox(width: 8),
                            Text(
                              tipo.toUpperCase(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _getTipoColor(tipo),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Status da Conta
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status da Conta',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: _buildStatusInfo(
                            'Status',
                            _formatStatus(statusConta),
                            _getStatusColor(statusConta),
                            Icons.account_circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Informações de Permissões
                Card(
                  elevation: 2,
                  shadowColor: Colors.black.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cabeçalho com título e botão alinhados
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.admin_panel_settings,
                                    color: Colors.red.shade900,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Acessos e ',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.shade100.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () => _mostrarDialogPermissoes(context),
                                icon: const Icon(Icons.security, size: 18),
                                label: const Text(
                                  'Permissões',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade900,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Divisor sutil
                        Container(
                          height: 1,
                          color: Colors.grey.shade200,
                        ),

                        const SizedBox(height: 24),

                        // Seção de Nível de Acesso
                        Text(
                          'NÍVEL DE ACESSO',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.2,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Card de peso de permissão
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: pesoPermissao >= 90
                                  ? [Colors.red.shade50, Colors.red.shade100]
                                  : [Colors.blue.shade50, Colors.blue.shade100],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: pesoPermissao >= 90
                                  ? Colors.red.shade200
                                  : Colors.blue.shade200,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Peso da Permissão',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: pesoPermissao >= 90
                                            ? Colors.red.shade900
                                            : Colors.blue.shade900,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          pesoPermissao.toString(),
                                          style: TextStyle(
                                            fontSize: 36,
                                            fontWeight: FontWeight.bold,
                                            color: pesoPermissao >= 90
                                                ? Colors.red.shade900
                                                : Colors.blue.shade900,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '/ 100',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: pesoPermissao >= 90
                                                ? Colors.red.shade700
                                                : Colors.blue.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  pesoPermissao >= 90
                                      ? Icons.admin_panel_settings
                                      : Icons.security,
                                  size: 40,
                                  color: pesoPermissao >= 90
                                      ? Colors.red.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Badge de Acesso Administrativo (apenas para peso >= 90)
                        if (pesoPermissao >= 90) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.stars,
                                    color: Colors.red.shade900,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Acesso Administrativo Total',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Este usuário possui privilégios administrativos completos',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          // Informação adicional sobre permissões
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
                                  Icons.info_outline,
                                  size: 20,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Configure permissões específicas clicando no botão "Permissões"',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Informações de Contato
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contato',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone, color: Colors.blue),
                          title: const Text('Telefone/WhatsApp'),
                          subtitle: Text(contato),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.email, color: Colors.green),
                          title: const Text('E-mail'),
                          subtitle: Text(email),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Informações de Datas
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registros de Datas',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildDateInfo(
                          'Data de Cadastro',
                          _formatTimestamp(dataCadastro),
                          Icons.calendar_today,
                        ),
                        _buildDateInfo(
                          'Última Atualização',
                          _formatTimestamp(ultimaAtualizacao),
                          Icons.update,
                        ),
                        if (aprovadoEm != null) ...[
                          _buildDateInfo(
                            'Aprovado em',
                            _formatTimestamp(aprovadoEm),
                            Icons.verified,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Informações de Aprovação
                if (aprovadoPor != null || aprovadoPorNome != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aprovação',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (aprovadoPorNome != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person, color: Colors.purple),
                              title: const Text('Aprovado por'),
                              subtitle: Text(aprovadoPorNome),
                            ),
                          if (aprovadoPor != null)
                            Text(
                              'ID: ${aprovadoPor!.substring(0, 8)}...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ID do Usuário
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Identificação',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          'ID: ${widget.userId}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use este ID para referenciar o usuário em outros sistemas',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
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