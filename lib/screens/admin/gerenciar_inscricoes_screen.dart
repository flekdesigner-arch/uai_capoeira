import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/screens/alunos/cadastro_aluno_turma_screen.dart';
import 'package:uai_capoeira/screens/inscricao/inscricoes_aprovadas_dialog.dart';
import 'package:uai_capoeira/screens/inscricao/visualizar_termo_screen.dart';

class GerenciarInscricoesScreen extends StatefulWidget {
  const GerenciarInscricoesScreen({super.key});

  @override
  State<GerenciarInscricoesScreen> createState() => _GerenciarInscricoesScreenState();
}

class _GerenciarInscricoesScreenState extends State<GerenciarInscricoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _turmas = [];

  @override
  void initState() {
    super.initState();
    _carregarTurmas();
  }

  Future<void> _carregarTurmas() async {
    try {
      final snapshot = await _firestore.collection('turmas').orderBy('nome').get();
      setState(() {
        _turmas = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'nome': data['nome'] ?? 'Sem nome',
            'academia_nome': data['academia_nome'] ?? '',
            'academia_id': data['academia_id'] ?? '',
            'capacidade_maxima': data['capacidade_maxima'] ?? 0,
            'alunos_ativos': data['alunos_ativos'] ?? 0,
          };
        }).toList();
      });
    } catch (e) {
      print('Erro ao carregar turmas: $e');
    }
  }

  // 🔥 MÉTODO PARA ABRIR FOTO EM TELA CHEIA
  void _abrirFotoTelaCheia(String? fotoUrl, String nomeAluno) {
    if (fotoUrl == null || fotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta inscrição não possui foto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withOpacity(0.95),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade800,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, size: 64, color: Colors.white54),
                              SizedBox(height: 16),
                              Text(
                                'Erro ao carregar imagem',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text(
                        nomeAluno,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(width: 20),
                      Icon(Icons.touch_app, size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      const Text(
                        'Toque para fechar',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🔥 MÉTODO COMPLETO DO WHATSAPP
  Future<void> _abrirWhatsApp(String numero, {String? mensagem, bool isApp = true}) async {
    try {
      String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanedPhone.startsWith('0')) {
        cleanedPhone = cleanedPhone.substring(1);
      }
      if (!cleanedPhone.startsWith('55')) {
        cleanedPhone = '55$cleanedPhone';
      }

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
      _mostrarErro('Erro ao abrir WhatsApp: $e');
    }
  }

  // 🔥 APROVAR - Abre tela de cadastro com dados preenchidos
  void _aprovarInscricao(String inscricaoId, Map<String, dynamic> dados, String turmaId, String turmaNome, String academiaId, String academiaNome) {
    final dadosComId = Map<String, dynamic>.from(dados);
    dadosComId['id'] = inscricaoId;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastroAlunoTurmaScreen(
          turmaId: turmaId,
          turmaNome: turmaNome,
          academiaId: academiaId,
          academiaNome: academiaNome,
          dadosIniciais: dadosComId,
        ),
      ),
    ).then((alunoCadastrado) {
      if (alunoCadastrado == true && mounted) {
        _firestore.collection('inscricoes').doc(inscricaoId).delete().then((_) {
          _atualizarContadorInscricoes();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Inscrição aprovada e aluno cadastrado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        });
      }
    });
  }

  // 🔥 RECUSAR - DELETA direto do Firebase
  Future<void> _recusarInscricao(String inscricaoId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('❌ Recusar Inscrição'),
        content: const Text('Tem certeza que deseja recusar esta inscrição? Esta ação é irreversível.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('RECUSAR'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('inscricoes').doc(inscricaoId).delete();
      await _atualizarContadorInscricoes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Inscrição recusada e removida'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao recusar: $e');
    }
  }

  // 🔥 MOSTRAR TERMO COMPLETO
  void _mostrarTermo(BuildContext context, Map<String, dynamic> dados, String inscricaoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VisualizarTermoScreen(
          dados: dados,
          inscricaoId: inscricaoId,
        ),
      ),
    );
  }

  // 🔥 DIÁLOGO DE SELEÇÃO DE TURMA
  void _mostrarDialogoSelecionarTurma(String inscricaoId, Map<String, dynamic> dados) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Selecionar Turma',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                width: double.maxFinite,
                child: _turmas.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nenhuma turma disponível'),
                  ),
                )
                    : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(0),
                  itemCount: _turmas.length,
                  itemBuilder: (context, index) {
                    final turma = _turmas[index];
                    final alunosAtivos = turma['alunos_ativos'] as int;
                    final capacidadeMaxima = turma['capacidade_maxima'] as int;
                    final temVaga = alunosAtivos < capacidadeMaxima;
                    final porcentagem = capacidadeMaxima > 0
                        ? (alunosAtivos / capacidadeMaxima * 100).round()
                        : 0;

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: temVaga ? Colors.green.shade200 : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      color: temVaga ? Colors.white : Colors.grey.shade50,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: temVaga ? () {
                          Navigator.pop(context);
                          _aprovarInscricao(
                              inscricaoId,
                              dados,
                              turma['id'],
                              turma['nome'],
                              turma['academia_id'],
                              turma['academia_nome']
                          );
                        } : null,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: temVaga
                                      ? Colors.green.shade100
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.class_,
                                  color: temVaga
                                      ? Colors.green.shade700
                                      : Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            turma['nome'],
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: temVaga
                                                  ? Colors.black87
                                                  : Colors.grey.shade500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!temVaga)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
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
                                      turma['academia_nome'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: temVaga
                                            ? Colors.grey.shade600
                                            : Colors.grey.shade400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: LinearProgressIndicator(
                                            value: alunosAtivos / capacidadeMaxima,
                                            backgroundColor: Colors.grey.shade200,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              porcentagem >= 90
                                                  ? Colors.red
                                                  : porcentagem >= 70
                                                  ? Colors.orange
                                                  : Colors.green,
                                            ),
                                            minHeight: 6,
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$alunosAtivos/$capacidadeMaxima',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: temVaga
                                                ? Colors.black87
                                                : Colors.grey.shade500,
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
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🔥 DIÁLOGO DE DETALHES COM FOTO E 4 BOTÕES
  void _mostrarDetalhesInscricao(String docId, Map<String, dynamic> dados) {
    final fotoUrl = dados['foto_url'];
    final nomeAluno = dados['nome'] ?? 'Aluno';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            maxWidth: 500,
          ),
          child: Column(
            children: [
              // CABEÇALHO
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    // 🔥 BOLINHA COM FOTO CLICÁVEL
                    GestureDetector(
                      onTap: () => _abrirFotoTelaCheia(fotoUrl, nomeAluno),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? CachedNetworkImage(
                            imageUrl: fotoUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade700,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade700,
                              child: const Icon(
                                Icons.person,
                                color: Colors.white54,
                                size: 30,
                              ),
                            ),
                          )
                              : Container(
                            color: Colors.grey.shade700,
                            child: const Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dados['nome'] ?? 'Detalhes da Inscrição',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _abrirFotoTelaCheia(fotoUrl, nomeAluno),
                            child: Text(
                              fotoUrl != null && fotoUrl.isNotEmpty
                                  ? '👆 Toque na foto para ampliar'
                                  : '📷 Nenhuma foto anexada',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
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

              // CONTEÚDO
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Nome do aluno - CLICÁVEL para ver termo
                    _buildInfoRowClickable(
                        'Nome',
                        dados['nome'],
                            () {
                          Navigator.pop(context);
                          _mostrarTermo(context, dados, docId);
                        }
                    ),

                    _buildInfoRow('Apelido', dados['apelido']),
                    _buildInfoRow('CPF', dados['cpf']),
                    _buildInfoRow('Sexo', dados['sexo']),
                    _buildInfoRow('Data Nascimento', dados['data_nascimento']),
                    _buildInfoRow('Contato Aluno', dados['contato_aluno']),
                    _buildInfoRow('Responsável', dados['nome_responsavel']),
                    _buildInfoRow('Contato Responsável', dados['contato_responsavel']),
                    _buildInfoRow('Endereço', dados['endereco']),

                    if (dados['data_inscricao'] != null)
                      _buildInfoRow(
                        'Data Inscrição',
                        DateFormat('dd/MM/yyyy HH:mm').format(
                          (dados['data_inscricao'] as Timestamp).toDate(),
                        ),
                      ),

                    const SizedBox(height: 8),

                    // CARD DO TERMO - TAMBÉM CLICÁVEL
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _mostrarTermo(context, dados, docId);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: dados['assinatura_url'] != null
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: dados['assinatura_url'] != null
                                ? Colors.green.shade200
                                : Colors.orange.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              dados['assinatura_url'] != null
                                  ? Icons.draw
                                  : Icons.description,
                              color: dados['assinatura_url'] != null
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dados['assinatura_url'] != null
                                        ? '✅ Termo assinado digitalmente'
                                        : '📝 Termo aceito (sem assinatura)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dados['assinatura_url'] != null
                                          ? Colors.green.shade800
                                          : Colors.orange.shade800,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Toque para visualizar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🔥 4 BOTÕES DE AÇÃO
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Column(
                  children: [
                    // BOTÃO APROVAR
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _mostrarDialogoSelecionarTurma(docId, dados);
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text(
                          'APROVAR INSCRIÇÃO',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // BOTÕES DE CONTATO
                    Row(
                      children: [
                        Expanded(
                          child: _buildContactButton(
                            label: 'CONTATO ALUNO',
                            numero: dados['contato_aluno'],
                            nome: dados['nome'],
                            cor: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildContactButton(
                            label: 'CONTATO RESP.',
                            numero: dados['contato_responsavel'],
                            nome: dados['nome_responsavel'],
                            cor: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // BOTÃO VER TERMO
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) {
                              _mostrarTermo(context, dados, docId);
                            }
                          });
                        },
                        icon: const Icon(Icons.description, color: Colors.blue),
                        label: const Text(
                          'VER TERMO COMPLETO',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.blue),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // BOTÃO RECUSAR
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _recusarInscricao(docId);
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text(
                          'RECUSAR INSCRIÇÃO',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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

  Widget _buildContactButton({
    required String label,
    required String? numero,
    required String? nome,
    required Color cor,
  }) {
    final bool temContato = numero != null && numero.isNotEmpty;

    return InkWell(
      onTap: temContato
          ? () {
        Navigator.pop(context);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _abrirWhatsApp(
              numero,
              mensagem: 'Olá $nome! Sua inscrição na UAI Capoeira foi recebida e está sendo analisada.',
              isApp: true,
            );
          }
        });
      }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: temContato ? cor.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: temContato ? cor.withOpacity(0.3) : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            SvgPicture.asset(
              'assets/images/whatsapp.svg',
              height: 24,
              width: 24,
              colorFilter: ColorFilter.mode(
                temContato ? cor : Colors.grey.shade400,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: temContato ? Colors.black87 : Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value?.isNotEmpty == true ? value! : 'Não informado'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRowClickable(String label, String? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                '$label:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Text(
                value?.isNotEmpty == true ? value! : 'Não informado',
                style: const TextStyle(
                  decoration: TextDecoration.underline,
                  color: Colors.blue,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _atualizarContadorTurma(String turmaId) async {
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      await _firestore.collection('turmas').doc(turmaId).update({
        'alunos_count': snapshot.docs.length,
        'alunos_ativos': snapshot.docs.length,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Erro ao atualizar contador da turma: $e');
    }
  }

  Future<void> _atualizarContadorInscricoes() async {
    try {
      final snapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'total_inscricoes': snapshot.docs.length,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Erro ao atualizar contador: $e');
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Gerenciar Inscrições'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const InscricoesAprovadasDialog(),
              );
            },
            tooltip: 'Ver inscrições aprovadas',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('inscricoes')
            .where('status', isEqualTo: 'pendente')
            .orderBy('data_inscricao', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Nenhuma inscrição pendente',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final inscricoes = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: inscricoes.length,
            itemBuilder: (context, index) {
              final doc = inscricoes[index];
              final data = doc.data() as Map<String, dynamic>;
              final dataInscricao = data['data_inscricao'] as Timestamp?;
              final fotoUrl = data['foto_url'];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: GestureDetector(
                    onTap: () => _abrirFotoTelaCheia(fotoUrl, data['nome'] ?? 'Aluno'),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.red.shade100,
                      backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
                          ? CachedNetworkImageProvider(fotoUrl)
                          : null,
                      child: fotoUrl == null || fotoUrl.isEmpty
                          ? Text(
                        (data['nome']?[0] ?? '?').toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                          : null,
                    ),
                  ),
                  title: Text(
                    data['nome'] ?? 'Nome não informado',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📞 ${data['contato_aluno'] ?? 'Sem contato'}'),
                      if (dataInscricao != null)
                        Text(
                          '📅 ${DateFormat('dd/MM/yyyy HH:mm').format(dataInscricao.toDate())}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      // 🔥 INDICADOR DE TERMO
                      Row(
                        children: [
                          Icon(
                            data['assinatura_url'] != null
                                ? Icons.draw
                                : Icons.description,
                            size: 14,
                            color: data['assinatura_url'] != null
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            data['assinatura_url'] != null
                                ? 'Termo assinado'
                                : 'Termo aceito',
                            style: TextStyle(
                              fontSize: 10,
                              color: data['assinatura_url'] != null
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.visibility, color: Colors.blue),
                    onPressed: () => _mostrarDetalhesInscricao(doc.id, data),
                    tooltip: 'Ver detalhes',
                  ),
                  onTap: () => _mostrarDetalhesInscricao(doc.id, data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}