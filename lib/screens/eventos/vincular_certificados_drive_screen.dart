// lib/screens/eventos/vincular_certificados_drive_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // 👈 IMPORT ADICIONADO!

class VincularCertificadosDriveScreen extends StatefulWidget {
  final List<Map<String, dynamic>> participantes;
  final String eventoId;
  final String eventoNome;

  const VincularCertificadosDriveScreen({
    super.key,
    required this.participantes,
    required this.eventoId,
    required this.eventoNome,
  });

  @override
  State<VincularCertificadosDriveScreen> createState() => _VincularCertificadosDriveScreenState();
}

class _VincularCertificadosDriveScreenState extends State<VincularCertificadosDriveScreen> {
  final TextEditingController _pastaUrlController = TextEditingController();
  bool _isVinculando = false;
  bool _isBuscando = false;
  bool _isSalvandoPasta = false;
  Map<String, dynamic>? _resultadosBusca;
  List<Map<String, dynamic>> _participantesComCertificado = [];
  Map<String, dynamic>? _pastaSalva;

  // Para logging
  final List<String> _logs = [];

  // Controller para busca manual
  final TextEditingController _buscaManualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _participantesComCertificado = widget.participantes.map((p) {
      return {
        ...p,
        'status': 'nao_encontrado',
        'link_encontrado': p['link_certificado'] ?? '',
        'arquivo_nome': '',
      };
    }).toList();

    _carregarPastaSalva();
    _verificarLinksExistentes();
  }

  // ============================================================
  // CARREGAR PASTA SALVA DO EVENTO
  // ============================================================
  Future<void> _carregarPastaSalva() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('pasta_certificados')) {
          final pastaData = data['pasta_certificados'];
          if (mounted) {
            setState(() {
              _pastaSalva = pastaData is Map<String, dynamic> ? pastaData : null;
              if (_pastaSalva != null) {
                _pastaUrlController.text = _pastaSalva!['url'] ?? '';
              }
            });
            _adicionarLog('📁 Pasta de certificados carregada do evento');
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar pasta: $e');
    }
  }

  // ============================================================
  // SALVAR PASTA NO FIRESTORE
  // ============================================================
  Future<void> _salvarPastaNoFirestore() async {
    if (_pastaUrlController.text.isEmpty) {
      _mostrarMensagem('Digite a URL da pasta primeiro', Colors.orange);
      return;
    }

    String? pastaId = _extrairPastaId(_pastaUrlController.text);
    if (pastaId == null) {
      _mostrarMensagem('URL da pasta inválida', Colors.red);
      return;
    }

    bool confirmar = await _mostrarConfirmacao(
      'Salvar pasta no evento?',
      'A pasta será vinculada a este evento e poderá ser usada depois.',
    );

    if (!confirmar) return;

    setState(() => _isSalvandoPasta = true);
    _adicionarLog('💾 Salvando pasta no evento...');

    try {
      final pastaData = {
        'id': pastaId,
        'url': _pastaUrlController.text,
        'salvo_em': FieldValue.serverTimestamp(),
        'salvo_por': 'Sistema',
      };

      await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .set({
        'pasta_certificados': pastaData,
      }, SetOptions(merge: true));

      setState(() {
        _pastaSalva = pastaData;
      });

      _adicionarLog('✅ Pasta salva com sucesso!');
      _mostrarMensagem('✅ Pasta salva no evento!', Colors.green);

    } catch (e) {
      _adicionarLog('❌ Erro ao salvar pasta: $e');
      _mostrarMensagem('Erro ao salvar pasta', Colors.red);
    } finally {
      setState(() => _isSalvandoPasta = false);
    }
  }

  void _verificarLinksExistentes() {
    int comLink = 0;
    for (var p in _participantesComCertificado) {
      if (p['link_encontrado'] != null && p['link_encontrado'].toString().isNotEmpty) {
        p['status'] = 'encontrado';
        comLink++;
      }
    }
    if (comLink > 0 && mounted) {
      setState(() {});
      _adicionarLog('📎 $comLink participantes já possuem certificados vinculados');
    }
  }

  void _adicionarLog(String mensagem) {
    if (mounted) {
      setState(() {
        _logs.insert(0, '${DateFormat('HH:mm:ss').format(DateTime.now())} - $mensagem');
      });
    }
    debugPrint('📝 LOG: $mensagem');
  }

  // ============================================================
  // FUNÇÃO PARA EXTRAIR ID DA PASTA
  // ============================================================
  String? _extrairPastaId(String url) {
    _adicionarLog('🔍 Extraindo ID da pasta: $url');

    RegExp regex = RegExp(r'(?:folders/|id=)([a-zA-Z0-9_-]+)');
    var match = regex.firstMatch(url);

    if (match != null && match.groupCount >= 1) {
      String id = match.group(1)!;
      _adicionarLog('✅ ID da pasta extraído: $id');
      return id;
    }

    _adicionarLog('❌ Não foi possível extrair ID da pasta');
    return null;
  }

  // ============================================================
  // FUNÇÃO PARA EXTRAIR ID DO ARQUIVO
  // ============================================================
  String? _extrairFileId(String url) {
    RegExp regex = RegExp(r'(?:/d/|id=)([a-zA-Z0-9_-]+)');
    var match = regex.firstMatch(url);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  // ============================================================
  // FUNÇÃO PARA GERAR LINK DE VISUALIZAÇÃO
  // ============================================================
  String _gerarLinkVisualizacaoWebView(String driveLink) {
    String? fileId = _extrairFileId(driveLink);
    if (fileId != null) {
      return 'https://drive.google.com/uc?export=download&id=$fileId';
    }
    return driveLink;
  }

  // ============================================================
  // FUNÇÃO PARA ABRIR PREVIEW DENTRO DO APP
  // ============================================================
  void _abrirPreviewCertificado(Map<String, dynamic> participante) {
    String? link = participante['link_encontrado'];
    if (link == null || link.isEmpty) {
      _mostrarMensagem('Este participante não tem certificado vinculado', Colors.orange);
      return;
    }

    String pdfLink = _gerarLinkVisualizacaoWebView(link);
    String nomeAluno = participante['aluno_nome'];

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Certificado - $nomeAluno',
              style: const TextStyle(fontSize: 16),
            ),
            backgroundColor: Colors.purple.shade900,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_browser),
                onPressed: () async {
                  final Uri uri = Uri.parse(link);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
          body: WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..setBackgroundColor(const Color(0x00000000))
              ..loadRequest(Uri.parse(pdfLink)),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FUNÇÃO PARA BUSCAR ARQUIVOS NA PASTA
  // ============================================================
  Future<void> _buscarArquivosNaPasta() async {
    if (_pastaUrlController.text.isEmpty) {
      _mostrarMensagem('Digite a URL da pasta do Drive', Colors.orange);
      return;
    }

    String? pastaId = _extrairPastaId(_pastaUrlController.text);
    if (pastaId == null) {
      _mostrarMensagem('URL da pasta inválida', Colors.red);
      return;
    }

    if (mounted) {
      setState(() {
        _isBuscando = true;
        _resultadosBusca = null;
        _logs.clear();
      });
    }

    _adicionarLog('🚀 Iniciando busca na pasta: $pastaId');
    _adicionarLog('📊 Total de participantes: ${widget.participantes.length}');

    try {
      const String apiKey = 'AIzaSyDIpd0CiOsY-07BWXkDPbOsvmlOZsLofRk';

      String url = 'https://www.googleapis.com/drive/v3/files'
          '?q="$pastaId" in parents and trashed=false'
          '&fields=files(id,name,mimeType,webViewLink)'
          '&key=$apiKey';

      _adicionarLog('📡 Fazendo requisição para API do Drive...');

      var response = await http.get(Uri.parse(url));

      if (!mounted) return;

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        List<dynamic> arquivos = data['files'] ?? [];

        List<dynamic> arquivosPdf = arquivos.where((a) =>
        a['mimeType'] == 'application/pdf' ||
            a['name'].toString().toLowerCase().endsWith('.pdf')
        ).toList();

        _adicionarLog('✅ Encontrados ${arquivos.length} arquivos totais');
        _adicionarLog('📄 ${arquivosPdf.length} são PDFs');

        Map<String, Map<String, dynamic>> arquivosPorNome = {};
        for (var arquivo in arquivosPdf) {
          String nome = arquivo['name'] ?? '';
          String nomeSemExtensao = nome.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').toUpperCase().trim();

          arquivosPorNome[nomeSemExtensao] = {
            'id': arquivo['id'],
            'nome': nome,
            'link': 'https://drive.google.com/file/d/${arquivo['id']}/view',
          };
        }

        List<Map<String, dynamic>> participantesAtualizados = [];
        int encontrados = 0;
        int naoEncontrados = 0;

        for (var p in widget.participantes) {
          String nomeAluno = (p['aluno_nome'] ?? '').toString().toUpperCase().trim();
          String nomeAlunoSimplificado = _removerAcentos(nomeAluno);

          Map<String, dynamic>? arquivoEncontrado;

          if (arquivosPorNome.containsKey(nomeAluno)) {
            arquivoEncontrado = arquivosPorNome[nomeAluno];
            _adicionarLog('✅ ENCONTRADO: $nomeAluno');
          }
          else {
            for (var entry in arquivosPorNome.entries) {
              String nomeArquivoSimplificado = _removerAcentos(entry.key);
              if (nomeArquivoSimplificado == nomeAlunoSimplificado) {
                arquivoEncontrado = entry.value;
                _adicionarLog('✅ ENCONTRADO (sem acentos): ${entry.key} para $nomeAluno');
                break;
              }
            }
          }

          if (arquivoEncontrado != null) {
            encontrados++;
            participantesAtualizados.add({
              ...p,
              'link_encontrado': arquivoEncontrado['link'],
              'arquivo_nome': arquivoEncontrado['nome'],
              'status': 'encontrado',
            });
          } else {
            naoEncontrados++;
            participantesAtualizados.add({
              ...p,
              'link_encontrado': p['link_certificado'] ?? '',
              'status': p['link_certificado']?.isNotEmpty == true ? 'encontrado' : 'nao_encontrado',
            });
          }
        }

        if (mounted) {
          setState(() {
            _participantesComCertificado = participantesAtualizados;
            _resultadosBusca = {
              'total': widget.participantes.length,
              'encontrados': encontrados,
              'naoEncontrados': naoEncontrados,
            };
          });
        }

        _adicionarLog('📊 RESULTADO FINAL:');
        _adicionarLog('   ✅ Encontrados: $encontrados');
        _adicionarLog('   ❌ Não encontrados: $naoEncontrados');

        _mostrarMensagem(
          'Busca concluída! $encontrados certificados encontrados',
          encontrados > 0 ? Colors.green : Colors.orange,
        );

        if (_pastaSalva == null && mounted) {
          _perguntarSalvarPasta();
        }

      } else {
        _adicionarLog('❌ Erro na API: ${response.statusCode} - ${response.body}');
        _mostrarMensagem('Erro ao acessar Drive: ${response.statusCode}', Colors.red);
      }
    } catch (e) {
      _adicionarLog('❌ Erro: $e');
      _mostrarMensagem('Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isBuscando = false);
      }
    }
  }

  Future<void> _perguntarSalvarPasta() async {
    bool? salvar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('💾 Salvar pasta?'),
        content: Text(
            'Deseja salvar esta pasta no evento "${widget.eventoNome}" para usar depois?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('NÃO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            child: const Text('SIM, SALVAR'),
          ),
        ],
      ),
    );

    if (salvar == true) {
      await _salvarPastaNoFirestore();
    }
  }

  // ============================================================
  // FUNÇÃO PARA REMOVER ACENTOS
  // ============================================================
  String _removerAcentos(String texto) {
    const comAcentos = 'ÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇáàãâäéèêëíìîïóòõôöúùûüç';
    const semAcentos = 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc';

    String resultado = texto;
    for (int i = 0; i < comAcentos.length; i++) {
      resultado = resultado.replaceAll(comAcentos[i], semAcentos[i]);
    }
    return resultado;
  }

  // ============================================================
  // FUNÇÃO PARA SALVAR LINKS NO FIRESTORE
  // ============================================================
  Future<void> _salvarLinksNoFirestore() async {
    final paraSalvar = _participantesComCertificado
        .where((p) => p['status'] == 'encontrado' && p['link_encontrado']?.isNotEmpty == true)
        .toList();

    if (paraSalvar.isEmpty) {
      _mostrarMensagem('Nenhum certificado para salvar', Colors.orange);
      return;
    }

    bool confirmar = await _mostrarConfirmacao(
      'Salvar ${paraSalvar.length} certificados?',
      'Os links serão salvos no Firestore e aparecerão na finalização da participação.',
    );

    if (!confirmar) return;

    if (mounted) setState(() => _isVinculando = true);
    _adicionarLog('💾 Salvando ${paraSalvar.length} certificados no Firestore...');

    try {
      int salvos = 0;
      int erros = 0;

      for (var p in paraSalvar) {
        try {
          await FirebaseFirestore.instance
              .collection('participacoes_eventos_em_andamento')
              .doc(p['id'])
              .update({
            'link_certificado': p['link_encontrado'],
            'certificado_atualizado_em': FieldValue.serverTimestamp(),
          });

          _adicionarLog('✅ Salvo: ${p['aluno_nome']}');
          salvos++;
        } catch (e) {
          _adicionarLog('❌ Erro ao salvar ${p['aluno_nome']}: $e');
          erros++;
        }
      }

      _adicionarLog('📊 FINALIZADO: $salvos salvos, $erros erros');

      if (mounted) {
        _mostrarMensagem(
          '✅ $salvos certificados salvos!',
          erros == 0 ? Colors.green : Colors.orange,
        );
      }

      if (erros == 0 && mounted) {
        Navigator.pop(context, true);
      }

    } catch (e) {
      _adicionarLog('❌ Erro geral: $e');
      _mostrarMensagem('Erro ao salvar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isVinculando = false);
    }
  }

  // ============================================================
  // FUNÇÃO PARA EDITAR LINK MANUALMENTE
  // ============================================================
  void _editarLinkManualmente(Map<String, dynamic> participante) {
    TextEditingController linkController = TextEditingController(
      text: participante['link_encontrado'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🔗 Editar link - ${participante['aluno_nome']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: linkController,
              decoration: const InputDecoration(
                labelText: 'Link do certificado',
                hintText: 'https://drive.google.com/...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      String link = linkController.text;
                      if (link.isNotEmpty) {
                        Navigator.pop(context);
                        _abrirPreviewCertificado({'link_encontrado': link, 'aluno_nome': participante['aluno_nome']});
                      }
                    },
                    icon: const Icon(Icons.visibility),
                    label: const Text('Visualizar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                participante['link_encontrado'] = linkController.text;
                participante['status'] = linkController.text.isNotEmpty ? 'encontrado' : 'nao_encontrado';
              });
              Navigator.pop(context);
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  Future<bool> _mostrarConfirmacao(String titulo, String mensagem) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('CONFIRMAR'),
          ),
        ],
      ),
    ) ??
        false;
  }

  void _mostrarMensagem(String texto, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> participantesFiltrados = _participantesComCertificado;
    if (_buscaManualController.text.isNotEmpty) {
      String query = _buscaManualController.text.toUpperCase().trim();
      participantesFiltrados = _participantesComCertificado.where((p) {
        return p['aluno_nome'].toString().toUpperCase().contains(query);
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.eventoNome,
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              'Vincular certificados do Drive',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
            ),
          ],
        ),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_pastaSalva != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Pasta salva', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 🔝 ÁREA DA URL DA PASTA
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '📁 URL da pasta do Google Drive',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    if (_pastaSalva != null)
                      Tooltip(
                        message: 'Pasta salva no evento',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '✓ Salva',
                            style: TextStyle(fontSize: 10, color: Colors.green.shade900),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pastaUrlController,
                        decoration: InputDecoration(
                          hintText: 'https://drive.google.com/drive/folders/...',
                          prefixIcon: const Icon(Icons.folder, color: Colors.purple),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isBuscando ? null : _buscarArquivosNaPasta,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isBuscando
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                          : const Text('BUSCAR'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '📌 Os arquivos devem ser PDF com o nome EXATO do aluno',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                    if (_pastaSalva == null && _pastaUrlController.text.isNotEmpty)
                      TextButton.icon(
                        onPressed: _isSalvandoPasta ? null : _salvarPastaNoFirestore,
                        icon: _isSalvandoPasta
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save, size: 16),
                        label: Text(_isSalvandoPasta ? 'Salvando...' : 'Salvar pasta'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.purple,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 🔍 BARRA DE BUSCA MANUAL
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _buscaManualController,
              decoration: InputDecoration(
                hintText: 'Buscar aluno...',
                prefixIcon: const Icon(Icons.search, color: Colors.purple),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: _buscaManualController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.purple),
                  onPressed: () {
                    _buscaManualController.clear();
                    setState(() {});
                  },
                )
                    : null,
              ),
              onChanged: (value) => setState(() {}),
            ),
          ),

          // 📊 RESULTADO DA BUSCA
          if (_resultadosBusca != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${_resultadosBusca!['encontrados']}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const Text('Encontrados', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    height: 40,
                    width: 1,
                    color: Colors.purple.shade300,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${_resultadosBusca!['naoEncontrados']}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const Text('Não encontrados', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    height: 40,
                    width: 1,
                    color: Colors.purple.shade300,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${_resultadosBusca!['total']}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                        const Text('Total', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // 👥 LISTA DE PARTICIPANTES
          Expanded(
            child: participantesFiltrados.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum aluno encontrado',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: participantesFiltrados.length,
              itemBuilder: (context, index) {
                final p = participantesFiltrados[index];
                final encontrado = p['status'] == 'encontrado' && p['link_encontrado']?.isNotEmpty == true;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: encontrado ? Colors.green.shade200 : Colors.orange.shade200,
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: encontrado ? () => _abrirPreviewCertificado(p) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: encontrado ? Colors.green.shade50 : Colors.orange.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              encontrado ? Icons.picture_as_pdf : Icons.error,
                              color: encontrado ? Colors.green : Colors.orange,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['aluno_nome'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (encontrado) ...[
                                  Text(
                                    '📄 ${p['arquivo_nome'] ?? 'Certificado'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '👆 Toque para visualizar no app',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    p['link_encontrado']?.isNotEmpty == true
                                        ? '✅ Link manual salvo'
                                        : '❌ Certificado não encontrado',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: p['link_encontrado']?.isNotEmpty == true
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                  if (p['link_encontrado']?.isNotEmpty == true)
                                    Text(
                                      '👆 Toque para visualizar',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.edit,
                                  color: encontrado ? Colors.green : Colors.orange,
                                  size: 20,
                                ),
                                onPressed: () => _editarLinkManualmente(p),
                              ),
                              if (encontrado || p['link_encontrado']?.isNotEmpty == true)
                                IconButton(
                                  icon: Icon(
                                    Icons.visibility,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  onPressed: () => _abrirPreviewCertificado(p),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 📝 LOGS
          if (_logs.isNotEmpty)
            Container(
              height: 150,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal, color: Colors.green, size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        'LOGS DA BUSCA',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey, size: 16),
                        onPressed: () => setState(() => _logs.clear()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _logs[index],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // BOTÃO SALVAR
          if (_resultadosBusca != null && _participantesComCertificado.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isVinculando ? null : _salvarLinksNoFirestore,
                  icon: const Icon(Icons.save),
                  label: Text(
                    _isVinculando
                        ? 'SALVANDO...'
                        : 'SALVAR ${_participantesComCertificado.where((p) => p['status'] == 'encontrado').length} CERTIFICADOS',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pastaUrlController.dispose();
    _buscaManualController.dispose();
    super.dispose();
  }
}