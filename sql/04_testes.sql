-- =====================================================================
-- 04_testes.sql  |  Consultas de teste da avaliação (para tirar os prints)
-- Execute APÓS 01, 02 e 03, em UMA ÚNICA sessão, na ordem abaixo:
-- as variáveis @id_os, @os2 etc. são criadas pelos itens P1 e T5.
-- Linhas marcadas com 'erro esperado' devem falhar (SIGNAL 45000): é o resultado correto.
-- =====================================================================
USE sistema_os_altave;

-- ---- Parte 2 — Contagem de linhas por tabela
SELECT 'PAPEL' tabela, COUNT(*) total FROM PAPEL
UNION ALL SELECT 'TIME', COUNT(*) FROM `TIME`
UNION ALL SELECT 'USUARIO', COUNT(*) FROM USUARIO
UNION ALL SELECT 'ORDEM_SERVICO', COUNT(*) FROM ORDEM_SERVICO
UNION ALL SELECT 'HISTORICO_OS', COUNT(*) FROM HISTORICO_OS
UNION ALL SELECT 'ANEXO', COUNT(*) FROM ANEXO
UNION ALL SELECT 'NOTIFICACAO', COUNT(*) FROM NOTIFICACAO
UNION ALL SELECT 'VERIFICACAO_QUALIDADE', COUNT(*) FROM VERIFICACAO_QUALIDADE;

-- ---- F1 — fn_dias_para_prazo
SELECT id_os, titulo, prazo, fn_dias_para_prazo(id_os) AS dias
FROM ORDEM_SERVICO WHERE status IN ('Aberta','Em andamento') ORDER BY dias
LIMIT 10;

-- ---- F2 — fn_classificar_urgencia
SELECT id_os, prioridade, status, prazo, fn_classificar_urgencia(id_os) AS urgencia
FROM ORDEM_SERVICO ORDER BY id_os DESC LIMIT 15;

-- ---- F3 — fn_total_os_abertas_usuario
SELECT u.nome, fn_total_os_abertas_usuario(u.id_usuario) AS os_abertas
FROM USUARIO u WHERE u.id_papel = 3 ORDER BY os_abertas DESC;

-- ---- F4 — fn_taxa_aprovacao_time
SELECT id_time, nome_time, fn_taxa_aprovacao_time(id_time) AS taxa_pct FROM `TIME`;

-- ---- F5 — fn_tempo_medio_resolucao_horas
SELECT id_time, nome_time, fn_tempo_medio_resolucao_horas(id_time) AS horas FROM `TIME`;

-- ---- F6 — fn_tecnico_menos_carregado
SELECT t.nome_time, fn_tecnico_menos_carregado(t.id_time) AS id_tecnico
FROM `TIME` t WHERE t.id_time <= 5;
SELECT * FROM vw_carga_tecnicos ORDER BY nome_time, os_em_aberto;

-- ---- P1 — sp_abrir_os
CALL sp_abrir_os('Suporte','Teste de abertura','Descrição de teste','Alta',
                 DATE_ADD(CURDATE(), INTERVAL 5 DAY), 40, 1, @id_os);
SELECT @id_os;
SELECT * FROM vw_os_detalhada WHERE id_os = @id_os;
SELECT * FROM HISTORICO_OS WHERE id_os = @id_os;
SELECT * FROM NOTIFICACAO WHERE id_os = @id_os;

-- ---- P2 — sp_atribuir_os
CALL sp_atribuir_os(@id_os, 15, 2);   -- técnico 15 é do time TI: funciona
SELECT id_os, id_usuario_responsavel FROM ORDEM_SERVICO WHERE id_os = @id_os;
CALL sp_atribuir_os(@id_os, 11, 2);   -- técnico 11 é de outro time: erro esperado

-- ---- P3 — sp_alterar_status
CALL sp_alterar_status(@id_os, 'Em andamento', 15);   -- permitido
CALL sp_alterar_status(@id_os, 'Concluída', 15);   -- erro esperado: transição não permitida
SELECT * FROM HISTORICO_OS WHERE id_os = @id_os ORDER BY id_historico;

-- ---- P4 — sp_registrar_verificacao
CALL sp_alterar_status(@id_os, 'Aguardando verificação', 15);
CALL sp_registrar_verificacao(@id_os, 55, 'Aprovado', 'Serviço conferido e aprovado.');
SELECT id_os, status FROM ORDEM_SERVICO WHERE id_os = @id_os;   -- Concluída

-- ---- P5 — sp_relatorio_os_por_time
CALL sp_relatorio_os_por_time('2026-01-01', '2026-11-30');

-- ---- P6 — sp_notificar_os_atrasadas
CALL sp_notificar_os_atrasadas(@total);
SELECT @total AS notificacoes_criadas;
SELECT * FROM NOTIFICACAO WHERE mensagem LIKE 'ATRASO:%' ORDER BY id_notificacao DESC LIMIT 10;
CALL sp_notificar_os_atrasadas(@total2);
SELECT @total2;   -- 0: não duplica no mesmo dia

-- ---- T1 — trg_os_before_insert
INSERT INTO ORDEM_SERVICO
(tipo,titulo,descricao,status,prioridade,prazo,id_solicitante,id_time_responsavel)
VALUES ('Inválido','x','x','Aberta','Alta',DATE_ADD(CURDATE(), INTERVAL 3 DAY),40,1);   -- erro esperado

-- ---- T3 — trg_os_before_update
UPDATE ORDEM_SERVICO SET status = 'Em andamento' WHERE id_os = 1;   -- OS concluída: erro esperado

-- ---- T4 — trg_os_after_update
SELECT * FROM NOTIFICACAO WHERE id_os = @id_os ORDER BY id_notificacao;

-- ---- T5 — trg_verificacao_after_insert (reprovação)
CALL sp_abrir_os('Manutenção','Teste reprovação','Teste','Média',DATE_ADD(CURDATE(), INTERVAL 7 DAY),40,2,@os2);
CALL sp_alterar_status(@os2,'Em andamento',(SELECT id_usuario_responsavel FROM ORDEM_SERVICO WHERE id_os=@os2));
CALL sp_alterar_status(@os2,'Aguardando verificação',(SELECT id_usuario_responsavel FROM ORDEM_SERVICO WHERE id_os=@os2));
CALL sp_registrar_verificacao(@os2,55,'Reprovado','Retrabalho necessário.');
SELECT id_os, status FROM ORDEM_SERVICO WHERE id_os = @os2;   -- Em andamento

-- ---- T6 — trg_anexo_after_insert
INSERT INTO ANEXO (id_os, id_usuario, nome_arquivo, caminho)
VALUES (@os2, 40, 'foto_teste.jpg', '/uploads/os/teste/foto_teste.jpg');
SELECT * FROM HISTORICO_OS WHERE id_os = @os2 ORDER BY id_historico DESC LIMIT 3;
