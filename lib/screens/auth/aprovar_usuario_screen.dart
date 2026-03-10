import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AprovarUsuarioScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;
  final Map<String, dynamic> adminData;

  const AprovarUsuarioScreen({
    super.key,
    required this.userId,
    required this.userData,
    required this.adminData,
  });

  @override
  State<AprovarUsuarioScreen> createState() => _AprovarUsuarioScreenState();
}

class _AprovarUsuarioScreenState extends State<AprovarUsuarioScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 🔥 Tipos carregados do Firestore (cache local)
  List<Map<String, dynamic>> _tiposUsuarios = [];
  String _selectedTipo = 'aluno';
  bool _carregando = true;
  bool _aprovando = false;
  bool _rejeitando = false;

  @override
  void initState() {
    super.initState();
    _carregarTiposUsuarios();
  }

  // 🔥 CARREGA TIPOS DO FIRESTORE (configurável)
  Future<void> _carregarTiposUsuarios() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('tipos_usuario').get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final tipos = data['tipos'] as List<dynamic>?;

        if (tipos != null && tipos.isNotEmpty) {
          setState(() {
            _tiposUsuarios = tipos.map((t) => Map<String, dynamic>.from(t)).toList();
            _carregando = false;
          });

          // Define o tipo padrão (primeiro ou o que já estava)
          final tipoAtual = widget.userData['tipo'];
          if (tipoAtual != null && _tiposUsuarios.any((t) => t['tipo'] == tipoAtual)) {
            _selectedTipo = tipoAtual;
          } else {
            _selectedTipo = _tiposUsuarios.first['tipo'];
          }

          return;
        }
      }

      // Fallback para tipos padrão se não encontrar no Firestore
      _carregarTiposFallback();

    } catch (e) {
      print('Erro ao carregar tipos: $e');
      _carregarTiposFallback();
    }
  }

  // 🔥 Tipos padrão (fallback)
  void _carregarTiposFallback() {
    setState(() {
      _tiposUsuarios = [
        {
          'tipo': 'aluno',
          'peso': 10,
          'descricao': 'Acesso básico ao conteúdo',
          'icone': 'person',
          'cor': '#4CAF50' // verde
        },
        {
          'tipo': 'monitor',
          'peso': 30,
          'descricao': 'Pode auxiliar alunos',
          'icone': 'supervised_user_circle',
          'cor': '#2196F3' // azul
        },
        {
          'tipo': 'professor',
          'peso': 50,
          'descricao': 'Cadastra alunos e agenda aulas',
          'icone': 'school',
          'cor': '#FF9800' // laranja
        },
        {
          'tipo': 'administrador',
          'peso': 100,
          'descricao': 'Acesso total ao sistema',
          'icone': 'admin_panel_settings',
          'cor': '#F44336' // vermelho
        },
      ];
      _carregando = false;

      final tipoAtual = widget.userData['tipo'];
      if (tipoAtual != null && _tiposUsuarios.any((t) => t['tipo'] == tipoAtual)) {
        _selectedTipo = tipoAtual;
      } else {
        _selectedTipo = _tiposUsuarios.first['tipo'];
      }
    });
  }

  // 🔥 Converte string icone para IconData
  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'person':
        return Icons.person;
      case 'supervised_user_circle':
        return Icons.supervised_user_circle;
      case 'school':
        return Icons.school;
      case 'admin_panel_settings':
        return Icons.admin_panel_settings;
      default:
        return Icons.person;
    }
  }

  // 🔥 Converte cor hex para Color
  Color _getColorFromHex(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  Color _getTipoColor(Map<String, dynamic> tipo) {
    final corHex = tipo['cor'] as String?;
    if (corHex != null && corHex.isNotEmpty) {
      return _getColorFromHex(corHex);
    }

    // Fallback por nome
    switch (tipo['tipo']) {
      case 'administrador':
        return Colors.red;
      case 'professor':
        return Colors.orange;
      case 'monitor':
        return Colors.blue;
      case 'aluno':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getTipoIcon(Map<String, dynamic> tipo) {
    final iconName = tipo['icone'] as String?;
    if (iconName != null && iconName.isNotEmpty) {
      return _getIconData(iconName);
    }
    return Icons.person;
  }

  String _getTipoDescricao(Map<String, dynamic> tipo) {
    return tipo['descricao'] ?? 'Sem descrição';
  }

  int _getPesoTipo(Map<String, dynamic> tipo) {
    return tipo['peso'] ?? 0;
  }

  Future<void> _aprovarUsuario() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _mostrarErro('Usuário não autenticado');
      return;
    }

    setState(() => _aprovando = true);

    try {
      final tipoSelecionado = _tiposUsuarios.firstWhere(
            (t) => t['tipo'] == _selectedTipo,
        orElse: () => _tiposUsuarios.first,
      );

      final adminNome = widget.adminData['nome_completo'] ?? 'Administrador';
      final adminId = currentUser.uid;

      await _firestore.collection('usuarios').doc(widget.userId).update({
        'tipo': _selectedTipo,
        'peso_permissao': _getPesoTipo(tipoSelecionado),
        'status_conta': 'ativa',
        'aprovado_por': adminId,
        'aprovado_por_nome': adminNome,
        'aprovado_em': FieldValue.serverTimestamp(),
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _mostrarSucesso('Usuário aprovado com sucesso!');
        await Future.delayed(const Duration(milliseconds: 1500));
        Navigator.pop(context, true);
      }
    } catch (e) {
      _mostrarErro('Erro ao aprovar: $e');
    } finally {
      if (mounted) {
        setState(() => _aprovando = false);
      }
    }
  }

  Future<void> _rejeitarUsuario() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejeitar Usuário'),
        content: const Text(
          'Tem certeza que deseja rejeitar este usuário? '
              'Ele será marcado como "bloqueado" e não poderá acessar o sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    setState(() => _rejeitando = true);

    try {
      await _firestore.collection('usuarios').doc(widget.userId).update({
        'status_conta': 'bloqueada',
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _mostrarSucesso('Usuário rejeitado!', cor: Colors.orange);
        await Future.delayed(const Duration(milliseconds: 1500));
        Navigator.pop(context, true);
      }
    } catch (e) {
      _mostrarErro('Erro ao rejeitar: $e');
    } finally {
      if (mounted) {
        setState(() => _rejeitando = false);
      }
    }
  }

  void _mostrarSucesso(String mensagem, {Color cor = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativa':
        return Colors.green;
      case 'pendente':
        return Colors.orange;
      case 'bloqueada':
        return Colors.red;
      case 'inativa':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'ativa':
        return Icons.check_circle;
      case 'pendente':
        return Icons.pending;
      case 'bloqueada':
        return Icons.block;
      case 'inativa':
        return Icons.person_off;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final data = widget.userData;
    final nome = data['nome_completo'] ?? 'Nome não informado';
    final email = data['email'] ?? 'Email não informado';
    final contato = data['contato'] ?? 'Não informado';
    final fotoUrl = data['foto_url'];
    final statusAtual = data['status_conta'] ?? 'pendente';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprovar Usuário'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner de status atual
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _getStatusColor(statusAtual).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getStatusColor(statusAtual)),
              ),
              child: Row(
                children: [
                  Icon(
                    _getStatusIcon(statusAtual),
                    color: _getStatusColor(statusAtual),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status atual: ${statusAtual.toUpperCase()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(statusAtual),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tipo: ${data['tipo'] ?? 'não definido'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Card de informações do usuário
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.primaryColor.withOpacity(0.1),
                      radius: 30,
                      backgroundImage: fotoUrl != null && fotoUrl.toString().isNotEmpty
                          ? NetworkImage(fotoUrl.toString()) as ImageProvider
                          : null,
                      child: fotoUrl == null || fotoUrl.toString().isEmpty
                          ? Text(
                        nome.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Contato: $contato',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Definir Tipo de Acesso',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecione o nível de permissão para este usuário:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Cards de seleção de tipo (dinâmico do Firestore)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _tiposUsuarios.map((tipo) => _buildTipoCard(tipo, theme)).toList(),
            ),

            const SizedBox(height: 24),

            // Resumo da seleção
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _getTipoIcon(_tiposUsuarios.firstWhere((t) => t['tipo'] == _selectedTipo)),
                      color: _getTipoColor(_tiposUsuarios.firstWhere((t) => t['tipo'] == _selectedTipo)),
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedTipo[0].toUpperCase() + _selectedTipo.substring(1),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _getTipoColor(_tiposUsuarios.firstWhere((t) => t['tipo'] == _selectedTipo)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getTipoDescricao(_tiposUsuarios.firstWhere((t) => t['tipo'] == _selectedTipo)),
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Peso: ${_getPesoTipo(_tiposUsuarios.firstWhere((t) => t['tipo'] == _selectedTipo))}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      backgroundColor: _getTipoColor(_tiposUsuarios.firstWhere((t) => t['tipo'] == _selectedTipo)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Informações do aprovador
            const Text(
              'Informações da Aprovação',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      'Aprovador:',
                      widget.adminData['nome_completo'] ?? 'Administrador',
                    ),
                    const SizedBox(height: 4),
                    _buildInfoRow(
                      'Data/Hora:',
                      DateTime.now().toLocal().toString().substring(0, 16),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _rejeitando ? null : _rejeitarUsuario,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _rejeitando
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.close, size: 20),
                    label: Text(_rejeitando ? 'REJEITANDO...' : 'REJEITAR'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _aprovando ? null : _aprovarUsuario,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _aprovando
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.check, size: 20),
                    label: Text(_aprovando ? 'APROVANDO...' : 'APROVAR USUÁRIO'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoCard(Map<String, dynamic> tipo, ThemeData theme) {
    final String tipoNome = tipo['tipo'];
    final int peso = tipo['peso'] ?? 0;
    final String descricao = tipo['descricao'] ?? '';
    final IconData icone = _getTipoIcon(tipo);
    final Color cor = _getTipoColor(tipo);
    final bool isSelected = _selectedTipo == tipoNome;

    return InkWell(
      onTap: () {
        if (!_aprovando && !_rejeitando) {
          setState(() => _selectedTipo = tipoNome);
        }
      },
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? cor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? cor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icone, color: cor, size: 24),
            const SizedBox(height: 8),
            Text(
              tipoNome[0].toUpperCase() + tipoNome.substring(1),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cor,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Peso: $peso',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 10,
              ),
            ),
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.check_circle, color: Colors.green, size: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
        ),
      ],
    );
  }
}