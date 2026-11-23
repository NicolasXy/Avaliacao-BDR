// Testes de integração: exigem o banco criado (sql/01, 02, 03) e DB_PASSWORD definido.
const test = require('node:test');
const assert = require('node:assert/strict');
const { app, pool } = require('../server');

let base, server;
test.before(async () => {
  server = app.listen(0);
  base = `http://localhost:${server.address().port}`;
});
test.after(async () => { server.close(); await pool.end(); });

const req = (method, path, body) =>
  fetch(base + path, { method, headers: { 'Content-Type': 'application/json' }, body: body && JSON.stringify(body) })
    .then(async r => ({ status: r.status, body: await r.json() }));

const os = { tipo: 'Suporte', titulo: 'Teclado com defeito', descricao: 'Teclas não respondem',
             prioridade: 'Média', prazo: '2099-12-10', id_solicitante: 40, id_time: 1 };

test('POST /os abre OS, atribui técnico do time e calcula urgência', async () => {
  const r = await req('POST', '/os', os);
  assert.equal(r.status, 201);
  assert.equal(r.body.status, 'Aberta');
  assert.equal(r.body.time_responsavel, 'TI');
  assert.ok(r.body.tecnico_responsavel, 'técnico deve ser atribuído automaticamente');
  assert.equal(r.body.prazo, '2099-12-10');
  assert.equal(r.body.urgencia, 'Normal');
});

test('POST /os com tipo inválido -> 422 com mensagem do trigger', async () => {
  const r = await req('POST', '/os', { ...os, tipo: 'Inválido' });
  assert.equal(r.status, 422);
  assert.equal(r.body.erro, 'Tipo de OS inválido.');
});

test('POST /os com prazo no passado -> 422', async () => {
  const r = await req('POST', '/os', { ...os, prazo: '2020-01-01' });
  assert.equal(r.status, 422);
});

test('POST /os sem campos obrigatórios -> 400', async () => {
  const r = await req('POST', '/os', { titulo: 'x' });
  assert.equal(r.status, 400);
});

test('POST /os com solicitante inexistente -> 422', async () => {
  const r = await req('POST', '/os', { ...os, id_solicitante: 99999 });
  assert.equal(r.status, 422);
});

test('GET /times/1/indicadores retorna as functions do banco', async () => {
  const r = await req('GET', '/times/1/indicadores');
  assert.equal(r.status, 200);
  assert.equal(r.body.nome_time, 'TI');
  assert.ok(Number(r.body.taxa_aprovacao_pct) >= 0 && Number(r.body.taxa_aprovacao_pct) <= 100);
});

test('GET /times/9999/indicadores -> 404', async () => {
  assert.equal((await req('GET', '/times/9999/indicadores')).status, 404);
});

test('PATCH /os/:id/status segue o fluxo e bloqueia transição inválida', async () => {
  const { body: nova } = await req('POST', '/os', os);
  const ok = await req('PATCH', `/os/${nova.id_os}/status`, { status: 'Em andamento', id_usuario: 40 });
  assert.equal(ok.status, 200);
  const ruim = await req('PATCH', `/os/${nova.id_os}/status`, { status: 'Concluída', id_usuario: 40 });
  assert.equal(ruim.status, 422);
  assert.equal(ruim.body.erro, 'Transição de status não permitida.');
});
