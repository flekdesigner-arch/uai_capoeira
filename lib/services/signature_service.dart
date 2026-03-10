import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:math';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SignatureService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 VERIFICAR SE O STORAGE ESTÁ ACESSÍVEL
  Future<bool> _verificarStorage() async {
    try {
      final testRef = _storage.ref().child('test.txt');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao acessar Storage: $e');
      return false;
    }
  }

  // 🔥 CONVERTER ASSINATURA PARA IMAGEM - AGORA COM RECORTE E CENTRALIZAÇÃO
  Future<Uint8List?> signatureToImage(
      BuildContext context,
      List<List<Offset>> points, {
        double padding = 20.0, // Espaço ao redor da assinatura
        double strokeWidth = 3.0,
        Color backgroundColor = Colors.white,
        Color penColor = Colors.black,
      }) async {
    try {
      debugPrint('🎨 Convertendo assinatura para imagem...');

      if (points.isEmpty) {
        debugPrint('⚠️ Nenhum ponto para desenhar');
        return null;
      }

      // ================================================================
      // PASSO 1: Calcular os limites reais da assinatura
      // ================================================================
      double minX = double.infinity;
      double minY = double.infinity;
      double maxX = double.negativeInfinity;
      double maxY = double.negativeInfinity;

      for (var stroke in points) {
        for (var point in stroke) {
          minX = min(minX, point.dx);
          minY = min(minY, point.dy);
          maxX = max(maxX, point.dx);
          maxY = max(maxY, point.dy);
        }
      }

      // Se não encontrou pontos válidos
      if (minX == double.infinity) {
        debugPrint('⚠️ Pontos inválidos');
        return null;
      }

      // ================================================================
      // PASSO 2: Calcular dimensões com padding
      // ================================================================
      double width = maxX - minX + (padding * 2);
      double height = maxY - minY + (padding * 2);

      // Garantir tamanho mínimo (para assinaturas muito pequenas)
      width = max(width, 200);
      height = max(height, 100);

      // Limitar tamanho máximo (para não ficar gigante)
      width = min(width, 800);
      height = min(height, 400);

      debugPrint('📏 Dimensões calculadas: ${width.toInt()}x${height.toInt()}');
      debugPrint('📐 Limites da assinatura: X($minX-$maxX) Y($minY-$maxY)');

      // ================================================================
      // PASSO 3: Criar canvas com as dimensões calculadas
      // ================================================================
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // Fundo branco
      final bgPaint = Paint()..color = backgroundColor;
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

      // ================================================================
      // PASSO 4: Desenhar assinatura CENTRALIZADA
      // ================================================================
      final paint = Paint()
        ..color = penColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // Calcular o deslocamento para centralizar
      double offsetX = padding - minX;
      double offsetY = padding - minY;

      for (var stroke in points) {
        if (stroke.length < 2) continue;

        for (int i = 0; i < stroke.length - 1; i++) {
          // Aplicar o offset para centralizar
          final p1 = Offset(stroke[i].dx + offsetX, stroke[i].dy + offsetY);
          final p2 = Offset(stroke[i + 1].dx + offsetX, stroke[i + 1].dy + offsetY);

          canvas.drawLine(p1, p2, paint);
        }
      }

      // ================================================================
      // PASSO 5: Gerar imagem
      // ================================================================
      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      debugPrint('✅ Assinatura convertida com sucesso - Tamanho final: ${width.toInt()}x${height.toInt()}');
      return byteData?.buffer.asUint8List();

    } catch (e) {
      debugPrint('❌ Erro ao converter assinatura: $e');
      return null;
    }
  }

  // 🔥 SALVAR ASSINATURA NO STORAGE
  Future<String?> salvarAssinatura({
    required Uint8List imageData,
    required String inscricaoId,
    required String nomeResponsavel,
    required String nomeAluno,
  }) async {
    try {
      debugPrint('📤 Iniciando upload da assinatura...');

      // Verificar storage
      final storageOk = await _verificarStorage();
      if (!storageOk) {
        throw Exception('Storage não está acessível');
      }

      // Gerar nome único
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(10000);
      final nomeLimpo = nomeResponsavel.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
      final fileName = 'assinatura_${nomeLimpo}_$timestamp$random.png';

      debugPrint('📁 Nome do arquivo: $fileName');

      // Referência no Storage
      final ref = _storage.ref().child('assinaturas').child(fileName);

      // Metadata
      final metadata = SettableMetadata(
        contentType: 'image/png',
        customMetadata: {
          'inscricao_id': inscricaoId,
          'responsavel': nomeResponsavel,
          'aluno': nomeAluno,
          'data': DateTime.now().toIso8601String(),
        },
      );

      // Upload
      debugPrint('⏫ Fazendo upload...');
      final uploadTask = await ref.putData(imageData, metadata);
      debugPrint('✅ Upload concluído: ${uploadTask.bytesTransferred} bytes');

      // Pegar URL
      final imageUrl = await ref.getDownloadURL();
      debugPrint('🔗 URL gerada: $imageUrl');

      // Salvar referência no Firestore
      try {
        await _firestore.collection('assinaturas').doc(fileName).set({
          'inscricao_id': inscricaoId,
          'image_url': imageUrl,
          'data_hora': DateTime.now().toIso8601String(),
          'nome_responsavel': nomeResponsavel,
          'nome_aluno': nomeAluno,
          'arquivo': fileName,
        });
        debugPrint('✅ Referência salva no Firestore');
      } catch (e) {
        debugPrint('⚠️ Erro ao salvar no Firestore (mas upload ok): $e');
      }

      return imageUrl;

    } catch (e) {
      debugPrint('❌ Erro ao salvar assinatura: $e');
      return null;
    }
  }

  // 🔥 MÉTODO ALTERNATIVO - Salvar como arquivo temporário primeiro
  Future<String?> salvarAssinaturaAlternativo({
    required Uint8List imageData,
    required String inscricaoId,
    required String nomeResponsavel,
    required String nomeAluno,
  }) async {
    try {
      debugPrint('📝 Usando método alternativo...');

      // Salvar arquivo temporário
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/assinatura_temp.png');
      await tempFile.writeAsBytes(imageData);
      debugPrint('✅ Arquivo temporário criado: ${tempFile.path}');

      // Fazer upload do arquivo
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(10000);
      final nomeLimpo = nomeResponsavel.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
      final fileName = 'assinatura_${nomeLimpo}_$timestamp$random.png';

      final ref = _storage.ref().child('assinaturas').child(fileName);

      debugPrint('⏫ Upload do arquivo...');
      await ref.putFile(tempFile);

      final imageUrl = await ref.getDownloadURL();
      debugPrint('✅ Upload alternativo concluído');

      // Limpar arquivo temporário
      await tempFile.delete();
      debugPrint('🧹 Arquivo temporário removido');

      return imageUrl;

    } catch (e) {
      debugPrint('❌ Erro no método alternativo: $e');
      return null;
    }
  }
}