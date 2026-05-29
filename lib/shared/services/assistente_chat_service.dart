import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AssistenteChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ==================== CONFIGURAÇÕES COMPLETAS ====================

  Future<Map<String, dynamic>> carregarConfiguracoesCompletas() async {
    try {
      final doc = await _firestore.collection('config_site_assistente').doc('config').get();

      if (doc.exists) {
        final data = doc.data()!;
        return {
          'ativo': data['ativo'] ?? false,
          'perfil': data['perfil'] ?? _getPerfilPadrao(),
          'informacoes': data['informacoes'] ?? _getInformacoesPadrao(),
          'regras': data['regras'] ?? _getRegrasPadrao(),
          'acoes': data['acoes'] ?? _getAcoesPadrao(),
          'aparencia': data['aparencia'] ?? _getAparenciaPadrao(),
          'respostas_rapidas': data['respostas_rapidas'] ?? _getRespostasRapidasPadrao(),
          'turmas_selecionadas': data['turmas_selecionadas'] ?? {},
        };
      } else {
        final configPadrao = {
          'ativo': false,
          'perfil': _getPerfilPadrao(),
          'informacoes': _getInformacoesPadrao(),
          'regras': _getRegrasPadrao(),
          'acoes': _getAcoesPadrao(),
          'aparencia': _getAparenciaPadrao(),
          'respostas_rapidas': _getRespostasRapidasPadrao(),
          'turmas_selecionadas': {},
          'criado_em': FieldValue.serverTimestamp(),
        };
        await _firestore.collection('config_site_assistente').doc('config').set(configPadrao);
        return configPadrao;
      }
    } catch (e) {
      print('Erro ao carregar configurações: $e');
      return {
        'ativo': false,
        'perfil': _getPerfilPadrao(),
        'informacoes': _getInformacoesPadrao(),
        'regras': _getRegrasPadrao(),
        'acoes': _getAcoesPadrao(),
        'aparencia': _getAparenciaPadrao(),
        'respostas_rapidas': _getRespostasRapidasPadrao(),
        'turmas_selecionadas': {},
      };
    }
  }

  Future<void> salvarConfiguracoesCompletas(Map<String, dynamic> config) async {
    try {
      await _firestore.collection('config_site_assistente').doc('config').set({
        ...config,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Erro ao salvar configurações: $e');
    }
  }

  // ==================== BUSCAR TURMAS DO FIRESTORE ====================

  Future<List<Map<String, dynamic>>> buscarTodasTurmas() async {
    try {
      final snapshot = await _firestore.collection('turmas').get();

      final List<Map<String, dynamic>> turmas = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        // Extrai os dias da semana que estão marcados como true
        final diasConfiguracao = data['dias_configuracao'] ?? {};
        final List<String> diasAtivos = [];

        diasConfiguracao.forEach((dia, config) {
          if (config['selecionado'] == true) {
            diasAtivos.add(_traduzirDia(dia));
          }
        });

        turmas.add({
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'nivel': data['nivel'] ?? '',
          'dias': diasAtivos,
          'dias_originais': data['dias_semana_display'] ?? [],
          'horario_inicio': data['horario_inicio'] ?? '',
          'horario_fim': data['horario_fim'] ?? '',
          'local': data['nucleo'] ?? 'Não informado',
          'vagas': data['capacidade_maxima'] ?? 0,
          'alunos_ativos': data['alunos_ativos'] ?? 0,
          'status': data['status'] ?? 'INATIVA',
          'cor': data['cor_turma'] ?? '#EF4444',
          'faixa_etaria': data['faixa_etaria'] ?? '',
          'idade_minima': data['idade_minima'] ?? 0,
          'idade_maxima': data['idade_maxima'] ?? 0,
        });
      }

      return turmas;
    } catch (e) {
      print('Erro ao buscar turmas: $e');
      return [];
    }
  }

  String _traduzirDia(String dia) {
    switch (dia) {
      case 'DOMINGO': return 'Domingo';
      case 'SEGUNDA': return 'Segunda';
      case 'TERCA': return 'Terça';
      case 'QUARTA': return 'Quarta';
      case 'QUINTA': return 'Quinta';
      case 'SEXTA': return 'Sexta';
      case 'SABADO': return 'Sábado';
      default: return dia;
    }
  }

  // ==================== BUSCAR CONFIGURAÇÕES DE INSCRIÇÃO ====================

  Future<Map<String, dynamic>> buscarConfigInscricoes() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('inscricoes').get();

      if (doc.exists) {
        final data = doc.data()!;
        return {
          'abertas': data['inscricoes_abertas'] ?? false,
          'vagas': data['vagas_disponiveis'] ?? 0,
          'idade_minima': data['idade_minima'] ?? 5,
          'idade_maxima': data['idade_maxima'] ?? 100,
          'assinatura': data['recolher_assinatura'] ?? true,
          'total_inscricoes': data['total_inscricoes'] ?? 0,
        };
      }
      return {
        'abertas': false,
        'vagas': 0,
        'idade_minima': 5,
        'idade_maxima': 100,
        'assinatura': true,
        'total_inscricoes': 0,
      };
    } catch (e) {
      print('Erro ao buscar config inscrições: $e');
      return {
        'abertas': false,
        'vagas': 0,
        'idade_minima': 5,
        'idade_maxima': 100,
        'assinatura': true,
        'total_inscricoes': 0,
      };
    }
  }

  // ==================== DADOS PADRÃO ====================

  Map<String, dynamic> _getPerfilPadrao() {
    return {
      'nome': 'Assistente UAI',
      'avatar': '🤖',
      'status': 'Online',
      'mensagem_boas_vindas': 'Olá! Sou o assistente virtual da UAI Capoeira. Como posso ajudar você hoje? 🇧🇷',
      'cor_assistente': '#FF0000',
      'icone_botao': '💬',
    };
  }

  Map<String, dynamic> _getInformacoesPadrao() {
    return {
      'nome_grupo': 'UAI Capoeira',
      'cidade': 'Bocaiuva - MG',
      'estado': 'Minas Gerais',
      'endereco': 'Rua das Flores, 123 - Centro, Bocaiuva/MG',
      'telefone': '(38) 99999-9999',
      'email': 'contato@uaicapoeira.com.br',
      'instagram': 'https://www.instagram.com/uai.capoeira.bocaiuva/',
      'youtube': 'https://www.youtube.com/@uaicapoeira',
      'dias_treino': 'Terças e Quintas',
      'horario_treino': '19h às 21h',
      'local_treino': 'Centro Cultural de Bocaiuva',
      'valor_mensalidade': r'R$ 80,00',
      'aula_experimental': 'Gratuita',
      'fundacao': '2015',
      'mestre': 'Mestre Uai',
    };
  }

  Map<String, dynamic> _getRegrasPadrao() {
    return {
      'descricao_geral': 'Você é o assistente virtual oficial do Grupo UAI Capoeira. Seja educado, acolhedor e responda apenas sobre o grupo.',
      'limitar_assuntos': true,
      'assuntos_permitidos': ['capoeira', 'treinos', 'inscrições', 'campeonato', 'graduações', 'história'],
      'resposta_fora_tema': 'Desculpe, só posso responder perguntas sobre a UAI Capoeira. Como posso ajudar com treinos, inscrições ou campeonato?',
      'tom_respostas': 'Acolhedor e profissional',
      'maximo_caracteres': 500,
    };
  }

  Map<String, dynamic> _getAcoesPadrao() {
    return {
      'inscricao': {
        'ativo': true,
        'palavras_chave': ['inscrição', 'aula experimental', 'quero treinar', 'como faço para treinar', 'matrícula', 'quero me inscrever'],
        'texto_botao': '📝 FAZER INSCRIÇÃO',
        'tela_destino': 'InscricaoPublicaScreen',
      },
      'campeonato': {
        'ativo': true,
        'palavras_chave': ['campeonato', 'competição', 'torneio', '1° campeonato', 'evento'],
        'texto_botao': '🏆 VER CAMPEONATO',
        'tela_destino': 'InscricaoCampeonatoScreen',
      },
      'whatsapp': {
        'ativo': true,
        'palavras_chave': ['contato', 'whatsapp', 'falar com professor', 'telefone', 'ligar'],
        'texto_botao': '📱 FALAR NO WHATSAPP',
        'url_base': 'https://wa.me/5538999999999',
      },
      'maps': {
        'ativo': true,
        'palavras_chave': ['endereço', 'localização', 'onde fica', 'como chegar', 'maps'],
        'texto_botao': '🗺️ VER MAPA',
        'url_base': 'https://maps.google.com/?q=',
      },
    };
  }

  Map<String, dynamic> _getAparenciaPadrao() {
    return {
      'cor_primaria': '#FF0000',
      'cor_secundaria': '#FFFFFF',
      'cor_usuario': '#E0E0E0',
      'tamanho_fonte': 14,
      'border_radius': 20,
      'mostrar_avatar': true,
      'animacao': true,
    };
  }

  Map<String, dynamic> _getRespostasRapidasPadrao() {
    return {
      'perguntas_sugeridas': [
        'Qual o horário dos treinos?',
        'Como faço uma inscrição?',
        'Onde fica o grupo?',
        'Tem campeonato?',
        'Quanto custa a mensalidade?',
      ],
      'respostas': {
        'Qual o horário dos treinos?': 'Os treinos acontecem às terças e quintas, das 19h às 21h, no Centro Cultural de Bocaiuva.',
        'Como faço uma inscrição?': 'Para se inscrever, clique no botão abaixo e preencha o formulário. [ACAO:inscricao]',
        'Onde fica o grupo?': 'Estamos na Rua das Flores, 123 - Centro, Bocaiuva/MG. Clique no botão para ver no mapa! [ACAO:maps]',
        'Tem campeonato?': 'Sim! Estamos com o 1° Campeonato UAI Capoeira. Clique abaixo para mais informações! [ACAO:campeonato]',
        'Quanto custa a mensalidade?': r'A mensalidade é R$ 80,00. A primeira aula experimental é gratuita!',
      },
    };
  }

  // ==================== MONTAR CONTEXTO PARA O GEMINI ====================

  Future<String> montarContextoCompleto(Map<String, dynamic> config) async {
    final perfil = config['perfil'] as Map<String, dynamic>;
    final info = config['informacoes'] as Map<String, dynamic>;
    final regras = config['regras'] as Map<String, dynamic>;
    final acoes = config['acoes'] as Map<String, dynamic>;
    final respostasRapidas = config['respostas_rapidas'] as Map<String, dynamic>;

    final configInscricoes = await buscarConfigInscricoes();
    final turmas = await buscarTodasTurmas();
    final turmasSelecionadas = config['turmas_selecionadas'] ?? {};

    final turmasAtivas = turmas.where((t) => turmasSelecionadas[t['id']] == true).toList();

    String contexto = '''
${regras['descricao_geral']}

PERFIL DO ASSISTENTE:
- Nome: ${perfil['nome']}
- Tom de resposta: ${regras['tom_respostas']}
- Mensagem de boas vindas: "${perfil['mensagem_boas_vindas']}"

INFORMAÇÕES DO GRUPO UAI CAPOEIRA:
- Nome completo: ${info['nome_grupo']}
- Cidade: ${info['cidade']}
- Endereço: ${info['endereco']}
- Mensalidade: ${info['valor_mensalidade']}
- Telefone: ${info['telefone']}
- Email: ${info['email']}

📋 INFORMAÇÕES DE INSCRIÇÃO (DADOS REAIS DO SISTEMA):
- Status das inscrições: ${configInscricoes['abertas'] ? 'ABERTAS ✅' : 'FECHADAS ❌'}
- Vagas disponíveis: ${configInscricoes['vagas'] - configInscricoes['total_inscricoes']}
- Idade mínima: ${configInscricoes['idade_minima']} anos
- Idade máxima: ${configInscricoes['idade_maxima']} anos
- Assinatura digital: ${configInscricoes['assinatura'] ? 'OBRIGATÓRIA ✍️' : 'NÃO OBRIGATÓRIA'}

🏫 TURMAS DISPONÍVEIS PARA TREINO:
''';

    if (turmasAtivas.isEmpty) {
      contexto += 'Nenhuma turma disponível no momento.\n';
    } else {
      for (var turma in turmasAtivas) {
        contexto += '''
- Turma: ${turma['nome']} (${turma['nivel']})
  Dias: ${(turma['dias'] as List).join(', ')}
  Horário: ${turma['horario_inicio']} às ${turma['horario_fim']}
  Local: ${turma['local']}
  Vagas: ${turma['vagas'] - turma['alunos_ativos']} disponíveis de ${turma['vagas']}
  Faixa etária: ${turma['faixa_etaria']}
\n''';
      }
    }

    contexto += '''

REGRAS IMPORTANTES:
1. ${regras['descricao_geral']}
2. ${regras['limitar_assuntos'] == true ? 'Responda APENAS sobre: ${(regras['assuntos_permitidos'] as List).join(", ")}' : 'Pode responder sobre qualquer assunto relacionado à capoeira'}
3. Se perguntarem sobre assuntos fora do tema, responda: "${regras['resposta_fora_tema']}"

AÇÕES ESPECIAIS (coloque no final da resposta quando detectar intenção):
''';

    acoes.forEach((key, value) {
      if (value['ativo'] == true) {
        contexto += '- Quando o usuário perguntar sobre ${(value['palavras_chave'] as List).join(" ou ")}, responda com [ACAO:$key] no final\n';
      }
    });

    contexto += '''

RESPOSTAS PRÉ-DEFINIDAS:
''';

    final respostas = respostasRapidas['respostas'] as Map<String, dynamic>;
    respostas.forEach((pergunta, resposta) {
      contexto += '- Pergunta: "$pergunta" -> Resposta: "$resposta"\n';
    });

    contexto += '''

EXEMPLOS DE RESPOSTAS CORRETAS:

Usuário: "Quais os horários de treino?"
Assistente: "Temos as seguintes turmas disponíveis:\n${turmasAtivosParaResposta(turmasAtivas)}\nQual turma você tem interesse? [ACAO:inscricao]"

Usuário: "Como faço para me inscrever?"
Assistente: "${_formatarRespostaInscricao(configInscricoes)} [ACAO:inscricao]"

Lembre-se: Seja ${regras['tom_respostas'].toString().toLowerCase()} e sempre ajude o aluno da melhor forma possível!
''';

    return contexto;
  }

  String _formatarRespostaInscricao(Map<String, dynamic> config) {
    if (!config['abertas']) {
      return "⚠️ As inscrições estão FECHADAS no momento. Fique de olho nas nossas redes sociais!";
    }

    final vagasRestantes = config['vagas'] - config['total_inscricoes'];

    if (vagasRestantes <= 0) {
      return "😢 Infelizmente as vagas estão ESGOTADAS. Em breve abriremos novas turmas!";
    }

    return "✅ INSCRIÇÕES ABERTAS! ✅\n\n📊 Temos $vagasRestantes vagas disponíveis.\n👧🧒 Idade: ${config['idade_minima']} a ${config['idade_maxima']} anos.\n\n👉 Clique no botão abaixo para se inscrever!";
  }

  // ==================== CHAMAR GEMINI ====================

  Future<String> enviarMensagem(String mensagem, Map<String, dynamic> config) async {
    try {
      final contexto = await montarContextoCompleto(config);

      final HttpsCallable callable = _functions.httpsCallable('chatAssistente');
      final result = await callable.call({
        'mensagem': mensagem,
        'contexto': contexto,
      });

      return result.data['resposta'] ?? 'Desculpe, não consegui processar sua pergunta.';
    } catch (e) {
      print('Erro ao chamar Cloud Function: $e');
      return 'Ops! Estou com problemas técnicos. Tente novamente mais tarde.';
    }
  }

  // ==================== UTILITÁRIOS ====================

  String extrairAcao(String resposta) {
    final regex = RegExp(r'\[ACAO:(\w+)\]');
    final match = regex.firstMatch(resposta);
    if (match != null) {
      return match.group(1)!;
    }
    return '';
  }

  String limparResposta(String resposta) {
    return resposta.replaceAll(RegExp(r'\s*\[ACAO:\w+\]\s*'), '').trim();
  }
}

String turmasAtivosParaResposta(List<Map<String, dynamic>> turmas) {
  if (turmas.isEmpty) return "Nenhuma turma disponível no momento.";

  String resultado = "";
  for (var turma in turmas) {
    resultado += "\n• 🥋 ${turma['nome']} (${turma['nivel']})\n";
    resultado += "  📅 Dias: ${(turma['dias'] as List).join(', ')}\n";
    resultado += "  ⏰ Horário: ${turma['horario_inicio']} às ${turma['horario_fim']}\n";
    resultado += "  📍 Local: ${turma['local']}\n";
  }
  return resultado;
}