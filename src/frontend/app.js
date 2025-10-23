/* AmneziaWG UI Logic for Asuswrt-Merlin
 - Tabs handling
 - API communication (load/save sections)
 - Key generation/import, public key derivation
 - Obfuscation/transport settings
 - Policy routing dynamic rows and serialization
 - Advanced scripts and extra config
*/

const UI = (() => {
  const q = (sel, root=document) => root.querySelector(sel);
  const qa = (sel, root=document) => Array.from(root.querySelectorAll(sel));
  const state = {
    activeTab: 'basic',
    data: {
      interface: {
        enabled: false,
        name: 'awg0',
        listen_port: 51820,
        mtu: '',
        private_key: '',
        public_key: '',
        ipv4: '',
        ipv6: '',
        dns: ''
      },
      peers: [],
      obfs: {
        enabled: false,
        mode: 'none',
        secret: '',
        padding: 0,
      },
      transport: {
        proto: 'UDP',
        endpoint_override: '',
        handshake_timeout: 5,
      },
      policy: {
        routes: [], // {table: 'wan'|'wg', dest: 'CIDR', sources: 'list'}
        marks: [],  // {fwmark: number, ports: 'spec'}
      },
      advanced: {
        pre_up: '', post_up: '', pre_down: '', post_down: '',
        extra: ''
      }
    }
  };

  // Tabs
  function initTabs() {
    qa('.tab-btn').forEach(b => {
      b.addEventListener('click', () => setTab(b.dataset.to));
    });
    setTab('basic');
  }
  function setTab(id){
    state.activeTab=id;
    qa('[data-tab]').forEach(el=> el.classList.toggle('hidden', el.dataset.tab!==id));
    qa('.tab-btn').forEach(b=> b.classList.toggle('active', b.dataset.to===id));
  }

  // API
  const API = {
    async get(path){
      // On-router this would be a real endpoint. Here we mock via window.awgApi if present
      if (window.awgApi?.get) return window.awgApi.get(path);
      // Fallback: try fetch relative json
      const res = await fetch(path, {cache:'no-store'}).catch(()=>null);
      if (!res || !res.ok) return null;
      try { return await res.json(); } catch { return null; }
    },
    async post(path, body){
      if (window.awgApi?.post) return window.awgApi.post(path, body);
      const res = await fetch(path, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)}).catch(()=>null);
      return res && res.ok;
    }
  };

  // Key utilities
  async function generateKeyPair() {
    // Use crypto.subtle to generate x25519 then derive wg-style keys if possible
    // For UI, fall back to random base64 for private and pseudo public
    try {
      // Not all environments support X25519 easily; keep a simple approach
      const priv = crypto.getRandomValues(new Uint8Array(32));
      const privB64 = b64(priv);
      // Public is placeholder since real wg requires curve operations; leave blank for router to derive
      return {private_key: privB64, public_key: ''};
    } catch {
      const rnd = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
      return {private_key: btoa(rnd).slice(0,44), public_key: ''};
    }
  }
  function b64(bytes){
    let bin = '';
    bytes.forEach(b=> bin += String.fromCharCode(b));
    return btoa(bin);
  }

  // DOM binding helpers
  function bindBasic() {
    const enable = q('#enable');
    const name = qa('input[placeholder="awg0"]')[0];
    const port = qa('input[placeholder="51820"]')[0];
    const mtu = qa('input[placeholder="1420"]')[0];
    const priv = qa('input[placeholder="base64 private key"]')[0];
    const pub = qa('input[placeholder="auto-derived"]')[0];
    const ipv4 = qa('input[placeholder="10.0.0.2/32"]')[0];
    const ipv6 = qa('input[placeholder="fd00::2/128"]')[0];
    const dns = qa('input[placeholder="1.1.1.1, 9.9.9.9"]')[0];
    const btns = qa('.card h6 ~ .row .btn'); // Generate, Import

    // Load from state into UI
    enable.checked = !!state.data.interface.enabled;
    if (name) name.value = state.data.interface.name || 'awg0';
    if (port) port.value = state.data.interface.listen_port || 51820;
    if (mtu) mtu.value = state.data.interface.mtu || '';
    if (priv) priv.value = state.data.interface.private_key || '';
    if (pub) pub.value = state.data.interface.public_key || '';
    if (ipv4) ipv4.value = state.data.interface.ipv4 || '';
    if (ipv6) ipv6.value = state.data.interface.ipv6 || '';
    if (dns) dns.value = state.data.interface.dns || '';

    // Events
    enable.addEventListener('change', () => state.data.interface.enabled = enable.checked);
    name?.addEventListener('input', () => state.data.interface.name = name.value.trim());
    port?.addEventListener('input', () => state.data.interface.listen_port = +port.value || 0);
    mtu?.addEventListener('input', () => state.data.interface.mtu = mtu.value.trim());
    priv?.addEventListener('input', () => state.data.interface.private_key = priv.value.trim());
    ipv4?.addEventListener('input', () => state.data.interface.ipv4 = ipv4.value.trim());
    ipv6?.addEventListener('input', () => state.data.interface.ipv6 = ipv6.value.trim());
    dns?.addEventListener('input', () => state.data.interface.dns = dns.value.trim());

    // Buttons: Generate, Import
    const [btnGen, btnImport] = btns;
    btnGen?.addEventListener('click', async () => {
      const kp = await generateKeyPair();
      state.data.interface.private_key = kp.private_key;
      state.data.interface.public_key = kp.public_key;
      if (priv) priv.value = kp.private_key;
      if (pub) pub.value = kp.public_key;
    });
    btnImport?.addEventListener('click', async () => {
      const v = prompt('Paste private key (base64):');
      if (!v) return;
      state.data.interface.private_key = v.trim();
      // Let backend derive public key
      state.data.interface.public_key = '';
      if (priv) priv.value = state.data.interface.private_key;
      if (pub) pub.value = '';
    });

    // Peers section dynamic rendering relies on index.html addPeer() which appends template
  }

  function collectPeers() {
    const peersWrap = q('#peers');
    const cards = qa('.card', peersWrap);
    const peers = cards.map(card => {
      const inputs = qa('input', card);
      return {
        name: inputs[0]?.value?.trim() || '',
        allowed_ips: inputs[1]?.value?.trim() || '',
        public_key: inputs[2]?.value?.trim() || '',
        preshared_key: inputs[3]?.value?.trim() || '',
        endpoint: inputs[4]?.value?.trim() || '',
        keepalive: +(inputs[5]?.value || 0)
      };
    });
    return peers;
  }

  // OBFS/Transport
  function bindObfs() {
    const en = q('#obfs-en');
    const mode = qa('section[data-tab="obfs"] select')[0];
    const secret = qa('section[data-tab="obfs"] input[placeholder="hex/base64 secret"]')[0];
    const padding = qa('section[data-tab="obfs"] input[type="number"]')[0];

    en.checked = !!state.data.obfs.enabled;
    mode.value = state.data.obfs.mode || 'none';
    secret.value = state.data.obfs.secret || '';
    padding.value = state.data.obfs.padding || 0;

    en.addEventListener('change', ()=> state.data.obfs.enabled = en.checked);
    mode.addEventListener('change', ()=> state.data.obfs.mode = mode.value);
    secret.addEventListener('input', ()=> state.data.obfs.secret = secret.value.trim());
    padding.addEventListener('input', ()=> state.data.obfs.padding = +(padding.value||0));

    const selects = qa('section[data-tab="obfs"] select');
    const proto = selects[1];
    const endpoint = qa('section[data-tab="obfs"] input[placeholder="host:port (optional)"]')[0];
    const hs = qa('section[data-tab="obfs"] input[placeholder="5"]')[0];

    proto.value = state.data.transport.proto || 'UDP';
    endpoint.value = state.data.transport.endpoint_override || '';
    hs.value = state.data.transport.handshake_timeout || 5;

    proto.addEventListener('change', ()=> state.data.transport.proto = proto.value);
    endpoint.addEventListener('input', ()=> state.data.transport.endpoint_override = endpoint.value.trim());
    hs.addEventListener('input', ()=> state.data.transport.handshake_timeout = +(hs.value||0));
  }

  // Policy Routing JS (from amneziawg-routing-js.md concepts)
  function bindPolicy() {
    // Add row buttons already wired via inline onclick in HTML (addRouteRow/addMarkRow)
    // We add collectors and save hooks
  }
  function collectPolicy() {
    const routesTable = q('#routes tbody') || q('#routes');
    const marksTable = q('#marks tbody') || q('#marks');
    const routeRows = qa('tr', routesTable).filter(tr => qa('td', tr).length);
    const markRows = qa('tr', marksTable).filter(tr => qa('td', tr).length);

    const routes = routeRows.map(tr => {
      const tds = qa('td', tr);
      const tableSel = q('select', tds[0]);
      const dest = q('input', tds[1]);
      const srcs = q('input', tds[2]);
      return {
        table: tableSel?.value || 'wan',
        dest: dest?.value?.trim() || '',
        sources: srcs?.value?.trim() || ''
      };
    }).filter(r => r.dest);

    const marks = markRows.map(tr => {
      const tds = qa('td', tr);
      const mark = q('input[type="number"]', tds[0]);
      const ports = q('input[type="text"]', tds[1]);
      return {
        fwmark: +(mark?.value||0),
        ports: (ports?.value||'').trim()
      };
    }).filter(m => m.fwmark>0 && m.ports);

    return {routes, marks};
  }

  function serializeConfig() {
    const cfg = JSON.parse(JSON.stringify(state.data));
    cfg.peers = collectPeers();
    cfg.policy = collectPolicy();
    return cfg;
  }

  // Save handlers
  function bindSaves() {
    const basicSave = qa('button').find(b => b.textContent?.includes('Save Basic'));
    const obfsSave = qa('button').find(b => b.textContent?.includes('Save Obfuscation'));
    const policySave = qa('button').find(b => b.textContent?.includes('Save Policy'));
    const advSave = qa('button').find(b => b.textContent?.includes('Save Advanced'));

    basicSave?.addEventListener('click', async ()=> {
      const ok = await API.post('/amneziawg/save/basic', serializeConfig());
      toast(ok? 'Basic settings saved':'Failed to save Basic');
    });
    obfsSave?.addEventListener('click', async ()=> {
      const ok = await API.post('/amneziawg/save/obfs', serializeConfig());
      toast(ok? 'Obfuscation saved':'Failed to save Obfuscation');
    });
    policySave?.addEventListener('click', async ()=> {
      const ok = await API.post('/amneziawg/save/policy', serializeConfig());
      toast(ok? 'Policy saved':'Failed to save Policy');
    });
    advSave?.addEventListener('click', async ()=> {
      const ok = await API.post('/amneziawg/save/advanced', serializeConfig());
      toast(ok? 'Advanced saved':'Failed to save Advanced');
    });
  }

  // Load existing config
  async function loadAll() {
    const cfg = await API.get('/amneziawg/config');
    if (cfg) Object.assign(state.data, cfg);
    // bind after load to reflect values
    bindBasic();
    bindObfs();
    bindPolicy();
  }

  function toast(msg){
    if (window.awgApi?.toast) return window.awgApi.toast(msg);
    console.log('[AWG]', msg);
  }

  function init() {
    initTabs();
    bindSaves();
    loadAll();
  }

  return {init, setTab};
})();

window.addEventListener('DOMContentLoaded', ()=> UI.init());
