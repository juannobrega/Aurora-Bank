const { useState, useEffect, useCallback } = React;
const h = React.createElement;

// A API vive em bank.pulsaz.com.br; o Manager é outro domínio (manager.*),
// então sempre aponta para a API por URL absoluta.
const API = 'https://bank.pulsaz.com.br';

const fromDecimal = v => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const fromCents = c => (c / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const statusLabel = s => ({ ACTIVE: 'Ativo', PENDING_KYC: 'KYC pendente',
  BLOCKED: 'Bloqueado', CLOSED: 'Encerrado' }[s] || s);
function relTime(iso) {
  const d = (Date.now() - new Date(iso)) / 1000;
  if (d < 60) return 'agora';
  if (d < 3600) return Math.floor(d / 60) + 'min';
  if (d < 86400) return Math.floor(d / 3600) + 'h';
  return Math.floor(d / 86400) + 'd';
}

async function callApi(key, path) {
  const r = await fetch(API + '/admin' + path, { headers: { 'X-Admin-Key': key } });
  if (r.status === 401) throw new Error('unauthorized');
  if (!r.ok) throw new Error('http ' + r.status);
  return r.json();
}

const Mark = () => h('svg', { className: 'brand-mark', viewBox: '0 0 120 84' },
  h('defs', null, h('linearGradient', { id: 'g', x1: 0, y1: 0, x2: 1, y2: 0 },
    h('stop', { offset: 0, stopColor: '#2447F5' }),
    h('stop', { offset: .55, stopColor: '#2E8BFF' }),
    h('stop', { offset: 1, stopColor: '#25E2D6' }))),
  h('path', { d: 'M30 60 A31 31 0 1 1 92 60', fill: 'none', stroke: 'url(#g)', strokeWidth: 13 }),
  h('path', { d: 'M3 72 C 22 56, 46 50, 66 57 C 82 63, 98 66, 116 59 C 104 71, 86 75, 67 69 C 48 63, 27 62, 3 72 Z', fill: 'url(#g)' }));

function Gate({ onEnter }) {
  const [key, setKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');

  const submit = async e => {
    e.preventDefault();
    setBusy(true); setErr('');
    try {
      await callApi(key, '/metrics');
      sessionStorage.setItem('aurora-admin-key', key);
      onEnter(key);
    } catch (e2) {
      setErr(e2.message === 'unauthorized' ? 'Chave inválida.' : 'Não foi possível conectar.');
    } finally { setBusy(false); }
  };

  return h('div', { className: 'gate' },
    h('form', { className: 'gate-card', onSubmit: submit },
      h('div', { className: 'brand' }, h(Mark),
        h('div', null, h('h1', null, 'Aurora Manager'),
          h('span', null, 'Painel de gestão'))),
      h('label', { htmlFor: 'key' }, 'Chave de administração'),
      h('input', { id: 'key', type: 'password', value: key, autoFocus: true,
        autoComplete: 'off', placeholder: 'X-Admin-Key',
        onChange: e => setKey(e.target.value) }),
      h('button', { type: 'submit', className: 'primary', disabled: busy },
        busy ? 'Entrando…' : 'Entrar'),
      h('div', { className: 'err' }, err)));
}

function Health({ health }) {
  const balanced = Number(health.globalSum) === 0 && health.unbalancedTransactions === 0;
  return h('div', { className: 'health ' + (balanced ? 'ok' : 'bad') },
    h('div', { className: 'dot' }),
    h('div', null,
      h('strong', null, balanced ? 'Razão íntegro' : 'Divergência no razão'),
      h('span', { className: 'sub' },
        health.totalEntries.toLocaleString('pt-BR') + ' lançamentos · '
        + health.unbalancedTransactions + ' transações desbalanceadas')),
    h('div', { className: 'ledger-sum' },
      h('b', { className: 'mono' }, fromDecimal(health.globalSum)),
      h('small', null, 'soma do razão')));
}

function Metrics({ m }) {
  const tiles = [
    ['Usuários', m.users], ['Ativos', m.activeUsers],
    ['Transações', m.transactions.toLocaleString('pt-BR')],
    ['Empréstimos abertos', m.openLoans],
    ['Depósitos', fromDecimal(m.totalDeposits), true],
    ['Investido', fromDecimal(m.totalInvested), true],
  ];
  return h('div', { className: 'metrics' }, tiles.map(([k, v, small], i) =>
    h('div', { className: 'tile', key: i },
      h('div', { className: 'k' }, k),
      h('div', { className: 'v' + (small ? ' small' : '') }, v))));
}

function Table({ title, head, rows, empty }) {
  return h('section', null, h('h2', null, title),
    h('div', { className: 'panel' }, h('div', { className: 'scroll' },
      h('table', null,
        h('thead', null, h('tr', null, head.map((c, i) =>
          h('th', { key: i, style: c.right ? { textAlign: 'right' } : null }, c.label)))),
        h('tbody', null, rows.length ? rows
          : h('tr', null, h('td', { colSpan: head.length, className: 'empty' }, empty)))))));
}

function PendingLoans({ apiKey, loans, onDecided }) {
  const [busy, setBusy] = useState(null);

  const decide = async (id, action) => {
    setBusy(id + action);
    try {
      await fetch(API + '/admin/loans/' + id + '/' + action, {
        method: 'POST', headers: { 'X-Admin-Key': apiKey, 'Content-Type': 'application/json' },
        body: action === 'reject' ? JSON.stringify({ note: 'Análise reprovada' }) : null
      });
      onDecided();
    } finally { setBusy(null); }
  };

  if (!loans.length) return null;   // some quando não há nada em análise

  const head = ['Cliente', 'Produto', 'Valor', 'Parcelas', 'Pedido', 'Decisão'].map((c, i) =>
    h('th', { key: i, style: i === 5 ? { textAlign: 'right' } : null }, c));

  const row = l => h('tr', { key: l.id },
    h('td', null, l.userName),
    h('td', { className: 'updated' }, l.product || 'Empréstimo'),
    h('td', { className: 'num' }, fromCents(l.principalCents)),
    h('td', { className: 'mono' }, l.installments + 'x ' + fromCents(l.paymentCents)),
    h('td', { className: 'updated' }, relTime(l.requestedAt)),
    h('td', { style: { textAlign: 'right', whiteSpace: 'nowrap' } },
      h('button', { className: 'btn-approve', disabled: !!busy,
        onClick: () => decide(l.id, 'approve') },
        busy === l.id + 'approve' ? '…' : 'Aprovar'),
      h('button', { className: 'btn-reject', disabled: !!busy,
        onClick: () => decide(l.id, 'reject') },
        busy === l.id + 'reject' ? '…' : 'Recusar')));

  return h('section', null,
    h('h2', null, 'Empréstimos em análise'),
    h('div', { className: 'panel' },
      h('div', { className: 'scroll' },
        h('table', null,
          h('thead', null, h('tr', null, head)),
          h('tbody', null, loans.map(row))))));
}

function Sessions({ apiKey, sessions, onRevoked }) {
  const [busy, setBusy] = useState(null);
  const revoke = async id => {
    setBusy(id);
    try {
      await fetch(API + '/admin/sessions/' + id + '/revoke',
        { method: 'POST', headers: { 'X-Admin-Key': apiKey } });
      onRevoked();
    } finally { setBusy(null); }
  };

  const head = ['Usuário', 'Dispositivo', 'Início', 'Expira', ''].map((c, i) =>
    h('th', { key: i, style: i === 4 ? { textAlign: 'right' } : null }, c));
  const row = sn => h('tr', { key: sn.id },
    h('td', null, sn.userName),
    h('td', { className: 'updated' }, sn.device),
    h('td', { className: 'updated' }, relTime(sn.issuedAt)),
    h('td', { className: 'updated' }, 'em ' + relTime(sn.expiresAt).replace('agora', 'breve')),
    h('td', { style: { textAlign: 'right' } },
      h('button', { className: 'btn-reject', disabled: busy === sn.id,
        onClick: () => revoke(sn.id) }, busy === sn.id ? '…' : 'Encerrar')));

  return h('section', null,
    h('h2', null, 'Sessões ativas'),
    h('div', { className: 'panel' }, h('div', { className: 'scroll' },
      h('table', null,
        h('thead', null, h('tr', null, head)),
        h('tbody', null, sessions.length ? sessions.map(row)
          : h('tr', null, h('td', { colSpan: 5, className: 'empty' }, 'Nenhuma sessão ativa')))))));
}

function Dashboard({ apiKey, onLogout }) {
  const [data, setData] = useState(null);
  const [err, setErr] = useState('');
  const [updated, setUpdated] = useState('');

  const load = useCallback(async () => {
    try {
      const [metrics, health, users, txs, pending, sessions] = await Promise.all([
        callApi(apiKey, '/metrics'), callApi(apiKey, '/ledger/health'),
        callApi(apiKey, '/users?limit=50'), callApi(apiKey, '/transactions?limit=30'),
        callApi(apiKey, '/loans/pending'), callApi(apiKey, '/sessions'),
      ]);
      setData({ metrics, health, users, txs, pending, sessions });
      setUpdated(new Date().toLocaleTimeString('pt-BR'));
      setErr('');
    } catch (e) {
      if (e.message === 'unauthorized') onLogout();
      else setErr('Falha ao carregar.');
    }
  }, [apiKey, onLogout]);

  useEffect(() => { load(); }, [load]);

  if (!data) return h('div', { className: 'app' },
    h('p', { className: 'updated' }, err || 'Carregando…'));

  const userRows = data.users.map((u, i) => h('tr', { key: i },
    h('td', null, u.fullName),
    h('td', { className: 'mono' }, u.maskedCpf),
    h('td', null, h('span', { className: 'pill ' + u.status }, statusLabel(u.status))),
    h('td', { className: 'num' }, fromDecimal(u.balance)),
    h('td', { className: 'updated' }, relTime(u.createdAt))));

  const txRows = data.txs.map((t, i) => h('tr', { key: i },
    h('td', null, t.title),
    h('td', null, t.counterparty),
    h('td', { className: 'updated' }, t.category),
    h('td', { className: 'updated' }, t.method),
    h('td', { className: 'num' + (t.isCredit ? ' credit' : '') },
      (t.isCredit ? '+ ' : '− ') + fromDecimal(t.amount)),
    h('td', { className: 'updated' }, relTime(t.occurredAt))));

  return h('div', { className: 'app' },
    h('div', { className: 'top' },
      h('div', { className: 'brand' }, h(Mark),
        h('div', null, h('h1', null, 'Aurora Manager'),
          h('span', { className: 'updated' }, updated && 'atualizado ' + updated))),
      h('div', { className: 'top-actions' },
        h('button', { className: 'btn-ghost', onClick: load }, 'Atualizar'),
        h('button', { className: 'btn-ghost', onClick: onLogout }, 'Sair'))),
    h(Health, { health: data.health }),
    h(Metrics, { m: data.metrics }),
    h(PendingLoans, { apiKey, loans: data.pending, onDecided: load }),
    h(Table, { title: 'Usuários',
      head: [{ label: 'Nome' }, { label: 'CPF' }, { label: 'Status' },
             { label: 'Saldo', right: true }, { label: 'Criado' }],
      rows: userRows, empty: 'Nenhum usuário ainda' }),
    h(Sessions, { apiKey, sessions: data.sessions, onRevoked: load }),
    h(Table, { title: 'Transações recentes',
      head: [{ label: 'Descrição' }, { label: 'Contraparte' }, { label: 'Categoria' },
             { label: 'Meio' }, { label: 'Valor', right: true }, { label: 'Quando' }],
      rows: txRows, empty: 'Nenhuma transação ainda' }));
}

function App() {
  const [apiKey, setApiKey] = useState(sessionStorage.getItem('aurora-admin-key') || '');
  const logout = useCallback(() => {
    sessionStorage.removeItem('aurora-admin-key'); setApiKey('');
  }, []);
  return apiKey
    ? h(Dashboard, { apiKey, onLogout: logout })
    : h(Gate, { onEnter: setApiKey });
}

ReactDOM.createRoot(document.getElementById('root')).render(h(App));
