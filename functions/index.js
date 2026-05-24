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
// HELPERS - NOTIFICAÇÕES FCM
// ============================================
function extrairDataNascimento(dataNascimento) {
    if (!dataNascimento) return null;

    try {
        // Firestore Timestamp
        if (dataNascimento.toDate) {
            const dt = DateTime
                .fromJSDate(dataNascimento.toDate())
                .setZone('America/Sao_Paulo');

            return {
                day: dt.day,
                month: dt.month,
            };
        }

        // String no formato dd/MM/yyyy ou dd/MM
        if (typeof dataNascimento === 'string') {
            const partes = dataNascimento.trim().split('/');

            if (partes.length >= 2) {
                const day = parseInt(partes[0], 10);
                const month = parseInt(partes[1], 10);

                if (!Number.isNaN(day) && !Number.isNaN(month)) {
                    return { day, month };
                }
            }
        }

        // Date JS puro, se algum dia vier assim
        if (dataNascimento instanceof Date) {
            const dt = DateTime
                .fromJSDate(dataNascimento)
                .setZone('America/Sao_Paulo');

            return {
                day: dt.day,
                month: dt.month,
            };
        }
    } catch (error) {
        console.error('❌ Erro ao extrair data de nascimento:', error);
    }

    return null;
}

async function buscarTokensUsuariosAtivos() {
    const usuariosSnapshot = await db
        .collection('usuarios')
        .where('status_conta', '==', 'ativa')
        .get();

    console.log(`👥 Usuários ativos encontrados: ${usuariosSnapshot.size}`);

    const tokens = [];
    const tokenOwners = new Map();

    usuariosSnapshot.forEach(doc => {
        const data = doc.data();
        const userTokens = [];

        if (data.current_fcm_token && typeof data.current_fcm_token === 'string') {
            userTokens.push(data.current_fcm_token);
        }

        if (Array.isArray(data.fcm_tokens)) {
            userTokens.push(...data.fcm_tokens.filter(t => typeof t === 'string'));
        }

        const uniqueUserTokens = [...new Set(userTokens)].filter(Boolean);

        console.log(`👤 Usuário ${doc.id}:`, {
            email: data.email || null,
            status_conta: data.status_conta || null,
            tem_current_fcm_token: !!data.current_fcm_token,
            total_fcm_tokens: Array.isArray(data.fcm_tokens) ? data.fcm_tokens.length : 0,
            tokens_unicos_usuario: uniqueUserTokens.length,
        });

        uniqueUserTokens.forEach(token => {
            tokens.push(token);
            tokenOwners.set(token, doc.ref);
        });
    });

    const uniqueTokens = [...new Set(tokens)].filter(Boolean);
    console.log(`📱 Tokens únicos encontrados: ${uniqueTokens.length}`);

    return {
        usuariosAtivos: usuariosSnapshot.size,
        tokens: uniqueTokens,
        tokenOwners,
    };
}

async function removerTokensInvalidos(tokensInvalidos, tokenOwners) {
    if (!tokensInvalidos || tokensInvalidos.length === 0) return;

    const batch = db.batch();
    let totalRemovidos = 0;

    tokensInvalidos.forEach(token => {
        const userRef = tokenOwners.get(token);
        if (!userRef) return;

        batch.set(userRef, {
            fcm_tokens: admin.firestore.FieldValue.arrayRemove(token),
            token_invalido_removido_em: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        totalRemovidos++;
    });

    if (totalRemovidos > 0) {
        await batch.commit();
        console.log(`🧹 ${totalRemovidos} token(s) inválido(s) removido(s) do Firestore`);
    }
}

async function enviarMulticastEmLotes({ tokens, title, body, data = {}, tokenOwners = new Map() }) {
    // ✅ V3: envio individual, um token por vez.
    // Motivo: algumas versões antigas do firebase-admin usam o endpoint /batch,
    // que pode retornar 404. O método messaging.send() individual usa endpoint moderno.
    const messaging = admin.messaging();

    let successCount = 0;
    let failureCount = 0;
    const tokensInvalidos = [];

    console.log(`📨 Enviando ${tokens.length} notificação(ões) via send individual`);

    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];

        try {
            await messaging.send({
                notification: { title, body },
                data,
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'default_channel',
                        priority: 'high',
                        defaultSound: true,
                        defaultVibrateTimings: true,
                    },
                },
                apns: {
                    payload: {
                        aps: {
                            sound: 'default',
                        },
                    },
                },
                token,
            });

            successCount++;
            console.log(`✅ Notificação enviada para token ${i + 1}/${tokens.length}`);
        } catch (error) {
            failureCount++;

            const code = error?.code || '';
            const errorMessage = error?.message || 'Erro desconhecido';

            console.log(`❌ Falha ao enviar para token ${i + 1}/${tokens.length}:`, {
                code,
                message: errorMessage,
            });

            if (
                code === 'messaging/registration-token-not-registered' ||
                code === 'messaging/invalid-registration-token' ||
                code === 'messaging/invalid-argument'
            ) {
                tokensInvalidos.push(token);
            }
        }
    }

    await removerTokensInvalidos(tokensInvalidos, tokenOwners);

    return {
        successCount,
        failureCount,
        tokensInvalidos: tokensInvalidos.length,
    };
}

// ============================================
// FUNÇÃO 1: NOTIFICAÇÕES DE ANIVERSARIANTES
// ============================================
exports.sendBirthdayNotifications = onSchedule(
    {
        schedule: '0 11 * * *',
        timeZone: 'America/Sao_Paulo',
    },
    async (event) => {
        const hojeBrasilia = DateTime.now().setZone('America/Sao_Paulo');
        const month = hojeBrasilia.month;
        const day = hojeBrasilia.day;

        console.log(`🔔 Verificando aniversariantes para ${day}/${month} (Horário BR)...`);

        try {
            const alunosSnapshot = await db
                .collection('alunos')
                .where('status_atividade', '==', 'ATIVO(A)')
                .get();

            console.log(`👥 Alunos ativos encontrados: ${alunosSnapshot.size}`);

            const birthdayStudents = [];

            alunosSnapshot.forEach(doc => {
                const data = doc.data();
                const nascimento = extrairDataNascimento(data.data_nascimento);

                if (!nascimento) return;

                if (nascimento.day === day && nascimento.month === month) {
                    birthdayStudents.push(data.nome || data.apelido || 'Aluno');
                }
            });

            if (birthdayStudents.length === 0) {
                console.log('😴 Nenhum aniversariante hoje');
                return;
            }

            console.log(`🎉 ${birthdayStudents.length} aniversariante(s) hoje:`, birthdayStudents);

            const { usuariosAtivos, tokens, tokenOwners } = await buscarTokensUsuariosAtivos();

            if (tokens.length === 0) {
                console.log('😴 Nenhum token FCM encontrado');
                return;
            }

            const title = birthdayStudents.length === 1
                ? '🎉 Aniversariante do Dia!'
                : `🎉 ${birthdayStudents.length} Aniversariantes Hoje!`;

            const body = birthdayStudents.length === 1
                ? `${birthdayStudents[0]} está fazendo aniversário hoje! 🎂`
                : `Hoje fazem aniversário: ${birthdayStudents.join(', ')}`;

            const response = await enviarMulticastEmLotes({
                tokens,
                title,
                body,
                data: {
                    tipo: 'aniversario',
                    quantidade: String(birthdayStudents.length),
                    data: hojeBrasilia.toFormat('yyyy-MM-dd'),
                },
                tokenOwners,
            });

            console.log('📊 Resultado envio aniversário:', {
                usuariosAtivos,
                tokens: tokens.length,
                successCount: response.successCount,
                failureCount: response.failureCount,
                tokensInvalidosRemovidos: response.tokensInvalidos,
            });
        } catch (error) {
            console.error('❌ Erro ao enviar notificações de aniversário:', error);
        }
    }
);

// ============================================
// FUNÇÃO 1.1: TESTE MANUAL DE NOTIFICAÇÃO
// ============================================
exports.testarNotificacaoAniversario = onCall(async (request) => {
    if (!request.auth) {
        throw new Error('Usuário não autenticado');
    }

    try {
        const { usuariosAtivos, tokens, tokenOwners } = await buscarTokensUsuariosAtivos();

        if (tokens.length === 0) {
            return {
                success: false,
                message: 'Nenhum token FCM encontrado em usuários ativos',
                usuariosAtivos,
                tokens: 0,
            };
        }

        const response = await enviarMulticastEmLotes({
            tokens,
            title: '🎉 Teste de aniversário',
            body: 'Se essa notificação chegou, o FCM está funcionando!',
            data: {
                tipo: 'teste_aniversario',
                origem: 'callable_function',
            },
            tokenOwners,
        });

        return {
            success: true,
            usuariosAtivos,
            tokens: tokens.length,
            successCount: response.successCount,
            failureCount: response.failureCount,
            tokensInvalidosRemovidos: response.tokensInvalidos,
        };
    } catch (error) {
        console.error('❌ Erro no teste de notificação:', error);
        return {
            success: false,
            error: error.message,
        };
    }
});

// ============================================
// HELPERS - CONTADORES DE FREQUÊNCIA DO DASHBOARD
// ============================================
function normalizarDiaSemanaAbrev(valor) {
    return (valor || '')
        .toString()
        .toLowerCase()
        .replace('.', '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '');
}

function getChavesPeriodo(dataBrasilia) {
    const ano = dataBrasilia.toFormat('yyyy');
    const mesAno = dataBrasilia.toFormat('yyyy-MM');
    const semana = `${dataBrasilia.weekYear}-W${String(dataBrasilia.weekNumber).padStart(2, '0')}`;

    return { ano, mesAno, semana };
}

function montarUpdatesContadorFrequencia({
    alunoId,
    alunoNome,
    turmaId,
    turmaNome,
    academiaId,
    academiaNome,
    dataBrasilia,
    timestampBrasilia,
    presenteAntes,
    presenteDepois,
    diaSemanaAbrev,
    professorId,
    professorNome
}) {
    const delta = (presenteDepois ? 1 : 0) - (presenteAntes ? 1 : 0);
    const { ano, mesAno, semana } = getChavesPeriodo(dataBrasilia);
    const dia = normalizarDiaSemanaAbrev(diaSemanaAbrev || dataBrasilia.setLocale('pt-BR').toFormat('ccc'));

    const updates = {
        aluno_id: alunoId,
        aluno_nome: alunoNome,
        turma_id_atual: turmaId,
        turma_nome_atual: turmaNome,
        academia_id_atual: academiaId,
        academia_nome_atual: academiaNome,
        cache_versao: 5,
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        ultima_sync_logs: admin.firestore.FieldValue.serverTimestamp(),
        ultimo_professor_id: professorId || null,
        ultimo_professor_nome: professorNome || null,
        periodo_mes_atual: mesAno,
        periodo_semana_atual: semana,
    };

    if (delta !== 0) {
        updates.total = admin.firestore.FieldValue.increment(delta);
        updates[`porAno.${ano}`] = admin.firestore.FieldValue.increment(delta);
        updates[`porMes.${mesAno}`] = admin.firestore.FieldValue.increment(delta);
        updates[`porSemana.${semana}`] = admin.firestore.FieldValue.increment(delta);

        if (dia) {
            // Contadores de presença por dia da semana.
            // Mantém os dois formatos:
            // 1) porDiaSemana.seg / porDiaSemana.ter...
            // 2) seg / ter / qua... no topo do documento para compatibilidade com telas antigas.
            updates[`porDiaSemana.${dia}`] = admin.firestore.FieldValue.increment(delta);
            updates[dia] = admin.firestore.FieldValue.increment(delta);
        }

        // Campos rápidos usados pelo dashboard atual.
        // Observação: esses campos representam o mês/semana da data da chamada.
        // O dashboard pode preferir porMes[yyyy-MM] e porSemana[yyyy-Wxx] para máxima precisão.
        updates.mes = admin.firestore.FieldValue.increment(delta);
        updates.semana = admin.firestore.FieldValue.increment(delta);
    }

    if (presenteDepois) {
        updates.ultima_presenca = timestampBrasilia;
        updates.ultimo_dia_presente = dataBrasilia.toFormat('yyyy-MM-dd');
    }

    return updates;
}

// ============================================
// FUNÇÃO 2: PROCESSAR CHAMADA (COM CONTADORES DO DASHBOARD)
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

    if (!turmaId || !dataChamada || !Array.isArray(alunos)) {
        throw new Error('Dados inválidos para processar chamada');
    }

    // 🔥 CORREÇÃO DO FUSO HORÁRIO
    // O app Flutter já envia no horário local (Brasília)
    const dataBrasilia = DateTime.fromISO(dataChamada, { zone: 'America/Sao_Paulo' });
    const dataFormatada = dataBrasilia.toFormat('yyyy-MM-dd');
    const timestampBrasilia = admin.firestore.Timestamp.fromDate(dataBrasilia.toJSDate());
    const diaSemanaAbrev = normalizarDiaSemanaAbrev(
        dataBrasilia.setLocale('pt-BR').toFormat('ccc')
    );
    const mesAno = dataFormatada.substring(0, 7);

    console.log(`🕐 Data recebida: ${dataChamada}`);
    console.log(`🕐 Data Brasília: ${dataFormatada} ${dataBrasilia.toFormat('HH:mm')}`);
    console.log(`📅 Dia da semana: ${diaSemanaAbrev}`);

    // 🔒 Evita duplicar chamada e duplicar contador se houver retry/toque duplo
    const chamadaExistente = await db
        .collection('chamadas')
        .where('turma_id', '==', turmaId)
        .where('data_formatada', '==', dataFormatada)
        .limit(1)
        .get();

    if (!chamadaExistente.empty) {
        const existente = chamadaExistente.docs[0];
        const dados = existente.data();

        console.log(`⚠️ Chamada já existia para ${turmaId} em ${dataFormatada}. Retornando sem duplicar contadores.`);

        await db.collection('locks_chamada').doc(turmaId).delete().catch(() => {});

        return {
            success: true,
            duplicate: true,
            chamadaId: existente.id,
            processados: dados.total_alunos || alunos.length,
            presentes: dados.presentes || 0,
            ausentes: dados.ausentes || 0,
            porcentagem_frequencia: dados.porcentagem_frequencia || 0,
            diaSemanaAbrev,
            dataFormatada,
            contadoresAtualizados: false
        };
    }

    const presentes = alunos.filter(a => a.presente === true).length;
    const ausentes = alunos.length - presentes;
    const porcentagem = alunos.length > 0 ? Math.round((presentes / alunos.length) * 100) : 0;

    const batch = db.batch();
    const chamadaRef = db.collection('chamadas').doc();

    const chamadaData = {
        turma_id: turmaId,
        turma_nome: turmaNome,
        academia_id: academiaId,
        academia_nome: academiaNome,
        data_chamada: timestampBrasilia,
        data_formatada: dataFormatada,
        dia_semana_abrev: diaSemanaAbrev,
        tipo_aula: tipoAula,
        total_alunos: alunos.length,
        presentes,
        ausentes,
        porcentagem_frequencia: porcentagem,
        professor_id: professorId,
        professor_nome: professorNome,
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        alunos: alunos.map(aluno => ({
            aluno_id: aluno.id,
            aluno_nome: aluno.nome,
            presente: aluno.presente === true,
            observacao: aluno.observacao || ''
        }))
    };

    batch.set(chamadaRef, chamadaData);

    for (const aluno of alunos) {
        const alunoId = aluno.id;
        const presenteDepois = aluno.presente === true;

        // 🔥 ID fixo evita duplicar log do mesmo aluno/turma/data
        const logId = `log_${turmaId}_${alunoId}_${dataFormatada}`;

        const logRef = db.collection('log_presenca_alunos').doc(logId);

        const contadorDashboardRef = db
            .collection('alunos')
            .doc(alunoId)
            .collection('contadores')
            .doc('frequencia_dashboard');

        const alunoRef = db.collection('alunos').doc(alunoId);

        const contadorGeralRef = db
            .collection('contador_presencas_alunos')
            .doc(alunoId);

        const logAnteriorDoc = await logRef.get();
        const presenteAntes =
            logAnteriorDoc.exists && logAnteriorDoc.data()?.presente === true;

        const logData = {
            log_id: logId,
            chamada_id: chamadaRef.id,
            aluno_id: alunoId,
            aluno_nome: aluno.nome,
            turma_id: turmaId,
            turma_nome: turmaNome,
            academia_id: academiaId,
            academia_nome: academiaNome,
            data_aula: timestampBrasilia,
            data_formatada: dataFormatada,
            dia_semana_abrev: diaSemanaAbrev,
            presente: presenteDepois,
            tipo_aula: tipoAula,
            observacao: aluno.observacao || '',
            professor_id: professorId,
            professor_nome: professorNome,
            registrado_em: logAnteriorDoc.exists
                ? (logAnteriorDoc.data()?.registrado_em || admin.firestore.FieldValue.serverTimestamp())
                : admin.firestore.FieldValue.serverTimestamp(),
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            tipo_registro: 'chamada_turma'
        };

        batch.set(logRef, logData, { merge: true });

        // Mantém compatibilidade com seu contador mensal antigo dentro do documento do aluno
        if (presenteDepois !== presenteAntes) {
            const delta = presenteDepois ? 1 : -1;

            batch.set(alunoRef, {
                [`contadores.${mesAno}`]: admin.firestore.FieldValue.increment(delta),
            }, { merge: true });
        }

        const alunoUpdate = {
            ultima_chamada: admin.firestore.FieldValue.serverTimestamp(),
            ultima_chamada_por: professorNome,
            ultima_chamada_por_id: professorId,
        };

        if (presenteDepois) {
            alunoUpdate.ultima_presenca = timestampBrasilia;
            alunoUpdate.ultimo_dia_presente = dataFormatada;
        }

        batch.set(alunoRef, alunoUpdate, { merge: true });

        // Novo contador usado pelo dashboard leve
        const contadorUpdates = montarUpdatesContadorFrequencia({
            alunoId,
            alunoNome: aluno.nome,
            turmaId,
            turmaNome,
            academiaId,
            academiaNome,
            dataBrasilia,
            timestampBrasilia,
            presenteAntes,
            presenteDepois,
            diaSemanaAbrev,
            professorId,
            professorNome
        });

        batch.set(contadorDashboardRef, contadorUpdates, { merge: true });

        // Mantém sua coleção antiga contador_presencas_alunos
        batch.set(contadorGeralRef, {
            turma_id: turmaId,
            academia_id: academiaId,
            aluno_id: alunoId,
            aluno_nome: aluno.nome,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            ultima_chamada: admin.firestore.FieldValue.serverTimestamp(),
            ultima_chamada_por: professorNome,
            ultima_chamada_por_id: professorId,
        }, { merge: true });
    }

    await batch.commit();

    await db.collection('locks_chamada').doc(turmaId).delete().catch(() => {});

    return {
        success: true,
        duplicate: false,
        chamadaId: chamadaRef.id,
        processados: alunos.length,
        presentes,
        ausentes,
        porcentagem_frequencia: porcentagem,
        diaSemanaAbrev,
        dataFormatada,
        contadoresAtualizados: true
    };
});

// ============================================
// FUNÇÃO 3: EXCLUIR CHAMADA (COM AJUSTE DOS CONTADORES DO DASHBOARD)
// ============================================
exports.excluirChamada = onCall(async (request) => {
    if (!request.auth) {
        throw new Error('Usuário não autenticado');
    }

    const { chamadaId, turmaId } = request.data;

    if (!chamadaId || !turmaId) {
        throw new Error('Parâmetros obrigatórios: chamadaId e turmaId');
    }

    const chamadaDoc = await db.collection('chamadas').doc(chamadaId).get();

    if (!chamadaDoc.exists) {
        throw new Error('Chamada não encontrada');
    }

    const chamadaData = chamadaDoc.data();
    const alunos = chamadaData.alunos || [];
    const dataFormatada = chamadaData.data_formatada;
    const dataChamadaTimestamp = chamadaData.data_chamada;
    const dataChamada = dataChamadaTimestamp.toDate();
    const dataBrasilia = DateTime.fromJSDate(dataChamada, { zone: 'America/Sao_Paulo' });
    const { ano, mesAno, semana } = getChavesPeriodo(dataBrasilia);
    const diaSemanaAbrev = normalizarDiaSemanaAbrev(
        chamadaData.dia_semana_abrev || dataBrasilia.setLocale('pt-BR').toFormat('ccc')
    );

    const logsQuery = await db
        .collection('log_presenca_alunos')
        .where('data_formatada', '==', dataFormatada)
        .where('turma_id', '==', turmaId)
        .get();

    const batch = db.batch();

    for (const aluno of alunos) {
        const alunoId = aluno.aluno_id;
        const estavaPresente = aluno.presente === true;
        const alunoRef = db.collection('alunos').doc(alunoId);
        const contadorDashboardRef = alunoRef
            .collection('contadores')
            .doc('frequencia_dashboard');

        if (estavaPresente) {
            // Compatibilidade com contador antigo
            batch.set(alunoRef, {
                [`contadores.${mesAno}`]: admin.firestore.FieldValue.increment(-1)
            }, { merge: true });

            // Novo contador do dashboard
            batch.set(contadorDashboardRef, {
                total: admin.firestore.FieldValue.increment(-1),
                [`porAno.${ano}`]: admin.firestore.FieldValue.increment(-1),
                [`porMes.${mesAno}`]: admin.firestore.FieldValue.increment(-1),
                [`porSemana.${semana}`]: admin.firestore.FieldValue.increment(-1),
                ...(diaSemanaAbrev ? {
                    [`porDiaSemana.${diaSemanaAbrev}`]: admin.firestore.FieldValue.increment(-1),
                    [diaSemanaAbrev]: admin.firestore.FieldValue.increment(-1),
                } : {}),
                mes: admin.firestore.FieldValue.increment(-1),
                semana: admin.firestore.FieldValue.increment(-1),
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                ultima_sync_logs: admin.firestore.FieldValue.serverTimestamp(),
                cache_versao: 5,
            }, { merge: true });
        }

        const ultimaPresencaQuery = await db
            .collection('log_presenca_alunos')
            .where('aluno_id', '==', alunoId)
            .where('presente', '==', true)
            .where('data_aula', '<', dataChamadaTimestamp)
            .orderBy('data_aula', 'desc')
            .limit(1)
            .get();

        if (ultimaPresencaQuery.docs.length > 0) {
            const ultimaPresencaData = ultimaPresencaQuery.docs[0].data();

            batch.set(alunoRef, {
                ultima_presenca: ultimaPresencaData.data_aula,
                ultimo_dia_presente: ultimaPresencaData.data_formatada || null,
            }, { merge: true });

            batch.set(contadorDashboardRef, {
                ultima_presenca: ultimaPresencaData.data_aula,
                ultimo_dia_presente: ultimaPresencaData.data_formatada || null,
            }, { merge: true });
        } else {
            batch.set(alunoRef, {
                ultima_presenca: null,
                ultimo_dia_presente: null,
            }, { merge: true });

            batch.set(contadorDashboardRef, {
                ultima_presenca: null,
                ultimo_dia_presente: null,
            }, { merge: true });
        }

        const ultimaChamadaQuery = await db
            .collection('log_presenca_alunos')
            .where('aluno_id', '==', alunoId)
            .orderBy('data_aula', 'desc')
            .limit(1)
            .get();

        if (ultimaChamadaQuery.docs.length > 0) {
            const ultimaChamada = ultimaChamadaQuery.docs[0].data();

            batch.set(alunoRef, {
                ultima_chamada: ultimaChamada.data_aula,
                ultima_chamada_por: ultimaChamada.professor_nome || null,
                ultima_chamada_por_id: ultimaChamada.professor_id || null
            }, { merge: true });
        } else {
            batch.set(alunoRef, {
                ultima_chamada: null,
                ultima_chamada_por: null,
                ultima_chamada_por_id: null
            }, { merge: true });
        }
    }

    batch.delete(chamadaDoc.ref);

    for (const logDoc of logsQuery.docs) {
        batch.delete(logDoc.ref);
    }

    await batch.commit();

    return {
        success: true,
        logsExcluidos: logsQuery.docs.length,
        alunosProcessados: alunos.length,
        contadoresAtualizados: true
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
    
    const ordemDias = ['SEGUNDA', 'TERCA', 'QUARTA', 'QUINTA', 'SEXTA', 'SABADO', 'DOMINGO'];
    
    for (const doc of turmasSnapshot.docs) {
      const id = doc.id;
      
      if (turmasSelecionadas[id] !== true) continue;
      
      const data = doc.data();
      
      const diasConfig = data.dias_configuracao || {};
      const diasComHorarios = [];
      
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

// ============================================
// FUNÇÃO 8: VALIDAR ACESSO DA ÁREA DO ALUNO
// ============================================

function normalizarTextoAreaAluno(valor) {
    return (valor || '')
        .toString()
        .trim()
        .toUpperCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[^A-Z0-9\s]/g, '')
        .replace(/\s+/g, ' ');
}

function gerarIniciaisAreaAluno(nome) {
    const nomeNormalizado = normalizarTextoAreaAluno(nome);

    if (!nomeNormalizado) return '';

    const palavrasIgnoradas = new Set(['DA', 'DE', 'DI', 'DO', 'DAS', 'DOS', 'E']);
    const partes = nomeNormalizado
        .split(' ')
        .map(p => p.trim())
        .filter(p => p.length > 0 && !palavrasIgnoradas.has(p));

    return partes.map(p => p[0]).join('');
}

function limparNumeroAreaAluno(valor) {
    return (valor || '').toString().replace(/\D/g, '');
}

function ultimos4AreaAluno(valor) {
    const limpo = limparNumeroAreaAluno(valor);
    if (limpo.length < 4) return '';
    return limpo.substring(limpo.length - 4);
}

function parseDataNascimentoAreaAluno(valor) {
    if (!valor) return null;

    const texto = valor.toString().trim();

    // Aceita dd/MM/yyyy
    let dt = DateTime.fromFormat(texto, 'dd/MM/yyyy', {
        zone: 'America/Sao_Paulo',
    });

    if (dt.isValid) return dt.startOf('day');

    // Aceita yyyy-MM-dd
    dt = DateTime.fromFormat(texto, 'yyyy-MM-dd', {
        zone: 'America/Sao_Paulo',
    });

    if (dt.isValid) return dt.startOf('day');

    return null;
}

function timestampToDataBR(timestamp) {
    if (!timestamp || !timestamp.toDate) return null;

    try {
        return DateTime
            .fromJSDate(timestamp.toDate())
            .setZone('America/Sao_Paulo')
            .toFormat('dd/MM/yyyy');
    } catch (e) {
        return null;
    }
}

function traduzirDiaAreaAluno(dia) {
    const dias = {
        'SEGUNDA': 'Segunda-feira',
        'TERCA': 'Terça-feira',
        'QUARTA': 'Quarta-feira',
        'QUINTA': 'Quinta-feira',
        'SEXTA': 'Sexta-feira',
        'SABADO': 'Sábado',
        'DOMINGO': 'Domingo',
    };

    return dias[dia] || dia;
}

function montarHorariosTurmaAreaAluno(turmaData) {
    const diasConfig = turmaData.dias_configuracao || {};
    const ordemDias = ['SEGUNDA', 'TERCA', 'QUARTA', 'QUINTA', 'SEXTA', 'SABADO', 'DOMINGO'];
    const horarios = [];

    for (const dia of ordemDias) {
        const config = diasConfig[dia];

        if (config && config.selecionado === true) {
            horarios.push({
                dia,
                dia_nome: traduzirDiaAreaAluno(dia),
                horario_inicio: config.horario_inicio || '',
                horario_fim: config.horario_fim || '',
                tipo_aula: config.tipoAula || config.tipo_aula || 'OBJETIVA',
            });
        }
    }

    // Fallback para turmas antigas.
    if (horarios.length === 0 && Array.isArray(turmaData.dias_semana)) {
        for (const dia of turmaData.dias_semana) {
            horarios.push({
                dia,
                dia_nome: traduzirDiaAreaAluno(dia),
                horario_inicio: turmaData.horario_inicio || '',
                horario_fim: turmaData.horario_fim || '',
                tipo_aula: turmaData.tipo_aula || 'OBJETIVA',
            });
        }
    }

    return horarios;
}

function montarDadosTurmaLiberados(turmaId, turmaData) {
    if (!turmaId || !turmaData) return null;

    return {
        turma_id: turmaId,
        nome: turmaData.nome || '',
        nivel: turmaData.nivel || '',
        nucleo: turmaData.nucleo || '',
        faixa_etaria: turmaData.faixa_etaria || '',
        status: turmaData.status || '',
        cor_turma: turmaData.cor_turma || '',
        logo_url: turmaData.logo_url || '',
        professores_nomes: turmaData.professores_nomes || [],
        professor_principal: turmaData.professor_principal || '',
        capacidade_maxima: turmaData.capacidade_maxima || 0,
        alunos_ativos: turmaData.alunos_ativos || 0,
        idade_minima: turmaData.idade_minima || null,
        idade_maxima: turmaData.idade_maxima || null,
        duracao_aula_minutos: turmaData.duracao_aula_minutos || null,
        data_inicio: timestampToDataBR(turmaData.data_inicio),
        observacoes: turmaData.observacoes || '',
        whatsapp_url: turmaData.whatsapp_url || '',
        horarios: montarHorariosTurmaAreaAluno(turmaData),
    };
}

async function montarDadosAlunoLiberados(alunoId, alunoData, config) {
    const dados = {
        aluno_id: alunoId,
        nome: alunoData.nome || '',
        apelido: alunoData.apelido || '',
        status_atividade: alunoData.status_atividade || '',
    };

    if (config.mostrar_foto !== false) {
        dados.foto_perfil_aluno = alunoData.foto_perfil_aluno || '';
    }

    if (config.mostrar_dados_basicos !== false) {
        dados.sexo = alunoData.sexo || '';
        dados.data_nascimento = timestampToDataBR(alunoData.data_nascimento);
        dados.cidade = alunoData.cidade || '';
        dados.endereco = alunoData.endereco || '';
        dados.nome_responsavel = alunoData.nome_responsavel || '';

        // Na Área do Aluno, o próprio aluno/responsável precisa conferir os dados.
        // Por isso retornamos os contatos cadastrados para leitura.
        dados.contato_aluno = alunoData.contato_aluno || '';
        dados.contato_responsavel = alunoData.contato_responsavel || '';

        // Mantém também os finais por compatibilidade/segurança visual se quiser usar depois.
        dados.contato_aluno_final = ultimos4AreaAluno(alunoData.contato_aluno || '');
        dados.contato_responsavel_final = ultimos4AreaAluno(alunoData.contato_responsavel || '');
    }

    if (config.mostrar_academia_turma !== false) {
        dados.academia = alunoData.academia || '';
        dados.academia_id = alunoData.academia_id || '';
        dados.turma = alunoData.turma || '';
        dados.turma_id = alunoData.turma_id || '';
        dados.modalidade = alunoData.modalidade || '';
    }

    if (config.mostrar_graduacao !== false) {
        dados.graduacao_atual = alunoData.graduacao_atual || alunoData.graduacao_nome || '';
        dados.graduacao_nome = alunoData.graduacao_nome || alunoData.graduacao_atual || '';
        dados.graduacao_cor1 = alunoData.graduacao_cor1 || '';
        dados.graduacao_cor2 = alunoData.graduacao_cor2 || '';
        dados.graduacao_ponta1 = alunoData.graduacao_ponta1 || '';
        dados.graduacao_ponta2 = alunoData.graduacao_ponta2 || '';
        dados.nivel_graduacao = alunoData.nivel_graduacao || 0;
        dados.data_graduacao_atual = timestampToDataBR(alunoData.data_graduacao_atual);
    }

    if (config.mostrar_presencas !== false) {
        dados.ultima_presenca = timestampToDataBR(alunoData.ultima_presenca);
        dados.ultimo_dia_presente = alunoData.ultimo_dia_presente || '';
        dados.ultima_chamada = timestampToDataBR(alunoData.ultima_chamada);
    }

    // Outros campos úteis em leitura.
    dados.tempo_capoeira = timestampToDataBR(alunoData.tempo_capoeira);

    // Dados da turma para o dashboard público do aluno.
    // Isso evita o site consultar diretamente a coleção turmas.
    dados.turma_info = null;

    if (alunoData.turma_id) {
        try {
            const turmaDoc = await db.collection('turmas').doc(alunoData.turma_id).get();

            if (turmaDoc.exists) {
                dados.turma_info = montarDadosTurmaLiberados(turmaDoc.id, turmaDoc.data() || {});
            }
        } catch (e) {
            console.error('⚠️ Erro ao buscar turma para Área do Aluno:', e);
        }
    }

    return dados;
}

async function registrarLogErroAreaAluno({
    dataNascimento,
    iniciais,
    telefoneFinal,
    motivo,
    detalhes = {},
}) {
    try {
        await db.collection('area_aluno_logs_erro').add({
            data_nascimento_usada: dataNascimento || '',
            iniciais_usadas: iniciais || '',
            telefone_final_usado: telefoneFinal || '',
            motivo,
            detalhes,
            origem: 'site_area_aluno',
            tentativa_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
        console.error('⚠️ Erro ao registrar log de erro da área do aluno:', e);
    }
}

async function registrarLogAcessoAreaAluno({
    alunoId,
    alunoData,
    iniciais,
}) {
    try {
        await db.collection('area_aluno_logs_acesso').add({
            aluno_id: alunoId,
            aluno_nome: alunoData.nome || '',
            iniciais_usadas: iniciais || '',
            status_aluno: alunoData.status_atividade || '',
            turma_id: alunoData.turma_id || '',
            turma: alunoData.turma || '',
            academia_id: alunoData.academia_id || '',
            academia: alunoData.academia || '',
            origem: 'site_area_aluno',
            sucesso: true,
            acesso_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
        console.error('⚠️ Erro ao registrar log de acesso da área do aluno:', e);
    }
}

exports.validarAcessoAreaAluno = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        const payload = request.data || {};

        const dataNascimentoInformada = (payload.dataNascimento || payload.data_nascimento || '').toString().trim();
        const iniciaisInformadas = normalizarTextoAreaAluno(payload.iniciais || '');
        const telefoneFinalInformado = limparNumeroAreaAluno(payload.telefoneFinal || payload.telefone_final || '');

        try {
            const configDoc = await db
                .collection('configuracoes_site')
                .doc('area_aluno')
                .get();

            const config = configDoc.exists ? (configDoc.data() || {}) : {};

            const visivelSite = config.visivel_site === true;
            const aceitarApenasAtivos = config.aceitar_apenas_ativos !== false;
            const exigirTelefone = config.exigir_telefone_confirmacao !== false;

            if (!visivelSite) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'area_aluno_desativada',
                });

                return {
                    success: false,
                    code: 'area_desativada',
                    message: 'A Área do Aluno não está disponível no momento.',
                };
            }

            if (!dataNascimentoInformada || !iniciaisInformadas) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'campos_obrigatorios_ausentes',
                });

                return {
                    success: false,
                    code: 'dados_invalidos',
                    message: 'Confira os dados informados e tente novamente.',
                };
            }

            if (exigirTelefone && telefoneFinalInformado.length !== 4) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'telefone_final_invalido',
                });

                return {
                    success: false,
                    code: 'dados_invalidos',
                    message: 'Confira os dados informados e tente novamente.',
                };
            }

            const dataNascimento = parseDataNascimentoAreaAluno(dataNascimentoInformada);

            if (!dataNascimento) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'data_nascimento_invalida',
                });

                return {
                    success: false,
                    code: 'dados_invalidos',
                    message: 'Confira os dados informados e tente novamente.',
                };
            }

            const inicioDia = admin.firestore.Timestamp.fromDate(dataNascimento.toJSDate());
            const fimDia = admin.firestore.Timestamp.fromDate(dataNascimento.plus({ days: 1 }).toJSDate());

            console.log('🔎 Área do Aluno - buscando aluno:', {
                dataNascimentoInformada,
                iniciaisInformadas,
                telefoneFinalInformado: telefoneFinalInformado ? '****' : '',
                aceitarApenasAtivos,
                exigirTelefone,
                inicioDia: inicioDia.toDate().toISOString(),
                fimDia: fimDia.toDate().toISOString(),
            });

            let query = db.collection('alunos');

            // Agora que o índice composto foi criado:
            // status_atividade ASC + data_nascimento ASC
            // usamos a query otimizada direto no Firestore.
            if (aceitarApenasAtivos) {
                query = query.where('status_atividade', '==', 'ATIVO(A)');
            }

            query = query
                .where('data_nascimento', '>=', inicioDia)
                .where('data_nascimento', '<', fimDia);

            const snapshot = await query.get();

            console.log(`🔎 Área do Aluno - documentos encontrados pela data/status: ${snapshot.size}`);

            if (snapshot.empty) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'nenhum_aluno_encontrado',
                });

                return {
                    success: false,
                    code: 'nao_encontrado',
                    message: 'Confira os dados informados e tente novamente.',
                };
            }

            let candidatos = [];

            snapshot.forEach(doc => {
                const alunoData = doc.data();
                const iniciaisAluno = gerarIniciaisAreaAluno(alunoData.nome || '');

                if (iniciaisAluno === iniciaisInformadas) {
                    candidatos.push({
                        id: doc.id,
                        data: alunoData,
                    });
                }
            });

            if (candidatos.length === 0) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'iniciais_nao_conferem',
                    detalhes: {
                        encontrados_mesma_data: snapshot.size,
                    },
                });

                return {
                    success: false,
                    code: 'nao_encontrado',
                    message: 'Confira os dados informados e tente novamente.',
                };
            }

            if (exigirTelefone) {
                candidatos = candidatos.filter(candidato => {
                    const aluno = candidato.data;
                    const finaisPossiveis = [
                        ultimos4AreaAluno(aluno.contato_aluno || ''),
                        ultimos4AreaAluno(aluno.contato_responsavel || ''),
                    ].filter(Boolean);

                    return finaisPossiveis.includes(telefoneFinalInformado);
                });

                if (candidatos.length === 0) {
                    await registrarLogErroAreaAluno({
                        dataNascimento: dataNascimentoInformada,
                        iniciais: iniciaisInformadas,
                        telefoneFinal: telefoneFinalInformado,
                        motivo: 'telefone_final_nao_confere',
                    });

                    return {
                        success: false,
                        code: 'nao_encontrado',
                        message: 'Confira os dados informados e tente novamente.',
                    };
                }
            }

            if (candidatos.length > 1) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'multiplos_alunos_encontrados',
                    detalhes: {
                        quantidade: candidatos.length,
                    },
                });

                return {
                    success: false,
                    code: 'multiplos_resultados',
                    message: 'Encontramos mais de um aluno com esses dados. Procure a coordenação.',
                };
            }

            const candidato = candidatos[0];
            const alunoData = candidato.data;

            if (aceitarApenasAtivos && alunoData.status_atividade !== 'ATIVO(A)') {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'aluno_inativo',
                    detalhes: {
                        aluno_id: candidato.id,
                        status_atividade: alunoData.status_atividade || '',
                    },
                });

                return {
                    success: false,
                    code: 'aluno_inativo',
                    message: 'Acesso não liberado para este cadastro. Procure a coordenação.',
                };
            }

            await registrarLogAcessoAreaAluno({
                alunoId: candidato.id,
                alunoData,
                iniciais: iniciaisInformadas,
            });

            const dadosAluno = await montarDadosAlunoLiberados(candidato.id, alunoData, config);

            return {
                success: true,
                code: 'acesso_liberado',
                message: 'Acesso liberado.',
                aluno: dadosAluno,
                config: {
                    mostrar_foto: config.mostrar_foto !== false,
                    mostrar_dados_basicos: config.mostrar_dados_basicos !== false,
                    mostrar_academia_turma: config.mostrar_academia_turma !== false,
                    mostrar_graduacao: config.mostrar_graduacao !== false,
                    mostrar_presencas: config.mostrar_presencas !== false,
                    mostrar_historico_chamadas: config.mostrar_historico_chamadas === true,
                    mensagem_topo: config.mensagem_topo || 'Bem-vindo(a) à Área do Aluno',
                },
            };
        } catch (error) {
            console.error('❌ Erro em validarAcessoAreaAluno:', error);

            await registrarLogErroAreaAluno({
                dataNascimento: dataNascimentoInformada,
                iniciais: iniciaisInformadas,
                telefoneFinal: telefoneFinalInformado,
                motivo: 'erro_interno',
                detalhes: {
                    message: error.message || String(error),
                },
            });

            return {
                success: false,
                code: 'erro_interno',
                message: 'Não foi possível validar o acesso agora. Tente novamente mais tarde.',
            };
        }
    }
);

// ============================================
// FUNÇÃO 9: CRIAR SOLICITAÇÃO DE ALTERAÇÃO DA ÁREA DO ALUNO
// ============================================

function limparStringSolicitacao(valor) {
    if (valor === null || valor === undefined) return '';
    return valor.toString().trim();
}

function normalizarComparacaoSolicitacao(valor) {
    return limparStringSolicitacao(valor)
        .toUpperCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
}

function dataNascimentoAlunoParaBR(alunoData) {
    return timestampToDataBR(alunoData.data_nascimento) || '';
}

function validarIdentidadeSolicitacao(alunoData, authPayload) {
    const dataNascimentoInformada = limparStringSolicitacao(
        authPayload.dataNascimento || authPayload.data_nascimento || ''
    );
    const iniciaisInformadas = normalizarTextoAreaAluno(authPayload.iniciais || '');
    const telefoneFinalInformado = limparNumeroAreaAluno(
        authPayload.telefoneFinal || authPayload.telefone_final || ''
    );

    if (!dataNascimentoInformada || !iniciaisInformadas) {
        return {
            ok: false,
            motivo: 'dados_de_validacao_ausentes',
        };
    }

    const nascimentoAluno = dataNascimentoAlunoParaBR(alunoData);

    if (nascimentoAluno !== dataNascimentoInformada) {
        return {
            ok: false,
            motivo: 'data_nascimento_nao_confere',
        };
    }

    const iniciaisAluno = gerarIniciaisAreaAluno(alunoData.nome || '');

    if (iniciaisAluno !== iniciaisInformadas) {
        return {
            ok: false,
            motivo: 'iniciais_nao_conferem',
        };
    }

    const finaisPossiveis = [
        ultimos4AreaAluno(alunoData.contato_aluno || ''),
        ultimos4AreaAluno(alunoData.contato_responsavel || ''),
    ].filter(Boolean);

    if (telefoneFinalInformado && telefoneFinalInformado.length === 4) {
        if (!finaisPossiveis.includes(telefoneFinalInformado)) {
            return {
                ok: false,
                motivo: 'telefone_final_nao_confere',
            };
        }
    }

    return {
        ok: true,
        motivo: 'validado',
    };
}

function montarOriginalSolicitacao(alunoData) {
    return {
        nome: alunoData.nome || '',
        apelido: alunoData.apelido || '',
        data_nascimento: dataNascimentoAlunoParaBR(alunoData),
        sexo: alunoData.sexo || '',
        cidade: alunoData.cidade || '',
        endereco: alunoData.endereco || '',
        contato_aluno: alunoData.contato_aluno || '',
        nome_responsavel: alunoData.nome_responsavel || '',
        contato_responsavel: alunoData.contato_responsavel || '',
    };
}

function limparDadosSolicitadosAreaAluno(dados) {
    const entrada = dados || {};

    return {
        nome: limparStringSolicitacao(entrada.nome).toUpperCase(),
        apelido: limparStringSolicitacao(entrada.apelido),
        data_nascimento: limparStringSolicitacao(entrada.data_nascimento),
        sexo: limparStringSolicitacao(entrada.sexo).toUpperCase(),
        cidade: limparStringSolicitacao(entrada.cidade).toUpperCase(),
        endereco: limparStringSolicitacao(entrada.endereco),
        contato_aluno: limparNumeroAreaAluno(entrada.contato_aluno || ''),
        nome_responsavel: limparStringSolicitacao(entrada.nome_responsavel),
        contato_responsavel: limparNumeroAreaAluno(entrada.contato_responsavel || ''),
    };
}

function calcularCamposAlteradosSolicitacao(originais, solicitados) {
    const campos = [];

    for (const key of Object.keys(solicitados)) {
        const original = originais[key] || '';
        const novo = solicitados[key] || '';

        if (key.includes('contato')) {
            if (limparNumeroAreaAluno(original) !== limparNumeroAreaAluno(novo)) {
                campos.push(key);
            }
        } else {
            if (normalizarComparacaoSolicitacao(original) !== normalizarComparacaoSolicitacao(novo)) {
                campos.push(key);
            }
        }
    }

    return campos;
}

exports.criarSolicitacaoAlteracaoAreaAluno = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        const payload = request.data || {};
        const alunoId = limparStringSolicitacao(payload.alunoId || payload.aluno_id || '');
        const authPayload = payload.auth || {};
        const dadosSolicitadosEntrada = payload.dadosSolicitados || payload.dados_solicitados || {};
        const observacaoAluno = limparStringSolicitacao(payload.observacaoAluno || payload.observacao_aluno || '');

        try {
            if (!alunoId) {
                return {
                    success: false,
                    code: 'aluno_id_ausente',
                    message: 'Não foi possível identificar o aluno.',
                };
            }

            const alunoRef = db.collection('alunos').doc(alunoId);
            const alunoDoc = await alunoRef.get();

            if (!alunoDoc.exists) {
                return {
                    success: false,
                    code: 'aluno_nao_encontrado',
                    message: 'Cadastro do aluno não encontrado.',
                };
            }

            const alunoData = alunoDoc.data() || {};
            const validacao = validarIdentidadeSolicitacao(alunoData, authPayload);

            if (!validacao.ok) {
                await registrarLogErroAreaAluno({
                    dataNascimento: authPayload.dataNascimento || '',
                    iniciais: authPayload.iniciais || '',
                    telefoneFinal: authPayload.telefoneFinal || '',
                    motivo: `solicitacao_alteracao_${validacao.motivo}`,
                    detalhes: {
                        aluno_id: alunoId,
                    },
                });

                return {
                    success: false,
                    code: 'validacao_falhou',
                    message: 'Não foi possível confirmar sua identidade. Acesse a Área do Aluno novamente.',
                };
            }

            const pendentesSnapshot = await db
                .collection('area_aluno_solicitacoes_alteracao')
                .where('aluno_id', '==', alunoId)
                .where('status', '==', 'pendente')
                .limit(1)
                .get();

            if (!pendentesSnapshot.empty) {
                return {
                    success: false,
                    code: 'solicitacao_pendente_existente',
                    message: 'Já existe uma solicitação pendente para este aluno. Aguarde a análise da coordenação.',
                };
            }

            const dadosOriginais = montarOriginalSolicitacao(alunoData);
            const dadosSolicitados = limparDadosSolicitadosAreaAluno(dadosSolicitadosEntrada);
            const camposAlterados = calcularCamposAlteradosSolicitacao(dadosOriginais, dadosSolicitados);

            if (camposAlterados.length === 0) {
                return {
                    success: false,
                    code: 'sem_alteracoes',
                    message: 'Nenhuma alteração foi identificada.',
                };
            }

            const solicitacao = {
                aluno_id: alunoId,
                aluno_nome: alunoData.nome || '',
                academia_id: alunoData.academia_id || '',
                academia: alunoData.academia || '',
                turma_id: alunoData.turma_id || '',
                turma: alunoData.turma || '',
                status: 'pendente',
                dados_originais: dadosOriginais,
                dados_solicitados: dadosSolicitados,
                campos_alterados: camposAlterados,
                observacao_aluno: observacaoAluno,
                origem: 'site_area_aluno',
                criado_em: admin.firestore.FieldValue.serverTimestamp(),
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                analisado_em: null,
                analisado_por: '',
                analisado_por_nome: '',
                observacao_admin: '',
            };

            const docRef = await db
                .collection('area_aluno_solicitacoes_alteracao')
                .add(solicitacao);

            return {
                success: true,
                code: 'solicitacao_criada',
                message: 'Solicitação enviada para análise.',
                solicitacao_id: docRef.id,
                campos_alterados: camposAlterados,
            };
        } catch (error) {
            console.error('❌ Erro em criarSolicitacaoAlteracaoAreaAluno:', error);

            return {
                success: false,
                code: 'erro_interno',
                message: 'Não foi possível enviar a solicitação agora. Tente novamente mais tarde.',
            };
        }
    }
);
