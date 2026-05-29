// lib/utils/certificado_conversor.dart

import 'package:flutter/material.dart';

class CertificadoConversor {
  // Constantes A4 (medidas em milímetros)
  static const double A4_WIDTH_MM = 297.0;
  static const double A4_HEIGHT_MM = 210.0;
  static const double MAX_FONT_SIZE_MM = 50.0;

  /// Converte porcentagem para milímetros
  /// Ex: percentToMm(50, 297) = 148.5 mm
  static double percentToMm(double percent, double maxSize) {
    return (percent / 100) * maxSize;
  }

  /// Converte milímetros para porcentagem
  /// Ex: mmToPercent(148.5, 297) = 50%
  static double mmToPercent(double mm, double maxSize) {
    return (mm / maxSize) * 100;
  }

  /// Obtém valor em milímetros a partir da configuração do Firestore
  ///
  /// [config] - Mapa com os dados do Firestore
  /// [campoId] - ID do campo (ex: 'nome_do_aluno')
  /// [tipo] - Tipo do valor: 'x', 'y', 'fontSize', 'maxWidth'
  /// [defaultValue] - Valor padrão caso não encontre
  ///
  /// Esta função é INTELIGENTE:
  /// - Se o valor for > 100, assume que já está em mm (dado antigo)
  /// - Se o valor for <= 100, assume que está em % e converte para mm
  static double getValueInMm(
      Map<String, dynamic> config,
      String campoId,
      String tipo,
      double defaultValue,
      ) {
    // Constrói a chave no Firestore (ex: 'pos_x_nome_do_aluno')
    final key = _getKey(campoId, tipo);
    final value = config[key];

    // Se não encontrar, retorna o valor padrão
    if (value == null) {
      debugPrint('⚠️ $key não encontrado, usando default: $defaultValue');
      return defaultValue;
    }

    // Converte para double
    double rawValue;
    if (value is num) {
      rawValue = value.toDouble();
    } else {
      rawValue = double.tryParse(value.toString()) ?? defaultValue;
    }

    // Determina o tamanho máximo baseado no tipo
    double maxSize;
    switch (tipo) {
      case 'x':
      case 'maxWidth':
        maxSize = A4_WIDTH_MM;
        break;
      case 'y':
        maxSize = A4_HEIGHT_MM;
        break;
      case 'fontSize':
        maxSize = MAX_FONT_SIZE_MM;
        break;
      default:
        maxSize = A4_WIDTH_MM;
    }

    // REGRA DE NEGÓCIO IMPORTANTE:
    // Se rawValue > 100, significa que é um dado ANTIGO (já estava em mm)
    // Se rawValue <= 100, significa que é um dado NOVO (está em %)
    if (rawValue > 100) {
      debugPrint('📏 $key está em MM (dado antigo): $rawValue');
      return rawValue;
    } else {
      // Converte % para mm
      final mmValue = percentToMm(rawValue, maxSize);
      debugPrint('📏 $key está em %: $rawValue% → ${mmValue.toStringAsFixed(2)}mm');
      return mmValue;
    }
  }

  /// Gera o mapa para salvar no Firestore (SEMPRE em porcentagem)
  ///
  /// [configEmMm] - Mapa com valores em milímetros (vindo dos controllers)
  /// [campos] - Lista de todos os campos possíveis
  ///
  /// Retorna um novo mapa com TODOS os valores convertidos para %
  static Map<String, dynamic> gerarConfigParaSalvar(
      Map<String, dynamic> configEmMm,
      List<String> campos,
      ) {
    final configParaSalvar = <String, dynamic>{};

    // PASSO 1: Copia todos os campos que NÃO são de posição
    // (textos, modelo_id, tipo, etc)
    configEmMm.forEach((key, value) {
      if (!key.startsWith('pos_x_') &&
          !key.startsWith('pos_y_') &&
          !key.startsWith('font_size_') &&
          !key.startsWith('max_width_')) {
        configParaSalvar[key] = value;
      }
    });

    // PASSO 2: Converte as posições de mm para %
    for (var campo in campos) {
      // Posição X
      if (configEmMm['pos_x_$campo'] != null) {
        final xMm = double.tryParse(configEmMm['pos_x_$campo'].toString()) ?? 0;
        configParaSalvar['pos_x_$campo'] = mmToPercent(xMm, A4_WIDTH_MM);
        debugPrint('💾 Convertendo pos_x_$campo: ${xMm}mm → ${configParaSalvar['pos_x_$campo']}%');
      }

      // Posição Y
      if (configEmMm['pos_y_$campo'] != null) {
        final yMm = double.tryParse(configEmMm['pos_y_$campo'].toString()) ?? 0;
        configParaSalvar['pos_y_$campo'] = mmToPercent(yMm, A4_HEIGHT_MM);
        debugPrint('💾 Convertendo pos_y_$campo: ${yMm}mm → ${configParaSalvar['pos_y_$campo']}%');
      }

      // Tamanho da fonte
      if (configEmMm['font_size_$campo'] != null) {
        final fontSizeMm = double.tryParse(configEmMm['font_size_$campo'].toString()) ?? 4;
        configParaSalvar['font_size_$campo'] = mmToPercent(fontSizeMm, MAX_FONT_SIZE_MM);
        debugPrint('💾 Convertendo font_size_$campo: ${fontSizeMm}mm → ${configParaSalvar['font_size_$campo']}%');
      }

      // Largura máxima
      if (configEmMm['max_width_$campo'] != null) {
        final maxWidthMm = double.tryParse(configEmMm['max_width_$campo'].toString()) ?? 100;
        configParaSalvar['max_width_$campo'] = mmToPercent(maxWidthMm, A4_WIDTH_MM);
        debugPrint('💾 Convertendo max_width_$campo: ${maxWidthMm}mm → ${configParaSalvar['max_width_$campo']}%');
      }
    }

    debugPrint('✅ Configuração convertida para % e pronta para salvar');
    return configParaSalvar;
  }

  /// Carrega configuração do Firestore e já converte para mm para exibição
  ///
  /// [config] - Mapa do Firestore (valores em %)
  /// [campos] - Lista de todos os campos
  ///
  /// Retorna um novo mapa com TODOS os valores em mm para exibição
  static Map<String, dynamic> carregarConfigParaExibicao(
      Map<String, dynamic> config,
      List<String> campos,
      ) {
    final configParaExibicao = <String, dynamic>{};

    // PASSO 1: Copia todos os campos que NÃO são de posição
    config.forEach((key, value) {
      if (!key.startsWith('pos_x_') &&
          !key.startsWith('pos_y_') &&
          !key.startsWith('font_size_') &&
          !key.startsWith('max_width_')) {
        configParaExibicao[key] = value;
      }
    });

    // PASSO 2: Converte as posições de % para mm
    for (var campo in campos) {
      // Posição X
      if (config['pos_x_$campo'] != null) {
        final xPercent = double.tryParse(config['pos_x_$campo'].toString()) ?? 0;
        configParaExibicao['pos_x_$campo'] = percentToMm(xPercent, A4_WIDTH_MM);
      }

      // Posição Y
      if (config['pos_y_$campo'] != null) {
        final yPercent = double.tryParse(config['pos_y_$campo'].toString()) ?? 0;
        configParaExibicao['pos_y_$campo'] = percentToMm(yPercent, A4_HEIGHT_MM);
      }

      // Tamanho da fonte
      if (config['font_size_$campo'] != null) {
        final fontSizePercent = double.tryParse(config['font_size_$campo'].toString()) ?? 4;
        configParaExibicao['font_size_$campo'] = percentToMm(fontSizePercent, MAX_FONT_SIZE_MM);
      }

      // Largura máxima
      if (config['max_width_$campo'] != null) {
        final maxWidthPercent = double.tryParse(config['max_width_$campo'].toString()) ?? 100;
        configParaExibicao['max_width_$campo'] = percentToMm(maxWidthPercent, A4_WIDTH_MM);
      }
    }

    return configParaExibicao;
  }

  /// Converte um valor em porcentagem para o tipo específico
  /// Versão simplificada quando você já tem o valor em %
  static double percentToMmByType(double percent, String tipo) {
    switch (tipo) {
      case 'x':
      case 'maxWidth':
        return percentToMm(percent, A4_WIDTH_MM);
      case 'y':
        return percentToMm(percent, A4_HEIGHT_MM);
      case 'fontSize':
        return percentToMm(percent, MAX_FONT_SIZE_MM);
      default:
        return percentToMm(percent, A4_WIDTH_MM);
    }
  }

  /// Constrói a chave do Firestore baseada no campo e tipo
  static String _getKey(String campoId, String tipo) {
    switch (tipo) {
      case 'x': return 'pos_x_$campoId';
      case 'y': return 'pos_y_$campoId';
      case 'fontSize': return 'font_size_$campoId';
      case 'maxWidth': return 'max_width_$campoId';
      default: return '';
    }
  }

  /// Valida se um valor está dentro dos limites aceitáveis
  static bool isValorValido(double valor, String tipo) {
    switch (tipo) {
      case 'x':
      case 'maxWidth':
        return valor >= 0 && valor <= A4_WIDTH_MM;
      case 'y':
        return valor >= 0 && valor <= A4_HEIGHT_MM;
      case 'fontSize':
        return valor > 0 && valor <= MAX_FONT_SIZE_MM;
      default:
        return true;
    }
  }
}