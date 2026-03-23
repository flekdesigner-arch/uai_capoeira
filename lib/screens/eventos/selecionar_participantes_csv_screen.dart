// lib/screens/eventos/selecionar_participantes_csv_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/google_sheets_oauth_service.dart';
import 'vincular_certificados_drive_screen.dart'; // 👈 NOVA TELA

class SelecionarParticipantesCsvScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;

  const SelecionarParticipantesCsvScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<SelecionarParticipantesCsvScreen> createState() => _SelecionarParticipantesCsvScreenState();
}

class _SelecionarParticipantesCsvScreenState extends State<SelecionarParticipantesCsvScreen> {
  final Map<String, Map<String, dynamic>> _participantes = {};
  bool _isLoading = true;
  bool _isGerandoCsv = false;
  bool _isEnviando = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _cacheCpf = {};

  // Estatísticas
  int get _totalParticipantes => _participantes.length;
  int get _selecionadosCount => _participantes.values.where((p) => p['selecionado'] == true).length;
  bool get _todosSelecionados => _participantes.isNotEmpty && _participantes.values.every((p) => p['selecionado'] == true);
  int get _totalComGraduacao => _participantes.values.where((p) => p['graduacao_nova'].isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _carregarParticipantes();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  Future<void> _carregarParticipantes() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('participacoes_eventos_em_andamento')
          .where('evento_id', isEqualTo: widget.eventoId)
          .orderBy('aluno_nome')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final alunoId = data['aluno_id'] ?? '';

        // Buscar foto do aluno
        String? fotoUrl;
        try {
          final alunoDoc = await FirebaseFirestore.instance
              .collection('alunos')
              .doc(alunoId)
              .get();
          fotoUrl = alunoDoc.data()?['foto_perfil_aluno']?.toString();
        } catch (e) {
          debugPrint('Erro ao buscar foto: $e');
        }

        _participantes[doc.id] = {
          'id': doc.id,
          'aluno_id': alunoId,
          'aluno_nome': data['aluno_nome'] ?? '',
          'graduacao_nova': data['graduacao_nova']?.toString() ?? '',
          'selecionado': false,
          'cpf': '',
          'foto': fotoUrl,
          'link_certificado': data['link_certificado']?.toString() ?? '', // 👈 JÁ CARREGA SE TIVER
        };
      }
      setState(() {});
    } catch (e) {
      _mostrarMensagem('Erro ao carregar: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String> _buscarCpf(String alunoId) async {
    if (_cacheCpf.containsKey(alunoId)) return _cacheCpf[alunoId]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('alunos').doc(alunoId).get();
      final cpf = doc.data()?['cpf']?.toString() ?? '0';
      _cacheCpf[alunoId] = cpf;
      return cpf;
    } catch (e) {
      return '0';
    }
  }

  void _selecionarTodos(bool? selecionado) {
    setState(() {
      for (var entry in _participantes.entries) {
        entry.value['selecionado'] = selecionado ?? false;
      }
    });
  }

  void _mostrarMensagem(String texto, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ============================================================
  // AÇÕES PRINCIPAIS
  // ============================================================
  Future<void> _enviarViaAPI() async {
    final selecionados = _participantes.values.where((p) => p['selecionado'] == true).toList();
    if (selecionados.isEmpty) {
      _mostrarMensagem('Selecione pelo menos um participante', Colors.orange);
      return;
    }

    setState(() => _isEnviando = true);
    try {
      for (var p in selecionados) p['cpf'] = await _buscarCpf(p['aluno_id']);
      final resultado = await GoogleSheetsOAuthService().adicionarParticipantes(selecionados);
      _mostrarMensagem(resultado['mensagem'], resultado['sucesso'] ? Colors.green : Colors.red);
      if (resultado['sucesso']) _selecionarTodos(false);
    } finally {
      setState(() => _isEnviando = false);
    }
  }

  Future<void> _gerarCsv() async {
    final selecionados = _participantes.values.where((p) => p['selecionado'] == true).toList();
    if (selecionados.isEmpty) {
      _mostrarMensagem('Selecione pelo menos um participante', Colors.orange);
      return;
    }

    setState(() => _isGerandoCsv = true);
    try {
      for (var p in selecionados) p['cpf'] = await _buscarCpf(p['aluno_id']);

      List<List<String>> linhas = [['NOME', 'CPF', 'GRADUAÇÃO']];
      for (var p in selecionados) {
        linhas.add([p['aluno_nome'], p['cpf'], p['graduacao_nova'].isEmpty ? 'SEM GRADUAÇÃO' : p['graduacao_nova']]);
      }

      String csv = linhas.map((linha) => linha.map((campo) {
        if (campo.contains(',') || campo.contains('"') || campo.contains('\n')) {
          return '"${campo.replaceAll('"', '""')}"';
        }
        return campo;
      }).join(',')).join('\n');

      final bom = [0xEF, 0xBB, 0xBF];
      List<int> bytes = [...bom, ...csv.codeUnits];

      final tempDir = await getTemporaryDirectory();
      final dataHora = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'participantes_${widget.eventoNome.replaceAll(' ', '_')}_$dataHora.csv';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Lista de participantes');

      _mostrarMensagem('✅ CSV gerado com ${selecionados.length} participantes!', Colors.green);
      _selecionarTodos(false);
    } catch (e) {
      _mostrarMensagem('Erro ao gerar CSV', Colors.red);
    } finally {
      setState(() => _isGerandoCsv = false);
    }
  }

  // 👇 NOVO MÉTODO: Abrir tela de vincular certificados
  void _abrirVincularCertificados() {
    final selecionados = _participantes.values.where((p) => p['selecionado'] == true).toList();

    if (selecionados.isEmpty) {
      _mostrarMensagem('Selecione pelo menos um participante', Colors.orange);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VincularCertificadosDriveScreen(
          participantes: selecionados,
          eventoId: widget.eventoId,
          eventoNome: widget.eventoNome,
        ),
      ),
    ).then((atualizar) {
      if (atualizar == true) {
        _carregarParticipantes(); // Recarrega a lista se voltou com sucesso
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.eventoNome,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Selecionar participantes',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 👇 NOVO BOTÃO DE CERTIFICADOS (Ícone do Google Drive)
          if (_selecionadosCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(Icons.drive_folder_upload, color: Colors.white),
                onPressed: _abrirVincularCertificados,
                tooltip: 'Vincular certificados do Drive',
              ),
            ),

          // Botão "Todos" existente
          if (_participantes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Text('  Todos', style: TextStyle(color: Colors.white)),
                  Checkbox(
                    value: _todosSelecionados,
                    onChanged: _selecionarTodos,
                    activeColor: Colors.white,
                    checkColor: Colors.red.shade900,
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // 🔝 PAINEL DE ESTATÍSTICAS
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.people,
                    value: '$_totalParticipantes',
                    label: 'Total',
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.check_circle,
                    value: '$_selecionadosCount',
                    label: 'Selecionados',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.school,
                    value: '$_totalComGraduacao',
                    label: 'Com graduação',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
          ),

          // 🔍 BARRA DE PESQUISA
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar participante...',
                prefixIcon: const Icon(Icons.search, color: Colors.red),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red),
                  onPressed: () => _searchController.clear(),
                )
                    : null,
              ),
            ),
          ),

          // 🎯 BOTÕES DE AÇÃO (só aparecem se houver selecionados)
          if (_selecionadosCount > 0)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          onPressed: _gerarCsv,
                          isLoading: _isGerandoCsv,
                          icon: Icons.file_download,
                          label: 'BAIXAR CSV',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          onPressed: _enviarViaAPI,
                          isLoading: _isEnviando,
                          icon: Icons.cloud_upload,
                          label: 'ENVIAR PLANILHA',
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),

                  // 👇 BOTÃO EXTRA DE CERTIFICADO (opcional, pode manter ou remover)
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _abrirVincularCertificados,
                      icon: const Icon(Icons.drive_folder_upload),
                      label: Text(
                        'VINCULAR CERTIFICADOS DO DRIVE (${_selecionadosCount})',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 👥 LISTA DE PARTICIPANTES
          Expanded(
            child: _participantes.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _participantes.length,
              itemBuilder: (context, index) {
                final entry = _participantes.entries.elementAt(index);
                final p = entry.value;

                if (_searchQuery.isNotEmpty && !p['aluno_nome'].toLowerCase().contains(_searchQuery)) {
                  return const SizedBox.shrink();
                }

                return _buildParticipantCard(p, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({required IconData icon, required String value, required String label, required Color color}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
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
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required bool isLoading,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
      child: isLoading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildParticipantCard(Map<String, dynamic> p, int index) {
    final temGraduacao = p['graduacao_nova'].isNotEmpty;
    final temCertificado = p['link_certificado'] != null && p['link_certificado'].toString().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: p['selecionado'] ? Colors.red.shade900 : Colors.grey.shade200,
          width: p['selecionado'] ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => p['selecionado'] = !p['selecionado']),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 📸 FOTO DO ALUNO
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: p['selecionado'] ? Colors.red.shade900 : Colors.grey.shade300,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: p['foto'] != null && p['foto'].toString().isNotEmpty
                      ? CachedNetworkImage(
                    imageUrl: p['foto'],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.red.shade50,
                      child: Icon(
                        Icons.person,
                        color: Colors.red.shade200,
                        size: 30,
                      ),
                    ),
                  )
                      : Container(
                    color: Colors.red.shade50,
                    child: Icon(
                      Icons.person,
                      color: Colors.red.shade200,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p['aluno_nome'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (temCertificado)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: temGraduacao ? Colors.green.shade50 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.school,
                                size: 12,
                                color: temGraduacao ? Colors.green.shade700 : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                temGraduacao ? p['graduacao_nova'] : 'Sem graduação',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: temGraduacao ? Colors.green.shade700 : Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Checkbox personalizado
              Container(
                decoration: BoxDecoration(
                  color: p['selecionado'] ? Colors.red.shade900 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Checkbox(
                  value: p['selecionado'],
                  onChanged: (value) => setState(() => p['selecionado'] = value ?? false),
                  activeColor: Colors.red.shade900,
                  checkColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.people_outline,
              size: 60,
              color: Colors.red.shade200,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nenhum participante no evento',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione participantes na tela anterior',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}