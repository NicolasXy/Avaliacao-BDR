-- =====================================================================
-- 03_programacao.sql  |  Sistema de Ordens de Serviço (ALTAVE)
-- Views, 6 Functions, 6 Stored Procedures e 6 Triggers (MySQL 8)
-- Execute APÓS 01_criacao_tabelas.sql e 02_insercao_dados.sql
-- =====================================================================
USE sistema_os_altave;

-- =====================================================================
-- VIEWS (usadas pela programação e pela API)
-- =====================================================================
-- Visão detalhada da OS: INNER JOIN (solicitante, time) + LEFT JOIN (responsável, opcional)
CREATE OR REPLACE VIEW vw_os_detalhada AS
SELECT os.id_os, os.tipo, os.titulo, os.status, os.prioridade,
       os.data_abertura, os.prazo,
       sol.nome        AS solicitante,
       t.nome_time     AS time_responsavel,
       resp.nome       AS tecnico_responsavel
FROM ORDEM_SERVICO os
INNER JOIN USUARIO sol ON sol.id_usuario = os.id_solicitante
INNER JOIN `TIME` t    ON t.id_time = os.id_time_responsavel
LEFT  JOIN USUARIO resp ON resp.id_usuario = os.id_usuario_responsavel;

-- Carga de trabalho dos técnicos: LEFT JOIN + GROUP BY + função de grupo
CREATE OR REPLACE VIEW vw_carga_tecnicos AS
SELECT u.id_usuario, u.nome, t.nome_time,
       COUNT(os.id_os) AS os_em_aberto
FROM USUARIO u
INNER JOIN PAPEL p  ON p.id_papel = u.id_papel AND p.nome_papel = 'Técnico'
INNER JOIN `TIME` t ON t.id_time = u.id_time
LEFT  JOIN ORDEM_SERVICO os ON os.id_usuario_responsavel = u.id_usuario
                           AND os.status NOT IN ('Concluída','Cancelada')
GROUP BY u.id_usuario, u.nome, t.nome_time;

DELIMITER $$

-- =====================================================================
-- FUNCTIONS (6)
-- =====================================================================

-- F1. Problema: saber quantos dias faltam (ou passaram) do prazo de uma OS.
DROP FUNCTION IF EXISTS fn_dias_para_prazo $$
CREATE FUNCTION fn_dias_para_prazo(p_id_os INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_dias INT;
    SELECT DATEDIFF(prazo, CURDATE()) INTO v_dias
      FROM ORDEM_SERVICO
     WHERE id_os = p_id_os;
    RETURN v_dias;   -- negativo = atrasada; NULL = OS inexistente ou sem prazo
END $$

-- F2. Problema: classificar a urgência de uma OS combinando prioridade e prazo.
DROP FUNCTION IF EXISTS fn_classificar_urgencia $$
CREATE FUNCTION fn_classificar_urgencia(p_id_os INT)
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
    DECLARE v_status VARCHAR(30);
    DECLARE v_prioridade VARCHAR(20);
    DECLARE v_dias INT;

    SELECT status, prioridade INTO v_status, v_prioridade
      FROM ORDEM_SERVICO WHERE id_os = p_id_os;

    IF v_status IS NULL THEN RETURN NULL; END IF;
    IF v_status IN ('Concluída','Cancelada') THEN RETURN 'Encerrada'; END IF;

    SET v_dias = fn_dias_para_prazo(p_id_os);

    IF v_dias IS NULL THEN RETURN 'Sem prazo'; END IF;
    IF v_dias < 0 THEN RETURN 'Atrasada'; END IF;
    IF v_prioridade = 'Crítica' OR v_dias <= 1 THEN RETURN 'Urgente'; END IF;
    IF v_prioridade = 'Alta' OR v_dias <= 3 THEN RETURN 'Atenção'; END IF;
    RETURN 'Normal';
END $$

-- F3. Problema: contar as OS ainda em aberto sob responsabilidade de um usuário.
DROP FUNCTION IF EXISTS fn_total_os_abertas_usuario $$
CREATE FUNCTION fn_total_os_abertas_usuario(p_id_usuario INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total
      FROM ORDEM_SERVICO
     WHERE id_usuario_responsavel = p_id_usuario
       AND status NOT IN ('Concluída','Cancelada');
    RETURN v_total;
END $$

-- F4. Problema: medir a qualidade de um time pela taxa (%) de verificações aprovadas.
DROP FUNCTION IF EXISTS fn_taxa_aprovacao_time $$
CREATE FUNCTION fn_taxa_aprovacao_time(p_id_time INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_aprovadas INT DEFAULT 0;

    SELECT COUNT(*), IFNULL(SUM(v.resultado = 'Aprovado'), 0)
      INTO v_total, v_aprovadas
      FROM VERIFICACAO_QUALIDADE v
      INNER JOIN ORDEM_SERVICO os ON os.id_os = v.id_os
     WHERE os.id_time_responsavel = p_id_time;

    IF v_total = 0 THEN RETURN 0; END IF;
    RETURN ROUND(v_aprovadas * 100 / v_total, 2);
END $$

-- F5. Problema: calcular o tempo médio (em horas) de resolução das OS de um time,
--     da abertura até o registro de "Conclusão" no histórico.
DROP FUNCTION IF EXISTS fn_tempo_medio_resolucao_horas $$
CREATE FUNCTION fn_tempo_medio_resolucao_horas(p_id_time INT)
RETURNS DECIMAL(10,1)
READS SQL DATA
BEGIN
    DECLARE v_media DECIMAL(10,1);
    SELECT ROUND(AVG(TIMESTAMPDIFF(HOUR, os.data_abertura, h.data_hora)), 1)
      INTO v_media
      FROM ORDEM_SERVICO os
      INNER JOIN HISTORICO_OS h ON h.id_os = os.id_os AND h.acao = 'Conclusão'
     WHERE os.id_time_responsavel = p_id_time
       AND os.status = 'Concluída';
    RETURN IFNULL(v_media, 0);
END $$

-- F6. Problema: distribuição automática — escolher o técnico do time com menos OS em aberto.
DROP FUNCTION IF EXISTS fn_tecnico_menos_carregado $$
CREATE FUNCTION fn_tecnico_menos_carregado(p_id_time INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_id INT;
    SELECT u.id_usuario INTO v_id
      FROM USUARIO u
      INNER JOIN PAPEL p ON p.id_papel = u.id_papel AND p.nome_papel = 'Técnico'
      LEFT  JOIN ORDEM_SERVICO os ON os.id_usuario_responsavel = u.id_usuario
                                 AND os.status NOT IN ('Concluída','Cancelada')
     WHERE u.id_time = p_id_time
     GROUP BY u.id_usuario
     ORDER BY COUNT(os.id_os) ASC, u.id_usuario ASC
     LIMIT 1;
    RETURN v_id;   -- NULL se o time não possuir técnicos
END $$

-- =====================================================================
-- STORED PROCEDURES (6)
-- =====================================================================

-- P1. Problema: abrir uma OS já atribuindo automaticamente o técnico menos carregado.
--     (Histórico e notificação são gerados pelos triggers.)
DROP PROCEDURE IF EXISTS sp_abrir_os $$
CREATE PROCEDURE sp_abrir_os(
    IN  p_tipo VARCHAR(20), IN p_titulo VARCHAR(150), IN p_descricao TEXT,
    IN  p_prioridade VARCHAR(20), IN p_prazo DATE,
    IN  p_id_solicitante INT, IN p_id_time INT,
    OUT p_id_os INT)
BEGIN
    DECLARE v_tecnico INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_tecnico = fn_tecnico_menos_carregado(p_id_time);
    SET @id_usuario_logado = p_id_solicitante;

    START TRANSACTION;
    INSERT INTO ORDEM_SERVICO
        (tipo, titulo, descricao, status, prioridade, prazo,
         id_solicitante, id_time_responsavel, id_usuario_responsavel)
    VALUES
        (p_tipo, p_titulo, p_descricao, 'Aberta', p_prioridade, p_prazo,
         p_id_solicitante, p_id_time, v_tecnico);
    SET p_id_os = LAST_INSERT_ID();
    COMMIT;
END $$

-- P2. Problema: atribuir/reatribuir uma OS a um técnico, garantindo que ele pertença ao time.
DROP PROCEDURE IF EXISTS sp_atribuir_os $$
CREATE PROCEDURE sp_atribuir_os(IN p_id_os INT, IN p_id_tecnico INT, IN p_id_executor INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ORDEM_SERVICO WHERE id_os = p_id_os) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OS não encontrada.';
    END IF;
    IF NOT EXISTS (SELECT 1
                     FROM USUARIO u
                     INNER JOIN ORDEM_SERVICO os ON os.id_time_responsavel = u.id_time
                    WHERE os.id_os = p_id_os AND u.id_usuario = p_id_tecnico) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O técnico não pertence ao time responsável pela OS.';
    END IF;

    SET @id_usuario_logado = p_id_executor;
    UPDATE ORDEM_SERVICO SET id_usuario_responsavel = p_id_tecnico WHERE id_os = p_id_os;
END $$

-- P3. Problema: alterar o status de uma OS registrando quem realizou a ação
--     (regras de transição validadas pelo trigger trg_os_before_update).
DROP PROCEDURE IF EXISTS sp_alterar_status $$
CREATE PROCEDURE sp_alterar_status(IN p_id_os INT, IN p_novo_status VARCHAR(30), IN p_id_usuario INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ORDEM_SERVICO WHERE id_os = p_id_os) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OS não encontrada.';
    END IF;
    SET @id_usuario_logado = p_id_usuario;
    UPDATE ORDEM_SERVICO SET status = p_novo_status WHERE id_os = p_id_os;
END $$

-- P4. Problema: registrar a verificação de qualidade (somente Analista de Qualidade e
--     somente para OS "Aguardando verificação"). O trigger atualiza o status da OS.
DROP PROCEDURE IF EXISTS sp_registrar_verificacao $$
CREATE PROCEDURE sp_registrar_verificacao(
    IN p_id_os INT, IN p_id_usuario INT, IN p_resultado VARCHAR(20), IN p_observacoes TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM USUARIO u INNER JOIN PAPEL p ON p.id_papel = u.id_papel
                    WHERE u.id_usuario = p_id_usuario AND p.nome_papel = 'Analista de Qualidade') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Apenas Analista de Qualidade pode registrar verificações.';
    END IF;
    IF (SELECT status FROM ORDEM_SERVICO WHERE id_os = p_id_os) <> 'Aguardando verificação' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A OS não está aguardando verificação.';
    END IF;
    IF p_resultado NOT IN ('Aprovado','Reprovado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Resultado inválido. Use Aprovado ou Reprovado.';
    END IF;

    INSERT INTO VERIFICACAO_QUALIDADE (id_os, id_usuario, resultado, observacoes)
    VALUES (p_id_os, p_id_usuario, p_resultado, p_observacoes);
END $$

-- P5. Problema: relatório gerencial por time em um período (inclui times sem OS).
--     RIGHT JOIN + LEFT JOIN + GROUP BY + funções de grupo + subconsulta + funções do banco.
DROP PROCEDURE IF EXISTS sp_relatorio_os_por_time $$
CREATE PROCEDURE sp_relatorio_os_por_time(IN p_data_ini DATE, IN p_data_fim DATE)
BEGIN
    SELECT t.id_time,
           t.nome_time,
           COUNT(os.id_os)                                         AS total_os,
           IFNULL(SUM(os.status = 'Concluída'), 0)                 AS concluidas,
           IFNULL(SUM(os.status IN ('Aberta','Em andamento','Aguardando verificação')), 0) AS em_aberto,
           IFNULL(SUM(os.status = 'Cancelada'), 0)                 AS canceladas,
           COUNT(DISTINCT os.id_usuario_responsavel)               AS tecnicos_envolvidos,
           fn_taxa_aprovacao_time(t.id_time)                       AS taxa_aprovacao_pct,
           fn_tempo_medio_resolucao_horas(t.id_time)               AS tempo_medio_horas,
           (SELECT COUNT(*) FROM VERIFICACAO_QUALIDADE v
              INNER JOIN ORDEM_SERVICO o2 ON o2.id_os = v.id_os
             WHERE o2.id_time_responsavel = t.id_time
               AND v.resultado = 'Reprovado')                      AS reprovacoes_total
    FROM ORDEM_SERVICO os
    RIGHT JOIN `TIME` t ON t.id_time = os.id_time_responsavel
                       AND DATE(os.data_abertura) BETWEEN p_data_ini AND p_data_fim
    GROUP BY t.id_time, t.nome_time
    ORDER BY total_os DESC, t.nome_time;
END $$

-- P6. Problema: alertar automaticamente sobre OS atrasadas (CURSOR).
--     Notifica o técnico responsável e o(s) gestor(es) do time, sem duplicar no mesmo dia.
DROP PROCEDURE IF EXISTS sp_notificar_os_atrasadas $$
CREATE PROCEDURE sp_notificar_os_atrasadas(OUT p_total_notificadas INT)
BEGIN
    DECLARE v_fim INT DEFAULT 0;
    DECLARE v_id_os INT;
    DECLARE v_titulo VARCHAR(150);
    DECLARE v_resp INT;
    DECLARE v_time INT;
    DECLARE v_dias INT;

    DECLARE cur_atrasadas CURSOR FOR
        SELECT os.id_os, os.titulo, os.id_usuario_responsavel, os.id_time_responsavel,
               ABS(DATEDIFF(os.prazo, CURDATE()))
          FROM ORDEM_SERVICO os
         WHERE os.status IN ('Aberta','Em andamento')
           AND os.prazo < CURDATE()
           AND NOT EXISTS (SELECT 1 FROM NOTIFICACAO n
                            WHERE n.id_os = os.id_os
                              AND n.mensagem LIKE 'ATRASO:%'
                              AND DATE(n.data_envio) = CURDATE());
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fim = 1;

    SET p_total_notificadas = 0;
    OPEN cur_atrasadas;
    leitura: LOOP
        FETCH cur_atrasadas INTO v_id_os, v_titulo, v_resp, v_time, v_dias;
        IF v_fim = 1 THEN LEAVE leitura; END IF;

        -- técnico responsável (se houver)
        IF v_resp IS NOT NULL THEN
            INSERT INTO NOTIFICACAO (id_usuario, id_os, mensagem)
            VALUES (v_resp, v_id_os,
                    LEFT(CONCAT('ATRASO: a OS #', v_id_os, ' (', v_titulo, ') está ', v_dias, ' dia(s) atrasada.'), 255));
            SET p_total_notificadas = p_total_notificadas + 1;
        END IF;

        -- gestores do time responsável
        INSERT INTO NOTIFICACAO (id_usuario, id_os, mensagem)
        SELECT u.id_usuario, v_id_os,
               LEFT(CONCAT('ATRASO: a OS #', v_id_os, ' (', v_titulo, ') do seu time está ', v_dias, ' dia(s) atrasada.'), 255)
          FROM USUARIO u
          INNER JOIN PAPEL p ON p.id_papel = u.id_papel AND p.nome_papel = 'Gestor'
         WHERE u.id_time = v_time;
        SET p_total_notificadas = p_total_notificadas + ROW_COUNT();
    END LOOP;
    CLOSE cur_atrasadas;
END $$

-- =====================================================================
-- TRIGGERS (6)
-- =====================================================================

-- T1. Problema: impedir dados inválidos na abertura da OS (domínios, prazo e responsável).
DROP TRIGGER IF EXISTS trg_os_before_insert $$
CREATE TRIGGER trg_os_before_insert BEFORE INSERT ON ORDEM_SERVICO
FOR EACH ROW
BEGIN
    IF NEW.tipo NOT IN ('Suporte','Manutenção','Instalação','Compra','Melhoria') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tipo de OS inválido.';
    END IF;
    IF NEW.prioridade NOT IN ('Baixa','Média','Alta','Crítica') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prioridade inválida.';
    END IF;
    IF NEW.status NOT IN ('Aberta','Em andamento','Aguardando verificação','Concluída','Cancelada') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status inválido.';
    END IF;
    IF NEW.prazo IS NOT NULL AND NEW.prazo < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O prazo não pode ser anterior à data atual.';
    END IF;
    IF NEW.id_usuario_responsavel IS NOT NULL AND
       NOT EXISTS (SELECT 1 FROM USUARIO
                    WHERE id_usuario = NEW.id_usuario_responsavel
                      AND id_time = NEW.id_time_responsavel) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O responsável deve pertencer ao time responsável.';
    END IF;
END $$

-- T2. Problema: registrar automaticamente a abertura no histórico e avisar o responsável.
DROP TRIGGER IF EXISTS trg_os_after_insert $$
CREATE TRIGGER trg_os_after_insert AFTER INSERT ON ORDEM_SERVICO
FOR EACH ROW
BEGIN
    INSERT INTO HISTORICO_OS (id_os, id_usuario, acao, descricao)
    VALUES (NEW.id_os, NEW.id_solicitante, 'Abertura',
            CONCAT('OS aberta pelo solicitante com prioridade ', NEW.prioridade, '.'));

    IF NEW.id_usuario_responsavel IS NOT NULL THEN
        INSERT INTO NOTIFICACAO (id_usuario, id_os, mensagem)
        VALUES (NEW.id_usuario_responsavel, NEW.id_os,
                LEFT(CONCAT('Nova OS atribuída a você: #', NEW.id_os, ' - ', NEW.titulo), 255));
    END IF;
END $$

-- T3. Problema: garantir o fluxo correto de status e a consistência do responsável.
--     Fluxo: Aberta → Em andamento → Aguardando verificação → Concluída
--            (Aguardando verificação → Em andamento em caso de reprovação;
--             Aberta/Em andamento → Cancelada). Concluída e Cancelada são finais.
DROP TRIGGER IF EXISTS trg_os_before_update $$
CREATE TRIGGER trg_os_before_update BEFORE UPDATE ON ORDEM_SERVICO
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        IF NEW.status NOT IN ('Aberta','Em andamento','Aguardando verificação','Concluída','Cancelada') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status inválido.';
        END IF;
        IF OLD.status IN ('Concluída','Cancelada') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OS encerrada não pode ter o status alterado.';
        END IF;
        IF NOT ( (OLD.status = 'Aberta'                 AND NEW.status IN ('Em andamento','Cancelada'))
              OR (OLD.status = 'Em andamento'           AND NEW.status IN ('Aguardando verificação','Cancelada'))
              OR (OLD.status = 'Aguardando verificação' AND NEW.status IN ('Concluída','Em andamento')) ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transição de status não permitida.';
        END IF;
        IF NEW.status = 'Em andamento' AND NEW.id_usuario_responsavel IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Atribua um responsável antes de iniciar a OS.';
        END IF;
    END IF;

    IF NEW.id_usuario_responsavel IS NOT NULL
       AND NOT (NEW.id_usuario_responsavel <=> OLD.id_usuario_responsavel)
       AND NOT EXISTS (SELECT 1 FROM USUARIO
                        WHERE id_usuario = NEW.id_usuario_responsavel
                          AND id_time = NEW.id_time_responsavel) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O responsável deve pertencer ao time responsável.';
    END IF;
END $$

-- T4. Problema: auditar mudanças de status/responsável no histórico e notificar os envolvidos.
--     O autor é lido da variável de sessão @id_usuario_logado (definida pelas procedures/API).
DROP TRIGGER IF EXISTS trg_os_after_update $$
CREATE TRIGGER trg_os_after_update AFTER UPDATE ON ORDEM_SERVICO
FOR EACH ROW
BEGIN
    DECLARE v_autor INT;
    DECLARE v_acao VARCHAR(50);
    SET v_autor = COALESCE(@id_usuario_logado, NEW.id_usuario_responsavel, NEW.id_solicitante);

    IF NEW.status <> OLD.status THEN
        SET v_acao = CASE NEW.status WHEN 'Concluída' THEN 'Conclusão'
                                     WHEN 'Cancelada' THEN 'Cancelamento'
                                     ELSE 'Mudança de status' END;
        INSERT INTO HISTORICO_OS (id_os, id_usuario, acao, descricao)
        VALUES (NEW.id_os, v_autor, v_acao,
                CONCAT('Status alterado de ', OLD.status, ' para ', NEW.status, '.'));

        INSERT INTO NOTIFICACAO (id_usuario, id_os, mensagem)
        VALUES (NEW.id_solicitante, NEW.id_os,
                LEFT(CONCAT('Sua OS #', NEW.id_os, ' está com o status: ', NEW.status), 255));
    END IF;

    IF NOT (NEW.id_usuario_responsavel <=> OLD.id_usuario_responsavel) THEN
        INSERT INTO HISTORICO_OS (id_os, id_usuario, acao, descricao)
        VALUES (NEW.id_os, v_autor, 'Atribuição',
                CONCAT('OS atribuída ao técnico responsável (usuário #', IFNULL(NEW.id_usuario_responsavel, 'nenhum'), ').'));

        IF NEW.id_usuario_responsavel IS NOT NULL THEN
            INSERT INTO NOTIFICACAO (id_usuario, id_os, mensagem)
            VALUES (NEW.id_usuario_responsavel, NEW.id_os,
                    LEFT(CONCAT('Nova OS atribuída a você: #', NEW.id_os, ' - ', NEW.titulo), 255));
        END IF;
    END IF;
END $$

-- T5. Problema: a verificação de qualidade deve decidir o destino da OS
--     (Aprovado → Concluída; Reprovado → volta para Em andamento) e ficar no histórico.
DROP TRIGGER IF EXISTS trg_verificacao_after_insert $$
CREATE TRIGGER trg_verificacao_after_insert AFTER INSERT ON VERIFICACAO_QUALIDADE
FOR EACH ROW
BEGIN
    INSERT INTO HISTORICO_OS (id_os, id_usuario, acao, descricao)
    VALUES (NEW.id_os, NEW.id_usuario, 'Verificação',
            CONCAT('Verificação de qualidade: ', NEW.resultado, '.'));

    SET @id_usuario_logado = NEW.id_usuario;
    UPDATE ORDEM_SERVICO
       SET status = IF(NEW.resultado = 'Aprovado', 'Concluída', 'Em andamento')
     WHERE id_os = NEW.id_os
       AND status = 'Aguardando verificação';
END $$

-- T6. Problema: registrar no histórico cada anexo enviado e avisar o responsável pela OS.
DROP TRIGGER IF EXISTS trg_anexo_after_insert $$
CREATE TRIGGER trg_anexo_after_insert AFTER INSERT ON ANEXO
FOR EACH ROW
BEGIN
    DECLARE v_resp INT;
    SELECT id_usuario_responsavel INTO v_resp FROM ORDEM_SERVICO WHERE id_os = NEW.id_os;

    INSERT INTO HISTORICO_OS (id_os, id_usuario, acao, descricao)
    VALUES (NEW.id_os, NEW.id_usuario, 'Anexo', CONCAT('Arquivo anexado: ', NEW.nome_arquivo));

    IF v_resp IS NOT NULL AND v_resp <> NEW.id_usuario THEN
        INSERT INTO NOTIFICACAO (id_usuario, id_os, mensagem)
        VALUES (v_resp, NEW.id_os, LEFT(CONCAT('Novo anexo na OS #', NEW.id_os, ': ', NEW.nome_arquivo), 255));
    END IF;
END $$

DELIMITER ;
