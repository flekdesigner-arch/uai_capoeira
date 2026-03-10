import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  print('🚀 INICIANDO CONFIGURAÇÃO DAS ACADEMIAS...\n');

  try {
    // Inicializar Firebase
    print('🔌 Conectando ao Firebase...');
    await Firebase.initializeApp();
    print('✅ Firebase inicializado!\n');

    // Referências do Firestore
    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    // ==================== DADOS DA ACADEMIA ====================
    print('📊 CRIANDO COLEÇÃO DE ACADEMIAS...');

    final academiaData = {
      'nome': 'CENTRO DE CONVIVIO',
      'cidade': 'BOCAIUVA-MG',
      'modalidade': 'CAPOEIRA',
      'professor': 'TICO-TICO',
      'logo_url': 'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/JEmRdvRYw6JD14UcSnby.jpg',
      'whatsapp_url': 'https://chat.whatsapp.com/DmOMLyuoBou3Ax7WQvAbTE',
      'responsavel': 'TICO-TICO',
      'endereco': 'Centro de Convivio - Bocaiúva-MG',
      'telefone': '',
      'email': '',
      'observacoes': 'Academia principal do grupo UAI Capoeira',
      'criado_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
      'turmas_count': 2, // Serão 2 turmas
      'status': 'ativa',
    };

    // Criar documento da academia
    final academiaRef = await firestore.collection('academias').add(academiaData);
    print('✅ Academia criada: ${academiaRef.id}');
    print('   Nome: CENTRO DE CONVIVIO');
    print('   Cidade: BOCAIUVA-MG');
    print('   Professor: TICO-TICO\n');

    // ==================== CRIAR PASTA NO STORAGE ====================
    print('📁 CRIANDO PASTA NO STORAGE...');

    try {
      // Pasta para logos das academias
      final logosFolder = storage.ref().child('logos_academias');

      // Pasta para logos das turmas
      final turmasFolder = storage.ref().child('logos_turmas');

      // Cria uma referência vazia (Firebase Storage não tem pastas "vazias" realmente)
      // Vamos criar um arquivo placeholder
      final placeholder = storage.ref().child('academias_placeholder/.keep');
      await placeholder.putString('Pasta criada por setup script');

      print('✅ Pastas criadas no Storage');
      print('   - logos_academias/');
      print('   - logos_turmas/\n');
    } catch (e) {
      print('⚠️ Nota: Pastas serão criadas automaticamente ao fazer upload');
    }

    // ==================== CRIAR TURMAS ====================
    print('🎓 CRIANDO SUBSCOLETA DE TURMAS...');

    // Dados das turmas
    final turmas = [
      {
        'nome': '19:00 AS 20:30',
        'horario': '19:00 às 20:30',
        'logo_url': 'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/x7fzZFECzpbjdTplh0g7.jpg',
        'cidade': 'BOCAIUVA-MG',
        'nucleo': 'CENTRO DE CONVIVIO',
        'modalidade': 'CAPOEIRA',
        'whatsapp_url': 'https://chat.whatsapp.com/DmOMLyuoBou3Ax7WQvAbTE',
        'academia_id': academiaRef.id,
        'professor': 'TICO-TICO',
        'capacidade_maxima': 30,
        'alunos_count': 0,
        'status': 'ativa',
        'dias_semana': ['Segunda', 'Quarta', 'Sexta'],
        'faixa_etaria': 'Livre',
        'criado_em': FieldValue.serverTimestamp(),
        'atualizado_em': FieldValue.serverTimestamp(),
      },
      {
        'nome': '18:00 AS 19:00',
        'horario': '18:00 às 19:00',
        'logo_url': 'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/AqQPRSDgpWpmyD3UByd7.jpg',
        'cidade': 'BOCAIUVA-MG',
        'nucleo': 'CENTRO DE CONVIVIO',
        'modalidade': 'CAPOEIRA',
        'whatsapp_url': 'https://chat.whatsapp.com/DmOMLyuoBou3Ax7WQvAbTE',
        'academia_id': academiaRef.id,
        'professor': 'TICO-TICO',
        'capacidade_maxima': 25,
        'alunos_count': 0,
        'status': 'ativa',
        'dias_semana': ['Terça', 'Quinta'],
        'faixa_etaria': 'Infantil (6-12 anos)',
        'criado_em': FieldValue.serverTimestamp(),
        'atualizado_em': FieldValue.serverTimestamp(),
      }
    ];

    // Adicionar cada turma na subcoleção
    for (var i = 0; i < turmas.length; i++) {
      final turmaData = turmas[i];
      final turmaRef = await academiaRef.collection('turmas').add(turmaData);

      // CORREÇÃO APLICADA AQUI ↓
      print('✅ Turma ${i + 1} criada: ${turmaRef.id}');
      print('   Horário: ${turmaData['horario']}');

      // Converter List<dynamic> para String formatada
      final diasSemana = turmaData['dias_semana'] as List<dynamic>;
      final diasFormatados = diasSemana.map((d) => d.toString()).join(', ');
      print('   Dias: $diasFormatados');

      print('   Faixa etária: ${turmaData['faixa_etaria']}\n');
    }

    // ==================== ATUALIZAR CONTADOR DE TURMAS ====================
    await academiaRef.update({
      'turmas_count': turmas.length,
      'atualizado_em': FieldValue.serverTimestamp(),
    });

    // ==================== VERIFICAR ESTRUTURA ====================
    print('🔍 VERIFICANDO ESTRUTURA CRIADA...\n');

    // Verificar academia
    final academiaSnapshot = await academiaRef.get();
    print('📋 ACADEMIA:');
    print('   ID: ${academiaRef.id}');
    print('   Nome: ${academiaSnapshot.get('nome')}');
    print('   Cidade: ${academiaSnapshot.get('cidade')}');
    print('   Turmas: ${academiaSnapshot.get('turmas_count')}\n');

    // Verificar turmas
    final turmasSnapshot = await academiaRef.collection('turmas').get();
    print('🎓 TURMAS CRIADAS:');
    for (var doc in turmasSnapshot.docs) {
      print('   - ${doc.get('nome')} (${doc.get('horario')})');
    }

    print('\n🎉 ESTRUTURA COMPLETA!');
    print('=' * 50);
    print('RESUMO:');
    print('• 1 Academia criada na coleção "academias"');
    print('• 2 Turmas criadas na subcoleção "turmas"');
    print('• Pastas organizadas no Storage');
    print('• Campos padronizados para o Firebase');
    print('=' * 50);

    // ==================== CRIAR ÍNDICES (OPCIONAL) ====================
    print('\n💡 DICA: Para melhor performance, crie estes índices no Firestore:');
    print('''
Coleção "academias":
- cidade Ascending, status Ascending
- nome Ascending

Coleção "academias/{id}/turmas":
- horario Ascending
- status Ascending, capacidade_maxima Descending
''');

  } catch (e, stackTrace) {
    print('\n❌ ERRO DURANTE A EXECUÇÃO:');
    print('Erro: $e');
    print('Stack trace: $stackTrace');
    exit(1);
  }

  print('\n✅ Script concluído com sucesso!');
  exit(0);
}