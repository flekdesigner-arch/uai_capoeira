import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:uai_capoeira/modules/alunos/services/mensagem_aniversario_service.dart';
import 'package:uai_capoeira/modules/alunos/models/mensagem_aniversario_model.dart';

class ArteAniversarioScreen extends StatefulWidget {
  final String alunoId;
  final String nomeAluno;
  final String? fotoUrl;

  ArteAniversarioScreen({
    super.key,
    required this.alunoId,
    required this.nomeAluno,
    this.fotoUrl,
  });

  @override
  State<ArteAniversarioScreen> createState() => _ArteAniversarioScreenState();
}

class _ArteAniversarioScreenState extends State<ArteAniversarioScreen> {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }


  MensagemAniversario? _mensagemAtual;
  bool _carregando = true;
  bool _baixando = false;
  final GlobalKey _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _carregarNovaMensagem();
  }

  Future<void> _carregarNovaMensagem() async {
    setState(() => _carregando = true);
    final mensagem = await MensagemAniversarioService().getMensagemAleatoria();
    setState(() {
      _mensagemAtual = mensagem;
      _carregando = false;
    });
  }

  // Pega só primeiro e segundo nome
  String _getPrimeiroESegundoNome(String nomeCompleto) {
    List<String> nomes = nomeCompleto.split(' ');
    if (nomes.length >= 2) {
      return '${nomes[0]} ${nomes[1]}';
    }
    return nomes[0];
  }

  List<String> _quebrarMensagem(String texto, String primeiroNome) {
    // Substitui o nome completo pelo primeiro nome na mensagem
    String textoFormatado = texto.replaceAll(RegExp(r'\{nome\}'), primeiroNome);

    List<String> palavras = textoFormatado.split(' ');
    List<String> linhas = [];
    String linhaAtual = '';
    int maxCaracteres = 45;

    for (String palavra in palavras) {
      String teste = linhaAtual.isEmpty ? palavra : '$linhaAtual $palavra';
      if (teste.length <= maxCaracteres) {
        linhaAtual = teste;
      } else {
        if (linhaAtual.isNotEmpty) {
          linhas.add(linhaAtual);
          linhaAtual = palavra;
        }
      }
    }
    if (linhaAtual.isNotEmpty) {
      linhas.add(linhaAtual);
    }

    // Limita a 3 linhas
    return linhas.take(3).toList();
  }

  // Função para escanear arquivo e aparecer na galeria
  Future<void> _scanFile(String path) async {
    try {
      if (Platform.isAndroid) {
        // Usar MethodChannel para chamar o MediaScanner no Android
        await MethodChannel('com.example.uai_capoeira/media')
            .invokeMethod('scanFile', {'path': path});
      }
    } catch (e) {
      print('Erro ao escanear arquivo: $e');
    }
  }

  // Função para baixar a imagem
  Future<void> _baixarArte() async {
    setState(() => _baixando = true);

    try {
      // Solicitar permissão
      PermissionStatus status = await Permission.storage.request();

      if (Platform.isAndroid) {
        // Para Android 13+, também verificar photos
        if (await Permission.photos.isGranted) {
          status = PermissionStatus.granted;
        }
      }

      if (status.isGranted) {
        // Capturar o widget como imagem
        RenderRepaintBoundary boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        Uint8List pngBytes = byteData!.buffer.asUint8List();

        // Diretório de destino
        Directory? directory;
        if (Platform.isAndroid) {
          // Tenta salvar no Download primeiro
          directory = Directory('/storage/emulated/0/Download');

          if (!await directory.exists()) {
            // Se não existir, usa Pictures
            directory = Directory('/storage/emulated/0/Pictures');
          }

          if (!await directory.exists()) {
            // Último recurso: diretório externo
            directory = await getExternalStorageDirectory();
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        if (directory != null) {
          // Nome do arquivo
          String fileName = 'arte_aniversario_${DateTime.now().millisecondsSinceEpoch}.png';
          String filePath = '${directory.path}/$fileName';

          // Salvar arquivo
          File file = File(filePath);
          await file.writeAsBytes(pngBytes);

          // Escanear para aparecer na galeria
          await _scanFile(filePath);

          if (mounted) {
            _mostrarOpcoesAposDownload(context, filePath);
          }
        } else {
          throw Exception('Diretório não encontrado');
        }
      } else {
        // Se não tiver permissão, abrir configurações
        _mostrarDialogoPermissao();
      }
    } catch (e) {
      print('Erro no download: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao baixar: ${e.toString()}'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _baixando = false);
      }
    }
  }

  void _mostrarDialogoPermissao() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permissão necessária'),
        content: Text(
            'Precisamos de permissão para salvar a arte no seu dispositivo. '
                'Deseja abrir as configurações e permitir o acesso?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Agora não'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.primary,
            ),
            child: Text('Abrir configurações'),
          ),
        ],
      ),
    );
  }

  void _mostrarOpcoesAposDownload(BuildContext context, String filePath) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: context.uai.success, size: 60),
            SizedBox(height: 8),
            Text(
              'Arte salva com sucesso!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'O que deseja fazer?',
              style: TextStyle(color: context.uai.textSecondary),
            ),
            SizedBox(height: 20),

            // Botão Abrir Galeria
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.uai.info.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.photo_library, color: context.uai.info),
              ),
              title: Text('Abrir Galeria'),
              subtitle: Text('Ver a arte na galeria', style: TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.pop(context);
                if (Platform.isAndroid) {
                  try {
                    await MethodChannel('com.example.uai_capoeira/media')
                        .invokeMethod('openGallery');
                  } catch (e) {
                    // Se não conseguir abrir a galeria, mostra mensagem
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Arte salva em Downloads/Pictures'),
                        ),
                      );
                    }
                  }
                }
              },
            ),

            // Botão Compartilhar
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.uai.success.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.share, color: context.uai.success),
              ),
              title: Text('Compartilhar'),
              subtitle: Text('Enviar via WhatsApp ou outros apps', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _compartilharArte(filePath);
              },
            ),

            // Botão Abrir Pasta
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.uai.warning.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.folder_open, color: context.uai.warning),
              ),
              title: Text('Abrir Pasta'),
              subtitle: Text('Ver arquivo no gerenciador de arquivos', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                // Abrir pasta não é fácil, então mostra localização
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Arquivo salvo em: $filePath'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              },
            ),

            SizedBox(height: 10),

            // Botão Fechar
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('FECHAR'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _compartilharArte(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        // Compartilha apenas o arquivo, sem texto adicional
        await Share.shareXFiles([XFile(filePath)]);
      }
    } catch (e) {
      print('Erro ao compartilhar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao compartilhar: $e')),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.card,
      appBar: AppBar(
        title: Text(
          'Arte de Aniversário',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _carregarNovaMensagem,
            tooltip: 'Nova mensagem',
          ),
        ],
      ),
      body: _carregando
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: context.uai.error),
            SizedBox(height: 20),
            Text(
              'Gerando arte especial...',
              style: TextStyle(color: context.uai.textSecondary),
            ),
          ],
        ),
      )
          : _buildArte(),
    );
  }

  Widget _buildArte() {
    if (_mensagemAtual == null) return SizedBox();

    final primeiroESegundoNome = _getPrimeiroESegundoNome(widget.nomeAluno);
    final primeiroNome = widget.nomeAluno.split(' ')[0];
    final textoPersonalizado = _mensagemAtual!.getTextoComNome(primeiroNome);
    final linhas = _quebrarMensagem(textoPersonalizado, primeiroNome);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            // Container da arte (capturável)
            RepaintBoundary(
              key: _repaintKey,
              child: Center(
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: context.uai.textPrimary.withOpacity(0.2),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AspectRatio(
                      aspectRatio: 1080 / 1600,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          double alturaReal = constraints.maxHeight;
                          double larguraReal = constraints.maxWidth;

                          // POSIÇÕES DOS ELEMENTOS
                          double fotoTopReal = (433.91 / 1600) * alturaReal;
                          double nomeTopReal = (940.0 / 1600) * alturaReal;
                          double msgTopReal = (1078.0 / 1600) * alturaReal;
                          double quadradoSize = 613.59 * (alturaReal / 1600);

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              // FUNDO
                              Image.asset(
                                'assets/images/fundo_aniversario_app_flutter.png',
                                fit: BoxFit.cover,
                              ),

                              // FOTO DO ALUNO
                              Positioned(
                                top: fotoTopReal,
                                left: (larguraReal - quadradoSize) / 2,
                                child: Container(
                                  width: quadradoSize,
                                  height: quadradoSize,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(quadradoSize * 0.05),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(quadradoSize * 0.05),
                                    child: widget.fotoUrl != null
                                        ? CachedNetworkImage(
                                      imageUrl: widget.fotoUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: context.uai.border,
                                        child: Center(
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: context.uai.border,
                                        child: Icon(Icons.person, size: quadradoSize * 0.3),
                                      ),
                                    )
                                        : Container(
                                      color: context.uai.border,
                                      child: Icon(Icons.person, size: quadradoSize * 0.3),
                                    ),
                                  ),
                                ),
                              ),

                              // NOME
                              Positioned(
                                top: nomeTopReal,
                                left: 0,
                                right: 0,
                                child: Text(
                                  primeiroESegundoNome.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 38 * (alturaReal/1600 * 1.3),
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Arial',
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 8,
                                        offset: Offset(2, 2),
                                      ),
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 8,
                                        offset: Offset(-2, -2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // MENSAGEM
                              Positioned(
                                top: msgTopReal,
                                left: 0,
                                right: 0,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0; i < linhas.length; i++)
                                        Padding(
                                          padding: EdgeInsets.symmetric(vertical: 0),
                                          child: Text(
                                            linhas[i],
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 32 * (alturaReal/1600 * 1.3),
                                              fontFamily: 'Arial',
                                              fontWeight: FontWeight.w600,
                                              height: 1.0,
                                              shadows: const [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 6,
                                                  offset: Offset(2, 2),
                                                ),
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 6,
                                                  offset: Offset(-2, -2),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: 30),

            // BOTÕES
            Row(
              children: [
                Expanded(
                  child: _buildBotaoGradiente(
                    onPressed: _carregarNovaMensagem,
                    icon: Icons.refresh,
                    label: 'NOVA MENSAGEM',
                    corInicio: context.uai.info,
                    corFim: context.uai.info,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _buildBotaoGradiente(
                    onPressed: _baixando ? null : _baixarArte,
                    icon: Icons.download,
                    label: _baixando ? 'BAIXANDO...' : 'BAIXAR',
                    corInicio: context.uai.success,
                    corFim: context.uai.success,
                  ),
                ),
              ],
            ),

            SizedBox(height: 12),

            // BOTÃO VOLTAR
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.uai.primary.withOpacity(0.5), width: 2),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back, color: context.uai.error),
                        SizedBox(width: 8),
                        Text(
                          'VOLTAR',
                          style: TextStyle(
                            color: context.uai.error,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoGradiente({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color corInicio,
    required Color corFim,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [corInicio, corFim],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: corFim.withOpacity(0.5),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: context.uai.textPrimary, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
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
}
