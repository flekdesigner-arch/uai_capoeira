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
  getDoc,
  getDocs,
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