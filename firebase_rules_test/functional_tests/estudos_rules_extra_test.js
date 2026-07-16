const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

const {
  doc,
  collection,
  query,
  orderBy,
  limit,
  setDoc,
  updateDoc,
  deleteDoc,
  writeBatch,
  getDoc,
  getDocs,
  where,
} = require("firebase/firestore");

const PROJECT_ID = "demo-uai-capoeira-rules-extra";
const RULES_PATH = path.resolve(__dirname, "../firestore.rules");

async function main() {
  console.log("Iniciando testes extras das Firestore Rules...");
  console.log("Rules:", RULES_PATH);

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8085,
    },
  });

  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, "estudos_config/global"), {
      ativo: true,
      mostrarCardAreaAluno: true,
      mostrarEmBreve: true,
    });

    await setDoc(doc(db, "usuarios/admin_uid"), {
      tipo: "admin",
      peso_permissao: 100,
      status_conta: "ativa",
    });

    await setDoc(doc(db, "usuarios/perm_uid"), {
      tipo: "usuario",
      peso_permissao: 10,
      status_conta: "ativa",
    });

    await setDoc(doc(db, "usuarios/perm_uid/permissoes_usuario/configuracoes"), {
      pode_gerenciar_estudos_fundamentos: true,
    });

    await setDoc(doc(db, "usuarios/avaliador_uid"), {
      tipo: "usuario",
      peso_permissao: 10,
      status_conta: "ativa",
    });

    await setDoc(doc(db, "usuarios/avaliador_uid/permissoes_usuario/configuracoes"), {
      pode_avaliar_aluno: true,
    });
    await setDoc(doc(db, "usuarios/aluno_uid"), {
      tipo: "aluno",
      peso_permissao: 0,
      status_conta: "ativa",
    });

    await setDoc(doc(db, "usuarios/outro_uid"), {
      tipo: "aluno",
      peso_permissao: 0,
      status_conta: "ativa",
    });

    await setDoc(doc(db, "usuarios/aluno_uid/temas_personalizados/tema_existente"), {
      nome: "Tema Existente",
      descricao: "Tema salvo para testes",
      primary: "#547A3B",
      background: "#07100B",
      surface: "#0E1A12",
      card: "#142219",
      textPrimary: "#F4F0D8",
      atualizadoEm: new Date("2026-07-14T12:00:00.000Z"),
    });

    await setDoc(doc(db, "temas_globais/tema_global_liberado"), {
      nome: "Tema Global Liberado",
      descricao: "Tema global disponivel para usuarios",
      ativo: true,
      disponivelParaUsuarios: true,
      disponivelParaEstudos: false,
      origem: "global_nuvem",
      primary: "#547A3B",
      background: "#07100B",
      surface: "#0E1A12",
      card: "#142219",
      textPrimary: "#F4F0D8",
      atualizadoEm: new Date("2026-07-15T12:00:00.000Z"),
    });

    await setDoc(doc(db, "temas_globais/tema_global_inativo"), {
      nome: "Tema Global Inativo",
      ativo: false,
      disponivelParaUsuarios: true,
      origem: "global_nuvem",
      primary: "#8B4A24",
      background: "#120D09",
      surface: "#1E1510",
      card: "#2B1D15",
      textPrimary: "#F8E6CF",
      atualizadoEm: new Date("2026-07-15T11:00:00.000Z"),
    });

    await setDoc(doc(db, "temas_globais/tema_global_indisponivel"), {
      nome: "Tema Global Indisponivel",
      ativo: true,
      disponivelParaUsuarios: false,
      origem: "global_nuvem",
      primary: "#C0A052",
      background: "#07100B",
      surface: "#0E1A12",
      card: "#142219",
      textPrimary: "#F4F0D8",
      atualizadoEm: new Date("2026-07-15T10:00:00.000Z"),
    });

    await setDoc(doc(db, "alunos/aluno_001"), {
      nome: "Aluno Teste",
      areaAlunoGoogleVinculado: true,
      areaAlunoGoogleUid: "aluno_uid",
    });

    await setDoc(doc(db, "estudos_ciclos/ciclo_001"), {
      titulo: "Ciclo Publicado",
      status: "publicado",
      mostrarNaLinhaDoTempo: true,
    });

    await setDoc(doc(db, "estudos/estudo_rascunho"), {
      titulo: "Estudo Rascunho",
      cicloId: "ciclo_001",
      status: "rascunho",
      mostrarNaLinhaDoTempo: true,
    });

    await setDoc(doc(db, "estudos/estudo_em_breve"), {
      titulo: "Estudo Em Breve",
      cicloId: "ciclo_001",
      status: "em_breve",
      mostrarNaLinhaDoTempo: true,
    });

    await setDoc(doc(db, "estudos_gabaritos/pergunta_extra"), {
      perguntaId: "pergunta_extra",
      estudoId: "estudo_em_breve",
      alternativaCorretaId: "a",
      justificativaCorreta: "Gabarito sensivel.",
    });
  });

  const adminDb = testEnv.authenticatedContext("admin_uid").firestore();
  const permDb = testEnv.authenticatedContext("perm_uid").firestore();
  const avaliadorDb = testEnv.authenticatedContext("avaliador_uid").firestore();
  const alunoDb = testEnv.authenticatedContext("aluno_uid").firestore();
  const outroDb = testEnv.authenticatedContext("outro_uid").firestore();
  const anonDb = testEnv.unauthenticatedContext().firestore();

  console.log("Teste extra 1: usuario com permissao granular consegue ler gabarito...");
  await assertSucceeds(getDoc(doc(permDb, "estudos_gabaritos/pergunta_extra")));

  console.log("Teste extra 2: aluno NAO consegue escrever gabarito...");
  await assertFails(
    setDoc(doc(alunoDb, "estudos_gabaritos/pergunta_extra_aluno"), {
      perguntaId: "pergunta_extra_aluno",
      estudoId: "estudo_em_breve",
      alternativaCorretaId: "a",
    })
  );

  console.log("Teste extra 3: usuario com permissao granular cria pergunta segura...");
  await assertSucceeds(
    setDoc(doc(permDb, "estudos_perguntas/pergunta_segura"), {
      cicloId: "ciclo_001",
      estudoId: "estudo_em_breve",
      enunciado: "Pergunta segura sem gabarito",
      tipo: "multipla_escolha",
      status: "ativa",
      alternativasPublicas: [
        { id: "a", texto: "Alternativa A", ordem: 1 },
        { id: "b", texto: "Alternativa B", ordem: 2 },
      ],
    })
  );

  console.log("Teste extra 4: usuario com permissao NAO consegue criar pergunta com respostaCorreta...");
  await assertFails(
    setDoc(doc(permDb, "estudos_perguntas/pergunta_insegura"), {
      cicloId: "ciclo_001",
      estudoId: "estudo_em_breve",
      enunciado: "Pergunta insegura",
      tipo: "multipla_escolha",
      status: "ativa",
      alternativasPublicas: [
        { id: "a", texto: "Alternativa A", ordem: 1 },
        { id: "b", texto: "Alternativa B", ordem: 2 },
      ],
      respostaCorreta: "a",
    })
  );

  console.log("Teste extra 5: admin consegue ler estudo rascunho...");
  await assertSucceeds(getDoc(doc(adminDb, "estudos/estudo_rascunho")));

  console.log("Teste extra 6: aluno consegue ler estudo em_breve quando mostrarEmBreve=true...");
  await assertSucceeds(getDoc(doc(alunoDb, "estudos/estudo_em_breve")));

  console.log("Alterando config para mostrarEmBreve=false...");
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "estudos_config/global"), {
      ativo: true,
      mostrarCardAreaAluno: true,
      mostrarEmBreve: false,
    });
  });

  console.log("Teste extra 7: aluno NAO consegue ler estudo em_breve quando mostrarEmBreve=false...");
  await assertFails(getDoc(doc(alunoDb, "estudos/estudo_em_breve")));

  console.log("Teste extra 8: anonimo NAO consegue ler config do modulo...");
  await assertFails(getDoc(doc(anonDb, "estudos_config/global")));

  console.log("Teste extra 9: aluno NAO consegue escrever config do modulo...");
  await assertFails(
    setDoc(doc(alunoDb, "estudos_config/global"), {
      ativo: false,
      mostrarCardAreaAluno: false,
      mostrarEmBreve: false,
    })
  );

  console.log("Teste extra 10: usuario com permissao granular consegue atualizar config...");
  await assertSucceeds(
    setDoc(doc(permDb, "estudos_config/global"), {
      ativo: true,
      mostrarCardAreaAluno: true,
      mostrarEmBreve: true,
    })
  );

  console.log("Teste extra 11: dono consegue ler tema personalizado proprio...");
  await assertSucceeds(
    getDoc(doc(alunoDb, "usuarios/aluno_uid/temas_personalizados/tema_existente"))
  );

  console.log("Teste extra 12: query do app lista temas personalizados do proprio usuario...");
  await assertSucceeds(
    getDocs(
      query(
        collection(alunoDb, "usuarios/aluno_uid/temas_personalizados"),
        orderBy("atualizadoEm", "desc"),
        limit(40)
      )
    )
  );

  console.log("Teste extra 13: dono consegue criar tema personalizado proprio...");
  await assertSucceeds(
    setDoc(doc(alunoDb, "usuarios/aluno_uid/temas_personalizados/tema_novo"), {
      nome: "Tema Novo",
      descricao: "Criado pelo dono",
      primary: "#C0A052",
      background: "#07100B",
      surface: "#0E1A12",
      card: "#142219",
      textPrimary: "#F4F0D8",
      atualizadoEm: new Date("2026-07-15T12:00:00.000Z"),
    })
  );

  console.log("Teste extra 14: dono consegue editar tema personalizado proprio...");
  await assertSucceeds(
    updateDoc(doc(alunoDb, "usuarios/aluno_uid/temas_personalizados/tema_novo"), {
      descricao: "Atualizado pelo dono",
      atualizadoEm: new Date("2026-07-15T12:05:00.000Z"),
    })
  );

  console.log("Teste extra 15: dono consegue excluir tema personalizado proprio...");
  await assertSucceeds(
    deleteDoc(doc(alunoDb, "usuarios/aluno_uid/temas_personalizados/tema_novo"))
  );

  console.log("Teste extra 16: outro usuario NAO consegue ler tema alheio...");
  await assertFails(
    getDoc(doc(outroDb, "usuarios/aluno_uid/temas_personalizados/tema_existente"))
  );

  console.log("Teste extra 17: outro usuario NAO consegue escrever tema alheio...");
  await assertFails(
    setDoc(doc(outroDb, "usuarios/aluno_uid/temas_personalizados/tema_invasor"), {
      nome: "Tema Invasor",
      atualizadoEm: new Date("2026-07-15T12:10:00.000Z"),
    })
  );

  console.log("Teste extra 18: anonimo NAO consegue ler tema personalizado...");
  await assertFails(
    getDoc(doc(anonDb, "usuarios/aluno_uid/temas_personalizados/tema_existente"))
  );

  console.log("Teste extra 19: anonimo NAO consegue escrever tema personalizado...");
  await assertFails(
    setDoc(doc(anonDb, "usuarios/aluno_uid/temas_personalizados/tema_anonimo"), {
      nome: "Tema Anonimo",
      atualizadoEm: new Date("2026-07-15T12:15:00.000Z"),
    })
  );

  console.log("Teste extra 20: admin consegue ler tema personalizado de usuario...");
  await assertSucceeds(
    getDoc(doc(adminDb, "usuarios/aluno_uid/temas_personalizados/tema_existente"))
  );

  console.log("Teste extra 21: admin consegue gerenciar tema personalizado de usuario...");
  await assertSucceeds(
    setDoc(doc(adminDb, "usuarios/aluno_uid/temas_personalizados/tema_admin"), {
      nome: "Tema Admin",
      descricao: "Gerenciado pelo admin",
      atualizadoEm: new Date("2026-07-15T12:20:00.000Z"),
    })
  );
  console.log("Teste extra 22: usuario autenticado le tema global ativo e disponivel...");
  await assertSucceeds(
    getDoc(doc(alunoDb, "temas_globais/tema_global_liberado"))
  );

  console.log("Teste extra 23: usuario autenticado NAO le tema global inativo...");
  await assertFails(
    getDoc(doc(alunoDb, "temas_globais/tema_global_inativo"))
  );

  console.log("Teste extra 24: usuario autenticado NAO le tema global indisponivel...");
  await assertFails(
    getDoc(doc(alunoDb, "temas_globais/tema_global_indisponivel"))
  );

  console.log("Teste extra 25: query real lista temas globais ativos e disponiveis...");
  await assertSucceeds(
    getDocs(
      query(
        collection(alunoDb, "temas_globais"),
        where("ativo", "==", true),
        where("disponivelParaUsuarios", "==", true),
        orderBy("atualizadoEm", "desc"),
        limit(40)
      )
    )
  );

  console.log("Teste extra 26: usuario comum NAO cria tema global...");
  await assertFails(
    setDoc(doc(alunoDb, "temas_globais/tema_global_usuario"), {
      nome: "Tema Global Usuario",
      ativo: true,
      disponivelParaUsuarios: true,
      atualizadoEm: new Date("2026-07-15T12:30:00.000Z"),
    })
  );

  console.log("Teste extra 27: usuario comum NAO edita tema global...");
  await assertFails(
    updateDoc(doc(alunoDb, "temas_globais/tema_global_liberado"), {
      descricao: "Alteracao indevida",
    })
  );

  console.log("Teste extra 28: usuario comum NAO exclui tema global...");
  await assertFails(
    deleteDoc(doc(alunoDb, "temas_globais/tema_global_liberado"))
  );

  console.log("Teste extra 29: anonimo NAO le tema global...");
  await assertFails(
    getDoc(doc(anonDb, "temas_globais/tema_global_liberado"))
  );

  console.log("Teste extra 30: anonimo NAO escreve tema global...");
  await assertFails(
    setDoc(doc(anonDb, "temas_globais/tema_global_anonimo"), {
      nome: "Tema Global Anonimo",
      ativo: true,
      disponivelParaUsuarios: true,
      atualizadoEm: new Date("2026-07-15T12:35:00.000Z"),
    })
  );

  console.log("Teste extra 31: admin le todos os temas globais...");
  await assertSucceeds(getDoc(doc(adminDb, "temas_globais/tema_global_liberado")));
  await assertSucceeds(getDoc(doc(adminDb, "temas_globais/tema_global_inativo")));
  await assertSucceeds(getDoc(doc(adminDb, "temas_globais/tema_global_indisponivel")));

  console.log("Teste extra 32: admin cria tema global...");
  await assertSucceeds(
    setDoc(doc(adminDb, "temas_globais/tema_global_admin"), {
      nome: "Tema Global Admin",
      descricao: "Criado pelo admin",
      ativo: true,
      disponivelParaUsuarios: true,
      origem: "global_nuvem",
      primary: "#C0A052",
      background: "#07100B",
      surface: "#0E1A12",
      card: "#142219",
      textPrimary: "#F4F0D8",
      atualizadoEm: new Date("2026-07-15T12:40:00.000Z"),
    })
  );

  console.log("Teste extra 33: admin edita tema global...");
  await assertSucceeds(
    updateDoc(doc(adminDb, "temas_globais/tema_global_admin"), {
      descricao: "Editado pelo admin",
      atualizadoEm: new Date("2026-07-15T12:45:00.000Z"),
    })
  );

  console.log("Teste extra 34: admin desativa/arquiva tema global...");
  await assertSucceeds(
    updateDoc(doc(adminDb, "temas_globais/tema_global_admin"), {
      ativo: false,
      disponivelParaUsuarios: false,
      arquivado: true,
      atualizadoEm: new Date("2026-07-15T12:50:00.000Z"),
    })
  );
  console.log("Teste extra 35: admin cria ciclo de avaliacao...");
  await assertSucceeds(setDoc(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07"), {
    id: "2026_07",
    nome: "Julho 2026",
    ano: 2026,
    mes: 7,
    status: "aberto",
    total_avaliacoes: 0,
  }));

  console.log("Teste extra 36: admin lista ciclos de avaliacao...");
  await assertSucceeds(getDocs(query(collection(adminDb, "turmas/turma_001/ciclos_avaliacao"), orderBy("ano", "desc"), orderBy("mes", "desc"))));

  console.log("Teste extra 37: admin fecha e reabre ciclo...");
  await assertSucceeds(updateDoc(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07"), { status: "fechado" }));
  await assertSucceeds(updateDoc(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07"), { status: "aberto" }));

  console.log("Teste extra 38: admin cria avaliacao do ciclo...");
  await assertSucceeds(setDoc(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_001"), {
    aluno_id: "aluno_001",
    nota_final: 8.5,
    status: "avaliado",
  }));

  console.log("Teste extra 39: admin cria historico da avaliacao...");
  await assertSucceeds(setDoc(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_001/historico/hist_admin"), {
    aluno_id: "aluno_001",
    nota_final: 8.5,
    tipo: "primeira_avaliacao",
  }));

  console.log("Teste extra 40: admin salva resumo de avaliacao do aluno...");
  await assertSucceeds(setDoc(doc(adminDb, "turmas/turma_001/avaliacoes_alunos/aluno_001"), {
    aluno_id: "aluno_001",
    aluno_nome: "Aluno Teste",
    ultima_nota: 8.5,
  }));

  console.log("Teste extra 41: usuario com pode_avaliar_aluno lista ciclos...");
  await assertSucceeds(getDocs(collection(avaliadorDb, "turmas/turma_001/ciclos_avaliacao")));

  console.log("Teste extra 42: usuario com pode_avaliar_aluno cria e atualiza avaliacao...");
  await assertSucceeds(setDoc(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_002"), {
    aluno_id: "aluno_002",
    nota_final: 7.0,
    status: "avaliado",
  }));
  await assertSucceeds(updateDoc(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_002"), {
    nota_final: 7.5,
  }));

  console.log("Teste extra 43: usuario com pode_avaliar_aluno cria historico...");
  await assertSucceeds(setDoc(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_002/historico/hist_avaliador"), {
    aluno_id: "aluno_002",
    nota_final: 7.5,
    tipo: "atualizacao",
  }));

  console.log("Teste extra 44: usuario com pode_avaliar_aluno salva resumo...");
  await assertSucceeds(setDoc(doc(avaliadorDb, "turmas/turma_001/avaliacoes_alunos/aluno_002"), {
    aluno_id: "aluno_002",
    aluno_nome: "Aluno Dois",
    ultima_nota: 7.5,
  }));

  console.log("Teste extra 45: usuario logado sem permissao NAO cria ciclo...");
  await assertFails(setDoc(doc(alunoDb, "turmas/turma_001/ciclos_avaliacao/2026_08"), {
    id: "2026_08",
    nome: "Agosto 2026",
  }));

  console.log("Teste extra 46: usuario logado sem permissao NAO cria avaliacao...");
  await assertFails(setDoc(doc(alunoDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_003"), {
    aluno_id: "aluno_003",
    nota_final: 9,
  }));

  console.log("Teste extra 47: usuario logado sem permissao NAO cria historico...");
  await assertFails(setDoc(doc(alunoDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_001/historico/hist_sem_permissao"), {
    aluno_id: "aluno_001",
    nota_final: 9,
  }));

  console.log("Teste extra 48: anonimo NAO le nem escreve avaliacao administrativa...");
  await assertFails(getDocs(collection(anonDb, "turmas/turma_001/ciclos_avaliacao")));
  await assertFails(setDoc(doc(anonDb, "turmas/turma_001/ciclos_avaliacao/2026_09"), { id: "2026_09" }));

  console.log("Teste extra 49: delete de avaliacao/historico negado para professor nao-admin...");
  await assertFails(deleteDoc(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_002")));
  await assertFails(deleteDoc(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_002/historico/hist_avaliador")));

  console.log("Teste extra 50: delete permitido apenas para admin...");
  await assertSucceeds(deleteDoc(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_002/historico/hist_avaliador")));
  await assertSucceeds(deleteDoc(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_002")));

  console.log("Teste extra 51: batch real da tela passa para admin...");
  const adminBatch = writeBatch(adminDb);
  adminBatch.set(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_batch_admin"), { aluno_id: "aluno_batch_admin", nota_final: 9.2 }, { merge: true });
  adminBatch.set(doc(adminDb, "turmas/turma_001/avaliacoes_alunos/aluno_batch_admin"), { aluno_id: "aluno_batch_admin", ultima_nota: 9.2 }, { merge: true });
  adminBatch.set(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_batch_admin/historico/hist_batch_admin"), { aluno_id: "aluno_batch_admin", nota_final: 9.2, tipo: "primeira_avaliacao" });
  adminBatch.set(doc(adminDb, "turmas/turma_001/ciclos_avaliacao/2026_07"), { total_avaliacoes: 2 }, { merge: true });
  await assertSucceeds(adminBatch.commit());

  console.log("Teste extra 52: batch real da tela passa para usuario com pode_avaliar_aluno...");
  const avaliadorBatch = writeBatch(avaliadorDb);
  avaliadorBatch.set(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_batch_avaliador"), { aluno_id: "aluno_batch_avaliador", nota_final: 8.8 }, { merge: true });
  avaliadorBatch.set(doc(avaliadorDb, "turmas/turma_001/avaliacoes_alunos/aluno_batch_avaliador"), { aluno_id: "aluno_batch_avaliador", ultima_nota: 8.8 }, { merge: true });
  avaliadorBatch.set(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07/avaliacoes/aluno_batch_avaliador/historico/hist_batch_avaliador"), { aluno_id: "aluno_batch_avaliador", nota_final: 8.8, tipo: "primeira_avaliacao" });
  avaliadorBatch.set(doc(avaliadorDb, "turmas/turma_001/ciclos_avaliacao/2026_07"), { total_avaliacoes: 3 }, { merge: true });
  await assertSucceeds(avaliadorBatch.commit());

  await testEnv.cleanup();

  console.log("");
  console.log("TODOS OS TESTES EXTRAS DAS RULES PASSARAM ✅");
  console.log("Nenhum deploy foi feito.");
  console.log("Perguntas continuam sem resposta correta no documento publico.");
}

main().catch((error) => {
  console.error("");
  console.error("TESTE EXTRA FALHOU ❌");
  console.error(error);
  process.exit(1);
});