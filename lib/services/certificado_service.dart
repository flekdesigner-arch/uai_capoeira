// lib/services/certificado_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/certificado_conversor.dart';

class CertificadoService {
  // Cache das imagens de fundo
  final Map<String, Uint8List> _cacheImagens = {};

  // Cache de fontes
  final Map<String, pw.Font> _cacheFontes = {};
  bool _fontsLoaded = false;

  // Lista de fontes disponíveis
  final List<String> _fontesDisponiveis = [
    'Arial',
    'Arial Black',
    'Courier New',
    'Georgia',
    'Times New Roman',
    'Times New Roman Bold',
    'Verdana',
    'Verdana Bold',
    'Bauhaus 93'
  ];

  // Carrega as fontes
  Future<void> _loadFonts() async {
    if (_fontsLoaded) return;

    try {
      final fontes = {
        'Arial': 'assets/fonts/arial.ttf',
        'Arial Black': 'assets/fonts/ariblk.ttf',
        'Courier New': 'assets/fonts/cour.ttf',
        'Georgia': 'assets/fonts/georgia.ttf',
        'Times New Roman': 'assets/fonts/times.ttf',
        'Times New Roman Bold': 'assets/fonts/timesbd.ttf',
        'Verdana': 'assets/fonts/verdana.ttf',
        'Verdana Bold': 'assets/fonts/verdanab.ttf',
        'Bauhaus 93': 'assets/fonts/bauhs93.ttf',
      };

      for (var entry in fontes.entries) {
        try {
          final fontData = await rootBundle.load(entry.value);
          _cacheFontes[entry.key] = pw.Font.ttf(fontData);
          debugPrint('✅ Fonte carregada: ${entry.key}');
        } catch (e) {
          debugPrint('⚠️ Erro ao carregar ${entry.key}: $e');
        }
      }

      if (!_cacheFontes.containsKey('Arial')) {
        _cacheFontes['Arial'] = pw.Font.helvetica();
      }

      _fontsLoaded = true;
      debugPrint('✅ Total de fontes carregadas: ${_cacheFontes.length}');
    } catch (e) {
      debugPrint('❌ Erro ao carregar fontes: $e');
      _cacheFontes['Arial'] = pw.Font.helvetica();
      _fontsLoaded = true;
    }
  }

  // Carrega imagem dos assets
  Future<Uint8List> _carregarImagemAsset(String path) async {
    if (_cacheImagens.containsKey(path)) {
      return _cacheImagens[path]!;
    }
    final byteData = await rootBundle.load(path);
    final bytes = byteData.buffer.asUint8List();
    _cacheImagens[path] = bytes;
    return bytes;
  }

  // 🔥 GERA O NOME DO ARQUIVO DO FUNDO BASEADO NA GRADUAÇÃO
  String _getFundoPath(Map<String, dynamic> graduacaoData) {
    final nivel = graduacaoData['nivel_graduacao'] ?? 1;
    final tipo = graduacaoData['tipo_publico'] == 'INFANTIL' ? 'i' : 'a';
    final nomeArquivo = '$nivel$tipo.png';

    debugPrint('🖼️ Fundo selecionado: $nomeArquivo (nível $nivel, ${graduacaoData['tipo_publico']})');
    return 'assets/images/certificados/graduacoes/$nomeArquivo';
  }

  // Converte cor Flutter para PdfColor
  PdfColor _colorToPdfColor(Color color) {
    return PdfColor.fromInt(color.value);
  }

  // Converte TextAlign para pw.TextAlign
  pw.TextAlign _textAlignToPwTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.center: return pw.TextAlign.center;
      case TextAlign.right: return pw.TextAlign.right;
      case TextAlign.left: return pw.TextAlign.left;
      case TextAlign.justify: return pw.TextAlign.justify;
      default: return pw.TextAlign.left;
    }
  }

  // Converte string para TextAlign
  TextAlign _getTextAlignFromString(String? align) {
    if (align == 'center') return TextAlign.center;
    if (align == 'right') return TextAlign.right;
    if (align == 'justify') return TextAlign.justify;
    return TextAlign.left;
  }

  // Pega fonte do cache com fallback
  pw.Font _getFont(String fontName) {
    if (_fontesDisponiveis.contains(fontName) && _cacheFontes.containsKey(fontName)) {
      return _cacheFontes[fontName]!;
    }

    if (fontName.contains('Bold') || fontName == 'Arial Black') {
      if (_cacheFontes.containsKey('Arial Black')) {
        return _cacheFontes['Arial Black']!;
      }
    }

    debugPrint('⚠️ Fonte "$fontName" não disponível, usando Arial');
    return _cacheFontes['Arial'] ?? pw.Font.helvetica();
  }

  // Substitui placeholders na frase
  String _substituirPlaceholders(
      String frase, {
        required String alunoNome,
        required String cpf,
        required String titulo,
        required String corda,
      }) {
    return frase
        .replaceAll('{nome}', alunoNome.isNotEmpty ? alunoNome : 'NOME')
        .replaceAll('{cpf}', cpf.isNotEmpty ? cpf : 'CPF')
        .replaceAll('{corda}', corda.isNotEmpty ? corda : 'CORDA')
        .replaceAll('{titulo_graduacao}', titulo.isNotEmpty ? titulo : 'TÍTULO')
        .replaceAll('{titulo}', titulo.isNotEmpty ? titulo : 'TÍTULO');
  }

  // Gera o PDF e já abre para compartilhar
  Future<void> gerarPDFECompartilhar({
    required String alunoNome,
    required String graduacao,
    required String titulo,
    required String corda,
    required String fraseDaGraduacao,
    required Map<String, dynamic> configCertificado,
    required String cpf,
    required String localData,
    required Map<String, dynamic> graduacaoData,
  }) async {
    try {
      await _loadFonts();

      final pdf = pw.Document();

      // 🔥 CARREGA O FUNDO COMPLETO (PNG DA GRADUAÇÃO)
      final fundoPath = _getFundoPath(graduacaoData);
      Uint8List fundoBytes;

      try {
        fundoBytes = await _carregarImagemAsset(fundoPath);
        debugPrint('✅ Fundo carregado: $fundoPath');
      } catch (e) {
        debugPrint('❌ Erro ao carregar fundo $fundoPath: $e');
        // Fallback para um fundo padrão
        fundoBytes = await _carregarImagemAsset('assets/images/certificados/graduacoes/1a.png');
      }

      final fundoImage = pw.MemoryImage(fundoBytes);

      // 🔥 LISTA DE CAMPOS
      final campos = [
        'assinatura1', 'assinatura2', 'assinatura3', 'assinatura4', 'assinatura5',
        'apelido1', 'apelido2', 'apelido3', 'apelido4', 'apelido5',
        'nome_do_aluno', 'cpf', 'localdata', 'frase_unica',
      ];

      debugPrint('🔍 Gerando PDF com todas as configurações...');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(0),
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                // FUNDO COMPLETO (PNG DA GRADUAÇÃO)
                pw.Positioned.fill(
                  child: pw.Image(fundoImage, fit: pw.BoxFit.contain),
                ),

                // TODOS OS CAMPOS DA CONFIGURAÇÃO
                ...campos.map((campoId) {
                  // 🔥 CORREÇÃO: Verifica pelo TIPO DO CERTIFICADO, não pelo ID do modelo
                  final tipoCertificado = configCertificado['tipo_certificado']?.toString() ?? '';

                  // Se for CERTIFICADO (sem CPF), esconde o campo CPF
                  if (tipoCertificado == 'CERTIFICADO' && campoId == 'cpf') {
                    return pw.SizedBox();
                  }

                  // 🔥 USA O MESMO MÉTODO DO VISUALIZADOR - CONVERSÃO PADRONIZADA
                  final x = CertificadoConversor.getValueInMm(
                    configCertificado,
                    campoId,
                    'x',
                    0,
                  );

                  final y = CertificadoConversor.getValueInMm(
                    configCertificado,
                    campoId,
                    'y',
                    0,
                  );

                  final fontSize = CertificadoConversor.getValueInMm(
                    configCertificado,
                    campoId,
                    'fontSize',
                    4,
                  );

                  final maxWidth = CertificadoConversor.getValueInMm(
                    configCertificado,
                    campoId,
                    'maxWidth',
                    100,
                  );

                  final fontFamily = configCertificado['fonte_$campoId']?.toString() ?? 'Arial';

                  final corValue = configCertificado['cor_$campoId'];
                  final cor = corValue != null && corValue is int
                      ? _colorToPdfColor(Color(corValue))
                      : PdfColors.black;

                  final alignStr = configCertificado['alinhamento_$campoId']?.toString() ?? 'left';

                  // Pega o texto para cada campo
                  String texto = '';
                  switch (campoId) {
                    case 'nome_do_aluno':
                      texto = alunoNome.isNotEmpty ? alunoNome : 'NOME DO ALUNO';
                      break;
                    case 'cpf':
                      texto = cpf.isNotEmpty ? cpf : '000.000.000-00';
                      break;
                    case 'frase_unica':
                      String fraseBase = fraseDaGraduacao.isNotEmpty
                          ? fraseDaGraduacao
                          : (configCertificado['frase_unica'] ??
                          'CERTIFICAMOS QUE {nome} CONCLUIU COM ÊXITO O CURSO DE CAPOEIRA.');
                      texto = _substituirPlaceholders(
                        fraseBase,
                        alunoNome: alunoNome,
                        cpf: cpf,
                        titulo: titulo,
                        corda: corda,
                      );
                      break;
                    case 'localdata':
                      texto = localData.isNotEmpty ? localData : 'LOCAL, DATA';
                      break;
                    default:
                      if (campoId.startsWith('assinatura')) {
                        final index = int.parse(campoId.replaceAll('assinatura', '')) - 1;
                        texto = configCertificado['assinatura${index+1}']?.toString() ?? 'ASSINATURA ${index+1}';
                      } else if (campoId.startsWith('apelido')) {
                        final index = int.parse(campoId.replaceAll('apelido', '')) - 1;
                        final apelido = configCertificado['apelido${index+1}']?.toString() ?? '';
                        texto = apelido.isNotEmpty ? '($apelido)' : '(APELIDO)';
                      }
                  }

                  if (texto.isEmpty) return pw.SizedBox();

                  // 🔥 LOG PARA VERIFICAR OS VALORES CONVERTIDOS
                  debugPrint('📐 PDF - Campo $campoId:');
                  debugPrint('   mm: x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}, fontSize=${fontSize.toStringAsFixed(2)}, maxWidth=${maxWidth.toStringAsFixed(2)}');
                  debugPrint('   tipo: $tipoCertificado, visível: ${!(tipoCertificado == 'CERTIFICADO' && campoId == 'cpf')}');

                  return pw.Positioned(
                    left: x,
                    top: y,
                    child: pw.Container(
                      width: maxWidth,
                      child: pw.Text(
                        texto,
                        style: pw.TextStyle(
                          fontSize: fontSize,
                          font: _getFont(fontFamily),
                          color: cor,
                        ),
                        textAlign: _textAlignToPwTextAlign(_getTextAlignFromString(alignStr)),
                        softWrap: true,
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );

      debugPrint('✅ PDF gerado, salvando arquivo...');

      final bytes = await pdf.save();
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'certificado_${alunoNome.replaceAll(' ', '_')}_$timestamp.pdf';
      final tempFile = File('${tempDir.path}/$fileName');

      debugPrint('📁 Salvando em: ${tempFile.path}');
      debugPrint('📦 Tamanho do PDF: ${bytes.length} bytes');

      await tempFile.writeAsBytes(bytes);

      if (await tempFile.exists()) {
        debugPrint('✅ Arquivo salvo com sucesso');
        await Share.shareXFiles(
          [XFile(tempFile.path)],
          text: 'Certificado de $alunoNome',
        );
        debugPrint('✅ Compartilhamento iniciado');
      }

    } catch (e) {
      debugPrint('❌ Erro: $e');
      rethrow;
    }
  }

  // Método original (mantido para compatibilidade)
  Future<String?> gerarCertificado({
    required String eventoId,
    required String participacaoId,
    required String alunoId,
    required String alunoNome,
    required String graduacao,
    required String titulo,
    required String corda,
    required Map<String, dynamic> configCertificado,
    required String cpf,
    required String localData,
  }) async {
    return null;
  }
}