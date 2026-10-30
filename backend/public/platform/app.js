// PWP POS Platform — vendor console. Talks to /api/platform on this server.
(function () {
  'use strict';

  const API = '/api/platform';
  const TOKEN_KEY = 'pwp_platform_token';
  const $ = (id) => document.getElementById(id);

  let token = null;
  let clients = [];

  function readToken() {
    try { return sessionStorage.getItem(TOKEN_KEY); } catch (_) { return null; }
  }
  function saveToken(value) {
    try {
      if (value) sessionStorage.setItem(TOKEN_KEY, value);
      else sessionStorage.removeItem(TOKEN_KEY);
    } catch (_) { /* private mode: stay logged in for this page only */ }
  }

  async function api(method, path, body) {
    const res = await fetch(API + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await res.json().catch(() => ({}));
    if (res.status === 401 && path !== '/auth/login') {
      logout();
      throw new Error('Session expired. Please log in again.');
    }
    if (!res.ok) throw new Error(json.message || 'Request failed (' + res.status + ').');
    return json.data;
  }

  function toast(message) {
    const el = $('toast');
    el.textContent = message;
    el.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { el.hidden = true; }, 2600);
  }

  function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function fmtDate(value) {
    if (!value) return 'No expiry';
    return new Date(value).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
  }

  function dateInput(value) {
    return value ? new Date(value).toISOString().slice(0, 10) : '';
  }

  function daysLeft(value) {
    if (!value) return null;
    return Math.ceil((new Date(value).getTime() - Date.now()) / 86400000);
  }

  // ---------- Views ----------

  function showLogin() {
    $('appView').hidden = true;
    $('loginView').hidden = false;
  }

  async function showApp() {
    $('loginView').hidden = true;
    $('appView').hidden = false;
    await loadClients();
  }

  async function loadClients() {
    try {
      clients = await api('GET', '/tenants');
      render();
    } catch (err) {
      toast(err.message);
    }
  }

  function licenceState(c) {
    if (c.status !== 'active') return { cls: 'bad', text: 'Suspended' };
    const left = daysLeft(c.validUntil);
    if (left !== null && left < 0) return { cls: 'bad', text: 'Expired' };
    if (left !== null && left <= 15) return { cls: 'warn', text: left + ' days left' };
    return { cls: 'ok', text: 'Active' };
  }

  function render() {
    const query = $('search').value.trim().toLowerCase();
    const list = clients.filter((c) =>
      !query ||
      c.name.toLowerCase().includes(query) ||
      c.code.includes(query) ||
      (c.contact?.phone || '').includes(query));

    const active = clients.filter((c) => licenceState(c).cls !== 'bad').length;
    const outlets = clients.reduce((n, c) => n + c.outlets.filter((o) => o.active).length, 0);
    const expiring = clients.filter((c) => licenceState(c).cls === 'warn').length;
    $('summary').innerHTML =
      stat('Clients', clients.length) + stat('Active', active) + stat('Active outlets', outlets) + stat('Expiring in 15 days', expiring);

    $('clients').innerHTML = list.length
      ? list.map(clientCard).join('')
      : '<p class="muted">No clients yet. Click "+ New client" to add your first cafe or restaurant.</p>';
  }

  function stat(label, value) {
    return '<div class="stat"><span class="muted">' + esc(label) + '</span><b>' + esc(value) + '</b></div>';
  }

  function clientCard(c) {
    const state = licenceState(c);
    const outlets = c.outlets.map((o) =>
      '<div class="outlet">' +
        '<span class="name">' + esc(o.name) + '</span>' +
        '<span class="code">' + esc(c.code + ':' + o.code) + '</span>' +
        '<span class="pill ' + (o.active ? 'ok' : 'bad') + '">' + (o.active ? 'On' : 'Off') + '</span>' +
        '<span class="spacer"></span>' +
        '<button class="small ghost" data-act="toggleOutlet" data-id="' + c._id + '" data-outlet="' + o._id + '">' + (o.active ? 'Turn off' : 'Turn on') + '</button>' +
      '</div>').join('');

    return (
      '<section class="client">' +
        '<div class="client-head">' +
          '<h3>' + esc(c.name) + '</h3>' +
          '<span class="code">' + esc(c.code) + '</span>' +
          '<span class="pill ' + state.cls + '">' + esc(state.text) + '</span>' +
          (c.isDefault ? '<span class="pill ok">Default</span>' : '') +
        '</div>' +
        '<div class="meta">' +
          '<span>Valid until: <b>' + esc(fmtDate(c.validUntil)) + '</b></span>' +
          '<span>Outlets: <b>' + c.outlets.length + ' / ' + c.maxOutlets + '</b></span>' +
          '<span>Plan: ' + esc(c.plan) + '</span>' +
          (c.contact?.name || c.contact?.phone ? '<span>Contact: ' + esc([c.contact.name, c.contact.phone].filter(Boolean).join(' · ')) + '</span>' : '') +
          (c.hasOwnDatabase ? '<span>Own database</span>' : '') +
        '</div>' +
        '<div class="outlets">' + outlets + '</div>' +
        '<div class="row-actions">' +
          '<button class="small" data-act="licence" data-id="' + c._id + '">Licence &amp; details</button>' +
          '<button class="small ghost" data-act="addOutlet" data-id="' + c._id + '"' + (c.outlets.length >= c.maxOutlets ? ' title="Raise the outlet limit first"' : '') + '>+ Outlet</button>' +
          '<button class="small ghost" data-act="password" data-id="' + c._id + '">Reset owner password</button>' +
          '<button class="small ghost" data-act="usage" data-id="' + c._id + '">Storage</button>' +
          (c.status === 'active'
            ? '<button class="small danger" data-act="suspend" data-id="' + c._id + '">Suspend</button>'
            : '<button class="small" data-act="activate" data-id="' + c._id + '">Activate</button>') +
        '</div>' +
      '</section>'
    );
  }

  // ---------- Dialog helper ----------

  function openDialog(title, bodyHtml, submitText, onSubmit) {
    $('dialogTitle').textContent = title;
    $('dialogBody').innerHTML = bodyHtml;
    $('dialogError').textContent = '';
    $('dialogSubmit').textContent = submitText || 'Save';
    $('dialogSubmit').hidden = !onSubmit;
    const dialog = $('dialog');
    $('dialogForm').onsubmit = async (event) => {
      event.preventDefault();
      if (!onSubmit) return dialog.close();
      $('dialogSubmit').disabled = true;
      try {
        const data = Object.fromEntries(new FormData($('dialogForm')).entries());
        await onSubmit(data);
        dialog.close();
        await loadClients();
      } catch (err) {
        $('dialogError').textContent = err.message;
      } finally {
        $('dialogSubmit').disabled = false;
      }
    };
    dialog.showModal();
  }

  function field(label, name, value, attrs) {
    return '<label>' + esc(label) + ' <input name="' + name + '" value="' + esc(value ?? '') + '" ' + (attrs || '') + '></label>';
  }

  // ---------- Actions ----------

  function newClient() {
    const nextYear = new Date(Date.now() + 365 * 86400000).toISOString().slice(0, 10);
    openDialog('New client',
      '<div class="grid2">' +
        field('Business name', 'name', '', 'required') +
        field('Business code (login)', 'code', '', 'required pattern="[a-z0-9]{3,16}" title="3-16 lowercase letters or digits"') +
      '</div>' +
      '<div class="grid2">' +
        field('First outlet name', 'outletName', '', 'placeholder="e.g. MG Road"') +
        field('Outlet code', 'outletCode', 'main', 'pattern="[a-z0-9]{2,12}" title="2-12 lowercase letters or digits"') +
      '</div>' +
      '<div class="grid2">' +
        field('Valid until', 'validUntil', nextYear, 'type="date"') +
        field('Outlet limit (franchise)', 'maxOutlets', '1', 'type="number" min="1"') +
      '</div>' +
      '<div class="grid2">' +
        field('Contact name', 'contactName', '') +
        field('Contact phone', 'contactPhone', '') +
      '</div>' +
      '<p class="muted">Owner login for the client (admin of all its outlets):</p>' +
      '<div class="grid2">' +
        field('Owner username', 'ownerUsername', 'owner', 'required') +
        field('Owner password', 'ownerPassword', '', 'required minlength="6"') +
      '</div>' +
      field('Own MongoDB URI (optional — separate free cluster)', 'dbUri', '', 'placeholder="mongodb+srv://..."'),
      'Create client',
      async (d) => {
        await api('POST', '/tenants', {
          name: d.name,
          code: d.code.trim().toLowerCase(),
          outletName: d.outletName || d.name,
          outletCode: (d.outletCode || 'main').trim().toLowerCase(),
          validUntil: d.validUntil || null,
          maxOutlets: Number(d.maxOutlets) || 1,
          contact: { name: d.contactName, phone: d.contactPhone },
          owner: { name: d.contactName || 'Owner', username: d.ownerUsername, password: d.ownerPassword, phone: d.contactPhone },
          dbUri: d.dbUri,
        });
        toast('Client created. Business code: ' + d.code.trim().toLowerCase());
      });
  }

  function editLicence(c) {
    openDialog('Licence & details — ' + c.name,
      field('Business name', 'name', c.name, 'required') +
      '<div class="grid2">' +
        '<label>Status <select name="status">' +
          '<option value="active"' + (c.status === 'active' ? ' selected' : '') + '>Active</option>' +
          '<option value="suspended"' + (c.status !== 'active' ? ' selected' : '') + '>Suspended</option>' +
        '</select></label>' +
        field('Valid until (empty = no expiry)', 'validUntil', dateInput(c.validUntil), 'type="date"') +
      '</div>' +
      '<div class="grid2">' +
        field('Outlet limit (franchise)', 'maxOutlets', c.maxOutlets, 'type="number" min="1"') +
        field('Plan', 'plan', c.plan) +
      '</div>' +
      '<div class="grid2">' +
        field('Contact name', 'contactName', c.contact?.name) +
        field('Contact phone', 'contactPhone', c.contact?.phone) +
      '</div>' +
      field('Message shown when suspended', 'suspendedMessage', c.suspendedMessage, 'placeholder="e.g. Payment pending — call 98xxxxxxx"') +
      '<label>Notes <textarea name="notes" rows="2">' + esc(c.notes) + '</textarea></label>',
      'Save',
      async (d) => {
        await api('PATCH', '/tenants/' + c._id, {
          name: d.name,
          status: d.status,
          validUntil: d.validUntil || null,
          maxOutlets: Number(d.maxOutlets),
          plan: d.plan,
          contact: { name: d.contactName, phone: d.contactPhone },
          suspendedMessage: d.suspendedMessage,
          notes: d.notes,
        });
        toast('Saved.');
      });
  }

  function addOutlet(c) {
    if (c.outlets.length >= c.maxOutlets) {
      toast('Limit reached (' + c.maxOutlets + '). Raise the outlet limit in "Licence & details" first.');
      return;
    }
    const options = c.outlets.map((o) => '<option value="' + esc(o.code) + '">' + esc(o.name) + '</option>').join('');
    openDialog('New outlet — ' + c.name,
      '<div class="grid2">' +
        field('Outlet name', 'name', '', 'required') +
        field('Outlet code', 'code', '', 'required pattern="[a-z0-9]{2,12}" title="2-12 lowercase letters or digits"') +
      '</div>' +
      '<div class="grid2">' +
        field('Phone', 'phone', '') +
        field('Address', 'address', '') +
      '</div>' +
      '<label>Copy menu from <select name="copyMenuFrom"><option value="">Start with an empty menu</option>' + options + '</select></label>' +
      '<p class="muted">Each outlet keeps its own customers, bills, tables and stock.</p>',
      'Add outlet',
      async (d) => {
        await api('POST', '/tenants/' + c._id + '/outlets', {
          name: d.name, code: d.code.trim().toLowerCase(), phone: d.phone, address: d.address, copyMenuFrom: d.copyMenuFrom || undefined,
        });
        toast('Outlet added.');
      });
  }

  function resetPassword(c) {
    openDialog('Reset owner password — ' + c.name,
      field('Username (empty = first admin)', 'username', '') +
      field('New password', 'password', '', 'required minlength="6"') +
      '<p class="muted">The user is signed out on all devices.</p>',
      'Reset password',
      async (d) => {
        const r = await api('POST', '/tenants/' + c._id + '/owner-password', d);
        toast('Password reset for ' + r.username + '.');
      });
  }

  async function showUsage(c) {
    openDialog('Storage — ' + c.name, '<p class="muted">Loading…</p>', null, null);
    try {
      const u = await api('GET', '/tenants/' + c._id + '/usage');
      const row = (label, s) => '<div class="outlet"><span class="name">' + esc(label) + '</span><span class="spacer"></span>' +
        (s.error ? '<span class="error">' + esc(s.error) + '</span>' : '<span>' + s.dataMB + ' MB data · ' + s.objects + ' records</span>') + '</div>';
      const total = [u.core, ...u.outlets].reduce((n, s) => n + (s.dataMB || 0), 0);
      $('dialogBody').innerHTML =
        row('Users (core)', u.core) + u.outlets.map((o) => row(o.name, o)).join('') +
        '<p class="muted">Total ≈ ' + total.toFixed(1) + ' MB. A free MongoDB Atlas cluster holds 512 MB; the client\'s admin gets an archive reminder every 4 months.</p>';
    } catch (err) {
      $('dialogBody').innerHTML = '<p class="error">' + esc(err.message) + '</p>';
    }
  }

  async function setStatus(c, status) {
    if (status === 'suspended' && !confirm('Suspend ' + c.name + '? Their staff will be logged out of every outlet until you activate it again.')) return;
    try {
      await api('PATCH', '/tenants/' + c._id, { status });
      toast(status === 'active' ? 'Client activated.' : 'Client suspended.');
      await loadClients();
    } catch (err) { toast(err.message); }
  }

  async function toggleOutlet(c, outletId) {
    const outlet = c.outlets.find((o) => o._id === outletId);
    if (outlet.active && !confirm('Turn off ' + outlet.name + '? Its staff cannot use it until you turn it on again.')) return;
    try {
      await api('PATCH', '/tenants/' + c._id + '/outlets/' + outletId, { active: !outlet.active });
      await loadClients();
    } catch (err) { toast(err.message); }
  }

  function logout() {
    token = null;
    saveToken(null);
    showLogin();
  }

  // ---------- Wiring ----------

  $('loginForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    $('loginError').textContent = '';
    const d = Object.fromEntries(new FormData(event.target).entries());
    try {
      const r = await api('POST', '/auth/login', d);
      token = r.token;
      saveToken(token);
      await showApp();
    } catch (err) {
      $('loginError').textContent = err.message;
    }
  });

  $('clients').addEventListener('click', (event) => {
    const btn = event.target.closest('button[data-act]');
    if (!btn) return;
    const c = clients.find((x) => x._id === btn.dataset.id);
    if (!c) return;
    ({
      licence: () => editLicence(c),
      addOutlet: () => addOutlet(c),
      password: () => resetPassword(c),
      usage: () => showUsage(c),
      suspend: () => setStatus(c, 'suspended'),
      activate: () => setStatus(c, 'active'),
      toggleOutlet: () => toggleOutlet(c, btn.dataset.outlet),
    })[btn.dataset.act]();
  });

  $('newClientBtn').addEventListener('click', newClient);
  $('logoutBtn').addEventListener('click', logout);
  $('search').addEventListener('input', render);
  $('dialogCancel').addEventListener('click', () => $('dialog').close());

  token = readToken();
  if (token) showApp();
  else showLogin();
})();
