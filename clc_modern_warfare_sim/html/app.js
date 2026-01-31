const root = document.getElementById('uiRoot');
const toastLayer = document.getElementById('toastLayer');
const hudPanel = document.getElementById('hudPanel');
const mapPanel = document.getElementById('mapPanel');
const factionPanel = document.getElementById('factionPanel');
const depotPanel = document.getElementById('depotPanel');
const closeBtn = document.getElementById('closeBtn');

const phaseVal = document.getElementById('phaseVal');
const factionName = document.getElementById('factionName');
const ticketsList = document.getElementById('ticketsList');
const resourceList = document.getElementById('resourceList');
const zoneList = document.getElementById('zoneList');
const mapZones = document.getElementById('mapZones');
const factionList = document.getElementById('factionList');
const depotName = document.getElementById('depotName');
const depotControl = document.getElementById('depotControl');
const depotResources = document.getElementById('depotResources');
const depotVehicles = document.getElementById('depotVehicles');
const depotNote = document.getElementById('depotNote');

let visible = false;
let activePanel = 'hud';

const state = {
  faction: null,
  state: {},
  zones: {},
  resources: {},
  vehicles: {},
  depots: {},
  factions: {},
  vehicleDefs: {},
  depotAccess: {},
  nearDepot: null
};

function post(action, data) {
  console.log(`[MW:UI] POST ${action}`, data || {});
  fetch(`https://${GetParentResourceName()}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).then(() => {
    console.log(`[MW:UI] POST ${action} ok`);
  }).catch((err) => {
    console.error(`[MW:UI] POST ${action} failed`, err);
  });
}

function pushToast(message, tone) {
  if (!message) return;
  const toast = document.createElement('div');
  toast.className = `toast ${tone || 'info'}`;
  toast.textContent = message;
  toastLayer.appendChild(toast);
  setTimeout(() => toast.remove(), 3500);
}

function showPanel(panel) {
  activePanel = panel || 'hud';
  hudPanel.classList.toggle('panel-hidden', activePanel !== 'hud');
  mapPanel.classList.toggle('panel-hidden', activePanel !== 'map');
  factionPanel.classList.toggle('panel-hidden', activePanel !== 'faction');
  depotPanel.classList.toggle('panel-hidden', activePanel !== 'depot');
}

function openUI(panel) {
  visible = true;
  root.classList.remove('hidden');
  showPanel(panel);
}

function closeUI() {
  visible = false;
  root.classList.add('hidden');
}

function renderTickets() {
  const tickets = state.state.tickets || {};
  ticketsList.innerHTML = '';
  Object.keys(tickets).forEach((faction) => {
    const row = document.createElement('div');
    row.className = 'row';
    row.innerHTML = `<span>${faction.toUpperCase()}</span><span>${tickets[faction]}</span>`;
    ticketsList.appendChild(row);
  });
}

function renderResources() {
  const res = state.resources || {};
  const factionRes = state.faction && res[state.faction] ? res[state.faction] : { fuel: 0, ammo: 0, parts: 0 };
  resourceList.innerHTML = '';
  ['fuel', 'ammo', 'parts'].forEach((key) => {
    const row = document.createElement('div');
    row.className = 'row';
    row.innerHTML = `<span>${key.toUpperCase()}</span><span>${factionRes[key] || 0}</span>`;
    resourceList.appendChild(row);
  });
}

function renderZones() {
  zoneList.innerHTML = '';
  mapZones.innerHTML = '';
  Object.keys(state.zones || {}).forEach((id) => {
    const zone = state.zones[id];
    const owner = zone.owner ? zone.owner.toUpperCase() : 'NEUTRAL';
    const aiStatus = zone.aiStatus ? ` | ${zone.aiStatus.toUpperCase()}` : '';
    const row = document.createElement('div');
    row.className = 'row';
    row.innerHTML = `<span>${id.toUpperCase()}</span><span>${owner}${aiStatus}</span>`;
    zoneList.appendChild(row);

    const mapRow = row.cloneNode(true);
    mapZones.appendChild(mapRow);
  });
}

function renderFactions() {
  factionList.innerHTML = '';
  Object.keys(state.factions || {}).forEach((id) => {
    const faction = state.factions[id];
    const button = document.createElement('button');
    button.className = 'btn faction-btn';
    button.textContent = faction.label;
    if (faction.identifierColor) {
      button.style.borderColor = faction.identifierColor;
      button.style.color = faction.identifierColor;
    }
    button.onclick = () => post('ui:selectFaction', { faction: id });
    factionList.appendChild(button);
  });
}

function renderDepotResources(res) {
  depotResources.innerHTML = '';
  ['fuel', 'ammo', 'parts'].forEach((key) => {
    const row = document.createElement('div');
    row.className = 'row';
    row.innerHTML = `<span>${key.toUpperCase()}</span><span>${res[key] || 0}</span>`;
    depotResources.appendChild(row);
  });
}

function renderDepot() {
  const depotId = state.nearDepot;
  const depot = depotId ? state.depots[depotId] : null;
  const access = depotId ? state.depotAccess[depotId] : null;
  const factionRes = state.faction && state.resources[state.faction] ? state.resources[state.faction] : { fuel: 0, ammo: 0, parts: 0 };

  depotVehicles.innerHTML = '';

  if (!depot) {
    depotName.textContent = 'Depot';
    depotControl.textContent = 'CONTROL: -';
    depotNote.textContent = 'No depot nearby.';
    renderDepotResources(factionRes);
    return;
  }

  const controlLabel = access && access.owner ? access.owner.toUpperCase() : 'NEUTRAL';
  depotName.textContent = depot.label || 'Depot';
  depotControl.textContent = `CONTROL: ${controlLabel}`;

  renderDepotResources(factionRes);

  if (!access || !access.allowed) {
    depotNote.textContent = 'Access denied. Depot control does not match your faction.';
    return;
  }

  depotNote.textContent = 'Select a vehicle and deploy to the frontline.';

  depot.vehicles.forEach((vehicleId) => {
    const def = state.vehicleDefs[vehicleId] || {};
    const cost = def.cost || { fuel: 0, ammo: 0, parts: 0 };
    const canAfford = (factionRes.fuel >= (cost.fuel || 0))
      && (factionRes.ammo >= (cost.ammo || 0))
      && (factionRes.parts >= (cost.parts || 0));
    const allowed = access && access.allowed;

    const card = document.createElement('div');
    card.className = 'vehicle-card';

    const title = document.createElement('div');
    title.className = 'vehicle-title';
    title.textContent = def.label || vehicleId.toUpperCase();
    card.appendChild(title);

    const meta = document.createElement('div');
    meta.className = 'vehicle-meta';
    meta.innerHTML = `<span>${def.type || 'vehicle'}</span><span>CD ${def.cooldown || 0}s</span>`;
    card.appendChild(meta);

    const costRow = document.createElement('div');
    costRow.className = 'vehicle-cost';
    ['fuel', 'ammo', 'parts'].forEach((key) => {
      const badge = document.createElement('div');
      const value = cost[key] || 0;
      const ok = (factionRes[key] || 0) >= value;
      badge.className = `cost-badge ${ok ? '' : 'low'}`;
      badge.textContent = `${key.toUpperCase()} ${value}`;
      costRow.appendChild(badge);
    });
    card.appendChild(costRow);

    const actions = document.createElement('div');
    actions.className = 'vehicle-actions';
    const btn = document.createElement('button');
    btn.className = 'btn btn-primary';
    btn.textContent = 'SPAWN';
    btn.disabled = !allowed || !canAfford;
    btn.onclick = () => {
      if (btn.dataset.locked === '1') return;
      btn.dataset.locked = '1';
      btn.disabled = true;
      const requestId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      console.log(`[MW:UI] Spawn click depot=${depotId} vehicle=${vehicleId}`);
      post('ui:spawnVehicle', { depotId: depotId, vehicleId: vehicleId, requestId: requestId });
    };
    actions.appendChild(btn);
    card.appendChild(actions);

    depotVehicles.appendChild(card);
  });
}

function render() {
  phaseVal.textContent = `PHASE: ${state.state.phase ?? '-'}`;
  factionName.textContent = `FACTION: ${state.faction ? state.faction.toUpperCase() : '-'}`;
  const faction = state.faction ? state.factions[state.faction] : null;
  factionName.style.color = faction && faction.identifierColor ? faction.identifierColor : '';
  renderTickets();
  renderResources();
  renderZones();
  renderFactions();
  renderDepot();
}

window.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || !data.action) return;

  if (data.action === 'open') {
    console.log('[MW:UI] action=open', data);
    openUI(data.panel);
  } else if (data.action === 'close') {
    console.log('[MW:UI] action=close');
    closeUI();
  } else if (data.action === 'update') {
    Object.assign(state, data.payload || {});
    render();
  } else if (data.action === 'toast') {
    console.log('[MW:UI] action=toast', data);
    pushToast(data.message, data.tone);
  }
});

closeBtn.addEventListener('click', () => post('ui:close'));

document.addEventListener('keydown', (event) => {
  if (!visible) return;
  if (event.key === 'Escape' || event.key === 'Backspace') {
    post('ui:close');
  }
});
