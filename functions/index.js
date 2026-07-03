require('dotenv').config();

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { Storage } = require('@google-cloud/storage');
const { DateTime } = require('luxon');
const axios = require('axios');
const crypto = require('crypto');
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

/**
 * Calcula a idade com base na data de nascimento.
 * @param {any} dataNascimento - Data de nascimento (Timestamp, ISO string ou Date).
 * @returns {number|null} - Idade em anos ou null.
 */
function calcularIdade(dataNascimento) {
    if (!dataNascimento) return null;
    try {
        let dt;
        if (dataNascimento.toDate) {
            dt = DateTime.fromJSDate(dataNascimento.toDate());
        } else if (typeof dataNascimento === 'string') {
            const partes = dataNascimento.trim().split('/');
            if (partes.length === 3) {
                dt = DateTime.fromFormat(dataNascimento.trim(), 'dd/MM/yyyy');
            } else {
                dt = DateTime.fromISO(dataNascimento);
            }
        } else if (dataNascimento instanceof Date) {
            dt = DateTime.fromJSDate(dataNascimento);
        }

        if (!dt || !dt.isValid) return null;

        const now = DateTime.now().setZone('America/Sao_Paulo');
        const diff = now.diff(dt, 'years').toObject();
        return Math.floor(diff.years);
    } catch (e) {
        return null;
    }
}

/**
 * Determina a faixa etária com base na idade.
 * @param {number|null} idade - Idade em anos.
 * @returns {string} - Label da faixa etária.
 */
function determinarFaixaEtaria(idade) {
    if (idade === null || idade === undefined || idade < 0) return "NAO_INFORMADA";
    if (idade <= 7) return "4-7 anos";
    if (idade <= 12) return "8-12 anos";
    if (idade <= 17) return "13-17 anos";
    if (idade <= 25) return "18-25 anos";
    if (idade <= 35) return "26-35 anos";
    if (idade <= 50) return "36-50 anos";
    return "50+ anos";
}

/**
 * Executa uma lista de operações de batch no Firestore, respeitando o limite de 500.
 * @param {Array<Function>} writes - Array de funções que recebem um batch como argumento.
 */
async function executarBatchWrites(writes) {
    if (!writes || writes.length === 0) return;
    const chunk_size = 450;
    for (let i = 0; i < writes.length; i += chunk_size) {
        const batch = admin.firestore().batch();
        const chunk = writes.slice(i, i + chunk_size);
        chunk.forEach(fn => fn(batch));
        await batch.commit();
    }
}

async function buscarTokensUsuariosAtivos() {
    const usuariosSnapshot = await db
        .collection('usuarios')
        .where('status_conta', '==', 'ativa')
        .get();

    console.log(`👥 Usuários ativos encontrados: ${usuariosSnapshot.size}`);

    const tokens = [];
    const tokenOwners = new Map();
    const usuariosMap = new Map();

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

        if (uniqueUserTokens.length > 0) {
            usuariosMap.set(doc.id, {
                ref: doc.ref,
                uid: doc.id,
                email: data.email || '',
                nome: data.nome_completo || data.nome || '',
                plataforma_token: data.plataforma_token || '',
                token_origem: data.token_origem || '',
            });
        }

        uniqueUserTokens.forEach(token => {
            tokens.push(token);
            tokenOwners.set(token, doc.ref);
        });
    });

    const uniqueTokens = [...new Set(tokens)].filter(Boolean);
    console.log(`📱 Tokens únicos encontrados: ${uniqueTokens.length}`);

    return {
        usuariosAtivos: usuariosSnapshot.size,
        usuariosNotificaveis: usuariosMap.size,
        tokens: uniqueTokens,
        tokenOwners,
        usuariosMap,
    };
}



async function buscarTokensUsuariosAtivosPorOrigem(origensPermitidas = []) {
    const usuariosSnapshot = await db
        .collection('usuarios')
        .where('status_conta', '==', 'ativa')
        .get();

    const origens = new Set(
        origensPermitidas
            .map(item => String(item || '').trim().toLowerCase())
            .filter(Boolean)
    );

    console.log(`👥 Usuários ativos encontrados para filtro: ${usuariosSnapshot.size}`);
    console.log(`🎯 Origens permitidas: ${Array.from(origens).join(', ')}`);

    const tokens = [];
    const tokenOwners = new Map();
    const usuariosNotificaveis = new Map();

    usuariosSnapshot.forEach(doc => {
        const data = doc.data() || {};

        const plataformaToken = String(data.plataforma_token || '').trim().toLowerCase();
        const tokenOrigem = String(data.token_origem || '').trim().toLowerCase();

        const origemPermitida =
            origens.has(plataformaToken) ||
            origens.has(tokenOrigem);

        if (!origemPermitida) {
            console.log(`🌐 Usuário ${doc.id} ignorado no filtro de APK:`, {
                email: data.email || null,
                plataforma_token: plataformaToken || null,
                token_origem: tokenOrigem || null,
            });
            return;
        }

        const userTokens = [];

        if (data.current_fcm_token && typeof data.current_fcm_token === 'string') {
            userTokens.push(data.current_fcm_token);
        }

        if (Array.isArray(data.fcm_tokens)) {
            userTokens.push(...data.fcm_tokens.filter(t => typeof t === 'string'));
        }

        const uniqueUserTokens = [...new Set(userTokens)].filter(Boolean);

        if (uniqueUserTokens.length === 0) {
            console.log(`⚠️ Usuário ${doc.id} passou no filtro, mas não tem tokens.`);
            return;
        }

        usuariosNotificaveis.set(doc.id, {
            ref: doc.ref,
            uid: doc.id,
            email: data.email || '',
            nome: data.nome_completo || data.nome || '',
            plataforma_token: plataformaToken,
            token_origem: tokenOrigem,
        });

        uniqueUserTokens.forEach(token => {
            tokens.push(token);
            tokenOwners.set(token, doc.ref);
        });

        console.log(`📲 Usuário ${doc.id} incluído no filtro APK:`, {
            email: data.email || null,
            plataforma_token: plataformaToken || null,
            token_origem: tokenOrigem || null,
            tokens: uniqueUserTokens.length,
        });
    });

    const uniqueTokens = [...new Set(tokens)].filter(Boolean);

    console.log(`📱 Tokens filtrados encontrados: ${uniqueTokens.length}`);
    console.log(`👤 Usuários notificáveis filtrados: ${usuariosNotificaveis.size}`);

    return {
        usuariosAtivos: usuariosSnapshot.size,
        usuariosNotificaveis: usuariosNotificaveis.size,
        tokens: uniqueTokens,
        tokenOwners,
        usuariosMap: usuariosNotificaveis,
    };
}

async function registrarNotificacaoUsuarios({
    usuariosMap,
    tipo,
    titulo,
    mensagem,
    data = {},
}) {
    if (!usuariosMap || usuariosMap.size === 0) {
        console.log('⚠️ Nenhum usuário para registrar notificação no sininho.');
        return 0;
    }

    const batch = db.batch();
    const notificationId = `${tipo}_${Date.now()}`;
    let total = 0;

    usuariosMap.forEach((userInfo) => {
        const ref = userInfo.ref
            .collection('notificacoes')
            .doc(notificationId);

        batch.set(ref, {
            tipo,
            titulo,
            mensagem,
            lida: false,
            criada_em: admin.firestore.FieldValue.serverTimestamp(),
            payload: data,
            origem: data.origem || 'cloud_functions',
            versao: data.versao || '',
            obrigatoria: data.obrigatoria === 'true' || data.obrigatoria === true,
        }, { merge: true });

        total++;
    });

    await batch.commit();

    console.log(`🔔 ${total} notificação(ões) registradas no sininho dos usuários.`);

    return total;
}




async function buscarUsuariosAtivosParaSininho() {
    const usuariosSnapshot = await db
        .collection('usuarios')
        .where('status_conta', '==', 'ativa')
        .get();

    const usuariosMap = new Map();

    usuariosSnapshot.forEach(doc => {
        const data = doc.data() || {};

        usuariosMap.set(doc.id, {
            ref: doc.ref,
            uid: doc.id,
            email: data.email || '',
            nome: data.nome_completo || data.nome || '',
            plataforma_token: data.plataforma_token || '',
            token_origem: data.token_origem || '',
        });
    });

    console.log(`🔔 Usuários ativos para sininho: ${usuariosMap.size}`);

    return {
        usuariosAtivos: usuariosSnapshot.size,
        usuariosMap,
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

async function enviarMulticastEmLotes({ tokens, title, body, data = {}, tokenOwners = new Map(), androidIcon = 'ic_notification' }) {
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
                        icon: androidIcon,
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
        // Roda todos os dias às 08:00 e às 18:00 no horário de Brasília.
        // Formato cron: minuto hora dia-do-mês mês dia-da-semana
        // '0 8,18 * * *' = minuto 0, nas horas 8 e 18, todos os dias.
        schedule: '0 8,18 * * *',
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

            const { usuariosAtivos, usuariosNotificaveis, tokens, tokenOwners, usuariosMap } = await buscarTokensUsuariosAtivos();

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

            const payloadAniversario = {
                tipo: 'aniversario',
                quantidade: String(birthdayStudents.length),
                data: hojeBrasilia.toFormat('yyyy-MM-dd'),
                nomes: birthdayStudents.join(', '),
                origem: 'scheduler_aniversario',
            };

            const response = await enviarMulticastEmLotes({
                tokens,
                title,
                body,
                data: payloadAniversario,
                tokenOwners,
                androidIcon: 'ic_notification_birthday',
            });

            const notificacoesRegistradas = await registrarNotificacaoUsuarios({
                usuariosMap,
                tipo: 'aniversario',
                titulo: title,
                mensagem: body,
                data: payloadAniversario,
            });

            console.log('📊 Resultado envio aniversário:', {
                usuariosAtivos,
                usuariosNotificaveis,
                tokens: tokens.length,
                notificacoesRegistradas,
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
        const { usuariosAtivos, usuariosNotificaveis, tokens, tokenOwners, usuariosMap } = await buscarTokensUsuariosAtivos();

        if (tokens.length === 0) {
            return {
                success: false,
                message: 'Nenhum token FCM encontrado em usuários ativos',
                usuariosAtivos,
                tokens: 0,
            };
        }

        const payloadTeste = {
            tipo: 'teste_aniversario',
            origem: 'callable_function',
        };

        const response = await enviarMulticastEmLotes({
            tokens,
            title: '🎉 Teste de aniversário',
            body: 'Se essa notificação chegou, o FCM está funcionando!',
            data: payloadTeste,
            tokenOwners,
            androidIcon: 'ic_notification_birthday',
        });

        const notificacoesRegistradas = await registrarNotificacaoUsuarios({
            usuariosMap,
            tipo: 'teste_aniversario',
            titulo: '🎉 Teste de aniversário',
            mensagem: 'Se essa notificação chegou, o FCM está funcionando!',
            data: payloadTeste,
        });

        return {
            success: true,
            usuariosAtivos,
            usuariosNotificaveis,
            notificacoesRegistradas,
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
        alunos: alunos.map(aluno => {
            const fotoPerfilAluno = String(
                aluno.foto_perfil_aluno ||
                aluno.foto ||
                aluno.foto_url ||
                aluno.imagem_url ||
                aluno.avatar_url ||
                ''
            ).trim();

            return {
                aluno_id: aluno.id,
                aluno_nome: aluno.nome,
                apelido: aluno.apelido || '',
                presente: aluno.presente === true,
                observacao: aluno.observacao || '',

                // Snapshot econômico para listas/histórico.
                // Evita consultar alunos/{id} só para exibir foto em chamadas novas.
                foto_perfil_aluno: fotoPerfilAluno,
                foto: fotoPerfilAluno,
                graduacao_id: aluno.graduacao_id || null,
                graduacao_nome: aluno.graduacao_nome || aluno.graduacao || aluno.corda || '',
                ultimo_dia_presente: aluno.ultimo_dia_presente ||
                    aluno.ultimoDiaPresente ||
                    aluno.ultima_presenca ||
                    aluno.ultimaPresenca ||
                    aluno.data_ultima_presenca ||
                    aluno.dataUltimaPresenca ||
                    null,
            };
        })
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
            foto_perfil_aluno: String(
                aluno.foto_perfil_aluno ||
                aluno.foto ||
                aluno.foto_url ||
                aluno.imagem_url ||
                aluno.avatar_url ||
                ''
            ).trim(),
            apelido: aluno.apelido || '',
            graduacao_id: aluno.graduacao_id || null,
            graduacao_nome: aluno.graduacao_nome || aluno.graduacao || aluno.corda || '',
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

    // =====================================================
    // 🔔 REGISTRA NO SININHO: CHAMADA REALIZADA
    // =====================================================
    // Não envia push para não incomodar a cada chamada.
    // Apenas registra na central de notificações:
    // usuarios/{uid}/notificacoes
    // =====================================================
    try {
        const horaBrasilia = dataBrasilia.toFormat('HH:mm');
        const dataBrasil = dataBrasilia.toFormat('dd/MM/yyyy');
        const professorLabel = professorNome || 'Usuário';
        const turmaLabel = turmaNome || 'Turma';
        const tipoAulaLabel = tipoAula || 'Aula';

        const tituloNotificacao = '📋 Chamada registrada';
        const mensagemNotificacao =
            `${professorLabel} registrou a chamada da turma ${turmaLabel} ` +
            `às ${horaBrasilia} de Brasília. ` +
            `Presentes: ${presentes} • Ausentes: ${ausentes} • Frequência: ${porcentagem}%.`;

        const payloadChamada = {
            tipo: 'chamada_registrada',
            chamada_id: chamadaRef.id,
            turma_id: turmaId || '',
            turma_nome: turmaNome || '',
            academia_id: academiaId || '',
            academia_nome: academiaNome || '',
            professor_id: professorId || '',
            professor_nome: professorNome || '',
            tipo_aula: tipoAulaLabel,
            total_alunos: String(alunos.length),
            presentes: String(presentes),
            ausentes: String(ausentes),
            porcentagem_frequencia: String(porcentagem),
            data_formatada: dataFormatada,
            data_brasil: dataBrasil,
            hora_brasilia: horaBrasilia,
            origem: 'processar_chamada',
        };

        const { usuariosMap } = await buscarUsuariosAtivosParaSininho();

        await registrarNotificacaoUsuarios({
            usuariosMap,
            tipo: 'chamada_registrada',
            titulo: tituloNotificacao,
            mensagem: mensagemNotificacao,
            data: payloadChamada,
        });

        await db.collection('logs_notificacoes_app').add({
            tipo: 'chamada_registrada',
            chamada_id: chamadaRef.id,
            turma_id: turmaId || '',
            turma_nome: turmaNome || '',
            academia_id: academiaId || '',
            academia_nome: academiaNome || '',
            professor_id: professorId || '',
            professor_nome: professorNome || '',
            total_alunos: alunos.length,
            presentes,
            ausentes,
            porcentagem_frequencia: porcentagem,
            data_formatada: dataFormatada,
            hora_brasilia: horaBrasilia,
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log('🔔 Notificação de chamada registrada no sininho:', {
            chamadaId: chamadaRef.id,
            turmaNome,
            professorNome,
            presentes,
            ausentes,
            porcentagem,
        });
    } catch (error) {
        console.error('⚠️ Chamada salva, mas falhou ao registrar no sininho:', error);
    }

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
        throw new HttpsError('unauthenticated', 'Usuário não autenticado');
    }

    const uid = request.auth.uid;
    const usuarioDoc = await db.collection('usuarios').doc(uid).get();
    const usuarioData = usuarioDoc.exists ? usuarioDoc.data() || {} : {};
    const pesoPermissao = Number(usuarioData.peso_permissao || 0);
    const tipoUsuario = String(usuarioData.tipo || '').trim().toLowerCase();
    const usuarioAdmin = pesoPermissao >= 90 || tipoUsuario === 'admin' || tipoUsuario === 'administrador';

    if (!usuarioAdmin) {
        const permissoesDoc = await db
            .collection('usuarios')
            .doc(uid)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get();
        const permissoes = permissoesDoc.exists ? permissoesDoc.data() || {} : {};
        const podeEditarChamada =
            permissoes.pode_editar_chamada === true ||
            permissoes.pode_editar_chamadas === true ||
            permissoes.podeEditarChamada === true;
        const podeExcluirChamada =
            permissoes.pode_excluir_chamada === true ||
            permissoes.pode_excluir_chamadas === true ||
            permissoes.podeExcluirChamada === true;

        if (!podeEditarChamada || !podeExcluirChamada) {
            throw new HttpsError('permission-denied', 'Você não tem permissão para excluir chamadas.');
        }
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

    try {
        await db.collection('logs_chamadas_excluidas').add({
            chamada_id: chamadaId,
            turma_id: turmaId,
            turma_nome: chamadaData.turma_nome || '',
            academia_id: chamadaData.academia_id || '',
            academia_nome: chamadaData.academia_nome || '',
            data_formatada: dataFormatada || '',
            presentes: Number(chamadaData.presentes || alunos.filter(aluno => aluno.presente === true).length || 0),
            ausentes: Number(chamadaData.ausentes || alunos.filter(aluno => aluno.presente !== true).length || 0),
            total_alunos: Number(chamadaData.total_alunos || alunos.length || 0),
            excluido_por_uid: uid,
            excluido_por_nome: usuarioData.nome_completo || usuarioData.nome || request.auth.token?.name || '',
            excluido_por_email: usuarioData.email || request.auth.token?.email || '',
            excluido_em: admin.firestore.FieldValue.serverTimestamp(),
            origem: 'listas_chamada_screen',
            resumo: 'Chamada excluída/desfeita com recálculo de contadores'
        });
    } catch (logError) {
        console.warn('Falha ao registrar auditoria de chamada excluída:', logError);
    }

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

function limparIpAcesso(valor) {
    if (!valor) return '';

    const texto = String(valor).trim();
    const primeiro = texto.split(',')[0].trim();

    return primeiro.replace(/^::ffff:/, '');
}

function obterIpRequisicao(request, ipFallback) {
    const raw = request.rawRequest;

    const headers = [
        raw?.headers?.['x-forwarded-for'],
        raw?.headers?.['x-real-ip'],
        raw?.headers?.['fastly-client-ip'],
        raw?.headers?.['cf-connecting-ip'],
    ];

    for (const item of headers) {
        const ip = limparIpAcesso(item);
        if (ip) return ip;
    }

    const ipSocket = limparIpAcesso(raw?.ip || raw?.socket?.remoteAddress);
    if (ipSocket) return ipSocket;

    return limparIpAcesso(ipFallback);
}

function valorSeguroLocalizacao(valor, fallback = 'Desconhecido') {
    const texto = String(valor || '').trim();
    return texto || fallback;
}

function limparMapaDispositivo(valor) {
    if (!valor || typeof valor !== 'object' || Array.isArray(valor)) {
        return {};
    }

    const permitido = [
        'tipo_dispositivo',
        'tipo_plataforma',
        'plataforma_flutter',
        'is_web',
        'largura_tela',
        'altura_tela',
        'menor_lado',
        'maior_lado',
        'pixel_ratio',
        'orientacao',
        'tema_sistema',
        'text_scale',
        'padding_top',
        'padding_bottom',
        'view_insets_bottom',
        'idioma',
        'timezone',
        'timezone_offset_minutos',
        'user_agent_cliente',
        'navegador_nome',
        'navegador_versao',
        'sistema_operacional_aproximado',
        'celular_marca_aproximada',
        'celular_modelo_aproximado',
        'user_agent_data',
        'mobile_user_agent_data',
        'brands_user_agent_data',
        'plataforma_browser',
        'tela',
        'origem',
        'coletado_em',
    ];

    const saida = {};

    for (const chave of permitido) {
        if (valor[chave] !== undefined && valor[chave] !== null) {
            saida[chave] = valor[chave];
        }
    }

    return saida;
}

function montarAssinaturaDispositivoAreaAluno({ dispositivo = {}, userAgent = '', ip = '' }) {
    const d = limparMapaDispositivo(dispositivo);

    const partes = [
        d.tipo_dispositivo || '',
        d.tipo_plataforma || '',
        d.plataforma_flutter || '',
        d.is_web === true ? 'web' : 'nao_web',
        d.largura_tela || '',
        d.altura_tela || '',
        d.pixel_ratio || '',
        d.sistema_operacional_aproximado || '',
        d.navegador_nome || '',
        d.celular_marca_aproximada || '',
        d.celular_modelo_aproximado || '',
        userAgent || '',
        ip || '',
    ];

    return partes
        .join('|')
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
}

async function buscarAlunosMesmoDispositivoAreaAluno({
    assinaturaDispositivo,
    alunoIdAtual = '',
}) {
    const resultado = {
        possivelTrocaAluno: false,
        alunosAnteriores: [],
        totalAcessosEncontrados: 0,
    };

    if (!assinaturaDispositivo) return resultado;

    try {
        const snapshot = await db
            .collection('area_aluno_logs_acesso')
            .where('assinatura_dispositivo', '==', assinaturaDispositivo)
            .orderBy('acesso_em', 'desc')
            .limit(20)
            .get();

        resultado.totalAcessosEncontrados = snapshot.size;

        const alunos = new Map();

        snapshot.forEach(doc => {
            const data = doc.data() || {};
            const alunoId = data.aluno_id || '';

            if (!alunoId || alunoId === alunoIdAtual) return;

            alunos.set(alunoId, {
                aluno_id: alunoId,
                aluno_nome: data.aluno_nome || '',
                turma_id: data.turma_id || '',
                turma: data.turma || '',
                acesso_em: data.acesso_em || null,
            });
        });

        resultado.alunosAnteriores = Array.from(alunos.values());
        resultado.possivelTrocaAluno = resultado.alunosAnteriores.length > 0;

        return resultado;
    } catch (e) {
        console.error('⚠️ Erro ao buscar alunos no mesmo dispositivo:', e);
        return resultado;
    }
}


// ============================================
// FUNÇÃO 5: REGISTRAR LOCALIZAÇÃO DE ACESSO
// ============================================
exports.registrarLocalizacaoAcesso = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        const payload = request.data || {};
        const ipDetectado = obterIpRequisicao(request, payload.ip);
        const origem = String(payload.origem || 'landing_page').trim() || 'landing_page';
        const dispositivo = limparMapaDispositivo(payload.dispositivo || {});
        const userAgent = request.rawRequest?.headers?.['user-agent'] || '';
        const ip = obterIpRequisicao(request, payload.ip || '');
        const assinaturaDispositivo = montarAssinaturaDispositivoAreaAluno({
            dispositivo,
            userAgent,
            ip,
        });

        if (!ipDetectado) {
            return {
                success: false,
                error: 'IP não identificado',
            };
        }

        try {
            const response = await axios.get(
                `http://ip-api.com/json/${encodeURIComponent(ipDetectado)}?fields=status,message,country,regionName,city,lat,lon,isp,timezone,query`
            );

            const location = response.data || {};

            if (location.status !== 'success') {
                console.log('⚠️ Localização não encontrada:', {
                    ip: ipDetectado,
                    message: location.message || null,
                });

                const docRef = await db.collection('estatisticas_acessos').add({
                    ip: ipDetectado,
                    cidade: 'Desconhecida',
                    estado: 'Desconhecido',
                    pais: 'Desconhecido',
                    latitude: null,
                    longitude: null,
                    data_acesso: admin.firestore.FieldValue.serverTimestamp(),
                    origem,
                    isp: 'Desconhecido',
                    timezone: '',
                    user_agent: userAgent,
                    dispositivo,
                    eventos: [],
                    total_eventos: 0,
                    ultima_atividade: admin.firestore.FieldValue.serverTimestamp(),
                    localizacao_status: 'falha',
                    localizacao_erro: location.message || 'Localização não encontrada',
                });

                await db.collection('estatisticas').doc('contadores_agregados').set({
                    total_visitas: admin.firestore.FieldValue.increment(1),
                    ultima_atualizacao: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });

                return {
                    success: true,
                    docId: docRef.id,
                    ip: ipDetectado,
                    cidade: 'Desconhecida',
                    estado: 'Desconhecido',
                    pais: 'Desconhecido',
                    latitude: null,
                    longitude: null,
                    isp: 'Desconhecido',
                    timezone: '',
                    localizacaoStatus: 'falha',
                };
            }

            const cidade = valorSeguroLocalizacao(location.city, 'Desconhecida');
            const estado = valorSeguroLocalizacao(location.regionName, 'Desconhecido');
            const pais = valorSeguroLocalizacao(location.country, 'Desconhecido');
            const isp = valorSeguroLocalizacao(location.isp, 'Desconhecido');
            const timezone = String(location.timezone || '').trim();

            const docRef = await db.collection('estatisticas_acessos').add({
                ip: ipDetectado,
                cidade,
                estado,
                pais,
                latitude: location.lat ?? null,
                longitude: location.lon ?? null,
                data_acesso: admin.firestore.FieldValue.serverTimestamp(),
                origem,
                isp,
                timezone,
                user_agent: userAgent,
                dispositivo,
                eventos: [],
                total_eventos: 0,
                ultima_atividade: admin.firestore.FieldValue.serverTimestamp(),
                localizacao_status: 'sucesso',
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
                ultima_atualizacao: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            console.log(`📍 Acesso registrado com ID: ${docRef.id} - ${cidade}/${estado}`, {
                origem,
                dispositivo,
            });

            return {
                success: true,
                docId: docRef.id,
                ip: ipDetectado,
                cidade,
                estado,
                pais,
                latitude: location.lat ?? null,
                longitude: location.lon ?? null,
                isp,
                timezone,
                localizacaoStatus: 'sucesso',
            };
        } catch (error) {
            console.error('❌ Erro ao registrar localização:', error);

            return {
                success: false,
                error: error.message,
            };
        }
    }
);

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
    const cfg = normalizarConfigAreaAluno(config);
    const dados = {
        aluno_id: alunoId,
        nome: alunoData.nome || '',
        apelido: alunoData.apelido || '',
        status_atividade: alunoData.status_atividade || '',
    };

    if (cfg.mostrar_foto !== false) {
        dados.foto_perfil_aluno = alunoData.foto_perfil_aluno || '';
    }

    if (cfg.mostrar_dados_basicos !== false && cfg.modo_dados_basicos !== 'oculto') {
        if (cfg.modo_dados_basicos === 'completo') {
            dados.sexo = alunoData.sexo || '';
            dados.data_nascimento = timestampToDataBR(alunoData.data_nascimento);
        }

        dados.cidade = alunoData.cidade || '';

        if (cfg.modo_endereco === 'completo') {
            dados.endereco = alunoData.endereco || '';
        } else if (cfg.modo_endereco === 'cidade_bairro') {
            dados.endereco = enderecoLimitadoAreaAluno(alunoData);
        }

        if (cfg.modo_responsavel === 'completo') {
            dados.nome_responsavel = alunoData.nome_responsavel || '';
            dados.contato_responsavel = cfg.modo_telefone === 'completo'
                ? (alunoData.contato_responsavel || '')
                : mascararTelefoneAreaAluno(alunoData.contato_responsavel || '');
        } else if (cfg.modo_responsavel === 'nome') {
            dados.nome_responsavel = alunoData.nome_responsavel || '';
        }

        if (cfg.modo_telefone === 'completo') {
            dados.contato_aluno = alunoData.contato_aluno || '';
        } else if (cfg.modo_telefone === 'mascarado') {
            dados.contato_aluno = mascararTelefoneAreaAluno(alunoData.contato_aluno || '');
        }

        // Mantém também os finais por compatibilidade/segurança visual se quiser usar depois.
        dados.contato_aluno_final = ultimos4AreaAluno(alunoData.contato_aluno || '');
        dados.contato_responsavel_final = ultimos4AreaAluno(alunoData.contato_responsavel || '');
    }

    if (cfg.mostrar_academia_turma !== false) {
        dados.academia = alunoData.academia || '';
        dados.academia_id = alunoData.academia_id || '';
        dados.turma = alunoData.turma || '';
        dados.turma_id = alunoData.turma_id || '';
        dados.modalidade = alunoData.modalidade || '';
    }

    if (cfg.mostrar_graduacao_atual !== false) {
        dados.graduacao_atual = alunoData.graduacao_atual || alunoData.graduacao_nome || '';
        dados.graduacao_nome = alunoData.graduacao_nome || alunoData.graduacao_atual || '';
        dados.graduacao_cor1 = alunoData.graduacao_cor1 || '';
        dados.graduacao_cor2 = alunoData.graduacao_cor2 || '';
        dados.graduacao_ponta1 = alunoData.graduacao_ponta1 || '';
        dados.graduacao_ponta2 = alunoData.graduacao_ponta2 || '';
        dados.nivel_graduacao = alunoData.nivel_graduacao || 0;
        dados.data_graduacao_atual = timestampToDataBR(alunoData.data_graduacao_atual);
    }

    if (cfg.mostrar_presencas !== false) {
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
    dispositivo = {},
    userAgent = '',
    ip = '',
    assinaturaDispositivo = '',
}) {
    try {
        const dispositivoLimpo = limparMapaDispositivo(dispositivo);
        const assinatura = assinaturaDispositivo || montarAssinaturaDispositivoAreaAluno({
            dispositivo: dispositivoLimpo,
            userAgent,
            ip,
        });

        await db.collection('area_aluno_logs_erro').add({
            data_nascimento_usada: dataNascimento || '',
            iniciais_usadas: iniciais || '',
            telefone_final_usado: telefoneFinal || '',
            motivo,
            detalhes,
            dispositivo: dispositivoLimpo,
            assinatura_dispositivo: assinatura,
            user_agent: userAgent || '',
            ip: ip || '',
            origem: 'site_area_aluno',
            sucesso: false,
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
    dispositivo = {},
    userAgent = '',
    ip = '',
    assinaturaDispositivo = '',
}) {
    try {
        const dispositivoLimpo = limparMapaDispositivo(dispositivo);
        const assinatura = assinaturaDispositivo || montarAssinaturaDispositivoAreaAluno({
            dispositivo: dispositivoLimpo,
            userAgent,
            ip,
        });

        const leituraMesmoDispositivo = await buscarAlunosMesmoDispositivoAreaAluno({
            assinaturaDispositivo: assinatura,
            alunoIdAtual: alunoId,
        });

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
            dispositivo: dispositivoLimpo,
            assinatura_dispositivo: assinatura,
            user_agent: userAgent || '',
            ip: ip || '',
            possivel_troca_aluno: leituraMesmoDispositivo.possivelTrocaAluno,
            alunos_anteriores_mesmo_dispositivo: leituraMesmoDispositivo.alunosAnteriores,
            total_acessos_mesmo_dispositivo: leituraMesmoDispositivo.totalAcessosEncontrados,
            acesso_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (leituraMesmoDispositivo.possivelTrocaAluno) {
            await db.collection('area_aluno_alertas_seguranca').add({
                tipo: 'mesmo_dispositivo_multiplos_alunos',
                aluno_id_atual: alunoId,
                aluno_nome_atual: alunoData.nome || '',
                alunos_anteriores_mesmo_dispositivo: leituraMesmoDispositivo.alunosAnteriores,
                assinatura_dispositivo: assinatura,
                dispositivo: dispositivoLimpo,
                user_agent: userAgent || '',
                ip: ip || '',
                origem: 'site_area_aluno',
                criado_em: admin.firestore.FieldValue.serverTimestamp(),
                resolvido: false,
            });
        }

        return leituraMesmoDispositivo;
    } catch (e) {
        console.error('⚠️ Erro ao registrar log de acesso da área do aluno:', e);
        return {
            possivelTrocaAluno: false,
            alunosAnteriores: [],
            totalAcessosEncontrados: 0,
        };
    }
}

function boolConfigAreaAluno(config, chave, padrao = true) {
    const valor = config?.[chave];
    return typeof valor === 'boolean' ? valor : padrao;
}

function textoConfigAreaAluno(config, chave, padrao) {
    const valor = String(config?.[chave] || '').trim();
    return valor || padrao;
}

function normalizarConfigAreaAluno(config = {}) {
    const mostrarGraduacaoLegado = boolConfigAreaAluno(config, 'mostrar_graduacao', true);
    const visivelSite = boolConfigAreaAluno(config, 'visivel_site', false);
    const ativo = boolConfigAreaAluno(config, 'ativo', visivelSite);

    return {
        ativo,
        visivel_site: visivelSite,
        aceitar_apenas_ativos: boolConfigAreaAluno(config, 'aceitar_apenas_ativos', true),
        exigir_telefone_confirmacao: boolConfigAreaAluno(config, 'exigir_telefone_confirmacao', true),
        mostrar_dashboard: boolConfigAreaAluno(config, 'mostrar_dashboard', true),
        mostrar_foto: boolConfigAreaAluno(config, 'mostrar_foto', true),
        mostrar_dados_basicos: boolConfigAreaAluno(config, 'mostrar_dados_basicos', true),
        mostrar_academia_turma: boolConfigAreaAluno(config, 'mostrar_academia_turma', true),
        mostrar_graduacao: mostrarGraduacaoLegado,
        mostrar_graduacao_atual: boolConfigAreaAluno(config, 'mostrar_graduacao_atual', mostrarGraduacaoLegado),
        mostrar_frequencia: boolConfigAreaAluno(config, 'mostrar_frequencia', true),
        mostrar_eventos: boolConfigAreaAluno(config, 'mostrar_eventos', true),
        mostrar_certificados: boolConfigAreaAluno(config, 'mostrar_certificados', true),
        mostrar_financeiro_eventos: boolConfigAreaAluno(config, 'mostrar_financeiro_eventos', true),
        mostrar_solicitacao_alteracao: boolConfigAreaAluno(config, 'mostrar_solicitacao_alteracao', true),
        mostrar_graduacao_evento: boolConfigAreaAluno(config, 'mostrar_graduacao_evento', true),
        mostrar_camisa_evento: boolConfigAreaAluno(config, 'mostrar_camisa_evento', true),
        mostrar_presenca_evento: boolConfigAreaAluno(config, 'mostrar_presenca_evento', true),
        mostrar_presencas: boolConfigAreaAluno(config, 'mostrar_presencas', false),
        mostrar_historico_chamadas: boolConfigAreaAluno(config, 'mostrar_historico_chamadas', false),
        mostrar_aviso_auditoria: boolConfigAreaAluno(config, 'mostrar_aviso_auditoria', false),
        google_login_ativo: boolConfigAreaAluno(config, 'google_login_ativo', false),
        google_vinculacao_modo: textoConfigAreaAluno(config, 'google_vinculacao_modo', 'desativada'),
        permitir_acesso_basico_sem_google: boolConfigAreaAluno(config, 'permitir_acesso_basico_sem_google', true),
        permitir_vincular_google_no_primeiro_acesso: boolConfigAreaAluno(config, 'permitir_vincular_google_no_primeiro_acesso', true),
        permitir_trocar_google_sem_admin: boolConfigAreaAluno(config, 'permitir_trocar_google_sem_admin', false),
        sem_google_mostrar_dashboard: boolConfigAreaAluno(config, 'sem_google_mostrar_dashboard', boolConfigAreaAluno(config, 'mostrar_dashboard', true)),
        sem_google_mostrar_dados_basicos: boolConfigAreaAluno(config, 'sem_google_mostrar_dados_basicos', boolConfigAreaAluno(config, 'mostrar_dados_basicos', true)),
        sem_google_modo_dados_basicos: textoConfigAreaAluno(config, 'sem_google_modo_dados_basicos', textoConfigAreaAluno(config, 'modo_dados_basicos', 'limitado')),
        sem_google_mostrar_frequencia: boolConfigAreaAluno(config, 'sem_google_mostrar_frequencia', boolConfigAreaAluno(config, 'mostrar_frequencia', true)),
        sem_google_mostrar_eventos: boolConfigAreaAluno(config, 'sem_google_mostrar_eventos', boolConfigAreaAluno(config, 'mostrar_eventos', true)),
        sem_google_mostrar_certificados: boolConfigAreaAluno(config, 'sem_google_mostrar_certificados', boolConfigAreaAluno(config, 'mostrar_certificados', true)),
        sem_google_mostrar_financeiro_eventos: boolConfigAreaAluno(config, 'sem_google_mostrar_financeiro_eventos', boolConfigAreaAluno(config, 'mostrar_financeiro_eventos', true)),
        sem_google_modo_financeiro: textoConfigAreaAluno(config, 'sem_google_modo_financeiro', textoConfigAreaAluno(config, 'modo_financeiro', 'completo')),
        sem_google_mostrar_graduacao_evento: boolConfigAreaAluno(config, 'sem_google_mostrar_graduacao_evento', boolConfigAreaAluno(config, 'mostrar_graduacao_evento', true)),
        sem_google_modo_graduacao_evento: textoConfigAreaAluno(config, 'sem_google_modo_graduacao_evento', textoConfigAreaAluno(config, 'modo_graduacao_evento', 'completo')),
        sem_google_mostrar_camisa_evento: boolConfigAreaAluno(config, 'sem_google_mostrar_camisa_evento', boolConfigAreaAluno(config, 'mostrar_camisa_evento', true)),
        sem_google_mostrar_presenca_evento: boolConfigAreaAluno(config, 'sem_google_mostrar_presenca_evento', boolConfigAreaAluno(config, 'mostrar_presenca_evento', true)),
        sem_google_mostrar_solicitacao_alteracao: boolConfigAreaAluno(config, 'sem_google_mostrar_solicitacao_alteracao', boolConfigAreaAluno(config, 'mostrar_solicitacao_alteracao', true)),
        com_google_mostrar_dashboard: boolConfigAreaAluno(config, 'com_google_mostrar_dashboard', boolConfigAreaAluno(config, 'mostrar_dashboard', true)),
        com_google_mostrar_dados_basicos: boolConfigAreaAluno(config, 'com_google_mostrar_dados_basicos', boolConfigAreaAluno(config, 'mostrar_dados_basicos', true)),
        com_google_modo_dados_basicos: textoConfigAreaAluno(config, 'com_google_modo_dados_basicos', textoConfigAreaAluno(config, 'modo_dados_basicos', 'limitado')),
        com_google_mostrar_frequencia: boolConfigAreaAluno(config, 'com_google_mostrar_frequencia', boolConfigAreaAluno(config, 'mostrar_frequencia', true)),
        com_google_mostrar_eventos: boolConfigAreaAluno(config, 'com_google_mostrar_eventos', boolConfigAreaAluno(config, 'mostrar_eventos', true)),
        com_google_mostrar_certificados: boolConfigAreaAluno(config, 'com_google_mostrar_certificados', boolConfigAreaAluno(config, 'mostrar_certificados', true)),
        com_google_mostrar_financeiro_eventos: boolConfigAreaAluno(config, 'com_google_mostrar_financeiro_eventos', boolConfigAreaAluno(config, 'mostrar_financeiro_eventos', true)),
        com_google_modo_financeiro: textoConfigAreaAluno(config, 'com_google_modo_financeiro', textoConfigAreaAluno(config, 'modo_financeiro', 'completo')),
        com_google_mostrar_graduacao_evento: boolConfigAreaAluno(config, 'com_google_mostrar_graduacao_evento', boolConfigAreaAluno(config, 'mostrar_graduacao_evento', true)),
        com_google_modo_graduacao_evento: textoConfigAreaAluno(config, 'com_google_modo_graduacao_evento', textoConfigAreaAluno(config, 'modo_graduacao_evento', 'completo')),
        com_google_mostrar_camisa_evento: boolConfigAreaAluno(config, 'com_google_mostrar_camisa_evento', boolConfigAreaAluno(config, 'mostrar_camisa_evento', true)),
        com_google_mostrar_presenca_evento: boolConfigAreaAluno(config, 'com_google_mostrar_presenca_evento', boolConfigAreaAluno(config, 'mostrar_presenca_evento', true)),
        com_google_mostrar_solicitacao_alteracao: boolConfigAreaAluno(config, 'com_google_mostrar_solicitacao_alteracao', boolConfigAreaAluno(config, 'mostrar_solicitacao_alteracao', true)),
        modo_dados_basicos: textoConfigAreaAluno(config, 'modo_dados_basicos', 'limitado'),
        modo_telefone: textoConfigAreaAluno(config, 'modo_telefone', 'mascarado'),
        modo_endereco: textoConfigAreaAluno(config, 'modo_endereco', 'cidade_bairro'),
        modo_responsavel: textoConfigAreaAluno(config, 'modo_responsavel', 'nome'),
        modo_financeiro: textoConfigAreaAluno(config, 'modo_financeiro', 'completo'),
        modo_graduacao_evento: textoConfigAreaAluno(config, 'modo_graduacao_evento', 'completo'),
        mensagem_topo: textoConfigAreaAluno(config, 'mensagem_topo', 'Bem-vindo(a) à Área do Aluno'),
        mensagem_area_desativada: textoConfigAreaAluno(
            config,
            'mensagem_area_desativada',
            'A Área do Aluno não está disponível no momento.'
        ),
        mensagem_dados_ocultos: textoConfigAreaAluno(
            config,
            'mensagem_dados_ocultos',
            'Algumas informações foram ocultadas pela coordenação.'
        ),
        aviso_auditoria_acesso: textoConfigAreaAluno(
            config,
            'aviso_auditoria_acesso',
            ''
        ),
    };
}

function configEfetivaAreaAluno(config, modoAcesso = 'basico', alunoData = {}) {
    const base = normalizarConfigAreaAluno(config);
    const prefixo = modoAcesso === 'google' ? 'com_google' : 'sem_google';
    const googleVinculado = alunoData.areaAlunoGoogleVinculado === true && !!alunoData.areaAlunoGoogleUid;
    const exigirGoogle = base.google_login_ativo === true && (
        base.google_vinculacao_modo === 'obrigatoria_para_completo' ||
        (base.google_vinculacao_modo === 'obrigatoria_apos_vincular' && googleVinculado)
    );

    const efetiva = { ...base };
    const campos = [
        'mostrar_dashboard',
        'mostrar_dados_basicos',
        'modo_dados_basicos',
        'mostrar_frequencia',
        'mostrar_eventos',
        'mostrar_certificados',
        'mostrar_financeiro_eventos',
        'modo_financeiro',
        'mostrar_graduacao_evento',
        'modo_graduacao_evento',
        'mostrar_camisa_evento',
        'mostrar_presenca_evento',
        'mostrar_solicitacao_alteracao',
    ];

    for (const campo of campos) {
        const chave = `${prefixo}_${campo}`;
        if (Object.prototype.hasOwnProperty.call(base, chave)) {
            efetiva[campo] = base[chave];
        }
    }

    if (modoAcesso !== 'google' && exigirGoogle && base.permitir_acesso_basico_sem_google !== true) {
        efetiva.mostrar_dashboard = true;
        efetiva.mostrar_foto = false;
        efetiva.mostrar_dados_basicos = false;
        efetiva.mostrar_academia_turma = false;
        efetiva.mostrar_graduacao_atual = false;
        efetiva.mostrar_frequencia = false;
        efetiva.mostrar_eventos = false;
        efetiva.mostrar_certificados = false;
        efetiva.mostrar_financeiro_eventos = false;
        efetiva.mostrar_graduacao_evento = false;
        efetiva.mostrar_camisa_evento = false;
        efetiva.mostrar_presenca_evento = false;
        efetiva.mostrar_solicitacao_alteracao = false;
        efetiva.mostrar_presencas = false;
        efetiva.mostrar_historico_chamadas = false;
    }

    efetiva.modo_acesso = modoAcesso;
    efetiva.google_vinculado = googleVinculado;
    efetiva.google_email_mascarado = mascararEmailAreaAluno(alunoData.areaAlunoGoogleEmail || '');
    efetiva.exige_google_para_completo = modoAcesso !== 'google' && exigirGoogle;
    efetiva.mostrar_aviso_auditoria = false;
    efetiva.aviso_auditoria_acesso = '';

    return efetiva;
}

function mascararEmailAreaAluno(email) {
    const clean = String(email || '').trim();
    const partes = clean.split('@');
    if (partes.length !== 2) return '';
    const nome = partes[0];
    const dominio = partes[1];
    const prefixo = nome.length <= 2 ? nome[0] || '*' : nome.slice(0, 2);
    return `${prefixo}${'*'.repeat(Math.max(2, nome.length - prefixo.length))}@${dominio}`;
}

function mascararTelefoneAreaAluno(valor) {
    const limpo = limparNumeroAreaAluno(valor);
    if (!limpo) return '';
    if (limpo.length <= 4) return `****${limpo}`;
    return `${'*'.repeat(Math.max(0, limpo.length - 4))}${limpo.slice(-4)}`;
}

function enderecoLimitadoAreaAluno(alunoData) {
    const bairro = alunoData.bairro || alunoData.endereco_bairro || '';
    const cidade = alunoData.cidade || '';
    return [bairro, cidade].filter(Boolean).join(' - ');
}

function millisTimestampAreaAluno(valor) {
    if (!valor) return 0;
    if (typeof valor.toMillis === 'function') return valor.toMillis();
    if (valor instanceof Date) return valor.getTime();
    return 0;
}

function chaveRateLimitAreaAluno({ ip = '', assinaturaDispositivo = '', origem = 'area_aluno_login' }) {
    const base = [
        origem || 'area_aluno_login',
        ip || 'ip_desconhecido',
        assinaturaDispositivo || 'assinatura_desconhecida',
    ].join('|');

    return crypto.createHash('sha256').update(base).digest('hex');
}

function rateLimitRefAreaAluno({ ip = '', assinaturaDispositivo = '', origem = 'area_aluno_login' }) {
    return db.collection('area_aluno_rate_limit').doc(
        chaveRateLimitAreaAluno({ ip, assinaturaDispositivo, origem })
    );
}

async function verificarRateLimitAreaAluno({ ip = '', assinaturaDispositivo = '', origem = 'area_aluno_login' }) {
    const ref = rateLimitRefAreaAluno({ ip, assinaturaDispositivo, origem });
    const doc = await ref.get();

    if (!doc.exists) {
        return { bloqueado: false, ref };
    }

    const data = doc.data() || {};
    const bloqueadoAteMillis = millisTimestampAreaAluno(data.bloqueado_ate);

    if (bloqueadoAteMillis > Date.now()) {
        return {
            bloqueado: true,
            ref,
            bloqueadoAte: data.bloqueado_ate,
        };
    }

    return { bloqueado: false, ref };
}

async function registrarRateLimitErroAreaAluno({
    ip = '',
    assinaturaDispositivo = '',
    origem = 'area_aluno_login',
    motivo = '',
}) {
    const ref = rateLimitRefAreaAluno({ ip, assinaturaDispositivo, origem });
    const agora = Date.now();
    const janela10Ms = 10 * 60 * 1000;
    const janela30Ms = 30 * 60 * 1000;

    await db.runTransaction(async tx => {
        const snap = await tx.get(ref);
        const atual = snap.exists ? (snap.data() || {}) : {};
        const inicio10 = millisTimestampAreaAluno(atual.janela_10_inicio);
        const inicio30 = millisTimestampAreaAluno(atual.janela_30_inicio);
        const dentro10 = inicio10 > 0 && agora - inicio10 <= janela10Ms;
        const dentro30 = inicio30 > 0 && agora - inicio30 <= janela30Ms;
        const erros10 = (dentro10 ? (atual.erros_10_min || 0) : 0) + 1;
        const erros30 = (dentro30 ? (atual.erros_30_min || 0) : 0) + 1;

        let bloqueadoAte = atual.bloqueado_ate || null;

        if (erros30 >= 10) {
            bloqueadoAte = admin.firestore.Timestamp.fromMillis(agora + janela30Ms);
        } else if (erros10 >= 5) {
            bloqueadoAte = admin.firestore.Timestamp.fromMillis(agora + janela10Ms);
        }

        tx.set(ref, {
            ip,
            assinatura_dispositivo: assinaturaDispositivo || '',
            origem,
            total_tentativas: admin.firestore.FieldValue.increment(1),
            total_erros: admin.firestore.FieldValue.increment(1),
            janela_inicio: admin.firestore.Timestamp.fromMillis(dentro30 ? inicio30 : agora),
            janela_10_inicio: admin.firestore.Timestamp.fromMillis(dentro10 ? inicio10 : agora),
            janela_30_inicio: admin.firestore.Timestamp.fromMillis(dentro30 ? inicio30 : agora),
            erros_10_min: erros10,
            erros_30_min: erros30,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            bloqueado_ate: bloqueadoAte,
            ultimo_motivo: motivo,
        }, { merge: true });
    });
}

async function limparRateLimitAreaAluno({ ip = '', assinaturaDispositivo = '', origem = 'area_aluno_login' }) {
    const ref = rateLimitRefAreaAluno({ ip, assinaturaDispositivo, origem });
    await ref.set({
        total_tentativas: 0,
        total_erros: 0,
        erros_10_min: 0,
        erros_30_min: 0,
        bloqueado_ate: null,
        ultimo_motivo: 'login_sucesso',
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}

async function registrarErroAcessoAreaAlunoComRateLimit(params) {
    await registrarLogErroAreaAluno(params);
    await registrarRateLimitErroAreaAluno({
        ip: params.ip || '',
        assinaturaDispositivo: params.assinaturaDispositivo || '',
        motivo: params.motivo || '',
    });
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
        const dispositivo = limparMapaDispositivo(payload.dispositivo || {});
        const userAgent = request.rawRequest?.headers?.['user-agent'] || '';
        const ip = obterIpRequisicao(request, payload.ip || '');
        const assinaturaDispositivo = montarAssinaturaDispositivoAreaAluno({
            dispositivo,
            userAgent,
            ip,
        });

        try {
            const rateLimit = await verificarRateLimitAreaAluno({
                ip,
                assinaturaDispositivo,
            });

            if (rateLimit.bloqueado) {
                await registrarLogErroAreaAluno({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'rate_limit',
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
                });

                return {
                    success: false,
                    code: 'rate_limit',
                    message: 'Muitas tentativas. Aguarde alguns minutos e tente novamente.',
                };
            }

            const configDoc = await db
                .collection('configuracoes_site')
                .doc('area_aluno')
                .get();

            const config = normalizarConfigAreaAluno(configDoc.exists ? (configDoc.data() || {}) : {});

            const visivelSite = config.ativo === true || config.visivel_site === true;
            const aceitarApenasAtivos = config.aceitar_apenas_ativos !== false;
            const exigirTelefone = config.exigir_telefone_confirmacao !== false;

            if (!visivelSite) {
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'area_aluno_desativada',
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
                });

                return {
                    success: false,
                    code: 'area_desativada',
                    message: 'A Área do Aluno não está disponível no momento.',
                };
            }

            if (!dataNascimentoInformada || !iniciaisInformadas) {
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'campos_obrigatorios_ausentes',
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
                });

                return {
                    success: false,
                    code: 'dados_invalidos',
                    message: 'Confira os dados informados e tente novamente.',
                };
            }

            if (exigirTelefone && telefoneFinalInformado.length !== 4) {
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'telefone_final_invalido',
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
                });

                return {
                    success: false,
                    code: 'dados_invalidos',
                    message: 'Confira os dados informados e tente novamente.',
                };
            }

            const dataNascimento = parseDataNascimentoAreaAluno(dataNascimentoInformada);

            if (!dataNascimento) {
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'data_nascimento_invalida',
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
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
                dispositivo,
                ip: ip ? 'registrado' : '',
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
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'nenhum_aluno_encontrado',
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
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
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'iniciais_nao_conferem',
                    detalhes: {
                        encontrados_mesma_data: snapshot.size,
                    },
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
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
                    await registrarErroAcessoAreaAlunoComRateLimit({
                        dataNascimento: dataNascimentoInformada,
                        iniciais: iniciaisInformadas,
                        telefoneFinal: telefoneFinalInformado,
                        motivo: 'telefone_final_nao_confere',
                        dispositivo,
                        userAgent,
                        ip,
                        assinaturaDispositivo,
                    });

                    return {
                        success: false,
                        code: 'nao_encontrado',
                        message: 'Confira os dados informados e tente novamente.',
                    };
                }
            }

            if (candidatos.length > 1) {
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'multiplos_alunos_encontrados',
                    detalhes: {
                        quantidade: candidatos.length,
                    },
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
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
                await registrarErroAcessoAreaAlunoComRateLimit({
                    dataNascimento: dataNascimentoInformada,
                    iniciais: iniciaisInformadas,
                    telefoneFinal: telefoneFinalInformado,
                    motivo: 'aluno_inativo',
                    detalhes: {
                        aluno_id: candidato.id,
                        status_atividade: alunoData.status_atividade || '',
                    },
                    dispositivo,
                    userAgent,
                    ip,
                    assinaturaDispositivo,
                });

                return {
                    success: false,
                    code: 'aluno_inativo',
                    message: 'Acesso não liberado para este cadastro. Procure a coordenação.',
                };
            }

            const configEfetiva = configEfetivaAreaAluno(config, 'basico', alunoData);
            const leituraMesmoDispositivo = await registrarLogAcessoAreaAluno({
                alunoId: candidato.id,
                alunoData,
                iniciais: iniciaisInformadas,
                dispositivo,
                userAgent,
                ip,
                assinaturaDispositivo,
            });

            const dadosAluno = await montarDadosAlunoLiberados(candidato.id, alunoData, configEfetiva);
            await limparRateLimitAreaAluno({
                ip,
                assinaturaDispositivo,
            });

            return {
                success: true,
                code: 'acesso_liberado',
                message: 'Acesso liberado.',
                aluno: dadosAluno,
                modo_acesso: 'basico',
                google_vinculado: configEfetiva.google_vinculado,
                google_email_mascarado: configEfetiva.google_email_mascarado,
                exige_google_para_completo: configEfetiva.exige_google_para_completo,
                auditoria: {
                    possivel_troca_aluno: leituraMesmoDispositivo.possivelTrocaAluno,
                    alunos_anteriores_mesmo_dispositivo: leituraMesmoDispositivo.alunosAnteriores,
                    total_acessos_mesmo_dispositivo: leituraMesmoDispositivo.totalAcessosEncontrados,
                    assinatura_dispositivo: assinaturaDispositivo,
                },
                config: configEfetiva,
            };
        } catch (error) {
            console.error('❌ Erro em validarAcessoAreaAluno:', error);

            await registrarErroAcessoAreaAlunoComRateLimit({
                dataNascimento: dataNascimentoInformada,
                iniciais: iniciaisInformadas,
                telefoneFinal: telefoneFinalInformado,
                motivo: 'erro_interno',
                detalhes: {
                    message: error.message || String(error),
                },
                dispositivo,
                userAgent,
                ip,
                assinaturaDispositivo,
            });

            return {
                success: false,
                code: 'erro_interno',
                message: 'Não foi possível validar o acesso agora. Tente novamente mais tarde.',
            };
        }
    }
);

async function carregarConfigAreaAluno() {
    const configDoc = await db.collection('configuracoes_site').doc('area_aluno').get();
    return normalizarConfigAreaAluno(configDoc.exists ? (configDoc.data() || {}) : {});
}

function dadosGoogleAuthAreaAluno(request) {
    const token = request.auth?.token || {};
    const provider = token.firebase?.sign_in_provider || '';
    return {
        uid: request.auth?.uid || '',
        email: token.email || '',
        nome: token.name || token.displayName || '',
        foto: token.picture || '',
        provider,
    };
}

function validarIdentidadeBasicaAreaAluno(alunoData, authPayload = {}) {
    const dataInformada = String(authPayload.dataNascimento || authPayload.data_nascimento || '').trim();
    const iniciaisInformadas = normalizarTextoAreaAluno(authPayload.iniciais || '');
    const telefoneFinalInformado = limparNumeroAreaAluno(authPayload.telefoneFinal || authPayload.telefone_final || '');
    const dataNascimento = parseDataNascimentoAreaAluno(dataInformada);

    if (!dataNascimento || !iniciaisInformadas || telefoneFinalInformado.length !== 4) return false;

    const nascimentoAluno = alunoData.data_nascimento;
    const nascimentoMillis = typeof nascimentoAluno?.toMillis === 'function'
        ? nascimentoAluno.toMillis()
        : 0;
    const inicioMillis = dataNascimento.startOf('day').toMillis();
    const fimMillis = dataNascimento.plus({ days: 1 }).startOf('day').toMillis();
    const dataConfere = nascimentoMillis >= inicioMillis && nascimentoMillis < fimMillis;
    const iniciaisConferem = gerarIniciaisAreaAluno(alunoData.nome || '') === iniciaisInformadas;
    const finaisPossiveis = [
        ultimos4AreaAluno(alunoData.contato_aluno || ''),
        ultimos4AreaAluno(alunoData.contato_responsavel || ''),
    ].filter(Boolean);

    return dataConfere && iniciaisConferem && finaisPossiveis.includes(telefoneFinalInformado);
}

async function registrarLogGoogleAreaAluno(evento, dados = {}) {
    try {
        await db.collection('area_aluno_google_logs').add({
            evento,
            ...dados,
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
        console.error('⚠️ Erro ao registrar log Google da área do aluno:', e);
    }
}

async function validarAdminAreaAluno(request) {
    if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'Usuário não autenticado.');
    }

    const userDoc = await db.collection('usuarios').doc(request.auth.uid).get();
    const data = userDoc.exists ? (userDoc.data() || {}) : {};
    const tipo = String(data.tipo || '').trim().toLowerCase();
    const peso = Number(data.peso_permissao || 0);
    const status = String(data.status_conta || '').trim().toLowerCase();
    const ativo = !['bloqueada', 'bloqueado', 'inativa', 'inativo', 'rejeitada', 'rejeitado'].includes(status);

    if (!ativo || (peso < 90 && tipo !== 'admin' && tipo !== 'administrador')) {
        throw new HttpsError('permission-denied', 'Apenas administradores podem executar esta ação.');
    }

    return {
        uid: request.auth.uid,
        nome: data.nome_completo || data.nome || request.auth.token?.email || 'Administrador',
    };
}

function timestampIsoAreaAluno(valor) {
    if (!valor) return '';
    if (typeof valor.toDate === 'function') {
        return valor.toDate().toISOString();
    }
    if (valor instanceof Date) return valor.toISOString();
    return '';
}

function sanitizarAlunoVinculadoGoogle(doc) {
    const data = doc.data() || {};
    return {
        alunoId: doc.id,
        nome: String(data.nome || ''),
        foto: String(data.foto_perfil_aluno || data.foto || ''),
        turma: String(data.turma || data.turma_nome || ''),
        academia: String(data.academia || data.academia_nome || ''),
        status_atividade: String(data.status_atividade || ''),
        graduacao: String(data.graduacao_nome || data.graduacao_atual || data.graduacao || ''),
        areaAlunoGoogleEmail: String(data.areaAlunoGoogleEmail || ''),
        areaAlunoGoogleNome: String(data.areaAlunoGoogleNome || ''),
        ultimoAcessoGoogleEm: timestampIsoAreaAluno(data.areaAlunoUltimoAcessoGoogleEm),
    };
}

async function buscarAlunosVinculadosGooglePorUid(uid) {
    const snapshot = await db
        .collection('alunos')
        .where('areaAlunoGoogleUid', '==', uid)
        .get();

    const alunos = [];
    snapshot.forEach((doc) => {
        const data = doc.data() || {};
        if (data.areaAlunoGoogleVinculado === true) {
            alunos.push(sanitizarAlunoVinculadoGoogle(doc));
        }
    });

    alunos.sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'));
    return alunos;
}

exports.buscarAlunosVinculadosAoGoogle = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError('unauthenticated', 'Entre com uma conta Google para continuar.');
        }

        const google = dadosGoogleAuthAreaAluno(request);
        const alunos = await buscarAlunosVinculadosGooglePorUid(request.auth.uid);

        await registrarLogGoogleAreaAluno('buscar_alunos_vinculados_google', {
            google_uid: request.auth.uid,
            google_email: google.email || '',
            total_alunos: alunos.length,
        });

        return {
            success: true,
            alunos,
        };
    }
);

exports.resolverDestinoInicialUsuario = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError('unauthenticated', 'Usuário não autenticado.');
        }

        const alunosVinculados = await buscarAlunosVinculadosGooglePorUid(request.auth.uid);
        let destinoAlunoSugerido = 'nenhum';
        let motivoAluno = 'sem_aluno_vinculado';

        if (alunosVinculados.length === 1) {
            destinoAlunoSugerido = 'area_aluno';
            motivoAluno = 'aluno_unico';
        } else if (alunosVinculados.length > 1) {
            destinoAlunoSugerido = 'escolher_aluno';
            motivoAluno = 'multiplos_alunos';
        }

        return {
            success: true,
            alunosVinculados,
            destinoAlunoSugerido,
            motivoAluno,
        };
    }
);

exports.registrarEventoGoogleAreaAluno = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError('unauthenticated', 'Usuário não autenticado.');
        }

        const evento = String(request.data?.evento || '').trim();
        if (!evento) {
            return { success: false, code: 'evento_invalido' };
        }

        const dados = request.data?.dados && typeof request.data.dados === 'object'
            ? request.data.dados
            : {};
        const google = dadosGoogleAuthAreaAluno(request);

        await registrarLogGoogleAreaAluno(evento, {
            ...dados,
            google_uid: request.auth.uid,
            google_email: google.email || '',
        });

        return { success: true };
    }
);

exports.vincularGoogleAreaAluno = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError('unauthenticated', 'Entre com uma conta Google para continuar.');
        }

        const payload = request.data || {};
        const alunoId = String(payload.alunoId || payload.aluno_id || '').trim();
        const authPayload = payload.authPayload || {};
        const google = dadosGoogleAuthAreaAluno(request);

        if (!alunoId || !google.uid || !google.email || google.provider !== 'google.com') {
            return {
                success: false,
                code: 'dados_invalidos',
                message: 'Não foi possível confirmar a conta Google.',
            };
        }

        const config = await carregarConfigAreaAluno();
        if (config.google_login_ativo !== true || config.google_vinculacao_modo === 'desativada') {
            return {
                success: false,
                code: 'google_desativado',
                message: 'O acesso com Google não está disponível no momento.',
            };
        }

        const alunoRef = db.collection('alunos').doc(alunoId);
        const alunoDoc = await alunoRef.get();

        if (!alunoDoc.exists) {
            return {
                success: false,
                code: 'aluno_nao_encontrado',
                message: 'Perfil não encontrado.',
            };
        }

        const alunoData = alunoDoc.data() || {};
        const identidadeOk = validarIdentidadeBasicaAreaAluno(alunoData, authPayload);

        if (!identidadeOk) {
            await registrarLogGoogleAreaAluno('vinculo_negado_identidade_basica', {
                aluno_id: alunoId,
                google_uid: google.uid,
                google_email: google.email,
            });

            return {
                success: false,
                code: 'identidade_nao_confirmada',
                message: 'Não foi possível confirmar este perfil. Entre novamente e tente vincular a conta Google.',
            };
        }

        const uidVinculado = String(alunoData.areaAlunoGoogleUid || '').trim();

        if (uidVinculado && uidVinculado !== google.uid) {
            await registrarLogGoogleAreaAluno('vinculo_negado_ja_vinculado_outro_uid', {
                aluno_id: alunoId,
                google_uid: google.uid,
                google_email: google.email,
            });

            return {
                success: false,
                code: 'google_diferente',
                message: 'Este perfil está vinculado a outra conta Google. Entre com a conta correta ou procure a coordenação.',
            };
        }

        const update = {
            areaAlunoGoogleVinculado: true,
            areaAlunoGoogleUid: google.uid,
            areaAlunoGoogleEmail: google.email,
            areaAlunoGoogleNome: google.nome || '',
            areaAlunoGoogleFoto: google.foto || '',
            areaAlunoUltimoAcessoGoogleEm: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (!uidVinculado) {
            update.areaAlunoVinculadoEm = admin.firestore.FieldValue.serverTimestamp();
            update.areaAlunoVinculadoOrigem = 'area_aluno';
        }

        await alunoRef.set(update, { merge: true });

        const alunoAtualizado = { ...alunoData, ...update, areaAlunoGoogleUid: google.uid };
        const configEfetiva = configEfetivaAreaAluno(config, 'google', alunoAtualizado);
        const dadosAluno = await montarDadosAlunoLiberados(alunoId, alunoAtualizado, configEfetiva);

        await registrarLogGoogleAreaAluno(uidVinculado ? 'vinculo_existente_confirmado' : 'vinculo_criado', {
            aluno_id: alunoId,
            aluno_nome: alunoData.nome || '',
            google_uid: google.uid,
            google_email: google.email,
        });

        return {
            success: true,
            code: 'acesso_google_liberado',
            message: 'Conta Google confirmada.',
            modo_acesso: 'google',
            google_vinculado: true,
            google_email_mascarado: mascararEmailAreaAluno(google.email),
            aluno: dadosAluno,
            config: configEfetiva,
        };
    }
);

exports.validarAcessoGoogleAreaAluno = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError('unauthenticated', 'Entre com a conta Google vinculada.');
        }

        const alunoId = String(request.data?.alunoId || request.data?.aluno_id || '').trim();
        const google = dadosGoogleAuthAreaAluno(request);

        if (!alunoId || google.provider !== 'google.com') {
            return { success: false, code: 'dados_invalidos', message: 'Perfil não informado.' };
        }

        const alunoDoc = await db.collection('alunos').doc(alunoId).get();
        if (!alunoDoc.exists) {
            return { success: false, code: 'aluno_nao_encontrado', message: 'Perfil não encontrado.' };
        }

        const alunoData = alunoDoc.data() || {};
        const uidVinculado = String(alunoData.areaAlunoGoogleUid || '').trim();

        if (!uidVinculado || alunoData.areaAlunoGoogleVinculado !== true) {
            return { success: false, code: 'sem_vinculo', message: 'Este perfil ainda não possui conta Google vinculada.' };
        }

        if (uidVinculado !== google.uid) {
            await registrarLogGoogleAreaAluno('acesso_google_negado_uid_diferente', {
                aluno_id: alunoId,
                google_uid: google.uid,
                google_email: google.email,
            });

            return {
                success: false,
                code: 'google_diferente',
                message: 'Este perfil está vinculado a outra conta Google. Entre com a conta correta ou procure a coordenação.',
            };
        }

        await db.collection('alunos').doc(alunoId).set({
            areaAlunoUltimoAcessoGoogleEm: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        const config = await carregarConfigAreaAluno();
        const configEfetiva = configEfetivaAreaAluno(config, 'google', alunoData);
        const dadosAluno = await montarDadosAlunoLiberados(alunoId, alunoData, configEfetiva);

        await registrarLogGoogleAreaAluno('acesso_google_sucesso', {
            aluno_id: alunoId,
            aluno_nome: alunoData.nome || '',
            google_uid: google.uid,
            google_email: google.email,
        });

        return {
            success: true,
            code: 'acesso_google_liberado',
            message: 'Acesso liberado.',
            modo_acesso: 'google',
            google_vinculado: true,
            google_email_mascarado: mascararEmailAreaAluno(google.email),
            aluno: dadosAluno,
            config: configEfetiva,
        };
    }
);

exports.resetarVinculoGoogleAreaAluno = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        const adminAtual = await validarAdminAreaAluno(request);
        const alunoIds = Array.isArray(request.data?.alunoIds)
            ? request.data.alunoIds
            : [request.data?.alunoId].filter(Boolean);

        if (alunoIds.length === 0) {
            return { success: false, code: 'sem_alunos', message: 'Nenhum aluno informado.' };
        }

        const batch = db.batch();
        for (const alunoIdRaw of alunoIds) {
            const alunoId = String(alunoIdRaw || '').trim();
            if (!alunoId) continue;
            batch.set(db.collection('alunos').doc(alunoId), {
                areaAlunoGoogleVinculado: false,
                areaAlunoGoogleUid: admin.firestore.FieldValue.delete(),
                areaAlunoGoogleEmail: admin.firestore.FieldValue.delete(),
                areaAlunoGoogleNome: admin.firestore.FieldValue.delete(),
                areaAlunoGoogleFoto: admin.firestore.FieldValue.delete(),
                areaAlunoVinculoResetadoEm: admin.firestore.FieldValue.serverTimestamp(),
                areaAlunoVinculoResetadoPor: adminAtual.uid,
            }, { merge: true });
        }

        await batch.commit();
        await registrarLogGoogleAreaAluno('vinculo_resetado_admin', {
            aluno_ids: alunoIds,
            resetado_por: adminAtual.uid,
            resetado_por_nome: adminAtual.nome,
        });

        return { success: true, total: alunoIds.length };
    }
);

exports.resetarVinculosGoogleAreaAlunoEmMassa = onCall(
    {
        cors: true,
        invoker: 'public',
    },
    async (request) => {
        const adminAtual = await validarAdminAreaAluno(request);
        const resetarTodos = request.data?.resetarTodos === true;
        const alunoIds = Array.isArray(request.data?.alunoIds) ? request.data.alunoIds : [];
        let refs = [];

        if (resetarTodos) {
            const snap = await db.collection('alunos')
                .where('areaAlunoGoogleVinculado', '==', true)
                .limit(450)
                .get();
            refs = snap.docs.map(doc => doc.ref);
        } else {
            refs = alunoIds
                .map(id => String(id || '').trim())
                .filter(Boolean)
                .map(id => db.collection('alunos').doc(id));
        }

        if (refs.length === 0) {
            return { success: false, code: 'sem_alunos', message: 'Nenhum vínculo encontrado.' };
        }

        const batch = db.batch();
        for (const ref of refs) {
            batch.set(ref, {
                areaAlunoGoogleVinculado: false,
                areaAlunoGoogleUid: admin.firestore.FieldValue.delete(),
                areaAlunoGoogleEmail: admin.firestore.FieldValue.delete(),
                areaAlunoGoogleNome: admin.firestore.FieldValue.delete(),
                areaAlunoGoogleFoto: admin.firestore.FieldValue.delete(),
                areaAlunoVinculoResetadoEm: admin.firestore.FieldValue.serverTimestamp(),
                areaAlunoVinculoResetadoPor: adminAtual.uid,
            }, { merge: true });
        }

        await batch.commit();
        await registrarLogGoogleAreaAluno('vinculos_resetados_em_massa', {
            total: refs.length,
            resetado_por: adminAtual.uid,
            resetado_por_nome: adminAtual.nome,
            resetar_todos: resetarTodos,
        });

        return { success: true, total: refs.length };
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


// ============================================
// FUNÇÃO: NOTIFICAR NOVA VERSÃO DO APP
// ============================================
// Callable usada pelo painel Admin / Controle de Atualizações.
// Envia push para usuários ativos quando uma nova versão é publicada.
//
// Ela reaproveita os helpers já existentes neste arquivo:
// - buscarTokensUsuariosAtivos()
// - enviarMulticastEmLotes()
// - removerTokensInvalidos()
//
// Payload esperado:
// {
//   versao: "2.0.61",
//   obrigatoria: false,
//   titulo: "🚀 Nova versão 2.0.61 disponível!",
//   mensagem: "Atualize o UAI Capoeira para receber as melhorias."
// }
exports.notifyNewAppVersion = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 300,
        memory: '512MiB',
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError(
                'unauthenticated',
                'Você precisa estar logado para enviar notificação de atualização.'
            );
        }

        const uid = request.auth.uid;
        const data = request.data || {};

        console.log('🚀 notifyNewAppVersion chamada por:', uid, data);

        const configRef = db.collection('configuracoes').doc('app');
        const configSnap = await configRef.get();
        const config = configSnap.exists ? configSnap.data() : {};

        const versao = String(
            data.versao ||
            config.versao_atual ||
            ''
        ).trim();

        if (!versao) {
            throw new HttpsError(
                'invalid-argument',
                'Informe a versão da atualização.'
            );
        }

        const obrigatoria = data.obrigatoria === true || config.atualizacao_obrigatoria === true;

        const titulo = String(
            data.titulo ||
            `🚀 Nova versão ${versao} disponível!`
        ).trim();

        const mensagem = String(
            data.mensagem ||
            config.mensagem_atualizacao ||
            (obrigatoria
                ? 'Atualização obrigatória disponível. Atualize para continuar usando o UAI Capoeira.'
                : 'Atualize o UAI Capoeira para receber as melhorias e correções.')
        ).trim();

        const apkPath = String(config.apk_path || data.apk_path || '').trim();
        const apkUrl = String(config.apk_url || data.apk_url || '').trim();

        const {
            usuariosAtivos,
            usuariosNotificaveis,
            tokens,
            tokenOwners,
            usuariosMap,
        } = await buscarTokensUsuariosAtivosPorOrigem([
            'app',
            'android_app',
            'android',
            'apk',
        ]);

        if (!tokens || tokens.length === 0) {
            console.log('⚠️ Nenhum token ativo encontrado para notificar.');

            await configRef.set({
                ultima_notificacao_versao: versao,
                ultima_notificacao_versao_status: 'sem_tokens',
                ultima_notificacao_versao_em: admin.firestore.FieldValue.serverTimestamp(),
                ultima_notificacao_versao_por: uid,
            }, { merge: true });

            return {
                success: false,
                code: 'sem_tokens',
                message: 'Nenhum token ativo encontrado.',
                versao,
                usuariosAtivos,
                usuariosNotificaveis: usuariosNotificaveis || 0,
                tokensEncontrados: 0,
                successCount: 0,
                failureCount: 0,
            };
        }

        const payloadNotificacao = {
            tipo: 'nova_versao_app',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
            versao,
            versao_atual: versao,
            obrigatoria: String(obrigatoria),
            apk_path: apkPath,
            apk_url: apkUrl,
            origem: 'controle_atualizacoes',
            destino: 'android_apk',
        };

        const resultado = await enviarMulticastEmLotes({
            tokens,
            title: titulo,
            body: mensagem,
            data: payloadNotificacao,
            tokenOwners,
            androidIcon: 'ic_notification_update',
        });

        const notificacoesRegistradas = await registrarNotificacaoUsuarios({
            usuariosMap,
            tipo: 'nova_versao_app',
            titulo,
            mensagem,
            data: payloadNotificacao,
        });

        await db.collection('logs_notificacoes_app').add({
            tipo: 'nova_versao_app',
            versao,
            obrigatoria,
            titulo,
            mensagem,
            usuarios_ativos: usuariosAtivos,
            usuarios_notificaveis: usuariosNotificaveis,
            tokens_encontrados: tokens.length,
            notificacoes_registradas: notificacoesRegistradas,
            success_count: resultado.successCount,
            failure_count: resultado.failureCount,
            tokens_invalidos: resultado.tokensInvalidos,
            enviado_por: uid,
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        await configRef.set({
            ultima_notificacao_versao: versao,
            ultima_notificacao_versao_status: 'enviada',
            ultima_notificacao_versao_success_count: resultado.successCount,
            ultima_notificacao_versao_failure_count: resultado.failureCount,
            ultima_notificacao_versao_tokens_invalidos: resultado.tokensInvalidos,
            ultima_notificacao_versao_destino: 'android_apk',
            ultima_notificacao_versao_sininho_registros: notificacoesRegistradas,
            ultima_notificacao_versao_em: admin.firestore.FieldValue.serverTimestamp(),
            ultima_notificacao_versao_por: uid,
        }, { merge: true });

        console.log('✅ Notificação de nova versão finalizada:', {
            versao,
            usuariosAtivos,
            tokens: tokens.length,
            resultado,
        });

        return {
            success: true,
            code: 'notificacao_enviada',
            message: `Notificação da versão ${versao} enviada.`,
            versao,
            obrigatoria,
            usuariosAtivos,
            usuariosNotificaveis,
            tokensEncontrados: tokens.length,
            notificacoesRegistradas,
            destino: 'android_apk',
            ...resultado,
        };
    }
);


// ============================================
// PAINEL ADMIN: SAÚDE FIREBASE
// ============================================
const FIREBASE_SAUDE_MAX_DOC_LIMIT = 50;
const FIREBASE_SAUDE_COUNT_LIMIT = 5000;

const FIREBASE_SAUDE_COLECOES = {
    alunos: {
        descricao: 'Cadastro de alunos e vínculos acadêmicos',
        risco: 'alto',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'updated_at', 'criado_em'],
    },
    usuarios: {
        descricao: 'Usuários administrativos e permissões',
        risco: 'alto',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'ultimo_login', 'criado_em'],
    },
    turmas: {
        descricao: 'Turmas, horários e vínculos com academias',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'criado_em'],
    },
    academias: {
        descricao: 'Academias, núcleos e responsáveis',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'criado_em'],
    },
    chamadas: {
        descricao: 'Registros de chamadas e frequência',
        risco: 'alto',
        podeVisualizarDetalhes: true,
        camposData: ['data_chamada', 'criado_em', 'atualizado_em'],
    },
    eventos: {
        descricao: 'Eventos cadastrados no app',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['data_evento', 'atualizado_em', 'criado_em'],
    },
    participacoes_eventos: {
        descricao: 'Participações, pagamentos e certificados de eventos',
        risco: 'alto',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'criado_em'],
    },
    graduacoes: {
        descricao: 'Graduações e faixas',
        risco: 'baixo',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'criado_em'],
    },
    configuracoes: {
        descricao: 'Configurações internas do sistema',
        risco: 'alto',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'ultima_atualizacao'],
    },
    estatisticas_acessos: {
        descricao: 'Estatísticas internas de acesso',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['ultima_atividade', 'ultima_atualizacao', 'criado_em'],
    },
    area_aluno_logs_acesso: {
        descricao: 'Logs de acesso da Área do Aluno',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['data_acesso', 'criado_em'],
    },
    area_aluno_logs_erro: {
        descricao: 'Logs de erro da Área do Aluno',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['tentativa_em', 'criado_em'],
    },
    area_aluno_google_logs: {
        descricao: 'Logs de vínculo e login Google da Área do Aluno',
        risco: 'alto',
        podeVisualizarDetalhes: true,
        camposData: ['criado_em', 'timestamp'],
    },
    area_aluno_solicitacoes_alteracao: {
        descricao: 'Solicitações de alteração cadastral de alunos',
        risco: 'alto',
        podeVisualizarDetalhes: true,
        camposData: ['atualizado_em', 'criado_em'],
    },
    atualizacoes_app: {
        descricao: 'Histórico e versões publicadas do app',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['publicado_em', 'criado_em', 'atualizado_em'],
    },
    notificacoes: {
        descricao: 'Notificações internas para usuários',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['criado_em', 'enviado_em'],
    },
    aniversariantes_logs: {
        descricao: 'Logs de notificações de aniversariantes',
        risco: 'baixo',
        podeVisualizarDetalhes: true,
        camposData: ['criado_em', 'data'],
    },
    firebase_saude_logs: {
        descricao: 'Auditoria de acesso ao painel Saúde Firebase',
        risco: 'medio',
        podeVisualizarDetalhes: true,
        camposData: ['criado_em'],
    },
};

const FIREBASE_SAUDE_STORAGE_PREFIXOS = [
    'alunos/',
    'site/',
    'logos/',
    'certificados/',
    'atualizacoes/',
    'comprovantes/',
    'eventos/',
];

const FIREBASE_SAUDE_FUNCTIONS_MANUAIS = [
    ['obterResumoSaudeFirebase', 'Resumo geral do Firestore, Storage, Functions e integridade'],
    ['listarColecoesFirebaseSaude', 'Lista controlada de coleções principais'],
    ['listarDocumentosColecaoFirebaseSaude', 'Explorador paginado de documentos sanitizados'],
    ['obterDocumentoFirebaseSaude', 'Detalhe sanitizado de documento permitido'],
    ['listarArquivosStorageFirebaseSaude', 'Lista controlada de prefixos seguros do Storage'],
    ['listarFunctionsFirebaseSaude', 'Lista informativa de Cloud Functions importantes'],
    ['notifyNewAppVersion', 'Notificação administrativa de nova versão do app'],
    ['validarAcessoGoogleAreaAluno', 'Validação de acesso Google para Área do Aluno'],
    ['vincularGoogleAreaAluno', 'Vínculo Google controlado da Área do Aluno'],
    ['criarSolicitacaoAlteracaoAreaAluno', 'Solicitação segura de alteração cadastral'],
    ['processarChamada', 'Processamento de chamada e frequência'],
];

function firebaseSaudeToIso(value) {
    if (!value) return null;

    try {
        if (value.toDate) return value.toDate().toISOString();
        if (value instanceof Date) return value.toISOString();
        if (typeof value === 'string') return value;
    } catch (error) {
        console.warn('Erro ao converter data do painel Saúde Firebase:', error);
    }

    return null;
}

function firebaseSaudeInt(value) {
    const number = Number(value || 0);
    return Number.isFinite(number) ? number : 0;
}

function firebaseSaudeDocIdSeguro(value) {
    const text = String(value || '').trim();
    if (!text || text.includes('/') || text.length > 180) return '';
    return text;
}

async function validarAdminFirebaseSaude(request) {
    if (!request.auth || !request.auth.uid) {
        throw new HttpsError('unauthenticated', 'Você precisa estar logado.');
    }

    const uid = request.auth.uid;
    const userDoc = await db.collection('usuarios').doc(uid).get();

    if (!userDoc.exists) {
        throw new HttpsError('permission-denied', 'Usuário administrativo não encontrado.');
    }

    const data = userDoc.data() || {};
    const status = String(data.status_conta || '').trim().toLowerCase();
    const tipo = String(data.tipo || '').trim().toLowerCase();
    const peso = firebaseSaudeInt(data.peso_permissao);
    const adminReal = status === 'ativa' && (
        peso >= 90 ||
        tipo === 'admin' ||
        tipo === 'administrador'
    );

    if (!adminReal) {
        throw new HttpsError('permission-denied', 'Apenas admin/master com conta ativa pode acessar este painel.');
    }

    return {
        uid,
        email: request.auth.token?.email || data.email || '',
        nome: data.nome_completo || data.nome || '',
        peso,
        tipo,
    };
}

async function registrarLogFirebaseSaude(adminAtual, evento, detalhes = {}) {
    try {
        await db.collection('firebase_saude_logs').add({
            evento,
            uid: adminAtual.uid,
            email: adminAtual.email || '',
            nome: adminAtual.nome || '',
            detalhes: sanitizarFirebaseSaude(detalhes),
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (error) {
        console.error('Erro ao registrar log Saúde Firebase:', error);
    }
}

function campoSensivelFirebaseSaude(key) {
    const lower = String(key || '').toLowerCase();
    return lower.includes('token') ||
        lower.includes('password') ||
        lower.includes('senha') ||
        lower.includes('secret') ||
        lower.includes('key') ||
        lower.includes('cpf') ||
        lower.includes('rg') ||
        lower.includes('endereco') ||
        lower.includes('pagamento') ||
        lower.includes('cartao') ||
        lower.includes('telefone') ||
        lower.includes('contato') ||
        lower.includes('fcm');
}

function mascararValorFirebaseSaude(key, value) {
    const lower = String(key || '').toLowerCase();
    const text = String(value || '');

    if (!text) return '';
    if (lower.includes('telefone') || lower.includes('contato')) {
        const digits = text.replace(/\D/g, '');
        return digits.length >= 4 ? `***${digits.slice(-4)}` : '[oculto]';
    }
    if (lower.includes('email')) {
        const [user, domain] = text.split('@');
        if (!user || !domain) return '[email oculto]';
        return `${user.slice(0, 2)}***@${domain}`;
    }
    return '[oculto]';
}

function sanitizarFirebaseSaude(value, parentKey = '') {
    if (value === null || value === undefined) return value;

    if (value.toDate) return firebaseSaudeToIso(value);
    if (value instanceof Date) return value.toISOString();

    if (campoSensivelFirebaseSaude(parentKey)) {
        return mascararValorFirebaseSaude(parentKey, value);
    }

    if (Array.isArray(value)) {
        return value.slice(0, 30).map(item => sanitizarFirebaseSaude(item, parentKey));
    }

    if (typeof value === 'object') {
        const out = {};
        for (const [key, child] of Object.entries(value)) {
            if (campoSensivelFirebaseSaude(key)) {
                out[key] = mascararValorFirebaseSaude(key, child);
            } else {
                out[key] = sanitizarFirebaseSaude(child, key);
            }
        }
        return out;
    }

    if (typeof value === 'string' && String(parentKey).toLowerCase().includes('email')) {
        return mascararValorFirebaseSaude(parentKey, value);
    }

    return value;
}

async function contarColecaoFirebaseSaude(nome, queryBuilder) {
    try {
        const baseQuery = queryBuilder ? queryBuilder(db.collection(nome)) : db.collection(nome);
        const snap = await baseQuery.count().get();
        return snap.data().count || 0;
    } catch (error) {
        console.warn(`Count indisponível para ${nome}, usando fallback limitado:`, error.message || error);
        try {
            const snap = await db.collection(nome).limit(FIREBASE_SAUDE_COUNT_LIMIT).get();
            return snap.size;
        } catch (innerError) {
            console.warn(`Falha ao contar ${nome}:`, innerError.message || innerError);
            return 0;
        }
    }
}

async function ultimaAtualizacaoColecaoFirebaseSaude(nome, campos = []) {
    for (const campo of campos) {
        try {
            const snap = await db
                .collection(nome)
                .orderBy(campo, 'desc')
                .limit(1)
                .get();

            if (!snap.empty) {
                const data = snap.docs[0].data() || {};
                const iso = firebaseSaudeToIso(data[campo]);
                if (iso) return iso;
            }
        } catch (error) {
            // Campo sem índice ou ausente: tenta o próximo campo conhecido.
        }
    }

    return null;
}

async function configAppFirebaseSaude() {
    const candidates = [
        ['configuracoes', 'app'],
        ['configuracoes', 'atualizacoes_app'],
        ['atualizacoes_app', 'config'],
    ];

    for (const [collection, docId] of candidates) {
        const doc = await db.collection(collection).doc(docId).get();
        if (doc.exists) return doc.data() || {};
    }

    return {};
}

async function diagnosticosFirebaseSaude() {
    const diagnosticos = [];

    const alunosAtivosSnap = await db
        .collection('alunos')
        .where('status', '==', 'ativo')
        .limit(500)
        .get()
        .catch(() => null);

    if (alunosAtivosSnap) {
        const semTurma = [];
        const semGraduacao = [];
        const semFoto = [];
        alunosAtivosSnap.forEach(doc => {
            const data = doc.data() || {};
            if (!data.turma_id && !data.turma) semTurma.push({ id: doc.id, nome: data.nome || '' });
            if (!data.graduacao_id && !data.graduacao) semGraduacao.push({ id: doc.id, nome: data.nome || '' });
            if (!data.foto_url && !data.foto && !data.imagem) semFoto.push({ id: doc.id, nome: data.nome || '' });
        });

        diagnosticos.push({
            titulo: 'Alunos ativos sem turma',
            descricao: 'Alunos ativos sem turma_id/turma preenchido.',
            quantidade: semTurma.length,
            nivel: semTurma.length ? 'medio' : 'info',
            exemplos: semTurma.slice(0, 8),
        });
        diagnosticos.push({
            titulo: 'Alunos ativos sem graduação',
            descricao: 'Alunos ativos sem graduação ou graduação_id.',
            quantidade: semGraduacao.length,
            nivel: semGraduacao.length ? 'medio' : 'info',
            exemplos: semGraduacao.slice(0, 8),
        });
        diagnosticos.push({
            titulo: 'Alunos ativos sem foto',
            descricao: 'Alunos ativos sem campo de foto conhecido.',
            quantidade: semFoto.length,
            nivel: semFoto.length ? 'baixo' : 'info',
            exemplos: semFoto.slice(0, 8),
        });
    }

    const usuariosAtivosSnap = await db
        .collection('usuarios')
        .where('status_conta', '==', 'ativa')
        .limit(500)
        .get()
        .catch(() => null);

    if (usuariosAtivosSnap) {
        const semPerfil = [];
        usuariosAtivosSnap.forEach(doc => {
            const data = doc.data() || {};
            if (!data.tipo && firebaseSaudeInt(data.peso_permissao) <= 0) {
                semPerfil.push({ id: doc.id, email: mascararValorFirebaseSaude('email', data.email || '') });
            }
        });
        diagnosticos.push({
            titulo: 'Usuários ativos sem perfil',
            descricao: 'Usuários ativos sem tipo e sem peso_permissao útil.',
            quantidade: semPerfil.length,
            nivel: semPerfil.length ? 'alto' : 'info',
            exemplos: semPerfil.slice(0, 8),
        });
    }

    const turmasSnap = await db.collection('turmas').limit(500).get().catch(() => null);
    if (turmasSnap) {
        const semAcademia = [];
        turmasSnap.forEach(doc => {
            const data = doc.data() || {};
            if (!data.academia_id && !data.academia) semAcademia.push({ id: doc.id, nome: data.nome || '' });
        });
        diagnosticos.push({
            titulo: 'Turmas sem academia',
            descricao: 'Turmas sem academia_id/academia preenchido.',
            quantidade: semAcademia.length,
            nivel: semAcademia.length ? 'medio' : 'info',
            exemplos: semAcademia.slice(0, 8),
        });
    }

    const eventosSnap = await db.collection('eventos').limit(500).get().catch(() => null);
    if (eventosSnap) {
        const semData = [];
        eventosSnap.forEach(doc => {
            const data = doc.data() || {};
            if (!data.data_evento && !data.data && !data.inicio_em) {
                semData.push({ id: doc.id, nome: data.nome || data.titulo || '' });
            }
        });
        diagnosticos.push({
            titulo: 'Eventos sem data',
            descricao: 'Eventos sem campos de data conhecidos.',
            quantidade: semData.length,
            nivel: semData.length ? 'medio' : 'info',
            exemplos: semData.slice(0, 8),
        });
    }

    const logsErro = await contarColecaoFirebaseSaude('area_aluno_logs_erro');
    diagnosticos.push({
        titulo: 'Logs de erro da Área do Aluno',
        descricao: 'Total contado na coleção de erros da Área do Aluno.',
        quantidade: logsErro,
        nivel: logsErro ? 'baixo' : 'info',
        exemplos: [],
    });

    return diagnosticos;
}

async function resumoStorageFirebaseSaude() {
    const bucket = storage.bucket(bucketName);
    let quantidade = 0;
    let tamanho = 0;

    for (const prefix of FIREBASE_SAUDE_STORAGE_PREFIXOS) {
        try {
            const [files] = await bucket.getFiles({
                prefix,
                maxResults: 100,
                autoPaginate: false,
            });
            quantidade += files.length;
            for (const file of files) {
                tamanho += firebaseSaudeInt(file.metadata?.size);
            }
        } catch (error) {
            console.warn(`Falha ao resumir storage em ${prefix}:`, error.message || error);
        }
    }

    return { quantidade, tamanho };
}

exports.obterResumoSaudeFirebase = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 120,
        memory: '512MiB',
    },
    async (request) => {
        const adminAtual = await validarAdminFirebaseSaude(request);
        await registrarLogFirebaseSaude(adminAtual, 'abriu_painel');

        const [
            usuariosTotal,
            usuariosAtivos,
            usuariosInativos,
            alunosTotal,
            alunosAtivos,
            alunosInativos,
            turmasTotal,
            eventosTotal,
            participacoesTotal,
            logsRecentes,
            solicitacoesPendentes,
            storageResumo,
            configApp,
            diagnosticos,
        ] = await Promise.all([
            contarColecaoFirebaseSaude('usuarios'),
            contarColecaoFirebaseSaude('usuarios', q => q.where('status_conta', '==', 'ativa')),
            contarColecaoFirebaseSaude('usuarios', q => q.where('status_conta', 'in', ['inativa', 'bloqueada', 'pendente'])),
            contarColecaoFirebaseSaude('alunos'),
            contarColecaoFirebaseSaude('alunos', q => q.where('status', '==', 'ativo')),
            contarColecaoFirebaseSaude('alunos', q => q.where('status', 'in', ['inativo', 'bloqueado'])),
            contarColecaoFirebaseSaude('turmas'),
            contarColecaoFirebaseSaude('eventos'),
            contarColecaoFirebaseSaude('participacoes_eventos'),
            contarColecaoFirebaseSaude('firebase_saude_logs'),
            contarColecaoFirebaseSaude('area_aluno_solicitacoes_alteracao', q => q.where('status', '==', 'pendente')),
            resumoStorageFirebaseSaude(),
            configAppFirebaseSaude(),
            diagnosticosFirebaseSaude(),
        ]);

        return {
            timestamp: new Date().toISOString(),
            statusGeral: diagnosticos.some(item => item.quantidade > 0 && item.nivel === 'alto')
                ? 'atenção'
                : 'operacional',
            projeto: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || '',
            contadores: {
                usuarios_total: usuariosTotal,
                usuarios_ativos: usuariosAtivos,
                usuarios_inativos: usuariosInativos,
                alunos_total: alunosTotal,
                alunos_ativos: alunosAtivos,
                alunos_inativos: alunosInativos,
                turmas_total: turmasTotal,
                eventos_total: eventosTotal,
                participacoes_total: participacoesTotal,
                logs_recentes: logsRecentes,
                solicitacoes_pendentes: solicitacoesPendentes,
                storage_arquivos_mapeados: storageResumo.quantidade,
                storage_tamanho_aproximado: storageResumo.tamanho,
            },
            configuracoes: {
                appConfigEncontrada: Object.keys(configApp).length > 0,
                storagePrefixosPermitidos: FIREBASE_SAUDE_STORAGE_PREFIXOS,
                colecoesPermitidas: Object.keys(FIREBASE_SAUDE_COLECOES),
            },
            atualizacoes: {
                versaoAtual: configApp.versao_atual || configApp.versaoAtual || configApp.versao || '',
                versaoMinima: configApp.versao_minima || configApp.versaoMinima || '',
                obrigatoria: configApp.atualizacao_obrigatoria === true || configApp.obrigatoria === true,
                ultimaAtualizacao: firebaseSaudeToIso(
                    configApp.ultima_atualizacao ||
                    configApp.atualizado_em ||
                    configApp.publicado_em
                ),
            },
            usoCustos: {
                status: 'não conectado ao Cloud Monitoring ainda',
                orientacao: 'Configure Google Cloud Monitoring/Billing para métricas reais de leituras, escritas, tráfego e custos.',
                metricasReaisDisponiveis: false,
            },
            diagnosticos: diagnosticos.map(item => sanitizarFirebaseSaude(item)),
        };
    }
);

exports.listarColecoesFirebaseSaude = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 120,
        memory: '512MiB',
    },
    async (request) => {
        const adminAtual = await validarAdminFirebaseSaude(request);
        await registrarLogFirebaseSaude(adminAtual, 'listou_colecoes');

        const colecoes = [];
        for (const [nome, config] of Object.entries(FIREBASE_SAUDE_COLECOES)) {
            const [quantidade, ultimaAtualizacao] = await Promise.all([
                contarColecaoFirebaseSaude(nome),
                ultimaAtualizacaoColecaoFirebaseSaude(nome, config.camposData),
            ]);

            colecoes.push({
                nome,
                descricao: config.descricao,
                quantidade,
                ultimaAtualizacao,
                risco: config.risco,
                podeVisualizarDetalhes: config.podeVisualizarDetalhes === true,
            });
        }

        return { colecoes };
    }
);

exports.listarDocumentosColecaoFirebaseSaude = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 120,
        memory: '512MiB',
    },
    async (request) => {
        const adminAtual = await validarAdminFirebaseSaude(request);
        const payload = request.data || {};
        const colecao = String(payload.colecao || '').trim();
        const config = FIREBASE_SAUDE_COLECOES[colecao];

        if (!config || config.podeVisualizarDetalhes !== true) {
            throw new HttpsError('invalid-argument', 'Coleção não permitida no explorador controlado.');
        }

        const limit = Math.min(Math.max(firebaseSaudeInt(payload.limit) || 25, 1), FIREBASE_SAUDE_MAX_DOC_LIMIT);
        const startAfter = firebaseSaudeDocIdSeguro(payload.startAfter);
        const filtro = String(payload.filtro || '').trim().toLowerCase().slice(0, 80);

        await registrarLogFirebaseSaude(adminAtual, 'listou_colecao', { colecao, limit, filtro: filtro ? '[informado]' : '' });

        let query = db.collection(colecao).orderBy(admin.firestore.FieldPath.documentId()).limit(limit + 1);
        if (startAfter) query = query.startAfter(startAfter);

        const snap = await query.get();
        let docs = snap.docs.map(doc => ({
            id: doc.id,
            dados: sanitizarFirebaseSaude(doc.data() || {}),
        }));

        if (filtro) {
            docs = docs.filter(doc => {
                const haystack = `${doc.id} ${JSON.stringify(doc.dados)}`.toLowerCase();
                return haystack.includes(filtro);
            });
        }

        const hasMore = docs.length > limit;
        const pageDocs = docs.slice(0, limit);

        return {
            documentos: pageDocs,
            nextPageToken: pageDocs.length ? pageDocs[pageDocs.length - 1].id : null,
            hasMore,
        };
    }
);

exports.obterDocumentoFirebaseSaude = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 60,
        memory: '256MiB',
    },
    async (request) => {
        const adminAtual = await validarAdminFirebaseSaude(request);
        const payload = request.data || {};
        const colecao = String(payload.colecao || '').trim();
        const docId = firebaseSaudeDocIdSeguro(payload.docId);
        const config = FIREBASE_SAUDE_COLECOES[colecao];

        if (!config || config.podeVisualizarDetalhes !== true || !docId) {
            throw new HttpsError('invalid-argument', 'Documento não permitido no explorador controlado.');
        }

        await registrarLogFirebaseSaude(adminAtual, 'visualizou_documento', { colecao, docId });

        const doc = await db.collection(colecao).doc(docId).get();
        if (!doc.exists) {
            throw new HttpsError('not-found', 'Documento não encontrado.');
        }

        return {
            id: doc.id,
            dados: sanitizarFirebaseSaude(doc.data() || {}),
        };
    }
);

exports.listarArquivosStorageFirebaseSaude = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 120,
        memory: '512MiB',
    },
    async (request) => {
        const adminAtual = await validarAdminFirebaseSaude(request);
        const payload = request.data || {};
        const requestedPrefix = String(payload.prefixo || '').trim();
        const prefixos = requestedPrefix
            ? FIREBASE_SAUDE_STORAGE_PREFIXOS.filter(prefix => prefix === requestedPrefix)
            : FIREBASE_SAUDE_STORAGE_PREFIXOS;

        if (requestedPrefix && prefixos.length === 0) {
            throw new HttpsError('invalid-argument', 'Prefixo de Storage não permitido.');
        }

        const limit = Math.min(Math.max(firebaseSaudeInt(payload.limit) || 40, 1), 100);
        const bucket = storage.bucket(bucketName);
        const arquivos = [];

        await registrarLogFirebaseSaude(adminAtual, 'listou_storage', {
            prefixo: requestedPrefix || 'todos',
            limit,
        });

        for (const prefix of prefixos) {
            if (arquivos.length >= limit) break;

            const [files] = await bucket.getFiles({
                prefix,
                maxResults: Math.max(1, limit - arquivos.length),
                autoPaginate: false,
            });

            for (const file of files) {
                const metadata = file.metadata || {};
                arquivos.push({
                    nome: file.name.split('/').filter(Boolean).pop() || file.name,
                    path: file.name,
                    tamanho: firebaseSaudeInt(metadata.size),
                    contentType: metadata.contentType || '',
                    updated: metadata.updated || null,
                    prefixo: prefix,
                    pasta: file.name.endsWith('/'),
                });
            }
        }

        return { arquivos };
    }
);

exports.listarFunctionsFirebaseSaude = onCall(
    {
        region: 'us-central1',
        timeoutSeconds: 60,
        memory: '256MiB',
    },
    async (request) => {
        const adminAtual = await validarAdminFirebaseSaude(request);
        await registrarLogFirebaseSaude(adminAtual, 'listou_functions');

        return {
            functions: FIREBASE_SAUDE_FUNCTIONS_MANUAIS.map(([nome, descricao]) => ({
                nome,
                descricao,
                status: 'lista manual backend',
            })),
        };
    }
);



// ============================================
// CACHE DE PARTICIPANTES DE EVENTO FINALIZADO
// ============================================
function normalizarTexto(valor) {
    return String(valor || '')
        .trim()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase();
}

function stringLimpa(valor) {
    if (valor === undefined || valor === null) return null;
    const texto = String(valor).trim();
    if (!texto || texto.toLowerCase() === 'null') return null;
    return texto;
}

function pickFirstString(data, keys) {
    const source = data || {};
    for (const key of keys) {
        const clean = stringLimpa(source[key]);
        if (clean) return clean;
    }
    return null;
}

function extrairEventoIdParticipacao(data) {
    return pickFirstString(data, [
        'evento_id', 'eventoId', 'id_evento', 'evento_doc_id',
        'eventoDocId', 'idEvento',
    ]);
}

function extrairAlunoIdParticipacao(data) {
    return pickFirstString(data, [
        'aluno_id', 'alunoId', 'id_aluno', 'alunoDocId', 'aluno_doc_id',
    ]);
}

function extrairGraduacaoParticipacao(data) {
    return pickFirstString(data, [
        'graduacao', 'graduacao_nova', 'graduacaoNova', 'graduacao_atual',
        'graduacaoAtual', 'nova_graduacao', 'novaGraduacao', 'corda',
        'corda_recebida', 'cordaRecebida',
    ]);
}

function extrairCertificadoParticipacao(data) {
    return pickFirstString(data, [
        'link_certificado', 'linkCertificado', 'certificado_url', 'certificadoUrl',
        'url_certificado', 'urlCertificado', 'certificado', 'certificado_link',
        'certificadoLink', 'pdf_certificado', 'pdfCertificado',
        'arquivo_certificado', 'arquivoCertificado',
    ]);
}

async function verificarPermissaoCacheParticipantes(uid) {
    const usuarioDoc = await db.collection('usuarios').doc(uid).get();
    const usuarioData = usuarioDoc.exists ? usuarioDoc.data() || {} : {};
    const pesoPermissao = Number(usuarioData.peso_permissao || 0);
    const tipoUsuario = String(usuarioData.tipo || '').trim().toLowerCase();
    const adminUsuario = pesoPermissao >= 80 || ['admin', 'administrador', 'super_admin', 'superadmin'].includes(tipoUsuario);

    if (adminUsuario) return true;

    const permissoesDoc = await db
        .collection('usuarios')
        .doc(uid)
        .collection('permissoes_usuario')
        .doc('configuracoes')
        .get();
    const permissoes = permissoesDoc.exists ? permissoesDoc.data() || {} : {};

    return [
        'pode_gerenciar_participantes_evento',
        'pode_ver_participantes_evento',
        'pode_editar_evento',
        'pode_finalizar_evento',
    ].some((key) => permissoes[key] === true);
}

async function buscarEventoIdPorNome(nomeEvento) {
    const nome = stringLimpa(nomeEvento);
    if (!nome) return null;
    const snap = await db.collection('eventos').where('nome', '==', nome).limit(1).get();
    return snap.empty ? null : snap.docs[0].id;
}

async function buscarAlunoSnapshot(alunoId) {
    const id = stringLimpa(alunoId);
    if (!id) return {};
    const doc = await db.collection('alunos').doc(id).get();
    return doc.exists ? doc.data() || {} : {};
}

async function buscarGraduacaoSnapshot({ graduacaoId, nomeGraduacao }) {
    const id = stringLimpa(graduacaoId);
    if (id) {
        const doc = await db.collection('graduacoes').doc(id).get();
        if (doc.exists) return { id: doc.id, ...(doc.data() || {}) };
    }

    const nome = stringLimpa(nomeGraduacao);
    if (!nome) return null;

    for (const field of ['nome_graduacao', 'nome']) {
        const snap = await db.collection('graduacoes').where(field, '==', nome).limit(1).get();
        if (!snap.empty) {
            const doc = snap.docs[0];
            return { id: doc.id, ...(doc.data() || {}) };
        }
    }

    const all = await db.collection('graduacoes').limit(500).get();
    const normalized = normalizarTexto(nome);
    for (const doc of all.docs) {
        const data = doc.data() || {};
        const candidate = pickFirstString(data, ['nome_graduacao', 'nome']);
        if (normalizarTexto(candidate) === normalized) {
            return { id: doc.id, ...data };
        }
    }

    return null;
}

async function montarParticipanteCacheData({ participacaoId, participacaoData, eventoId, eventoData }) {
    const evento = eventoData || {};
    const alunoId = extrairAlunoIdParticipacao(participacaoData);
    const aluno = await buscarAlunoSnapshot(alunoId);
    const graduacaoId = pickFirstString(participacaoData, ['graduacao_id', 'graduacaoId']);
    const graduacaoTexto = extrairGraduacaoParticipacao(participacaoData) || pickFirstString(aluno, [
        'graduacao', 'graduacao_nome', 'nome_graduacao', 'corda',
    ]);
    const graduacao = await buscarGraduacaoSnapshot({ graduacaoId, nomeGraduacao: graduacaoTexto });

    return {
        participacao_id: participacaoId,
        aluno_id: alunoId,
        aluno_nome: pickFirstString(participacaoData, [
            'aluno_nome', 'alunoNome', 'nome_aluno', 'nomeAluno', 'nome',
        ]) || pickFirstString(aluno, [
            'aluno_nome', 'alunoNome', 'nome_aluno', 'nomeAluno', 'nome', 'nome_completo',
        ]) || 'Participante sem nome',
        aluno_foto_url: pickFirstString(participacaoData, [
            'aluno_foto_url', 'foto_perfil_aluno', 'foto_url', 'fotoUrl', 'photoURL',
            'avatar', 'avatar_url', 'imagem_url', 'foto',
        ]) || pickFirstString(aluno, [
            'aluno_foto_url', 'foto_perfil_aluno', 'foto_url', 'fotoUrl', 'photoURL',
            'avatar', 'avatar_url', 'imagem_url', 'foto',
        ]),
        evento_id: eventoId,
        evento_nome: pickFirstString(evento, ['nome']) || pickFirstString(participacaoData, [
            'evento_nome', 'eventoNome', 'nome_evento', 'nomeEvento',
        ]),
        tipo_evento: pickFirstString(evento, ['tipo']) || pickFirstString(participacaoData, [
            'tipo_evento', 'tipoEvento', 'tipo',
        ]),
        data_evento: evento.data || participacaoData.data_evento || participacaoData.dataEvento || participacaoData.data || null,
        status: pickFirstString(participacaoData, ['status', 'status_participacao', 'statusParticipacao']) || 'finalizado',
        graduacao: graduacaoTexto,
        graduacao_id: graduacaoId || (graduacao ? graduacao.id : null),
        graduacao_nome: pickFirstString(graduacao, ['nome_graduacao', 'nome']) || graduacaoTexto,
        graduacao_hex_cor1: pickFirstString(graduacao, ['hex_cor1', 'cor1', 'cor_1', 'hexCor1']),
        graduacao_hex_cor2: pickFirstString(graduacao, ['hex_cor2', 'cor2', 'cor_2', 'hexCor2']),
        graduacao_hex_ponta1: pickFirstString(graduacao, ['hex_ponta1', 'ponta1', 'cor_ponta1', 'hexPonta1']),
        graduacao_hex_ponta2: pickFirstString(graduacao, ['hex_ponta2', 'ponta2', 'cor_ponta2', 'hexPonta2']),
        link_certificado: extrairCertificadoParticipacao(participacaoData),
        origem_cache: 'cloud_function',
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
    };
}

async function commitOperacoesEmLotes(operacoes) {
    const limite = 450;
    for (let i = 0; i < operacoes.length; i += limite) {
        const batch = db.batch();
        for (const operacao of operacoes.slice(i, i + limite)) {
            operacao(batch);
        }
        await batch.commit();
    }
}

async function buscarParticipacoesDoEvento(eventoId, eventoData) {
    const collection = db.collection('participacoes_eventos');
    const result = new Map();

    async function addQuery(field, value) {
        const clean = stringLimpa(value);
        if (!clean) return;
        const snap = await collection.where(field, '==', clean).get();
        snap.forEach((doc) => result.set(doc.id, doc));
    }

    await addQuery('evento_id', eventoId);
    if (result.size === 0) await addQuery('eventoId', eventoId);
    if (result.size === 0) await addQuery('id_evento', eventoId);
    if (result.size === 0) await addQuery('evento_doc_id', eventoId);
    if (result.size === 0) await addQuery('eventoDocId', eventoId);
    if (result.size === 0) await addQuery('idEvento', eventoId);

    const eventoNome = pickFirstString(eventoData, ['nome']);
    if (result.size === 0) await addQuery('evento_nome', eventoNome);
    if (result.size === 0) await addQuery('eventoNome', eventoNome);
    if (result.size === 0) await addQuery('nome_evento', eventoNome);
    if (result.size === 0) await addQuery('nomeEvento', eventoNome);

    return result;
}

async function reconstruirCacheParticipantesEventoInterno(eventoId) {
    const cleanEventoId = stringLimpa(eventoId);
    if (!cleanEventoId) throw new HttpsError('invalid-argument', 'eventoId obrigatório.');

    const eventoRef = db.collection('eventos').doc(cleanEventoId);
    const eventoDoc = await eventoRef.get();
    if (!eventoDoc.exists) throw new HttpsError('not-found', 'Evento não encontrado.');

    const eventoData = eventoDoc.data() || {};
    const participacoes = await buscarParticipacoesDoEvento(cleanEventoId, eventoData);
    const cacheRef = eventoRef.collection('participantes_cache');
    const cacheAtual = await cacheRef.get();
    const idsParticipacoes = new Set(participacoes.keys());
    const operacoes = [];

    for (const [participacaoId, doc] of participacoes.entries()) {
        const cacheData = await montarParticipanteCacheData({
            participacaoId,
            participacaoData: doc.data() || {},
            eventoId: cleanEventoId,
            eventoData,
        });
        operacoes.push((batch) => batch.set(cacheRef.doc(participacaoId), cacheData, { merge: true }));
    }

    cacheAtual.forEach((doc) => {
        if (!idsParticipacoes.has(doc.id)) {
            operacoes.push((batch) => batch.delete(doc.ref));
        }
    });

    await commitOperacoesEmLotes(operacoes);

    return {
        success: true,
        eventoId: cleanEventoId,
        totalParticipantes: participacoes.size,
        cacheAtualizado: true,
    };
}

exports.reconstruirCacheParticipantesEvento = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Usuário não autenticado.');
    }

    const permitido = await verificarPermissaoCacheParticipantes(request.auth.uid);
    if (!permitido) {
        throw new HttpsError('permission-denied', 'Você não tem permissão para atualizar participantes do evento.');
    }

    const eventoId = request.data && request.data.eventoId;
    return reconstruirCacheParticipantesEventoInterno(eventoId);
});

exports.sincronizarCacheParticipacaoEvento = onDocumentWritten('participacoes_eventos/{participacaoId}', async (event) => {
    const participacaoId = event.params.participacaoId;
    const beforeData = event.data && event.data.before.exists ? event.data.before.data() || {} : null;
    const afterData = event.data && event.data.after.exists ? event.data.after.data() || {} : null;
    const source = afterData || beforeData || {};

    let eventoId = extrairEventoIdParticipacao(source);
    if (!eventoId) {
        eventoId = await buscarEventoIdPorNome(pickFirstString(source, [
            'evento_nome', 'eventoNome', 'nome_evento', 'nomeEvento',
        ]));
    }

    if (!eventoId) {
        console.log(`Cache participantes: participação ${participacaoId} sem evento identificável.`);
        return;
    }

    if (!afterData) {
        await db.collection('eventos').doc(eventoId).collection('participantes_cache').doc(participacaoId).delete();
        return;
    }

    const eventoDoc = await db.collection('eventos').doc(eventoId).get();
    const eventoData = eventoDoc.exists ? eventoDoc.data() || {} : {};
    const cacheData = await montarParticipanteCacheData({
        participacaoId,
        participacaoData: afterData,
        eventoId,
        eventoData,
    });

    await db.collection('eventos').doc(eventoId).collection('participantes_cache').doc(participacaoId).set(cacheData, { merge: true });
});

exports.reconstruirCacheAoAlterarEvento = onDocumentWritten('eventos/{eventoId}', async (event) => {
    const before = event.data && event.data.before.exists ? event.data.before.data() || {} : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() || {} : null;
    if (!after) return;

    const beforeStatus = before ? stringLimpa(before.status) : null;
    const afterStatus = stringLimpa(after.status);
    const finalizou = beforeStatus !== 'finalizado' && afterStatus === 'finalizado';
    const metadataMudou = before && afterStatus === 'finalizado' && [
        'nome', 'tipo', 'data', 'local', 'cidade',
    ].some((field) => JSON.stringify(before[field] || null) !== JSON.stringify(after[field] || null));

    if (!finalizou && !metadataMudou) return;

    await reconstruirCacheParticipantesEventoInterno(event.params.eventoId);
});

/**
 * Reconstrói o documento de metadados, distribuições e snapshots de alunos do Cache V2 do Dashboard de uma Turma.
 *
 * @param {Object} request - Objeto da requisição.
 * @param {string} request.data.turmaId - ID da turma.
 * @param {boolean} request.data.force - Se deve forçar o recálculo (reservado para v2 completa).
 * @returns {Promise<Object>} - Resultado da operação.
 */
exports.reconstruirDashboardTurmaCache = onCall(async (request) => {
    // 1. Validar autenticação
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Usuário não autenticado.');
    }

    const { turmaId, force } = request.data || {};

    // 2. Validar input
    if (!turmaId) {
        throw new HttpsError('invalid-argument', 'O campo "turmaId" é obrigatório.');
    }

    const metaRef = db.collection('turmas').doc(turmaId).collection('dashboard_cache').doc('meta');
    const distribuicoesRef = db.collection('turmas').doc(turmaId).collection('dashboard_cache').doc('distribuicoes');
    const cacheAlunosColl = db.collection('turmas').doc(turmaId).collection('dashboard_cache_alunos');

    try {
        console.log("[CacheV2] Reconstruindo turma", turmaId);

        // 3. Buscar dados básicos (Turma, Alunos, Graduacoes, Avaliacoes)
        const [turmaDoc, alunosSnap, graduacoesSnap, avaliacoesSnap] = await Promise.all([
            db.collection('turmas').doc(turmaId).get(),
            db.collection('alunos').where('turma_id', '==', turmaId).where('status_atividade', '==', 'ATIVO(A)').get(),
            db.collection('graduacoes').get(),
            db.collection('turmas').doc(turmaId).collection('avaliacoes_alunos').get()
        ]);

        if (!turmaDoc.exists) {
            throw new HttpsError('not-found', `Turma ${turmaId} não encontrada.`);
        }
        const turmaData = turmaDoc.data() || {};
        const turmaNome = turmaData.nome || turmaData.nome_turma || 'Turma sem nome';

        // 4. Mapear Graduações e Avaliações para lookup rápido
        const graduacoesMap = {};
        graduacoesSnap.forEach(doc => {
            const data = doc.data();
            graduacoesMap[doc.id] = { id: doc.id, ...data };
            if (data.nome_graduacao) {
                graduacoesMap[data.nome_graduacao.trim()] = { id: doc.id, ...data };
            }
        });

        const avaliacoesMap = {};
        avaliacoesSnap.forEach(doc => {
            avaliacoesMap[doc.id] = doc.data();
        });

        const alunosRaw = [];
        alunosSnap.forEach(doc => {
            alunosRaw.push({ id: doc.id, ...doc.data() });
        });

        console.log("[CacheV2] alunos ativos", alunosRaw.length);

        // 5. Buscar Logs de Presença REAIS da coleção log_presenca_alunos
        const studentLogsMap = {};
        const allStudentIds = alunosRaw.map(a => a.id);
        let totalLogsLidos = 0;
        let totalLogsUsados = 0;

        for (let i = 0; i < allStudentIds.length; i += 10) {
            const batchIds = allStudentIds.slice(i, i + 10);
            const logsSnap = await db.collection('log_presenca_alunos')
                .where('aluno_id', 'in', batchIds)
                .get();

            totalLogsLidos += logsSnap.size;

            logsSnap.forEach(doc => {
                const data = doc.data();
                const alunoId = data.aluno_id;

                // Só conta presenças válidas
                const v = data.presente ?? data.is_presente ?? data.presenca ?? data.status_presenca ?? data.status;
                const isPresente = v === true || v === 1 || v === '1' || v === 'true' || v === 'sim' || v === 'presente';

                if (isPresente) {
                    if (!studentLogsMap[alunoId]) studentLogsMap[alunoId] = [];
                    studentLogsMap[alunoId].push(data);
                    totalLogsUsados++;
                }
            });
        }

        console.log("[CacheV2] logs lidos", totalLogsLidos);
        console.log("[CacheV2] logs presentes usados", totalLogsUsados);

        // 6. Configuração de Datas e Períodos (Timezone Brasil)
        const tz = 'America/Sao_Paulo';
        const now = DateTime.now().setZone(tz);
        const currentYear = now.toFormat('yyyy');
        const currentMonthKey = now.toFormat('yyyy-MM');
        const currentWeekKey = `${now.weekYear}-W${String(now.weekNumber).padStart(2, '0')}`;

        // Início da semana limitada ao mês atual (Regra da Dashboard)
        const inicioSemanaISO = now.startOf('week');
        const inicioMesAtual = now.startOf('month');
        const inicioSemanaDashboard = DateTime.max(inicioSemanaISO, inicioMesAtual);

        console.log("[CacheV2] mesAtual", currentMonthKey, "semanaAtual", currentWeekKey, "anoAtual", currentYear);
        console.log("[CacheV2] inicioSemanaISO", inicioSemanaISO.toISO());
        console.log("[CacheV2] inicioMesAtual", inicioMesAtual.toISO());
        console.log("[CacheV2] inicioSemanaDashboard", inicioSemanaDashboard.toISO());

        const parseDataLog = (log) => {
            const candidatos = ['data_aula', 'data', 'data_chamada', 'dataChamada', 'createdAt', 'criado_em'];
            for (const c of candidatos) {
                const val = log[c];
                if (!val) continue;
                if (val.toDate) return DateTime.fromJSDate(val.toDate()).setZone(tz);
                if (val instanceof Date) return DateTime.fromJSDate(val).setZone(tz);
                if (typeof val === 'string') {
                    const dt = DateTime.fromISO(val, { zone: tz });
                    if (dt.isValid) return dt;
                    // Tenta dd/MM/yyyy se ISO falhar
                    const dt2 = DateTime.fromFormat(val, 'dd/MM/yyyy', { zone: tz });
                    if (dt2.isValid) return dt2;
                }
            }
            return null;
        };

        const normalizarDia = (dt) => {
            const dias = { 1: 'seg', 2: 'ter', 3: 'qua', 4: 'qui', 5: 'sex', 6: 'sab', 7: 'dom' };
            return dias[dt.weekday] || 'seg';
        };

        const anosDisponiveisSet = new Set();
        let maxFreqTotal = 0;
        let maxFreqSemana = 0;
        let maxFreqMes = 0;
        let maxFreqAno = 0;

        // 7. Processamento dos Alunos e Cálculo de Frequência do Zero
        const processedAlunos = alunosRaw.map((aluno, index) => {
            const logs = studentLogsMap[aluno.id] || [];
            const avaliacao = avaliacoesMap[aluno.id] || {};

            const fTotal = logs.length;
            let fSemana = 0;
            let fMes = 0;
            let fAno = 0;
            const fPorAno = {};
            const fPorMes = {};
            const fPorSemana = {};
            const fPorDiaSemana = { 'seg': 0, 'ter': 0, 'qua': 0, 'qui': 0, 'sex': 0, 'sab': 0, 'dom': 0 };

            logs.forEach(log => {
                const dt = parseDataLog(log);
                if (dt) {
                    const y = dt.toFormat('yyyy');
                    const m = dt.toFormat('yyyy-MM');
                    const w = `${dt.weekYear}-W${String(dt.weekNumber).padStart(2, '0')}`;
                    const d = normalizarDia(dt);

                    fPorAno[y] = (fPorAno[y] || 0) + 1;
                    fPorMes[m] = (fPorMes[m] || 0) + 1;
                    fPorSemana[w] = (fPorSemana[w] || 0) + 1;
                    fPorDiaSemana[d] = (fPorDiaSemana[d] || 0) + 1;

                    if (y === currentYear) fAno++;
                    if (m === currentMonthKey) fMes++;

                    // Lógica de Semana Corrigida: dentro da semana ISO AND dentro do mês atual
                    if (dt >= inicioSemanaDashboard && dt <= now) {
                        fSemana++;
                    }

                    anosDisponiveisSet.add(y);
                }
            });

            if (fTotal > maxFreqTotal) maxFreqTotal = fTotal;
            if (fSemana > maxFreqSemana) maxFreqSemana = fSemana;
            if (fMes > maxFreqMes) maxFreqMes = fMes;
            if (fAno > maxFreqAno) maxFreqAno = fAno;

            // Perfil
            const nome = (aluno.nome || aluno.nome_completo || 'Sem nome').trim();
            const nome_busca = nome.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");

            const extrairFotoUrl = (data) => {
                const campos = [
                    'foto_perfil_aluno', 'foto_url', 'aluno_foto', 'foto', 'foto_perfil',
                    'fotoPerfil', 'fotoPerfilAluno', 'photoUrl', 'imageUrl', 'avatarUrl',
                    'url_foto', 'imagem_url'
                ];
                for (const campo of campos) {
                    const valor = String(data[campo] || '').trim();
                    if (valor && valor.startsWith('http')) return valor;
                }
                return '';
            };

            const foto_url = extrairFotoUrl(aluno);

            let sexo_normalizado = 'NAO_INFORMADO';
            const s = (aluno.sexo || '').toUpperCase();
            if (s === 'MASCULINO' || s === 'M') sexo_normalizado = 'MASCULINO';
            else if (s === 'FEMININO' || s === 'F') sexo_normalizado = 'FEMININO';
            else if (s === 'OUTRO') sexo_normalizado = 'OUTRO';

            const idade = calcularIdade(aluno.data_nascimento);
            const faixa_idade = determinarFaixaEtaria(idade);

            // Graduação
            let gradData = null;
            if (aluno.graduacao_id && graduacoesMap[aluno.graduacao_id]) {
                gradData = graduacoesMap[aluno.graduacao_id];
            } else if (aluno.graduacao_nome && graduacoesMap[aluno.graduacao_nome.trim()]) {
                gradData = graduacoesMap[aluno.graduacao_nome.trim()];
            } else if (aluno.graduacao_atual && graduacoesMap[aluno.graduacao_atual.trim()]) {
                gradData = graduacoesMap[aluno.graduacao_atual.trim()];
            }

            const graduacao_nome = gradData ? gradData.nome_graduacao : "SEM GRADUAÇÃO";
            const graduacao_nivel = gradData ? (gradData.nivel_graduacao || 0) : 0;
            const hex_cor1 = gradData ? (gradData.hex_cor1 || '#FFFFFF') : '#FFFFFF';
            const hex_cor2 = gradData ? (gradData.hex_cor2 || '#FFFFFF') : '#FFFFFF';
            const hex_ponta1 = gradData ? (gradData.hex_ponta1 || '#FFFFFF') : '#FFFFFF';
            const hex_ponta2 = gradData ? (gradData.hex_ponta2 || '#FFFFFF') : '#FFFFFF';

            if (index < 5) {
                console.log("[CacheV2] aluno", nome, "total", fTotal, "mes", fMes, "semana", fSemana);
            }

            return {
                aluno_id: aluno.id,
                turma_id: turmaId,
                nome,
                nome_busca,
                foto_url,
                sexo: aluno.sexo || '',
                sexo_normalizado,
                data_nascimento: aluno.data_nascimento || null,
                idade,
                faixa_idade,
                ativo: true,
                graduacao_id: aluno.graduacao_id || (gradData ? gradData.id : null),
                graduacao_nome,
                graduacao_nivel,
                hex_cor1,
                hex_cor2,
                hex_ponta1,
                hex_ponta2,
                freq_total: fTotal,
                freq_semana: fSemana,
                freq_mes: fMes,
                freq_ano: fAno,
                freq_por_ano: fPorAno,
                freq_por_mes: fPorMes,
                freq_por_semana: fPorSemana,
                freq_por_dia_semana: fPorDiaSemana,
                mes_key_atual: currentMonthKey,
                semana_key_atual: currentWeekKey,
                semana_dashboard_inicio: inicioSemanaDashboard.toISO(),
                semana_regra: "semana_atual_limitada_ao_mes",
                ano_key_atual: currentYear,
                frequencia_origem: "log_presenca_alunos",
                frequencia_recalculada_em: admin.firestore.FieldValue.serverTimestamp(),
                avaliacao_nota: parseFloat(avaliacao.nota_final || 0),
                avaliacao_conceito: avaliacao.conceito || "Sem avaliação"
            };
        });

        // 8. Cálculo de Scores de Destaque (60/40)
        processedAlunos.forEach(aluno => {
            const calcScore = (freq, max) => {
                const score_freq = max <= 0 ? 0 : (freq / max) * 10;
                return parseFloat(((aluno.avaliacao_nota * 0.60) + (score_freq * 0.40)).toFixed(2));
            };

            aluno.destaque_score_total = calcScore(aluno.freq_total, maxFreqTotal);
            aluno.destaque_score_semana = calcScore(aluno.freq_semana, maxFreqSemana);
            aluno.destaque_score_mes = calcScore(aluno.freq_mes, maxFreqMes);
            aluno.destaque_score_por_ano = calcScore(aluno.freq_ano, maxFreqAno);
        });

        // 9. Cálculo de Rankings
        const sortByScore = (field) => [...processedAlunos].sort((a, b) => b[field] - a[field]);
        const rankTotal = sortByScore('destaque_score_total');
        const rankSemana = sortByScore('destaque_score_semana');
        const rankMes = sortByScore('destaque_score_mes');
        const rankAno = sortByScore('destaque_score_por_ano');

        processedAlunos.forEach(aluno => {
            aluno.ranking_total = rankTotal.findIndex(a => a.aluno_id === aluno.aluno_id) + 1;
            aluno.ranking_semana = rankSemana.findIndex(a => a.aluno_id === aluno.aluno_id) + 1;
            aluno.ranking_mes = rankMes.findIndex(a => a.aluno_id === aluno.aluno_id) + 1;
            aluno.ranking_por_ano = rankAno.findIndex(a => a.aluno_id === aluno.aluno_id) + 1;
        });

        // 10. Distribuições e Top Lists
        const dist_idade = { '4-7 anos': 0, '8-12 anos': 0, '13-17 anos': 0, '18-25 anos': 0, '26-35 anos': 0, '36-50 anos': 0, '50+ anos': 0, 'NAO_INFORMADA': 0 };
        const dist_sexo = { 'MASCULINO': 0, 'FEMININO': 0, 'OUTRO': 0, 'NAO_INFORMADO': 0 };
        const dist_graduacao = {};

        processedAlunos.forEach(aluno => {
            dist_idade[aluno.faixa_idade] = (dist_idade[aluno.faixa_idade] || 0) + 1;
            dist_sexo[aluno.sexo_normalizado]++;
            dist_graduacao[aluno.graduacao_nome] = (dist_graduacao[aluno.graduacao_nome] || 0) + 1;
        });

        const getTop10Destaque = (list, scoreField, rankField) => list.slice(0, 10).map(a => ({
            aluno_id: a.aluno_id,
            nome: a.nome,
            foto_url: a.foto_url,
            score: a[scoreField],
            nota_final: a[scoreField],
            posicao: a[rankField]
        }));

        const getTop5Freq = (list, freqField) => [...list].sort((a, b) => b[freqField] - a[freqField]).slice(0, 5).map(a => ({
            aluno_id: a.aluno_id,
            nome: a.nome,
            valor: a[freqField]
        }));

        const distribuicoesData = {
            idade: dist_idade,
            sexo: dist_sexo,
            graduacao: dist_graduacao,
            frequencia_top5_total: getTop5Freq(processedAlunos, 'freq_total'),
            frequencia_top5_semana: getTop5Freq(processedAlunos, 'freq_semana'),
            frequencia_top5_mes: getTop5Freq(processedAlunos, 'freq_mes'),
            frequencia_top5_por_ano: getTop5Freq(processedAlunos, 'freq_ano'),
            ranking_destaque_top10_total: getTop10Destaque(rankTotal, 'destaque_score_total', 'ranking_total'),
            ranking_destaque_top10_semana: getTop10Destaque(rankSemana, 'destaque_score_semana', 'ranking_semana'),
            ranking_destaque_top10_mes: getTop10Destaque(rankMes, 'destaque_score_mes', 'ranking_mes'),
            ranking_destaque_top10_por_ano: getTop10Destaque(rankAno, 'destaque_score_por_ano', 'ranking_por_ano'),
            cache_versao: 200,
            cache_modelo: "dashboard_cache_v2_distribuicoes",
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            origem_cache: "cloud_function"
        };

        // 11. Resumo Meta
        const avg = (list, field) => list.length === 0 ? 0 : parseFloat((list.reduce((s, a) => s + a[field], 0) / list.length).toFixed(2));
        const best = (list, field) => list.length === 0 ? null : list.reduce((p, c) => (c[field] > (p ? p[field] : -1)) ? c : p, null);

        const metaResumo = (periodList, freqField) => {
            const b = best(periodList, freqField);
            return {
                media_frequencia: avg(periodList, freqField),
                melhor_aluno_id: b ? b.aluno_id : null,
                melhor_aluno_nome: b ? b.nome : null,
                melhor_aluno_presencas: b ? b[freqField] : 0
            };
        };

        const metaData = {
            turma_id: turmaId,
            turma_nome: turmaNome,
            total_alunos: processedAlunos.length,
            anos_disponiveis: Array.from(anosDisponiveisSet).sort((a, b) => b - a),
            cache_versao: 200,
            cache_modelo: "dashboard_cache_v2_completo_inicial",
            status_processamento: "pronto",
            necessita_reconstrucao: false,
            erro_processamento: null,
            origem_cache: "cloud_function",
            resumo_total: metaResumo(processedAlunos, 'freq_total'),
            resumo_semana: metaResumo(processedAlunos, 'freq_semana'),
            resumo_mes: metaResumo(processedAlunos, 'freq_mes'),
            resumo_por_ano: metaResumo(processedAlunos, 'freq_ano'),
            ultima_reconstrucao: admin.firestore.FieldValue.serverTimestamp(),
            ultima_atualizacao: admin.firestore.FieldValue.serverTimestamp()
        };

        // 12. Gravação em Batch
        const writes = [];

        processedAlunos.forEach(aluno => {
            // Snapshot Cache V2
            const data = {
                ...aluno,
                cache_versao: 200,
                cache_modelo: "dashboard_cache_v2_alunos",
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                origem_cache: "cloud_function"
            };
            delete data.freq_ano;
            writes.push((b) => b.set(cacheAlunosColl.doc(aluno.aluno_id), data, { merge: true }));

            // Sincronizar Contador Legado (Opcional, mas recomendado)
            const legacyRef = db.collection('alunos').doc(aluno.aluno_id).collection('contadores').doc('frequencia_dashboard');
            const legacyData = {
                total: aluno.freq_total,
                semana: aluno.freq_semana,
                mes: aluno.freq_mes,
                porAno: aluno.freq_por_ano,
                porMes: aluno.freq_por_mes,
                porSemana: aluno.freq_por_semana,
                porDiaSemana: aluno.freq_por_dia_semana,
                ...aluno.freq_por_dia_semana, // seg, ter, qua...
                ultima_sync_logs: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                cache_versao: 6,
                modelo: "contador_recalculado_cloud_function_cache_v2",
                recalculado_completo: true
            };
            writes.push((b) => b.set(legacyRef, legacyData, { merge: true }));
        });

        writes.push((b) => b.set(distribuicoesRef, distribuicoesData, { merge: true }));
        writes.push((b) => b.set(metaRef, metaData, { merge: true }));

        // Limpeza de snapshots órfãos
        const existingCacheSnap = await cacheAlunosColl.get();
        const currentIds = new Set(processedAlunos.map(a => a.aluno_id));
        existingCacheSnap.forEach(doc => {
            if (!currentIds.has(doc.id)) {
                writes.push((b) => b.delete(doc.ref));
            }
        });

        await executarBatchWrites(writes);

        console.log(`✅ Dashboard Cache V2 reconstruído para turma ${turmaId} (${turmaNome}) - Total alunos: ${processedAlunos.length}`);

        return {
            success: true,
            turmaId,
            totalAlunos: processedAlunos.length,
            totalSnapshots: processedAlunos.length,
            cacheVersao: 200,
            message: "Dashboard Cache V2 reconstruído do zero pelos logs reais."
        };

    } catch (error) {
        console.error(`❌ Erro ao reconstruir dashboard para turma ${turmaId}:`, error);

        try {
            const metaRef = db.collection('turmas').doc(turmaId).collection('dashboard_cache').doc('meta');
            await metaRef.set({
                status_processamento: "erro",
                erro_processamento: error.message || String(error),
                necessita_reconstrucao: true,
                ultima_atualizacao: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
        } catch (dbError) {
            console.error('❌ Erro crítico ao gravar status de erro no Firestore:', dbError);
        }

        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', error.message || 'Erro interno ao reconstruir cache.');
    }
});
