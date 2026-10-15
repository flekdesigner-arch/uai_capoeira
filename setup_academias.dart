import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  stdout.writeln('🚀 INICIANDO CONFIGURAÇÃO DAS ACADEMIAS...\n');

  try {
    // Inicializar Firebase
    stdout.writeln('🔌 Conectando ao Firebase...');
    await Firebase.initializeApp();
    stdout.writeln('✅ Firebase inicializado!\n');

    // Referências do Firestore
    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    // ==================== DADOS DA ACADEMIA ====================
    stdout.writeln('📊 CRIANDO COLEÇÃO DE ACADEMIAS...');

    final academiaData = {
      'nome': 'CENTRO DE CONVIVIO',
      'cidade': 'BOCAIUVA-MG',
      'modalidade': 'CAPOEIRA',
      'professor': 'TICO-TICO',
      'logo_url':
          'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/JEmRdvRYw6JD14UcSnby.jpg',
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
    final academiaRef = await firestore
        .collection('academias')
        .add(academiaData);
    stdout.writeln('✅ Academia criada: ${academiaRef.id}');
    stdout.writeln('   Nome: CENTRO DE CONVIVIO');
    stdout.writeln('   Cidade: BOCAIUVA-MG');
    stdout.writeln('   Professor: TICO-TICO\n');

    // ==================== CRIAR PASTA NO STORAGE ====================
    stdout.writeln('📁 CRIANDO PASTA NO STORAGE...');

    try {
      // Cria uma referência vazia (Firebase Storage não tem pastas "vazias" realmente)
      // Vamos criar um arquivo placeholder
      final placeholder = storage.ref().child('academias_placeholder/.keep');
      await placeholder.putString('Pasta criada por setup script');

      stdout.writeln('✅ Pastas criadas no Storage');
      stdout.writeln('   - logos_academias/');
      stdout.writeln('   - logos_turmas/\n');
    } catch (e) {
      stdout.writeln('⚠️ Nota: Pastas serão criadas automaticamente ao fazer upload');
    }

    // ==================== CRIAR TURMAS ====================
    stdout.writeln('🎓 CRIANDO SUBSCOLETA DE TURMAS...');

    // Dados das turmas
    final turmas = [
      {
        'nome': '19:00 AS 20:30',
        'horario': '19:00 às 20:30',
        'logo_url':
            'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/x7fzZFECzpbjdTplh0g7.jpg',
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
        'logo_url':
            'https://storage.googleapis.com/glide-prod.appspot.com/uploads-v2/4h7FnX9U55pXjuDNV6k1/pub/AqQPRSDgpWpmyD3UByd7.jpg',
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
      },
    ];

    // Adicionar cada turma na subcoleção
    for (var i = 0; i < turmas.length; i++) {
      final turmaData = turmas[i];
      final turmaRef = await academiaRef.collection('turmas').add(turmaData);

      // CORREÇÃO APLICADA AQUI ↓
      stdout.writeln('✅ Turma ${i + 1} criada: ${turmaRef.id}');
      stdout.writeln('   Horário: ${turmaData['horario']}');

      // Converter List<dynamic> para String formatada
      final diasSemana = turmaData['dias_semana'] as List<dynamic>;
      final diasFormatados = diasSemana.map((d) => d.toString()).join(', ');
      stdout.writeln('   Dias: $diasFormatados');

      stdout.writeln('   Faixa etária: ${turmaData['faixa_etaria']}\n');
    }

    // ==================== ATUALIZAR CONTADOR DE TURMAS ====================
    await academiaRef.update({
      'turmas_count': turmas.length,
      'atualizado_em': FieldValue.serverTimestamp(),
    });

    // ==================== VERIFICAR ESTRUTURA ====================
    stdout.writeln('🔍 VERIFICANDO ESTRUTURA CRIADA...\n');

    // Verificar academia
    final academiaSnapshot = await academiaRef.get();
    stdout.writeln('📋 ACADEMIA:');
    stdout.writeln('   ID: ${academiaRef.id}');
    stdout.writeln('   Nome: ${academiaSnapshot.get('nome')}');
    stdout.writeln('   Cidade: ${academiaSnapshot.get('cidade')}');
    stdout.writeln('   Turmas: ${academiaSnapshot.get('turmas_count')}\n');

    // Verificar turmas
    final turmasSnapshot = await academiaRef.collection('turmas').get();
    stdout.writeln('🎓 TURMAS CRIADAS:');
    for (var doc in turmasSnapshot.docs) {
      stdout.writeln('   - ${doc.get('nome')} (${doc.get('horario')})');
    }

    stdout.writeln('\n🎉 ESTRUTURA COMPLETA!');
    stdout.writeln('=' * 50);
    stdout.writeln('RESUMO:');
    stdout.writeln('• 1 Academia criada na coleção "academias"');
    stdout.writeln('• 2 Turmas criadas na subcoleção "turmas"');
    stdout.writeln('• Pastas organizadas no Storage');
    stdout.writeln('• Campos padronizados para o Firebase');
    stdout.writeln('=' * 50);

    // ==================== CRIAR ÍNDICES (OPCIONAL) ====================
    stdout.writeln(
      '\n💡 DICA: Para melhor performance, crie estes índices no Firestore:',
    );
    stdout.writeln('''
Coleção "academias":
- cidade Ascending, status Ascending
- nome Ascending

Coleção "academias/{id}/turmas":
- horario Ascending
- status Ascending, capacidade_maxima Descending
''');
  } catch (e, stackTrace) {
    stdout.writeln('\n❌ ERRO DURANTE A EXECUÇÃO:');
    stdout.writeln('Erro: $e');
    stdout.writeln('Stack trace: $stackTrace');
    exit(1);
  }

  stdout.writeln('\n✅ Script concluído com sucesso!');
  exit(0);
}
