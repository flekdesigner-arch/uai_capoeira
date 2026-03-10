import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/models/inscricao_campeonato_model.dart'; // 👈 CORRIGIDO: import correto
import 'package:uai_capoeira/services/campeonato_service.dart';

class FichaCompetidorScreen extends StatefulWidget {
  final InscricaoCampeonatoModel competidor;

  const FichaCompetidorScreen({
    super.key,
    required this.competidor,
  });

  @override
  State<FichaCompetidorScreen> createState() => _FichaCompetidorScreenState();
}

class _FichaCompetidorScreenState extends State<FichaCompetidorScreen> {
  final CampeonatoService _campeonatoService = CampeonatoService();

  late bool _presente;
  late String _observacao;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _presente = false; // TODO: Carregar do Firestore quando implementado
    _observacao = '';
  }

  Future<void> _salvarPresenca() async {
    setState(() => _isSaving = true);

    try {
      await _campeonatoService.marcarPresenca(widget.competidor.id, _presente);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_presente ? '✅ Presença marcada!' : '❌ Presença removida'),
            backgroundColor: _presente ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar presença'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _salvarObservacao() async {
    if (_observacao.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite uma observação'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _campeonatoService.adicionarObservacao(widget.competidor.id, _observacao);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Observação salva!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _observacao = '');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar observação'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _abrirWhatsApp(String numero, {String? mensagem}) async {
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Número de telefone não disponível'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (!cleanedPhone.startsWith('55')) {
      cleanedPhone = '55$cleanedPhone';
    }

    String url = 'https://wa.me/$cleanedPhone';
    if (mensagem != null && mensagem.isNotEmpty) {
      final encodedMessage = Uri.encodeComponent(mensagem);
      url += '?text=$encodedMessage';
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final comp = widget.competidor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha do Competidor'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Editar informações
            },
            tooltip: 'Editar',
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Foto e nome
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.amber.shade400, width: 3),
                          ),
                          child: comp.fotoUrl != null
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(50),
                            child: CachedNetworkImage(
                              imageUrl: comp.fotoUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (context, url, error) => Center(
                                child: Text(
                                  comp.nome[0],
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ),
                          )
                              : Center(
                            child: Text(
                              comp.nome[0],
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comp.nome,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (comp.apelido.isNotEmpty)
                                Text(
                                  comp.apelido,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: comp.isMaiorIdade
                                          ? Colors.green.shade50
                                          : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      comp.isMaiorIdade ? 'MAIOR DE IDADE' : 'MENOR DE IDADE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: comp.isMaiorIdade
                                            ? Colors.green.shade800
                                            : Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
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
                  ),
                ),

                const SizedBox(height: 16),

                // Presença - CORRIGIDO: activeColor substituído por activeTrackColor
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SwitchListTile(
                    title: const Text('PRESENÇA', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_presente ? '✅ Competidor presente' : '⏳ Aguardando'),
                    value: _presente,
                    onChanged: _isSaving ? null : (value) {
                      setState(() => _presente = value);
                      _salvarPresenca();
                    },
                    activeTrackColor: Colors.green, // 👈 CORRIGIDO: activeColor -> activeTrackColor
                    inactiveTrackColor: Colors.grey.shade300,
                    activeThumbColor: Colors.white, // Cor do botão quando ativo
                    inactiveThumbColor: Colors.white, // Cor do botão quando inativo
                  ),
                ),

                const SizedBox(height: 16),

                // Botões de contato - CORRIGIDO: contatoAluno ao invés de contato
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📱 CONTATOS',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildContactButton(
                                label: 'COMPETIDOR',
                                numero: comp.contatoAluno, // 👈 CORRIGIDO: contato -> contatoAluno
                                nome: comp.nome,
                                cor: Colors.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildContactButton(
                                label: 'PROFESSOR',
                                numero: comp.professorContato,
                                nome: comp.professorNome,
                                cor: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        if (!comp.isMaiorIdade) ...[
                          const SizedBox(height: 8),
                          // Removido bloco do responsável pois não existe no model
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Informações Pessoais - CORRIGIDO: contatoAluno ao invés de contato
                _buildSection(
                  title: '👤 DADOS PESSOAIS',
                  icon: Icons.person,
                  color: Colors.blue,
                  children: [
                    _buildInfoRow('Idade', '${comp.idade} anos'),
                    _buildInfoRow('Sexo', comp.sexo),
                    _buildInfoRow('CPF', _formatarCPF(comp.cpf)),
                    _buildInfoRow('Contato', comp.contatoAluno), // 👈 CORRIGIDO: contato -> contatoAluno
                    _buildInfoRow('Cidade', comp.cidade),
                    _buildInfoRow('Endereço', comp.endereco), // Adicionado campo endereço
                  ],
                ),

                const SizedBox(height: 16),

                // Grupo e Graduação
                _buildSection(
                  title: '🥋 GRUPO E GRADUAÇÃO',
                  icon: Icons.group,
                  color: Colors.green,
                  children: [
                    _buildInfoRow('Grupo', comp.grupo),
                    _buildInfoRow('Professor', comp.professorNome),
                    _buildInfoRow('Contato Prof.', comp.professorContato),
                    const Divider(height: 16),
                    _buildInfoRow('Graduação', comp.graduacaoNome ?? 'Não informada'),
                    if (comp.graduacaoId != null)
                      _buildInfoRow('ID Graduação', comp.graduacaoId!),
                    _buildInfoRow('Grupo UAI', comp.isGrupoUai ? 'Sim' : 'Não'),
                  ],
                ),

                const SizedBox(height: 16),

                // Categoria
                if (comp.categoriaNome != null || comp.categoriaId != null)
                  _buildSection(
                    title: '🏆 CATEGORIA',
                    icon: Icons.emoji_events,
                    color: Colors.orange,
                    children: [
                      if (comp.categoriaNome != null)
                        _buildInfoRow('Categoria', comp.categoriaNome!),
                      if (comp.categoriaId != null)
                        _buildInfoRow('ID Categoria', comp.categoriaId!),
                    ],
                  ),

                const SizedBox(height: 16),

                // Informações da Inscrição
                _buildSection(
                title: '📋 INFORMAÇÕES DA INSCRIÇÃO',
                icon: Icons.receipt,
                color: Colors.purple,
                children: [
                _buildInfoRow('Status', _getStatusText(comp.status)),
                _buildInfoRow('Taxa', 'R\$ ${comp.taxaInscricao.toStringAsFixed(2)}'),
                _buildInfoRow('Taxa Paga', comp.taxaPaga ? 'Sim' : 'Não'),
                _buildInfoRow('Autorização', comp.autorizacao ? 'Sim' : 'Não'),
    if (comp.dataInscricao != null)
    _buildInfoRow('Data Insc.', DateFormat('dd/MM/yyyy HH:mm').format(comp.dataInscricao!)),
    _buildInfoRow('Campeonato', comp.nomeCampeonato), // 👈 CORRIGIDO: campeonato -> nomeCampeonato
    _buildInfoRow('Data Evento', comp.dataEvento), // Adicionado também a data do evento
    ],
    ),

                const SizedBox(height: 16),

                // Observações
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📝 OBSERVAÇÕES',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Adicionar observações...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          onChanged: (value) => _observacao = value,
                          controller: TextEditingController(text: _observacao),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _salvarObservacao,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.white,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text('SALVAR'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pendente':
        return '⏳ Pendente';
      case 'confirmado':
        return '✅ Confirmado';
      case 'cancelado':
        return '❌ Cancelado';
      case 'pago':
        return '💰 Pago';
      default:
        return status;
    }
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
          ? () => _abrirWhatsApp(
        numero,
        mensagem: 'Olá $nome! Informações sobre o campeonato.',
      )
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: temContato ? cor.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: temContato ? cor.withValues(alpha: 0.3) : Colors.grey.shade300,
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

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Não informado' : value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatarCPF(String cpf) {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.${cpf.substring(6, 9)}-${cpf.substring(9)}';
  }
}