require('dotenv').config();

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { Storage } = require('@google-cloud/storage');
const { DateTime } = require('luxon');
const axios = require('axios');
const { GoogleGenerativeAI } = require('@google/generative-ai');

admin.initializeApp();

const db = admin.firestore();
const storage = new Storage();
const bucketName = 'uai-capoeira-52753.firebasestorage.app';

// ============================================
// FUNÇÃO 1: NOTIFICAÇÕES DE ANIVERSARIANTES
// ============================================
exports.sendBirthdayNotifications = onSchedule('0 11 * * *', async (event) => {
    const hojeBrasilia = DateTime.now().setZone('America/Sao_Paulo');
    const month = hojeBrasilia.month;
    const day = hojeBrasilia.day;

    console.log(`🔔 Verificando aniversariantes para ${day}/${month} (Horário BR)...`);

    try {
        const alunosSnapshot = await db
            .collection('alunos')
            .where('status_atividade', '==', 'ATIVO(A)')
            .get();

        const birthdayStudents = [];
        
        alunosSnapshot.forEach(doc => {
            const data = doc.data();
            if (data.data_nascimento) {
                let birthDate;
                if (data.data_nascimento.toDate) {
                    birthDate = data.data_nascimento.toDate();
                } else {
                    const [d, m, a] = data.data_nascimento.split('/');
                    birthDate = new Date(parseInt(a), parseInt(m) - 1, parseInt(d));
                }
                
                if (birthDate.getDate() === day && 
                    birthDate.getMonth() + 1 === month) {
                    birthdayStudents.push(data.nome || data.apelido || 'Aluno');
                }
            }
        });

        if (birthdayStudents.length === 0) {
            console.log('😴 Nenhum aniversariante hoje');
            return;
        }

        console.log(`🎉 ${birthdayStudents.length} aniversariante(s) hoje!`);

        const usuariosSnapshot = await db
            .collection('usuarios')
            .where('status_conta', '==', 'ativa')
            .get();

        const tokens = [];
        usuariosSnapshot.forEach(doc => {
            const data = doc.data();
            if (data.fcm_tokens && Array.isArray(data.fcm_tokens)) {
                tokens.push(...data.fcm_tokens);
            }
        });

        if (tokens.length === 0) {
            console.log('😴 Nenhum token FCM encontrado');
            return;
        }

        const uniqueTokens = [...new Set(tokens)];

        const title = birthdayStudents.length === 1 
            ? '🎉 Aniversariante do Dia!'
            : `🎉 ${birthdayStudents.length} Aniversariantes Hoje!`;

        const body = birthdayStudents.length === 1
            ? `${birthdayStudents[0]} está fazendo aniversário hoje! 🎂`
            : `Hoje fazem aniversário: ${birthdayStudents.join(', ')}`;

        const message = {
            notification: { title, body },
            tokens: uniqueTokens
        };

        const response = await admin.messaging().sendEachForMulticast(message);
        
        console.log(`✅ ${response.successCount} notificações enviadas`);
        console.log(`❌ ${response.failureCount} falhas`);

    } catch (error) {
        console.error('❌ Erro:', error);
    }
});

// ============================================
// FUNÇÃO 2: PROCESSAR CHAMADA EM LOTE
// ============================================
exports.processarChamada = onCall(async (request) => {
    if (!request.auth) {
        throw new Error('Usuário não autenticado');
    }

    const data = request.data;
    
    const {
        turmaId,
        turmaNome,
        academiaId,
        academiaNome,
        dataChamada,
        alunos,
        tipoAula,
        professorId,
        professorNome
    } = data;

    const batch = db.batch();
    const chamadaRef = db.collection('chamadas').doc();
    
    const dataBrasilia = DateTime.fromISO(dataChamada, { zone: 'America/Sao_Paulo' });
    const dataFormatada = dataBrasilia.toFormat('yyyy-MM-dd');
    const timestampBrasilia = admin.firestore.Timestamp.fromDate(dataBrasilia.toJSDate());
    
    const presentes = alunos.filter(a => a.presente).length;
    const ausentes = alunos.length - presentes;
    const porcentagem = alunos.length > 0 ? Math.round((presentes / alunos.length) * 100) : 0;
    
    const chamadaData = {
        turma_id: turmaId,
        turma_nome: turmaNome,
        academia_id: academiaId,
        academia_nome: academiaNome,
        data_chamada: timestampBrasilia,
        data_formatada: dataFormatada,
        tipo_aula: tipoAula,
        total_alunos: alunos.length,
        presentes: presentes,
        ausentes: ausentes,
        porcentagem_frequencia: porcentagem,
        professor_id: professorId,
        professor_nome: professorNome,
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
        alunos: alunos.map(aluno => ({
            aluno_id: aluno.id,
            aluno_nome: aluno.nome,
            presente: aluno.presente,
            observacao: aluno.observacao || ''
        }))
    };
    
    batch.set(chamadaRef, chamadaData);
    
    const logs = [];
    const updates = [];
    
    for (const aluno of alunos) {
        const alunoId = aluno.id;
        const presente = aluno.presente;
        const mesAno = dataFormatada.substring(0, 7);
        
        updates.push(
            db.collection('alunos').doc(alunoId).update({
                [`contadores.${mesAno}`]: admin.firestore.FieldValue.increment(presente ? 1 : 0)
            }).catch(err => console.error(`Erro ao atualizar contador ${alunoId}:`, err))
        );
        
        if (presente) {
            updates.push(
                db.collection('alunos').doc(alunoId).update({
                    ultima_presenca: timestampBrasilia,
                    ultimo_dia_presente: dataFormatada
                }).catch(err => console.error(`Erro ao atualizar ultima_presenca ${alunoId}:`, err))
            );
        }
        
        logs.push({
            log_id: `log_${alunoId}_${dataFormatada}`,
            aluno_id: alunoId,
            aluno_nome: aluno.nome,
            turma_id: turmaId,
            turma_nome: turmaNome,
            academia_id: academiaId,
            academia_nome: academiaNome,
            data_aula: timestampBrasilia,
            data_formatada: dataFormatada,
            presente: presente,
            observacao: aluno.observacao || '',
            professor_id: professorId,
            professor_nome: professorNome,
            registrado_em: admin.firestore.FieldValue.serverTimestamp(),
            tipo_registro: 'chamada_turma'
        });
        
        updates.push(
            db.collection('alunos').doc(alunoId).update({
                ultima_chamada: admin.firestore.FieldValue.serverTimestamp(),
                ultima_chamada_por: professorNome,
                ultima_chamada_por_id: professorId
            }).catch(err => console.error(`Erro ao atualizar ultima_chamada ${alunoId}:`, err))
        );
    }
    
    await Promise.all([
        batch.commit(),
        ...updates,
        ...logs.map(log => db.collection('log_presenca_alunos').add(log))
    ]);
    
    await db.collection('locks_chamada').doc(turmaId).delete().catch(() => {});
    
    return {
        success: true,
        chamadaId: chamadaRef.id,
        processados: alunos.length,
        presentes: presentes,
        ausentes: ausentes
    };
});

// ============================================
// FUNÇÃO 3: EXCLUIR CHAMADA
// ============================================
exports.excluirChamada = onCall(async (request) => {
    if (!request.auth) {
        throw new Error('Usuário não autenticado');
    }

    const { chamadaId, turmaId } = request.data;

    if (!chamadaId || !turmaId) {
        throw new Error('Parâmetros obrigatórios: chamadaId e turmaId');
    }

    const batch = db.batch();

    const chamadaDoc = await db.collection('chamadas').doc(chamadaId).get();

    if (!chamadaDoc.exists) {
        throw new Error('Chamada não encontrada');
    }

    const chamadaData = chamadaDoc.data();
    const alunos = chamadaData.alunos || [];
    const dataFormatada = chamadaData.data_formatada;
    const dataChamada = chamadaData.data_chamada.toDate();

    const logsQuery = await db
        .collection('log_presenca_alunos')
        .where('data_formatada', '==', dataFormatada)
        .where('turma_id', '==', turmaId)
        .get();

    const updates = [];

    for (const aluno of alunos) {
        const alunoId = aluno.aluno_id;
        const estavaPresente = aluno.presente;
        const mesAno = dataFormatada.substring(0, 7);

        if (estavaPresente) {
            updates.push(
                db.collection('alunos').doc(alunoId).update({
                    [`contadores.${mesAno}`]: admin.firestore.FieldValue.increment(-1)
                }).catch(err => console.error(`Erro ao decrementar contador ${alunoId}:`, err))
            );
        }

        const ultimaPresencaQuery = await db
            .collection('log_presenca_alunos')
            .where('aluno_id', '==', alunoId)
            .where('presente', '==', true)
            .where('data_aula', '<', dataChamada)
            .orderBy('data_aula', 'desc')
            .limit(1)
            .get();

        const alunoRef = db.collection('alunos').doc(alunoId);

        if (ultimaPresencaQuery.docs.length > 0) {
            const ultimaPresenca = ultimaPresencaQuery.docs[0].data().data_aula;
            updates.push(
                alunoRef.update({
                    ultimo_dia_presente: ultimaPresenca
                }).catch(err => console.error(`Erro ao atualizar ultima_presenca ${alunoId}:`, err))
            );
        } else {
            updates.push(
                alunoRef.update({
                    ultimo_dia_presente: null
                }).catch(err => console.error(`Erro ao remover ultima_presenca ${alunoId}:`, err))
            );
        }

        const ultimaChamadaQuery = await db
            .collection('log_presenca_alunos')
            .where('aluno_id', '==', alunoId)
            .orderBy('data_aula', 'desc')
            .limit(1)
            .get();

        if (ultimaChamadaQuery.docs.length > 0) {
            const ultimaChamada = ultimaChamadaQuery.docs[0].data();
            updates.push(
                alunoRef.update({
                    ultima_chamada: ultimaChamada.data_aula,
                    ultima_chamada_por: ultimaChamada.professor_nome || null,
                    ultima_chamada_por_id: ultimaChamada.professor_id || null
                }).catch(err => console.error(`Erro ao atualizar ultima_chamada ${alunoId}:`, err))
            );
        } else {
            updates.push(
                alunoRef.update({
                    ultima_chamada: null,
                    ultima_chamada_por: null,
                    ultima_chamada_por_id: null
                }).catch(err => console.error(`Erro ao remover ultima_chamada ${alunoId}:`, err))
            );
        }
    }

    batch.delete(chamadaDoc.ref);
    for (const logDoc of logsQuery.docs) {
        batch.delete(logDoc.ref);
    }

    await Promise.all([
        batch.commit(),
        ...updates
    ]);

    return {
        success: true,
        logsExcluidos: logsQuery.docs.length,
        alunosProcessados: alunos.length
    };
});

// ============================================
// FUNÇÃO 4: RESTAURAR FOTOS DO BACKUP
// ============================================
exports.restaurarFotosDoBackup = onRequest(
    {
        timeoutSeconds: 540,
        memory: '1GiB'
    },
    async (req, res) => {
        res.set('Access-Control-Allow-Origin', '*');
        res.set('Access-Control-Allow-Methods', 'GET, POST');
        res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

        if (req.method === 'OPTIONS') {
            res.status(204).send('');
            return;
        }

        const bucket = storage.bucket(bucketName);
        const pastaBackup = 'backup_fotos_alunos/';

        try {
            console.log('🚀 Iniciando restauração de fotos...');

            const [files] = await bucket.getFiles({ prefix: pastaBackup });
            
            if (files.length === 0) {
                res.status(200).json({ 
                    success: false, 
                    message: 'Nenhuma foto encontrada no backup',
                    totalFotos: 0
                });
                return;
            }

            console.log(`📸 Encontradas ${files.length} fotos no backup`);

            const alunosSnapshot = await db.collection('alunos').get();
            
            const mapaAlunos = new Map();
            alunosSnapshot.docs.forEach(doc => {
                const data = doc.data();
                const nome = data.nome?.trim();
                if (nome) {
                    const nomeNormalizado = nome
                        .toLowerCase()
                        .normalize('NFD')
                        .replace(/[\u0300-\u036f]/g, '');
                    mapaAlunos.set(nomeNormalizado, {
                        id: doc.id,
                        nome: data.nome,
                        fotoAtual: data.foto_perfil_aluno
                    });
                }
            });

            console.log(`👥 ${mapaAlunos.size} alunos encontrados no Firestore`);

            const resultados = {
                totalFotos: files.length,
                atualizadas: 0,
                naoEncontrados: [],
                erros: []
            };

            for (const file of files) {
                const nomeArquivo = file.name.replace(pastaBackup, '');
                const nomeAlunoBackup = nomeArquivo
                    .replace(/\.(jpg|jpeg|png|gif)$/i, '')
                    .trim()
                    .toLowerCase()
                    .normalize('NFD')
                    .replace(/[\u0300-\u036f]/g, '');

                console.log(`🔍 Processando: ${nomeArquivo}`);

                if (!mapaAlunos.has(nomeAlunoBackup)) {
                    resultados.naoEncontrados.push(nomeArquivo);
                    console.log(`   ❌ Aluno não encontrado: ${nomeArquivo}`);
                    continue;
                }

                const aluno = mapaAlunos.get(nomeAlunoBackup);
                
                try {
                    const extensao = nomeArquivo.includes('.') ? nomeArquivo.split('.').pop() : 'jpg';
                    const nomeDestino = `fotos_perfil_alunos/${aluno.id}_${Date.now()}.${extensao}`;
                    const arquivoDestino = bucket.file(nomeDestino);
                    
                    await file.copy(arquivoDestino);
                    await arquivoDestino.makePublic();
                    
                    const publicUrl = `https://storage.googleapis.com/${bucketName}/${nomeDestino}`;
                    
                    await db.collection('alunos').doc(aluno.id).update({
                        foto_perfil_aluno: publicUrl,
                        foto_restaurada_em: admin.firestore.FieldValue.serverTimestamp(),
                        foto_backup_original: file.name
                    });
                    
                    resultados.atualizadas++;
                    console.log(`   ✅ Foto atualizada: ${aluno.nome}`);
                    
                } catch (erro) {
                    resultados.erros.push({
                        aluno: aluno.nome,
                        erro: erro.message
                    });
                    console.log(`   ❌ Erro ao processar ${aluno.nome}: ${erro.message}`);
                }
            }

            console.log(`✅ Restauração concluída! ${resultados.atualizadas} fotos atualizadas`);

            res.status(200).json({
                success: true,
                totalFotos: resultados.totalFotos,
                atualizadas: resultados.atualizadas,
                naoEncontrados: resultados.naoEncontrados,
                erros: resultados.erros,
                mensagem: `${resultados.atualizadas} fotos atualizadas com sucesso!`
            });

        } catch (erro) {
            console.error('❌ Erro na restauração:', erro);
            res.status(500).json({
                success: false,
                error: erro.message
            });
        }
    }
);

// ============================================
// FUNÇÃO 5: REGISTRAR LOCALIZAÇÃO DE ACESSO
// ============================================
exports.registrarLocalizacaoAcesso = onCall(async (request) => {
    const { ip } = request.data;
    
    try {
        const response = await axios.get(`http://ip-api.com/json/${ip}`);
        const location = response.data;
        
        if (location.status === 'success') {
            const cidade = location.city;
            const estado = location.regionName;
            const pais = location.country;
            
            const docRef = await db.collection('estatisticas_acessos').add({
                ip: ip,
                cidade: cidade,
                estado: estado,
                pais: pais,
                latitude: location.lat,
                longitude: location.lon,
                data_acesso: admin.firestore.FieldValue.serverTimestamp(),
                origem: 'landing_page',
                isp: location.isp,
                timezone: location.timezone,
                eventos: [],
                total_eventos: 0,
                ultima_atividade: admin.firestore.FieldValue.serverTimestamp(),
            });
            
            const statsRef = db.collection('estatisticas').doc('contadores_agregados');
            
            await statsRef.set({
                total_visitas: admin.firestore.FieldValue.increment(1),
                [`paises.${pais}.total`]: admin.firestore.FieldValue.increment(1),
                [`paises.${pais}.nome`]: pais,
                [`paises.${pais}.estados.${estado}.total`]: admin.firestore.FieldValue.increment(1),
                [`paises.${pais}.estados.${estado}.nome`]: estado,
                [`paises.${pais}.estados.${estado}.cidades.${cidade}.total`]: admin.firestore.FieldValue.increment(1),
                [`paises.${pais}.estados.${estado}.cidades.${cidade}.nome`]: cidade,
                ultima_atualizacao: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            
            console.log(`📍 Acesso registrado com ID: ${docRef.id} - ${cidade}/${estado}`);
            
            return { 
                success: true,
                docId: docRef.id,
                cidade: cidade,
                estado: estado,
                pais: pais,
                latitude: location.lat,
                longitude: location.lon,
                isp: location.isp,
                timezone: location.timezone
            };
        }
        
        return { success: false, error: 'Localização não encontrada' };
        
    } catch (error) {
        console.error('❌ Erro:', error);
        return { success: false, error: error.message };
    }
});

// ============================================
// 🔥 FUNÇÃO PARA BUSCAR TURMAS E HORÁRIOS (ATUALIZADA)
// ============================================
async function getRespostaHorarios() {
  try {
    const turmasSnapshot = await db.collection('turmas').get();
    
    const configDoc = await db.collection('config_site_assistente').doc('config').get();
    const turmasSelecionadas = configDoc.data()?.turmas_selecionadas || {};
    
    const turmas = [];
    
    // 🔥 ORDEM CORRETA DOS DIAS
    const ordemDias = ['SEGUNDA', 'TERCA', 'QUARTA', 'QUINTA', 'SEXTA', 'SABADO', 'DOMINGO'];
    
    for (const doc of turmasSnapshot.docs) {
      const id = doc.id;
      
      if (turmasSelecionadas[id] !== true) continue;
      
      const data = doc.data();
      
      const diasConfig = data.dias_configuracao || {};
      const diasComHorarios = [];
      
      // 🔥 PERCORRE OS DIAS NA ORDEM CORRETA
      for (const dia of ordemDias) {
        const config = diasConfig[dia];
        if (config && config.selecionado === true) {
          diasComHorarios.push({
            dia: traduzirDia(dia),
            horarioInicio: config.horario_inicio || '19:00',
            horarioFim: config.horario_fim || '20:30',
            tipoAula: config.tipoAula || 'OBJETIVA'
          });
        }
      }
      
      if (diasComHorarios.length === 0) continue;
      
      turmas.push({
        nome: data.nome || 'Sem nome',
        nivel: data.nivel || '',
        diasComHorarios: diasComHorarios,
        local: data.nucleo || 'Não informado',
        vagasTotal: data.capacidade_maxima || 0,
        alunosAtivos: data.alunos_ativos || 0,
        cor: data.cor_turma || '#EF4444'
      });
    }
    
    if (turmas.length === 0) {
      return "No momento não temos turmas disponíveis para exibir. Em breve divulgaremos novos horários!";
    }
    
    let resposta = "🏫 **HORÁRIOS DE TREINO** 🏫\n\n";
    
    for (const turma of turmas) {
      const vagasRestantes = turma.vagasTotal - turma.alunosAtivos;
      const statusVagas = vagasRestantes > 0 ? `✅ ${vagasRestantes} vagas disponíveis` : "❌ Lotado";
      
      resposta += `**${turma.nome}** ${turma.nivel ? `(${turma.nivel})` : ''}\n`;
      resposta += `📍 Local: ${turma.local}\n`;
      
      for (const diaInfo of turma.diasComHorarios) {
        resposta += `📅 ${diaInfo.dia}: ${diaInfo.horarioInicio} às ${diaInfo.horarioFim}`;
        if (diaInfo.tipoAula && diaInfo.tipoAula !== 'OBJETIVA') {
          resposta += ` (${diaInfo.tipoAula})`;
        }
        resposta += `\n`;
      }
      
      resposta += `🎯 ${statusVagas}\n\n`;
    }
    
    // 🔥 SÓ PERGUNTA "QUAL TURMA" SE TIVER MAIS DE 1 TURMA
    if (turmas.length === 1) {
      resposta += "👉 Clique no botão abaixo para fazer sua inscrição! [ACAO:inscricao]";
    } else {
      resposta += "👉 Qual turma você tem interesse? Posso te ajudar com mais informações ou com a inscrição! [ACAO:inscricao]";
    }
    
    return resposta;
    
  } catch (error) {
    console.error('❌ Erro ao buscar turmas:', error);
    return "Os treinos acontecem às terças e quintas, das 19h às 21h, no Centro Cultural de Bocaiuva. Em breve teremos mais informações sobre outras turmas!";
  }
}

// ============================================
// FUNÇÃO PARA BUSCAR CONFIGURAÇÕES DE INSCRIÇÃO
// ============================================
async function getRespostaInscricao() {
  try {
    const doc = await db.collection('configuracoes').doc('inscricoes').get();
    
    if (!doc.exists) {
      return "As inscrições estão abertas! Clique no botão abaixo para se inscrever. [ACAO:inscricao]";
    }
    
    const data = doc.data();
    const abertas = data?.inscricoes_abertas ?? false;
    const vagas = data?.vagas_disponiveis ?? 0;
    const totalInscricoes = data?.total_inscricoes ?? 0;
    const idadeMin = data?.idade_minima ?? 5;
    const idadeMax = data?.idade_maxima ?? 100;
    const assinatura = data?.recolher_assinatura ?? true;
    
    if (!abertas) {
      return "⚠️ As inscrições estão FECHADAS no momento. Fique de olho nas nossas redes sociais para saber quando reabriremos!";
    }
    
    const vagasRestantes = vagas - totalInscricoes;
    
    if (vagasRestantes <= 0) {
      return "😢 Infelizmente as vagas estão ESGOTADAS. Temos " + totalInscricoes + " inscrições para " + vagas + " vagas. Mas não desanima! Em breve abriremos novas turmas.";
    }
    
    let resposta = "✅ **INSCRIÇÕES ABERTAS!** ✅\n\n";
    resposta += `📊 Temos ${vagasRestantes} vaga${vagasRestantes > 1 ? 's' : ''} disponível${vagasRestantes > 1 ? 'is' : ''}.\n\n`;
    resposta += `👧🧒 Idade permitida: ${idadeMin} a ${idadeMax} anos.\n\n`;
    
    if (assinatura) {
      resposta += "✍️ Será necessário assinar digitalmente no final do formulário.\n\n";
    }
    
    resposta += "👉 Clique no botão abaixo para fazer sua inscrição! [ACAO:inscricao]";
    
    return resposta;
    
  } catch (error) {
    console.error('❌ Erro ao buscar inscrições:', error);
    return "As inscrições estão abertas! Clique no botão abaixo para se inscrever. [ACAO:inscricao]";
  }
}

// ============================================
// FUNÇÃO AUXILIAR: TRADUZIR DIAS
// ============================================
function traduzirDia(dia) {
  const dias = {
    'DOMINGO': 'Domingo',
    'SEGUNDA': 'Segunda',
    'TERCA': 'Terça',
    'QUARTA': 'Quarta',
    'QUINTA': 'Quinta',
    'SEXTA': 'Sexta',
    'SABADO': 'Sábado'
  };
  return dias[dia] || dia;
}

// ============================================
// 🔥 FUNÇÃO PRINCIPAL: CHAT ASSISTENTE
// ============================================
exports.chatAssistente = onCall(
  { 
    cors: true,
    invoker: 'public'
  },
  async (request) => {
    console.log('🚀 Função chatAssistente foi chamada!');
    
    const data = request.data || {};
    const mensagem = data.mensagem ? String(data.mensagem) : '';
    
    console.log('📩 Mensagem recebida:', mensagem);
    
    if (!mensagem || mensagem.trim().length === 0) {
      return { 
        resposta: "Olá! Sou o assistente da UAI Capoeira. Como posso ajudar você hoje? Digite sua pergunta!" 
      };
    }
    
    const msgLower = mensagem.toLowerCase();
    
    if (msgLower.includes('horário') || msgLower.includes('horario') || 
        msgLower.includes('quando') || msgLower.includes('dias') ||
        msgLower.includes('treino') || msgLower.includes('aula') ||
        msgLower.includes('funciona')) {
      console.log('📅 Detectada pergunta sobre horários');
      const respostaHorarios = await getRespostaHorarios();
      return { resposta: respostaHorarios };
    }
    
    if (msgLower.includes('inscrição') || msgLower.includes('inscricao') || 
        msgLower.includes('quero treinar') || msgLower.includes('matrícula') ||
        msgLower.includes('aula experimental')) {
      console.log('📝 Detectada pergunta sobre inscrições');
      const respostaInscricao = await getRespostaInscricao();
      return { resposta: respostaInscricao };
    }
    
    if (msgLower.includes('endereço') || msgLower.includes('local') || msgLower.includes('onde fica')) {
      return { 
        resposta: "Estamos na Rua das Flores, 123 - Centro, Bocaiuva/MG. Clique no botão para ver no mapa! [ACAO:maps]" 
      };
    }
    
    if (msgLower.includes('campeonato') || msgLower.includes('competição') || msgLower.includes('torneio')) {
      return { 
        resposta: "Sim! Estamos com o 1° Campeonato UAI Capoeira. Clique abaixo para mais informações! [ACAO:campeonato]" 
      };
    }
    
    if (msgLower.includes('whatsapp') || msgLower.includes('contato') || msgLower.includes('telefone')) {
      return { 
        resposta: "Você pode falar conosco pelo WhatsApp! Clique no botão abaixo para conversar. [ACAO:whatsapp]" 
      };
    }
    
    if (msgLower.includes('mensalidade') || msgLower.includes('valor') || msgLower.includes('quanto custa')) {
      return { 
        resposta: "A mensalidade é R$ 80,00. A primeira aula experimental é gratuita!" 
      };
    }
    
    if (msgLower.includes('obrigado') || msgLower.includes('valeu') || msgLower.includes('gratidão')) {
      return { 
        resposta: "Por nada! Estamos aqui para ajudar. Qualquer dúvida é só chamar. Axé! 🙏" 
      };
    }
    
    if (msgLower.includes('olá') || msgLower.includes('oi') || msgLower.includes('opa') || msgLower.includes('bom dia')) {
      return { 
        resposta: "Olá! Seja bem-vindo(a) ao site da UAI Capoeira! 🇧🇷\n\nComo posso ajudar você hoje?" 
      };
    }
    
    return { 
      resposta: "Olá! Sou o assistente da UAI Capoeira. Posso ajudar com:\n\n• 📝 Inscrições\n• ⏰ Horários de treino\n• 🏆 Campeonato\n• 📍 Localização\n• 📱 Contato via WhatsApp\n• 💰 Mensalidade\n\nO que você gostaria de saber?" 
    };
  }
);

// ============================================
// FUNÇÃO 7: REGISTRAR EVENTO DO ASSISTENTE
// ============================================
exports.registrarEventoAssistente = onCall(
  { 
    cors: true,
    invoker: 'public'
  },
  async (request) => {
    const { docId, tipo, nome, origem, metadata } = request.data;
    
    if (!docId) {
        return { success: false, error: 'docId é obrigatório' };
    }
    
    try {
        const evento = {
            tipo: tipo,
            nome: nome,
            origem: origem || 'chat',
            metadata: metadata || {},
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        };
        
        await admin.firestore().collection('estatisticas_acessos').doc(docId).update({
            eventos: admin.firestore.FieldValue.arrayUnion(evento),
            total_eventos: admin.firestore.FieldValue.increment(1),
            ultima_atividade: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        return { success: true };
        
    } catch (error) {
        console.error('❌ Erro ao registrar evento:', error);
        return { success: false, error: error.message };
    }
  }
);