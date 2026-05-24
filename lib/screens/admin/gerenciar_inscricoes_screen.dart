import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  final FirebaseStorage _storage = FirebaseStorage.instance;
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
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width - 32,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  nomeAluno,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 16,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Toque para fechar',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

  // 🔥 RECUSAR - DELETA documento + arquivos do Storage
  Future<void> _recusarInscricao(String inscricaoId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.warning_rounded, color: Colors.red.shade700),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Recusar inscrição?',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: const Text(
          'Essa ação vai remover a inscrição pendente e também apagar os arquivos enviados, como foto e assinatura, do Firebase Storage.\n\nEssa ação é irreversível.',
          style: TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('RECUSAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final docRef = _firestore.collection('inscricoes').doc(inscricaoId);
      final doc = await docRef.get();

      if (!doc.exists) {
        _mostrarErro('Inscrição não encontrada.');
        return;
      }

      final dados = doc.data() ?? {};
      final fotoUrl = dados['foto_url']?.toString();
      final assinaturaUrl = dados['assinatura_url']?.toString();

      final arquivosFalharam = <String>[];

      final fotoApagada = await _deletarArquivoStoragePorUrl(
        fotoUrl,
        descricao: 'foto do aluno',
      );

      if (!fotoApagada && _temTexto(fotoUrl)) {
        arquivosFalharam.add('foto');
      }

      final assinaturaApagada = await _deletarArquivoStoragePorUrl(
        assinaturaUrl,
        descricao: 'assinatura digital',
      );

      if (!assinaturaApagada && _temTexto(assinaturaUrl)) {
        arquivosFalharam.add('assinatura');
      }

      await docRef.delete();
      await _atualizarContadorInscricoes();

      if (!mounted) return;

      final mensagem = arquivosFalharam.isEmpty
          ? '❌ Inscrição recusada e arquivos removidos'
          : '❌ Inscrição removida, mas houve falha ao apagar: ${arquivosFalharam.join(', ')}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: arquivosFalharam.isEmpty ? Colors.red : Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _mostrarErro('Erro ao recusar inscrição: $e');
    }
  }

  Future<bool> _deletarArquivoStoragePorUrl(
      String? url, {
        required String descricao,
      }) async {
    if (!_temTexto(url)) return true;

    try {
      final ref = _storage.refFromURL(url!.trim());
      await ref.delete();

      debugPrint('✅ Arquivo removido do Storage: $descricao');
      return true;
    } on FirebaseException catch (e) {
      // Se o arquivo já não existe, não precisa travar a recusa.
      if (e.code == 'object-not-found') {
        debugPrint('⚠️ Arquivo já não existia no Storage: $descricao');
        return true;
      }

      debugPrint('❌ Erro ao deletar $descricao: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Erro ao deletar $descricao: $e');
      return false;
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
  void _mostrarDialogoSelecionarTurma(
      String inscricaoId,
      Map<String, dynamic> dados,
      ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade800, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.16)),
                        ),
                        child: const Icon(
                          Icons.class_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selecionar turma',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Escolha onde o aluno será cadastrado.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _turmas.isEmpty
                      ? _buildEmptyDialogState(
                    icon: Icons.class_outlined,
                    title: 'Nenhuma turma disponível',
                    subtitle: 'Cadastre uma turma antes de aprovar a inscrição.',
                  )
                      : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: _turmas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final turma = _turmas[index];
                      final alunosAtivos = _asInt(turma['alunos_ativos']);
                      final capacidadeMaxima = _asInt(turma['capacidade_maxima']);
                      final temLimite = capacidadeMaxima > 0;
                      final temVaga = !temLimite || alunosAtivos < capacidadeMaxima;
                      final porcentagem = temLimite
                          ? ((alunosAtivos / capacidadeMaxima) * 100).clamp(0, 100).round()
                          : 0;
                      final progress = temLimite
                          ? (alunosAtivos / capacidadeMaxima).clamp(0.0, 1.0)
                          : 0.0;

                      return InkWell(
                        onTap: temVaga
                            ? () {
                          Navigator.pop(context);
                          _aprovarInscricao(
                            inscricaoId,
                            dados,
                            turma['id'],
                            turma['nome'],
                            turma['academia_id'],
                            turma['academia_nome'],
                          );
                        }
                            : null,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: temVaga ? Colors.white : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: temVaga
                                  ? Colors.green.shade100
                                  : Colors.grey.shade200,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.035),
                                blurRadius: 7,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: temVaga
                                      ? Colors.green.shade50
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  temVaga
                                      ? Icons.meeting_room_rounded
                                      : Icons.block_rounded,
                                  color: temVaga
                                      ? Colors.green.shade700
                                      : Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            turma['nome']?.toString() ?? 'Sem nome',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                              color: temVaga
                                                  ? Colors.grey.shade900
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                        if (!temVaga)
                                          _buildSmallStatusChip(
                                            label: 'LOTADA',
                                            color: Colors.red,
                                          )
                                        else
                                          _buildSmallStatusChip(
                                            label: 'DISPONÍVEL',
                                            color: Colors.green,
                                          ),
                                      ],
                                    ),
                                    if ((turma['academia_nome']?.toString() ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        turma['academia_nome'].toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(99),
                                            child: LinearProgressIndicator(
                                              minHeight: 7,
                                              value: progress,
                                              backgroundColor: Colors.grey.shade200,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                !temLimite
                                                    ? Colors.green
                                                    : porcentagem >= 90
                                                    ? Colors.red
                                                    : porcentagem >= 70
                                                    ? Colors.orange
                                                    : Colors.green,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          temLimite
                                              ? '$alunosAtivos/$capacidadeMaxima'
                                              : '$alunosAtivos alunos',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.grey.shade700,
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
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCELAR'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🔥 DIÁLOGO DE DETALHES COM FOTO E AÇÕES
  void _mostrarDetalhesInscricao(String docId, Map<String, dynamic> dados) {
    final fotoUrl = dados['foto_url']?.toString();
    final nomeAluno = _texto(dados['nome'], fallback: 'Aluno');
    final dataInscricao = _formatarDataHora(dados['data_inscricao']);
    final temAssinatura = _temTexto(dados['assinatura_url']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.88,
            minChildSize: 0.55,
            maxChildSize: 0.96,
            builder: (context, scrollController) {
              return Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 12, 10, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade900, Colors.red.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => _abrirFotoTelaCheia(fotoUrl, nomeAluno),
                                child: Hero(
                                  tag: 'foto_inscricao_$docId',
                                  child: _buildFotoAvatar(
                                    fotoUrl: fotoUrl,
                                    nome: nomeAluno,
                                    radius: 32,
                                    borderColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nomeAluno,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        height: 1.05,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      dataInscricao == null
                                          ? 'Inscrição pendente'
                                          : 'Inscrito em $dataInscricao',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.78),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(14),
                        children: [
                          _buildTermoCard(
                            temAssinatura: temAssinatura,
                            onTap: () {
                              Navigator.pop(context);
                              _mostrarTermo(context, dados, docId);
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildSectionCard(
                            icon: Icons.person_rounded,
                            title: 'Dados do aluno',
                            children: [
                              _buildInfoTile(
                                icon: Icons.person_rounded,
                                label: 'Nome',
                                value: dados['nome'],
                                onTap: () {
                                  Navigator.pop(context);
                                  _mostrarTermo(context, dados, docId);
                                },
                              ),
                              _buildInfoTile(
                                icon: Icons.badge_rounded,
                                label: 'Apelido',
                                value: dados['apelido'],
                              ),
                              _buildInfoTile(
                                icon: Icons.credit_card_rounded,
                                label: 'CPF',
                                value: dados['cpf'],
                              ),
                              _buildInfoTile(
                                icon: Icons.wc_rounded,
                                label: 'Sexo',
                                value: dados['sexo'],
                              ),
                              _buildInfoTile(
                                icon: Icons.cake_rounded,
                                label: 'Nascimento',
                                value: dados['data_nascimento'],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSectionCard(
                            icon: Icons.phone_android_rounded,
                            title: 'Contato',
                            children: [
                              _buildInfoTile(
                                icon: Icons.phone_rounded,
                                label: 'Contato do aluno',
                                value: dados['contato_aluno'],
                              ),
                              _buildInfoTile(
                                icon: Icons.family_restroom_rounded,
                                label: 'Responsável',
                                value: dados['nome_responsavel'],
                              ),
                              _buildInfoTile(
                                icon: Icons.phone_in_talk_rounded,
                                label: 'Contato do responsável',
                                value: dados['contato_responsavel'],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSectionCard(
                            icon: Icons.location_on_rounded,
                            title: 'Endereço',
                            children: [
                              _buildInfoTile(
                                icon: Icons.home_rounded,
                                label: 'Endereço',
                                value: dados['endereco'],
                              ),
                              if (dataInscricao != null)
                                _buildInfoTile(
                                  icon: Icons.event_rounded,
                                  label: 'Data da inscrição',
                                  value: dataInscricao,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(28),
                        ),
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _mostrarDialogoSelecionarTurma(docId, dados);
                              },
                              icon: const Icon(Icons.check_circle_rounded),
                              label: const Text('APROVAR INSCRIÇÃO'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildContactButton(
                                  label: 'Aluno',
                                  numero: dados['contato_aluno']?.toString(),
                                  nome: dados['nome']?.toString(),
                                  cor: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildContactButton(
                                  label: 'Responsável',
                                  numero: dados['contato_responsavel']?.toString(),
                                  nome: dados['nome_responsavel']?.toString(),
                                  cor: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Future.delayed(const Duration(milliseconds: 100), () {
                                      if (mounted) _mostrarTermo(context, dados, docId);
                                    });
                                  },
                                  icon: const Icon(Icons.description_rounded, size: 19),
                                  label: const Text('TERMO'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue.shade700,
                                    side: BorderSide(color: Colors.blue.shade200),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _recusarInscricao(docId);
                                  },
                                  icon: const Icon(Icons.delete_rounded, size: 19),
                                  label: const Text('RECUSAR'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(color: Colors.red.shade200),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildContactButton({
    required String label,
    required String? numero,
    required String? nome,
    required Color cor,
  }) {
    final temContato = numero != null && numero.trim().isNotEmpty;

    return InkWell(
      onTap: temContato
          ? () {
        Navigator.pop(context);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _abrirWhatsApp(
              numero,
              mensagem:
              'Olá ${nome ?? ''}! Sua inscrição na UAI Capoeira foi recebida e está sendo analisada.',
              isApp: true,
            );
          }
        });
      }
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: temContato ? cor.withOpacity(0.08) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: temContato ? cor.withOpacity(0.18) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/images/whatsapp.svg',
              height: 20,
              width: 20,
              colorFilter: ColorFilter.mode(
                temContato ? cor : Colors.grey.shade400,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: temContato ? cor : Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermoCard({
    required bool temAssinatura,
    required VoidCallback onTap,
  }) {
    final color = temAssinatura ? Colors.green : Colors.orange;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Icon(
              temAssinatura ? Icons.draw_rounded : Icons.description_rounded,
              color: color.shade700,
              size: 28,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temAssinatura
                        ? 'Termo assinado digitalmente'
                        : 'Termo aceito sem assinatura',
                    style: TextStyle(
                      color: color.shade800,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Toque para visualizar o termo completo.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.red.shade900, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required dynamic value,
    VoidCallback? onTap,
  }) {
    final text = _texto(value);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.red.shade800, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 13.2,
                      color: onTap == null ? Colors.grey.shade900 : Colors.blue.shade800,
                      fontWeight: FontWeight.w800,
                      decoration: onTap == null ? null : TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return _buildInfoTile(
      icon: Icons.info_outline_rounded,
      label: label,
      value: value,
    );
  }

  Widget _buildInfoRowClickable(String label, String? value, VoidCallback onTap) {
    return _buildInfoTile(
      icon: Icons.touch_app_rounded,
      label: label,
      value: value,
      onTap: onTap,
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

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _temTexto(dynamic value) {
    return value?.toString().trim().isNotEmpty == true;
  }

  String _texto(dynamic value, {String fallback = 'Não informado'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _formatarDataHora(dynamic value) {
    if (value == null) return '';

    try {
      if (value is Timestamp) {
        return DateFormat('dd/MM/yyyy HH:mm').format(value.toDate());
      }

      if (value is DateTime) {
        return DateFormat('dd/MM/yyyy HH:mm').format(value);
      }
    } catch (_) {}

    return value.toString();
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';

    if (partes.length == 1) {
      return partes.first.characters.first.toUpperCase();
    }

    return '${partes.first.characters.first}${partes.last.characters.first}'
        .toUpperCase();
  }

  Widget _buildFotoAvatar({
    required String? fotoUrl,
    required String nome,
    required double radius,
    Color? borderColor,
  }) {
    final temFoto = fotoUrl != null && fotoUrl.trim().isNotEmpty;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? Colors.red.shade100,
          width: borderColor == null ? 1.5 : 2.5,
        ),
      ),
      child: ClipOval(
        child: temFoto
            ? CachedNetworkImage(
          imageUrl: fotoUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey.shade200,
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.red.shade900,
                strokeWidth: 2,
              ),
            ),
          ),
          errorWidget: (context, url, error) => _avatarFallback(nome),
        )
            : _avatarFallback(nome),
      ),
    );
  }

  Widget _avatarFallback(String nome) {
    return Container(
      color: Colors.red.shade50,
      alignment: Alignment.center,
      child: Text(
        _iniciais(nome),
        style: TextStyle(
          color: Colors.red.shade900,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildSmallStatusChip({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildEmptyDialogState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _buildHeroResumo(int total) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.pending_actions_rounded,
              color: Colors.white,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Gerenciar Inscrições',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Acompanhe candidatos, veja termos, entre em contato e aprove alunos para uma turma.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.80),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildWhiteChip(
                    icon: Icons.inbox_rounded,
                    label: '$total pendentes',
                  ),
                  _buildWhiteChip(
                    icon: Icons.class_rounded,
                    label: '${_turmas.length} turmas',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteChip({
    required IconData icon,
    required String label,
  }) {
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
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInscricaoCard({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final nome = _texto(data['nome'], fallback: 'Nome não informado');
    final contato = _texto(data['contato_aluno'], fallback: 'Sem contato');
    final responsavel = _texto(data['nome_responsavel'], fallback: '');
    final dataInscricao = _formatarDataHora(data['data_inscricao']);
    final fotoUrl = data['foto_url']?.toString();
    final temAssinatura = _temTexto(data['assinatura_url']);

    return InkWell(
      onTap: () => _mostrarDetalhesInscricao(docId, data),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _abrirFotoTelaCheia(fotoUrl, nome),
              child: Hero(
                tag: 'foto_inscricao_$docId',
                child: _buildFotoAvatar(
                  fotoUrl: fotoUrl,
                  nome: nome,
                  radius: 31,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade900,
                      fontSize: 15.5,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildMiniInfo(
                        icon: Icons.phone_rounded,
                        text: contato,
                        color: Colors.green,
                      ),
                      if (responsavel.isNotEmpty)
                        _buildMiniInfo(
                          icon: Icons.family_restroom_rounded,
                          text: responsavel,
                          color: Colors.blue,
                        ),
                    ],
                  ),
                  if (dataInscricao.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      dataInscricao,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildSmallStatusChip(
                    label: temAssinatura ? 'TERMO ASSINADO' : 'TERMO ACEITO',
                    color: temAssinatura ? Colors.green : Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade500,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInfo({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 74, color: Colors.grey.shade300),
              const SizedBox(height: 14),
              const Text(
                'Nenhuma inscrição pendente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                'Quando alguém preencher o formulário, a inscrição aparecerá aqui automaticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.3),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const InscricoesAprovadasDialog(),
                  );
                },
                icon: const Icon(Icons.history_rounded),
                label: const Text('VER APROVADAS'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 70, color: Colors.red.shade700),
              const SizedBox(height: 12),
              const Text(
                'Erro ao carregar inscrições',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'Tente novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: CircularProgressIndicator(color: Colors.red.shade900),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Gerenciar Inscrições',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
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
          if (snapshot.hasError) {
            return _buildErrorScreen(snapshot.error);
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingScreen();
          }

          final inscricoes = snapshot.data?.docs ?? [];

          if (inscricoes.isEmpty) {
            return _buildEmptyScreen();
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        children: [
                          _buildHeroResumo(inscricoes.length),
                          const SizedBox(height: 14),
                          if (isWide)
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: inscricoes.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return SizedBox(
                                  width: (constraints.maxWidth.clamp(0, 1120) - 12) / 2,
                                  child: _buildInscricaoCard(
                                    docId: doc.id,
                                    data: data,
                                  ),
                                );
                              }).toList(),
                            )
                          else
                            Column(
                              children: inscricoes.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildInscricaoCard(
                                    docId: doc.id,
                                    data: data,
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
