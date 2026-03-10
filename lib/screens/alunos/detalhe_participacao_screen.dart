import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:cached_network_image/cached_network_image.dart';

class DetalheParticipacaoScreen extends StatefulWidget {
  final Map<String, dynamic> participacao;
  final String participacaoId;

  const DetalheParticipacaoScreen({
    super.key,
    required this.participacao,
    required this.participacaoId,
  });

  @override
  State<DetalheParticipacaoScreen> createState() => _DetalheParticipacaoScreenState();
}

class _DetalheParticipacaoScreenState extends State<DetalheParticipacaoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _eventoDetalhes;
  Map<String, dynamic>? _alunoDetalhes;
  Map<String, dynamic>? _coresGraduacao;
  String? _svgContent;
  String? _svgColorido;
  bool _isLoading = true;

  // Cache de cores por nome da graduação
  final Map<String, Map<String, dynamic>> _cacheCoresPorNome = {};

  @override
  void initState() {
    super.initState();
    _carregarSvg();
    _carregarDados();
  }

  Future<void> _carregarSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() {
          _svgContent = content;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar SVG: $e');
    }
  }

  Future<void> _carregarDados() async {
    try {
      final eventoId = widget.participacao['evento_id'] as String?;
      final alunoId = widget.participacao['aluno_id'] as String?;
      final nomeGraduacao = widget.participacao['graduacao'] as String?;

      // Carregar detalhes do evento
      if (eventoId != null) {
        final eventoDoc = await _firestore.collection('eventos').doc(eventoId).get();
        if (eventoDoc.exists) {
          _eventoDetalhes = eventoDoc.data();
        }
      }

      // Carregar detalhes do aluno
      if (alunoId != null) {
        final alunoDoc = await _firestore.collection('alunos').doc(alunoId).get();
        if (alunoDoc.exists) {
          _alunoDetalhes = alunoDoc.data();
        }
      }

      // Buscar cores da graduação pelo nome
      if (nomeGraduacao != null && nomeGraduacao.isNotEmpty) {
        await _buscarCoresPorNome(nomeGraduacao);
      }

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('❌ Erro ao carregar dados: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _buscarCoresPorNome(String nomeGraduacao) async {
    // Verificar se já está em cache
    if (_cacheCoresPorNome.containsKey(nomeGraduacao)) {
      setState(() {
        _coresGraduacao = _cacheCoresPorNome[nomeGraduacao];
      });
      await _colorirSvg();
      return;
    }

    try {
      // Buscar todas as graduações
      final snapshot = await _firestore.collection('graduacoes').get();

      // Procurar por correspondência no nome
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome_graduacao']?.toString() ?? '';

        // Comparação flexível (case insensitive e contém)
        if (nome.toLowerCase().contains(nomeGraduacao.toLowerCase()) ||
            nomeGraduacao.toLowerCase().contains(nome.toLowerCase())) {

          _coresGraduacao = {
            'hex_cor1': data['hex_cor1'] ?? '#FFFFFF',
            'hex_cor2': data['hex_cor2'] ?? '#FFFFFF',
            'hex_ponta1': data['hex_ponta1'] ?? '#FFFFFF',
            'hex_ponta2': data['hex_ponta2'] ?? '#FFFFFF',
            'nome_graduacao': data['nome_graduacao'],
          };

          _cacheCoresPorNome[nomeGraduacao] = _coresGraduacao!;
          break;
        }
      }

      // Se não encontrou, usar cores padrão baseadas no texto
      if (_coresGraduacao == null) {
        _coresGraduacao = _getCoresPadraoPorNome(nomeGraduacao);
      }

      await _colorirSvg();

    } catch (e) {
      debugPrint('Erro ao buscar cores: $e');
      _coresGraduacao = _getCoresPadraoPorNome(nomeGraduacao);
      await _colorirSvg();
    }
  }

  Map<String, dynamic> _getCoresPadraoPorNome(String nome) {
    final nomeLower = nome.toLowerCase();

    // Mapeamento de cores por palavras-chave
    if (nomeLower.contains('branco') || nomeLower.contains('branca')) {
      return {
        'hex_cor1': '#FFFFFF',
        'hex_cor2': '#F5F5F5',
        'hex_ponta1': '#E0E0E0',
        'hex_ponta2': '#BDBDBD',
        'nome_graduacao': 'Branco',
      };
    } else if (nomeLower.contains('amarelo') || nomeLower.contains('amarela')) {
      return {
        'hex_cor1': '#FFEB3B',
        'hex_cor2': '#FDD835',
        'hex_ponta1': '#FBC02D',
        'hex_ponta2': '#F9A825',
        'nome_graduacao': 'Amarelo',
      };
    } else if (nomeLower.contains('laranja')) {
      return {
        'hex_cor1': '#FF9800',
        'hex_cor2': '#FB8C00',
        'hex_ponta1': '#F57C00',
        'hex_ponta2': '#EF6C00',
        'nome_graduacao': 'Laranja',
      };
    } else if (nomeLower.contains('azul')) {
      return {
        'hex_cor1': '#2196F3',
        'hex_cor2': '#1E88E5',
        'hex_ponta1': '#1976D2',
        'hex_ponta2': '#1565C0',
        'nome_graduacao': 'Azul',
      };
    } else if (nomeLower.contains('verde')) {
      return {
        'hex_cor1': '#4CAF50',
        'hex_cor2': '#43A047',
        'hex_ponta1': '#388E3C',
        'hex_ponta2': '#2E7D32',
        'nome_graduacao': 'Verde',
      };
    } else if (nomeLower.contains('roxo') || nomeLower.contains('roxa')) {
      return {
        'hex_cor1': '#9C27B0',
        'hex_cor2': '#8E24AA',
        'hex_ponta1': '#7B1FA2',
        'hex_ponta2': '#6A1B9A',
        'nome_graduacao': 'Roxo',
      };
    } else if (nomeLower.contains('vermelho') || nomeLower.contains('vermelha')) {
      return {
        'hex_cor1': '#F44336',
        'hex_cor2': '#E53935',
        'hex_ponta1': '#D32F2F',
        'hex_ponta2': '#C62828',
        'nome_graduacao': 'Vermelho',
      };
    } else if (nomeLower.contains('marrom')) {
      return {
        'hex_cor1': '#8D6E63',
        'hex_cor2': '#7B5E57',
        'hex_ponta1': '#6D4C41',
        'hex_ponta2': '#5D4037',
        'nome_graduacao': 'Marrom',
      };
    } else if (nomeLower.contains('cinza') || nomeLower.contains('crua')) {
      return {
        'hex_cor1': '#9E9E9E',
        'hex_cor2': '#757575',
        'hex_ponta1': '#616161',
        'hex_ponta2': '#424242',
        'nome_graduacao': 'Cinza',
      };
    } else if (nomeLower.contains('preta')) {
      return {
        'hex_cor1': '#212121',
        'hex_cor2': '#1E1E1E',
        'hex_ponta1': '#1A1A1A',
        'hex_ponta2': '#151515',
        'nome_graduacao': 'Preta',
      };
    }

    // Padrão: cinza claro
    return {
      'hex_cor1': '#BDBDBD',
      'hex_cor2': '#9E9E9E',
      'hex_ponta1': '#757575',
      'hex_ponta2': '#616161',
      'nome_graduacao': nome,
    };
  }

  Future<void> _colorirSvg() async {
    if (_svgContent == null || _coresGraduacao == null) return;

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String hexColor) {
        if (hexColor.isEmpty || hexColor.length < 7) return Colors.grey;
        try {
          return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
        } catch (e) {
          return Colors.grey;
        }
      }

      void changeColor(String id, Color color) {
        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );
        if (element.name.local.isNotEmpty) {
          final style = element.getAttribute('style') ?? '';
          final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
          final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
          element.setAttribute('style', 'fill:$hex;$newStyle');
        }
      }

      changeColor('cor1', colorFromHex(_coresGraduacao!['hex_cor1']));
      changeColor('cor2', colorFromHex(_coresGraduacao!['hex_cor2']));
      changeColor('corponta1', colorFromHex(_coresGraduacao!['hex_ponta1']));
      changeColor('corponta2', colorFromHex(_coresGraduacao!['hex_ponta2']));

      setState(() {
        _svgColorido = document.toXmlString();
      });

    } catch (e) {
      debugPrint('Erro ao colorir SVG: $e');
    }
  }

  Future<void> _abrirLink(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o link'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _abrirPDF(String? url) async {
    if (url == null || url.isEmpty) return;

    // Verifica se é um link do Google Drive e converte para visualização direta
    String pdfUrl = url;

    // Se for link do Google Drive, converte para o formato de visualização
    if (url.contains('drive.google.com')) {
      // Extrai o ID do arquivo
      final RegExp regex = RegExp(r'/d/([a-zA-Z0-9_-]+)');
      final match = regex.firstMatch(url);

      if (match != null && match.groupCount >= 1) {
        final fileId = match.group(1);
        pdfUrl = 'https://drive.google.com/file/d/$fileId/preview';
      }
    }

    try {
      final Uri uri = Uri.parse(pdfUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Não informada';
    if (data is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(data.toDate());
    }
    return data.toString();
  }

  @override
  Widget build(BuildContext context) {
    final participacao = widget.participacao;
    final nomeEvento = participacao['evento_nome'] ?? 'Evento';
    final dataEvento = _formatarData(participacao['data_evento']);
    final tipoEvento = participacao['tipo_evento'] ?? '';
    final graduacao = participacao['graduacao'] ?? 'Graduação não informada';
    final certificado = participacao['link_certificado'] as String?;

    final eventoDetalhes = _eventoDetalhes;
    final alunoDetalhes = _alunoDetalhes;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Participação em Evento',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : SingleChildScrollView(
        child: Column(
          children: [
            // CARD PRINCIPAL DO EVENTO
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // BANNER DO EVENTO - Formato 1:1 (quadrado e maior)
                  if (eventoDetalhes != null &&
                      eventoDetalhes['link_banner'] != null &&
                      eventoDetalhes['link_banner'].toString().isNotEmpty)
                    AspectRatio(
                      aspectRatio: 1 / 1, // Proporção 1:1 (quadrado)
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          image: DecorationImage(
                            image: NetworkImage(eventoDetalhes['link_banner']),
                            fit: BoxFit.cover, // Cover para preencher o espaço
                          ),
                        ),
                      ),
                    )
                  else
                    AspectRatio(
                      aspectRatio: 1 / 1, // Proporção 1:1 (quadrado)
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event, color: Colors.red.shade900, size: 50),
                              const SizedBox(height: 8),
                              Text(
                                'Evento',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // NOME DO EVENTO
                        Text(
                          nomeEvento,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // TIPO DO EVENTO
                        if (tipoEvento.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tipoEvento,
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),

                        // DATA
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.calendar_today, color: Colors.orange.shade700),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Data do Evento',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  dataEvento,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // LOCAL
                        if (eventoDetalhes != null)
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.location_on, color: Colors.red.shade700),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Local',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '${eventoDetalhes['local'] ?? ''} - ${eventoDetalhes['cidade'] ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
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
                ],
              ),
            ),

            // CARD DA PARTICIPAÇÃO DO ALUNO
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Participação do Aluno',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // GRADUAÇÃO COM CORDA
                  Row(
                    children: [
                      // CORDA COLORIDA
                      if (_svgColorido != null)
                        Container(
                          width: 80,
                          height: 120,
                          padding: const EdgeInsets.all(8),
                          child: SvgPicture.string(
                            _svgColorido!,
                            placeholderBuilder: (context) => const SizedBox(),
                          ),
                        )
                      else
                        Container(
                          width: 80,
                          height: 120,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.emoji_events, color: Colors.grey),
                        ),

                      const SizedBox(width: 16),

                      // INFORMAÇÕES DA GRADUAÇÃO
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Graduação na época',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              graduacao,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_coresGraduacao != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _coresGraduacao!['nome_graduacao'] ?? 'Graduação',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.amber.shade900,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // CERTIFICADO - AGORA EM VERMELHO COMBINANDO COM O TEMA
                  if (certificado != null && certificado.isNotEmpty) ...[
                    const Divider(),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50, // Fundo vermelho claro
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.picture_as_pdf, color: Colors.red.shade700), // Ícone vermelho
                      ),
                      title: Text(
                        'Certificado Disponível',
                        style: TextStyle(
                          color: Colors.red.shade900, // Texto vermelho escuro
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        certificado,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.red.shade700), // Subtítulo vermelho
                      ),
                      trailing: Icon(Icons.open_in_new, color: Colors.red.shade700), // Ícone vermelho
                      onTap: () => _abrirPDF(certificado),
                    ),
                  ],

                  // FOTO DO ALUNO (se disponível)
                  if (alunoDetalhes != null && alunoDetalhes['foto_perfil_aluno'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: alunoDetalhes['foto_perfil_aluno'],
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey.shade100,
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey.shade100,
                                  child: const Icon(Icons.person),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Aluno',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                Text(
                                  alunoDetalhes['nome'] ?? 'Nome não informado',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // BOTÕES DE AÇÃO - AGORA OS DOIS BOTÕES COMBINAM
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('VOLTAR'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        side: BorderSide(color: Colors.red.shade900.withOpacity(0.5)),
                        foregroundColor: Colors.red.shade900, // Texto vermelho
                      ),
                    ),
                  ),
                  if (certificado != null && certificado.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _abrirPDF(certificado),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('CERTIFICADO'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900, // Fundo vermelho
                          foregroundColor: Colors.white, // Texto branco
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}