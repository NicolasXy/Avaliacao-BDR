// API do Sistema de Ordens de Serviço (ALTAVE) — Parte 5 da avaliação.
// Funcionalidade: ABERTURA DE ORDEM DE SERVIÇO com distribuição automática.
//  - Procedure : sp_abrir_os (grava a OS; triggers geram histórico e notificação)
//  - Functions : fn_tecnico_menos_carregado (dentro da procedure), fn_classificar_urgencia,
//                fn_taxa_aprovacao_time e fn_tempo_medio_resolucao_horas (consultas)
const express = require('express');
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'sistema_os_altave',
  waitForConnections: true,
  connectionLimit: 10,
  dateStrings: true, // DATE/DATETIME como texto: evita deslocamento de fuso no JSON
});

const app = express();
app.use(express.json());

// SIGNAL 45000 (regra de negócio) e FK inexistente (1452) viram 422; o resto é 500.
const erro = (res, err) =>
  res.status(err.sqlState === '45000' || err.errno === 1452 ? 422 : 500)
     .json({ erro: err.sqlMessage || err.message });

// POST /os -> chama a STORED PROCEDURE sp_abrir_os
app.post('/os', async (req, res) => {
  const { tipo, titulo, descricao, prioridade, prazo = null, id_solicitante, id_time } = req.body;
  const faltando = Object.entries({ tipo, titulo, descricao, prioridade, id_solicitante, id_time })
    .filter(([, v]) => v === undefined || v === null || v === '').map(([k]) => k);
  if (faltando.length) return res.status(400).json({ erro: `Campos obrigatórios: ${faltando.join(', ')}` });

  const conn = await pool.getConnection(); // mesma conexão para ler o parâmetro OUT
  try {
    await conn.query('CALL sp_abrir_os(?,?,?,?,?,?,?,@id_os)',
      [tipo, titulo, descricao, prioridade, prazo, id_solicitante, id_time]);
    const [[{ id_os }]] = await conn.query('SELECT @id_os AS id_os');
    // FUNCTION usada na leitura: urgência calculada no banco
    const [[os]] = await conn.query(
      `SELECT v.*, fn_classificar_urgencia(v.id_os) AS urgencia
         FROM vw_os_detalhada v WHERE v.id_os = ?`, [id_os]);
    res.status(201).json(os);
  } catch (err) {
    erro(res, err);
  } finally {
    conn.release();
  }
});

// GET /times/:id/indicadores -> chama FUNCTIONS diretamente
app.get('/times/:id/indicadores', async (req, res) => {
  try {
    const [[r]] = await pool.query(
      `SELECT t.nome_time,
              fn_taxa_aprovacao_time(t.id_time)         AS taxa_aprovacao_pct,
              fn_tempo_medio_resolucao_horas(t.id_time) AS tempo_medio_horas
         FROM \`TIME\` t WHERE t.id_time = ?`, [req.params.id]);
    r ? res.json(r) : res.status(404).json({ erro: 'Time não encontrado' });
  } catch (err) { erro(res, err); }
});

// PATCH /os/:id/status -> chama a PROCEDURE sp_alterar_status
app.patch('/os/:id/status', async (req, res) => {
  const { status, id_usuario } = req.body;
  if (!status || !id_usuario) return res.status(400).json({ erro: 'Campos obrigatórios: status, id_usuario' });
  try {
    await pool.query('CALL sp_alterar_status(?,?,?)', [req.params.id, status, id_usuario]);
    res.json({ ok: true });
  } catch (err) { erro(res, err); }
});

module.exports = { app, pool };

if (require.main === module) {
  const port = process.env.PORT || 3000;
  app.listen(port, () => console.log(`API rodando em http://localhost:${port}`));
}
