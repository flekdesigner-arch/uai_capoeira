import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/modules/certificados/data/certificado_template_assets.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_slot_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_studio_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';

/// Serviço responsável por carregar e manipular os SVGs de certificado.
///
/// PONTO IMPORTANTE:
/// A partir desta versão, a coloração do SVG final é feita por substituição
/// de texto nos elementos com id `cor1`, `cor2` e `contornocorda`.
///
/// Motivo:
/// O SVG exportado do Corel tem muitos paths grandes, gradientes e linhas
/// pontilhadas no grupo `fixo`. Quando a gente parseia o SVG inteiro e salva
/// novamente com XML, alguns renderizadores podem interpretar diferente.
/// Então preservamos o SVG original praticamente intacto e trocamos somente
/// os fills dos ids dinâmicos.
class CertificadoSvgService {
  const CertificadoSvgService();

  Future<String> carregarTemplate(CertificadoTemplateTipo tipo) {
    return rootBundle.loadString(CertificadoTemplateAssets.templatePath(tipo));
  }

  Future<String> carregarGuia(CertificadoTemplateTipo tipo) {
    return rootBundle.loadString(CertificadoTemplateAssets.guiaPath(tipo));
  }

  Future<String> gerarPreviewColorido({
    required CertificadoTemplateTipo tipo,
    required Color cor1,
    required Color cor2,
    Color? corContorno,
    Color? corFundo,
    Color? corEstrutura,
    Color? corDestaque,
    Color? corDetalhe,
    CertificadoStudioConfig? studioConfig,
  }) async {
    final svg = studioConfig?.baseEmBranco == true
        ? svgEmBranco(
            widthMm: studioConfig?.larguraDocumentoMm ?? 297,
            heightMm: studioConfig?.alturaDocumentoMm ?? 210,
          )
        : studioConfig?.baseSvgStoragePath?.trim().isNotEmpty == true
            ? await carregarSvgStorage(studioConfig!.baseSvgStoragePath!)
            : await carregarTemplate(tipo);

    var result = aplicarSubstituicoesCores(
      svg,
      studioConfig?.substituicoesCor ?? const {},
    );

    final externalBase = studioConfig?.baseSvgStoragePath?.trim().isNotEmpty == true;
    if (externalBase) {
      // SVG importado do Corel: preservar a arte original.
      // Recoloração só acontece quando o usuário mandar pelo Inspector.
      return result;
    }

    result = aplicarPaletaVisual(
      result,
      corFundo: corFundo,
      corEstrutura: corEstrutura,
      corDestaque: corDestaque,
      corDetalhe: corDetalhe,
    );

    return colorirSvg(
      result,
      cor1: cor1,
      cor2: cor2,
      corContorno: corContorno ?? const Color(0xFF373435),
    );
  }


  String svgEmBranco({double widthMm = 297, double heightMm = 210}) {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="${widthMm}mm" height="${heightMm}mm" viewBox="0 0 $widthMm $heightMm"><rect x="0" y="0" width="$widthMm" height="$heightMm" fill="#EBECEC"/></svg>';
  }

  Future<String> carregarSvgStorage(String storagePath) async {
    final bytes = await FirebaseStorage.instance.ref(storagePath).getData(12 * 1024 * 1024);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('SVG do Studio não encontrado no Storage: $storagePath');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }


  Future<Uint8List> carregarBytesStorage(
    String storagePath, {
    int maxBytes = 12 * 1024 * 1024,
  }) async {
    final bytes = await FirebaseStorage.instance.ref(storagePath).getData(maxBytes);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Arquivo do Studio não encontrado no Storage: $storagePath');
    }
    return bytes;
  }

  String aplicarSubstituicoesCores(String svg, Map<String, String> substituicoes) {
    if (substituicoes.isEmpty) return svg;
    var result = svg;
    final tokens = <String, String>{};
    var index = 0;

    // Duas passagens evitam cascata: #AAAAAA -> #BBBBBB e #BBBBBB -> #CCCCCC
    // não transforma a primeira cor duas vezes por acidente.
    substituicoes.forEach((origem, destino) {
      final o = origem.trim();
      final d = destino.trim();
      if (o.isEmpty || d.isEmpty) return;
      final token = '__UAI_STUDIO_COLOR_${index++}__';
      result = result.replaceAll(
        RegExp(RegExp.escape(o), caseSensitive: false),
        token,
      );
      tokens[token] = d;
    });

    tokens.forEach((token, destino) {
      result = result.replaceAll(token, destino);
    });
    return result;
  }

  Future<List<String>> carregarCamadasSvg(CertificadoStudioConfig? studio) async {
    if (studio == null || studio.camadas.isEmpty) return const [];
    final out = <String>[];
    for (final layer in studio.camadas.where((e) => e.visivel && e.storagePath.trim().isNotEmpty)) {
      var svg = await carregarSvgStorage(layer.storagePath);
      svg = aplicarSubstituicoesCores(svg, layer.substituicoesCor);
      out.add(svg);
    }
    return out;
  }

  Map<String, CertificadoSlotModel> aplicarLayoutsStudio(
    Map<String, CertificadoSlotModel> slots,
    CertificadoStudioConfig? studio,
  ) {
    if (studio == null || studio.blocosLayout.isEmpty) return slots;
    final out = Map<String, CertificadoSlotModel>.from(slots);
    studio.blocosLayout.forEach((id, rect) {
      if (rect.largura <= 0 || rect.altura <= 0) return;
      out[id] = CertificadoSlotModel(
        id: id,
        x: rect.x,
        y: rect.y,
        width: rect.largura,
        height: rect.altura,
      );
    });
    return out;
  }

  /// Recolore a arte fixa do certificado sem reserializar o XML.
  /// Isso preserva os paths do Corel e troca apenas a paleta conhecida
  /// dos templates oficiais. `cor1` e `cor2` continuam reservadas para
  /// as cores dinâmicas da corda/graduação e são aplicadas depois.
  String aplicarPaletaVisual(
    String svg, {
    Color? corFundo,
    Color? corEstrutura,
    Color? corDestaque,
    Color? corDetalhe,
  }) {
    if (svg.trim().isEmpty) return svg;

    var result = svg;

    void replaceHexes(List<String> originais, Color? novaCor) {
      if (novaCor == null) return;
      final hex = _colorToHex(novaCor);
      for (final original in originais) {
        result = result.replaceAll(
          RegExp(RegExp.escape(original), caseSensitive: false),
          hex,
        );
      }
    }

    // Fundo principal do papel/arte.
    replaceHexes(const ['#EBECEC'], corFundo);

    // Estrutura escura: molduras, blocos e tons escuros dos gradientes.
    replaceHexes(
      const ['#373435', '#392C2D', '#502E2D'],
      corEstrutura,
    );

    // Destaques vinho/vermelhos/rosa usados pela identidade visual fixa.
    replaceHexes(
      const ['#ED3237', '#B83336', '#ED2884', '#B71C1C'],
      corDestaque,
    );

    // Cinza de ornamentos e pequenos detalhes.
    replaceHexes(const ['#BDBFC1'], corDetalhe);

    return result;
  }

  String colorirSvg(
    String svg, {
    required Color cor1,
    required Color cor2,
    required Color corContorno,
  }) {
    if (svg.trim().isEmpty) return svg;

    var result = svg;

    result = _replaceFillById(result, 'cor1', _colorToHex(cor1));
    result = _replaceFillById(result, 'cor2', _colorToHex(cor2));
    result = _replaceFillById(
      result,
      'contornocorda',
      _colorToHex(corContorno),
    );

    return result;
  }

  /// Troca o fill apenas do elemento que tem o id informado.
  ///
  /// Exemplo:
  /// `<path id="cor1" ... fill="#FFF212"/>`
  ///
  /// vira:
  /// `<path id="cor1" ... fill="#0000FF"/>`
  ///
  /// O restante do SVG fica intacto.
  String _replaceFillById(String svg, String id, String hex) {
    final regex = RegExp(
      r'(<[a-zA-Z][^>]*\bid="' + RegExp.escape(id) + r'"[^>]*)(/?>)',
      multiLine: true,
    );

    return svg.replaceFirstMapped(regex, (match) {
      var tagStart = match.group(1) ?? '';
      final tagEnd = match.group(2) ?? '>';

      tagStart = _upsertXmlAttribute(tagStart, 'fill', hex);

      // Se este elemento tiver stroke próprio, acompanha a mesma cor.
      // Se não tiver, não criamos stroke para não alterar arte original.
      if (RegExp(r'\bstroke="[^"]*"').hasMatch(tagStart)) {
        tagStart = _upsertXmlAttribute(tagStart, 'stroke', hex);
      }

      // Se tiver style com fill/stroke, também troca dentro do style.
      tagStart = _upsertStylePaintIfExists(tagStart, 'fill', hex);
      tagStart = _upsertStylePaintIfExists(tagStart, 'stroke', hex);

      return '$tagStart$tagEnd';
    });
  }

  String _upsertXmlAttribute(String tagStart, String attr, String value) {
    final attrRegex = RegExp(r'\b' + RegExp.escape(attr) + r'="[^"]*"');

    if (attrRegex.hasMatch(tagStart)) {
      return tagStart.replaceFirst(attrRegex, '$attr="$value"');
    }

    return '$tagStart $attr="$value"';
  }

  String _upsertStylePaintIfExists(
    String tagStart,
    String property,
    String value,
  ) {
    final styleRegex = RegExp(r'style="([^"]*)"');

    return tagStart.replaceFirstMapped(styleRegex, (match) {
      final style = match.group(1) ?? '';
      final updated = _upsertStyleProperty(style, property, value);
      return 'style="$updated"';
    });
  }

  Future<Map<String, CertificadoSlotModel>> carregarSlotsDoGuia(
    CertificadoTemplateTipo tipo,
  ) async {
    final guiaSvg = await carregarGuia(tipo);
    return extrairSlotsDoGuia(guiaSvg);
  }

  Map<String, CertificadoSlotModel> extrairSlotsDoGuia(String guiaSvg) {
    final slots = <String, CertificadoSlotModel>{};

    if (guiaSvg.trim().isEmpty) return slots;

    try {
      final document = xml.XmlDocument.parse(guiaSvg);

      for (final id in CertificadoSlotIds.todos) {
        final element = _findElementById(document, id);
        if (element == null) continue;

        final slot = _slotFromElement(element);
        if (slot != null && slot.isValid) {
          slots[id] = slot;
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao extrair slots do SVG guia: $e');
    }

    return slots;
  }

  CertificadoSlotModel? _slotFromElement(xml.XmlElement element) {
    final id = element.getAttribute('id');
    if (id == null || id.trim().isEmpty) return null;

    final local = element.name.local.toLowerCase();

    if (local == 'rect') {
      final x = _parseSvgNumber(element.getAttribute('x'));
      final y = _parseSvgNumber(element.getAttribute('y'));
      final width = _parseSvgNumber(element.getAttribute('width'));
      final height = _parseSvgNumber(element.getAttribute('height'));

      return CertificadoSlotModel(
        id: id,
        x: x,
        y: y,
        width: width,
        height: height,
      );
    }

    if (local == 'polygon' || local == 'polyline') {
      return _slotFromPoints(id, element.getAttribute('points'));
    }

    if (local == 'path') {
      return _slotFromPathData(id, element.getAttribute('d'));
    }

    if (local == 'g') {
      for (final child in element.descendants.whereType<xml.XmlElement>()) {
        final childSlot = _slotFromElementWithForcedId(child, id);
        if (childSlot != null && childSlot.isValid) return childSlot;
      }
    }

    return null;
  }

  CertificadoSlotModel? _slotFromElementWithForcedId(
    xml.XmlElement element,
    String forcedId,
  ) {
    final local = element.name.local.toLowerCase();

    if (local == 'rect') {
      final x = _parseSvgNumber(element.getAttribute('x'));
      final y = _parseSvgNumber(element.getAttribute('y'));
      final width = _parseSvgNumber(element.getAttribute('width'));
      final height = _parseSvgNumber(element.getAttribute('height'));

      return CertificadoSlotModel(
        id: forcedId,
        x: x,
        y: y,
        width: width,
        height: height,
      );
    }

    if (local == 'polygon' || local == 'polyline') {
      return _slotFromPoints(forcedId, element.getAttribute('points'));
    }

    if (local == 'path') {
      return _slotFromPathData(forcedId, element.getAttribute('d'));
    }

    return null;
  }

  CertificadoSlotModel? _slotFromPoints(String id, String? points) {
    if (points == null || points.trim().isEmpty) return null;

    final numbers = _extractNumbers(points);
    if (numbers.length < 4) return null;

    final xs = <double>[];
    final ys = <double>[];

    for (var i = 0; i + 1 < numbers.length; i += 2) {
      xs.add(numbers[i]);
      ys.add(numbers[i + 1]);
    }

    if (xs.isEmpty || ys.isEmpty) return null;

    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);

    return CertificadoSlotModel(
      id: id,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  CertificadoSlotModel? _slotFromPathData(String id, String? d) {
    if (d == null || d.trim().isEmpty) return null;

    final numbers = _extractNumbers(d);
    if (numbers.length < 4) return null;

    final xs = <double>[];
    final ys = <double>[];

    for (var i = 0; i + 1 < numbers.length; i += 2) {
      xs.add(numbers[i]);
      ys.add(numbers[i + 1]);
    }

    if (xs.isEmpty || ys.isEmpty) return null;

    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);

    return CertificadoSlotModel(
      id: id,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  List<double> _extractNumbers(String value) {
    final regex = RegExp(
      r'-?\d+(?:[\.,]\d+)?(?:e[-+]?\d+)?',
      caseSensitive: false,
    );

    return regex
        .allMatches(value)
        .map((match) => _parseSvgNumber(match.group(0)))
        .toList();
  }

  xml.XmlElement? _findElementById(xml.XmlDocument document, String id) {
    try {
      return document.rootElement.descendants
          .whereType<xml.XmlElement>()
          .firstWhere((element) => element.getAttribute('id') == id);
    } catch (_) {
      return null;
    }
  }

  String _upsertStyleProperty(String style, String property, String value) {
    final parts = style
        .split(';')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    var found = false;

    final updated = parts.map((item) {
      final splitIndex = item.indexOf(':');
      if (splitIndex <= 0) return item;

      final key = item.substring(0, splitIndex).trim();

      if (key == property) {
        found = true;
        return '$property:$value';
      }

      return item;
    }).toList();

    if (!found) {
      updated.insert(0, '$property:$value');
    }

    return updated.join(';');
  }

  double _parseSvgNumber(String? value) {
    if (value == null) return 0.0;

    final cleaned = value
        .trim()
        .replaceAll(',', '.')
        .replaceAll('mm', '')
        .replaceAll('px', '');

    return double.tryParse(cleaned) ?? 0.0;
  }

  String _colorToHex(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2).toUpperCase()}';
  }

  Color colorFromHex(String? hex, {Color fallback = const Color(0xFF9E9E9E)}) {
    final raw = hex?.trim();
    if (raw == null || raw.isEmpty) return fallback;

    try {
      final cleaned = raw.replaceAll('#', '').toUpperCase();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }
}
