// ── KernelSU exec wrapper ──────────
let _cbId = 0;
function exec(cmd) {
  return new Promise((resolve) => {
    const key = `_ksu_cb_${Date.now()}_${_cbId++}`;
    window[key] = (errno, stdout, stderr) => {
      delete window[key];
      resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
    };
    if (typeof ksu !== 'undefined') {
      ksu.exec(cmd, '{}', key);
    } else {
      resolve({ errno: 1, stdout: '', stderr: 'ksu not defined' });
    }
  });
}

function toast(msg) {
  if (typeof ksu !== 'undefined') { ksu.toast(msg); return; }
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), 2800);
}

// ── constants ─────────────────────────────────────────────────────────────
const MODULES_DIR   = '/data/adb/modules';
const META_DIR      = `${MODULES_DIR}/meta-nomountfs`;
const ORDER_FILE    = `${META_DIR}/mount_order`;
const STATE_DIR     = '/dev/nomountfs_state';
const PARTITIONS    = ['system','vendor','product','system_ext','odm','oem'];
const PART_TARGET   = { system:'/system', vendor:'/vendor', product:'/product',
                        system_ext:'/system_ext', odm:'/odm', oem:'/oem' };

// ── shell helpers ─────────────────────────────────────────────────────────
async function sh(cmd) {
  const r = await exec(cmd);
  return r.stdout.trim();
}

async function getProp(key) {
  return sh(`getprop ${key}`);
}

async function readOrderFile() {
  const raw = await sh(`cat "${ORDER_FILE}" 2>/dev/null`);
  return raw.split('\n')
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'));
}

async function getMountableModules() {
  const script = [
    'for MOD in ' + MODULES_DIR + '/*/; do',
    '  [ -d "$MOD" ] || continue',
    '  ID=$(basename "$MOD")',
    '  [ "$ID" = "meta-nomountfs" ] && continue',
    '  PARTS=""',
    '  for P in system vendor product system_ext odm oem; do',
    '    [ -d "$MOD$P" ] && PARTS="${PARTS:+${PARTS},}$P"',
    '  done',
    '  [ -z "$PARTS" ] && continue',
    '  DIS="-"; SM="-"',
    '  [ -f "${MOD}disable" ]    && DIS="D"',
    '  [ -f "${MOD}skip_mount" ] && SM="S"',
    '  printf "%s %s%s %s\n" "$ID" "$DIS" "$SM" "$PARTS"',
    'done',
  ].join('\n');
  const out = await sh(script);
  if (!out) return [];
  return out.split('\n').filter(Boolean).map(line => {
    const parts = line.trim().split(' ');
    const id       = parts[0];
    const flags    = parts[1] || '--';
    const partsStr = parts[2] || '';
    return {
      id,
      disabled:  flags.includes('D'),
      skipMount: flags.includes('S'),
      parts: partsStr ? partsStr.split(',') : [],
    };
  });
}

// ── Mount State Check ──────────────────────────────────────────
// Instead of checking files individually, we just check /proc/mounts to see 
// if the module's path is listed in the `lowerdir=` string for that partition.
// ── Mount State Check ──────────────────────────────────────────
async function getModuleMountStates(modules) {
  if (!modules.length) return new Map();

  const mpRaw = await sh(`grep '${MODULES_DIR}' /proc/mounts`);
  const mountedPathsStr = mpRaw || ''; 

  const states = new Map();
  for (const mod of modules) {
    const modMap = new Map();
    for (const part of mod.parts) {
      // exact path (ej. /data/adb/modules/ViPER4AndroidFX/vendor)
      const modDir = `${MODULES_DIR}/${mod.id}/${part}`;
      
      // Is this module's directory present in ANY lowerdir string?
      const inStack = mountedPathsStr.includes(modDir);
      modMap.set(part, inStack);
    }
    states.set(mod.id, modMap);
  }
  return states;
}

// ══════════════════════════════════════════════════════════════════════════
// ── NAV ──
// ══════════════════════════════════════════════════════════════════════════
const navItems = document.querySelectorAll('.nav-item');
const views    = document.querySelectorAll('.view');

navItems.forEach(item => {
  item.addEventListener('click', () => {
    navItems.forEach(n => n.classList.remove('active'));
    views.forEach(v => v.classList.remove('active'));
    item.classList.add('active');
    const view = document.getElementById(item.dataset.view);
    if (view) view.classList.add('active');

    if (item.dataset.view === 'view-mounts') loadMountsView();
    if (item.dataset.view === 'view-order')  loadOrderView();
  });
});

async function loadHome() {
  const [model, brand, android, kernel, mountsRaw, orderRaw] = await Promise.all([
    getProp('ro.product.model'),
    getProp('ro.product.brand'),
    getProp('ro.build.version.release'),
    sh('uname -r'),
    sh(`grep '${MODULES_DIR}' /proc/mounts 2>/dev/null | wc -l`),
    readOrderFile(),
  ]);

  document.getElementById('h-device').textContent  = `${brand} ${model}`;
  document.getElementById('h-android').textContent = `Android ${android}`;
  document.getElementById('h-kernel').textContent  = kernel;
  document.getElementById('h-mounts').textContent  = mountsRaw.trim() || '0';
  document.getElementById('h-modcount').textContent = orderRaw.length;

  const nomountfsOk = await sh('grep -q nomountfs /proc/filesystems 2>/dev/null && echo 1 || echo 0');
  const sub = document.getElementById('status-sub');
  const card = document.getElementById('status-card');
  if (nomountfsOk === '1') {
    sub.textContent = 'NoMountFS driver active';
    card.style.background = '#0d2e0d';
    card.style.color = '#c8e6c9';
    document.getElementById('status-icon-glyph').textContent = 'check_circle';
  } else {
    sub.textContent = 'NoMountFS NOT in /proc/filesystems';
    card.style.background = 'var(--md-sys-color-error-container)';
    card.style.color = 'var(--md-sys-color-on-error-container)';
    document.getElementById('status-icon-glyph').textContent = 'error';
  }
}

async function loadMountsView() {
  const list = document.getElementById('mounts-list');
  list.innerHTML = '<div class="empty-state"><span class="spinner" style="width:32px;height:32px;border-width:3px"></span></div>';

  const modules = await getMountableModules();
  if (!modules.length) {
    list.innerHTML = '<div class="empty-state"><span class="icon">inbox</span>No mountable modules found</div>';
    return;
  }

  const mountStates = await getModuleMountStates(modules);
  list.innerHTML = '';

  for (const mod of modules) {
    const modStates = mountStates.get(mod.id) || new Map();
    const mountedParts   = mod.parts.filter(p => modStates.get(p) === true);
    const unmountedParts = mod.parts.filter(p => modStates.get(p) !== true);
    const allMounted  = unmountedParts.length === 0;
    const anyMounted  = mountedParts.length > 0;
    const state = allMounted ? 'mounted' : anyMounted ? 'partial' : 'unmounted';

    const card = document.createElement('div');
    card.className = 'module-card ' + (state === 'unmounted' ? 'unmounted' : 'mounted');
    card.dataset.modid = mod.id;

    const partPills = mod.parts.map(function(p) {
      const isMounted = modStates.get(p) === true;
      const style = isMounted ? 'background:#1b3a1b;color:#66bb6a' : 'background:#2a1a1a;color:#ef9a9a';
      return '<span class="part-pill" style="' + style + '">' + p + '</span>';
    }).join('');

    const flagChips = [
      mod.disabled  ? '<span class="flag-chip disabled-chip">disabled</span>'   : '',
      mod.skipMount ? '<span class="flag-chip skipmount-chip">skip_mount</span>' : '',
    ].join('');

    const stateLabel = state === 'mounted' ? 'mounted' : state === 'partial' ? 'partial' : 'not mounted';
    const badgeClass = state === 'unmounted' ? 'mod-badge off' : 'mod-badge';
    const btnLabel   = state === 'unmounted' ? 'Mount'   : 'Unmount';
    const btnClass   = state === 'unmounted' ? 'btn btn-mount' : 'btn btn-umount';
    const iconGlyph  = state === 'unmounted' ? 'upload'  : 'eject';

    card.innerHTML =
      '<div class="mod-icon"><span class="icon">extension</span></div>' +
      '<div class="mod-info">' +
        '<div class="mod-name">' + mod.id + '</div>' +
        '<div class="mod-sub" style="margin-bottom:4px">' + partPills + flagChips + '</div>' +
        '<span class="' + badgeClass + '">' + stateLabel + '</span>' +
      '</div>' +
      '<button class="btn ' + btnClass + '" data-action="' + (state === 'unmounted' ? 'mount' : 'umount') + '">' +
        '<span class="icon" style="font-size:16px">' + iconGlyph + '</span>' + btnLabel +
      '</button>';

    card.querySelector('button').addEventListener('click', function() {
      handleMountToggle(mod, card, card.querySelector('button'));
    });

    list.appendChild(card);
  }
}

// ── Toggle ──────────────────────────────────────────────
async function handleMountToggle(mod, card, btn) {
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span>';

  const action = btn.dataset.action;

  // We delegate the heavy lifting directly to the optimized metamount/uninstall scripts!
  if (action === 'mount') {
    // Instead of rebuilding logic in JS, we just trigger the mount script 
    // but ONLY for the missing partitions of this specific module (to save time).
    // For a robust system, simply calling metamount.sh refreshes everything instantly.
    await exec(`${META_DIR}/metamount.sh`);
    
    toast('✓ Re-mounted with ' + mod.id);
    card.className = 'module-card mounted';
    card.querySelector('.mod-badge').textContent = 'mounted';
    card.querySelector('.mod-badge').className = 'mod-badge';
    btn.innerHTML = '<span class="icon" style="font-size:16px">eject</span>Unmount';
    btn.className = 'btn btn-umount';
    btn.dataset.action = 'umount';
    card.querySelectorAll('.part-pill').forEach(el => {
      el.style.background = '#1b3a1b'; el.style.color = '#66bb6a';
    });
  } else {
    // Unmount using the ultra-fast metauninstall hook logic
    await exec(`${META_DIR}/metauninstall.sh ${mod.id}`);
    
    toast('✓ Unmounted ' + mod.id);
    card.className = 'module-card unmounted';
    card.querySelector('.mod-badge').textContent = 'not mounted';
    card.querySelector('.mod-badge').className = 'mod-badge off';
    btn.innerHTML = '<span class="icon" style="font-size:16px">upload</span>Mount';
    btn.className = 'btn btn-mount';
    btn.dataset.action = 'mount';
    card.querySelectorAll('.part-pill').forEach(el => {
      el.style.background = '#2a1a1a'; el.style.color = '#ef9a9a';
    });
  }

  btn.disabled = false;
  // Refresh view to ensure accurate state across all modules
  loadMountsView(); 
}

// ══════════════════════════════════════════════════════════════════════════
// ── ORDER VIEW ──
// ══════════════════════════════════════════════════════════════════════════
let _originalOrder = [];
let _currentOrder  = [];

async function loadOrderView() {
  const orderList = document.getElementById('order-list');
  orderList.innerHTML = `<div class="empty-state"><span class="spinner" style="width:32px;height:32px;border-width:3px"></span></div>`;
  document.getElementById('btn-save-order').disabled = true;

  _originalOrder = await readOrderFile();
  _currentOrder  = [..._originalOrder];

  if (!_currentOrder.length) {
    orderList.innerHTML = `<div class="empty-state"><span class="icon">sort</span>mount_order is empty</div>`;
    return;
  }

  renderOrderList();
  document.getElementById('btn-save-order').disabled = true;
}

function renderOrderList() {
  const list = document.getElementById('order-list');
  list.innerHTML = '';
  const total = _currentOrder.length;

  _currentOrder.forEach((id, i) => {
    const item = document.createElement('div');
    item.className = 'order-item';
    item.draggable = true;
    item.dataset.index = i;

    const priority = i === total - 1 ? 'highest' : i === 0 ? 'lowest' : `#${i + 1}`;

    item.innerHTML = `
      <span class="icon drag-handle">drag_indicator</span>
      <div class="order-badge">${i + 1}</div>
      <span class="order-name">${id}</span>
      <span class="order-hint">${priority}</span>`;

    item.addEventListener('dragstart', onDragStart);
    item.addEventListener('dragover',  onDragOver);
    item.addEventListener('dragleave', onDragLeave);
    item.addEventListener('drop',      onDrop);
    item.addEventListener('dragend',   onDragEnd);

    item.addEventListener('touchstart', onTouchStart, { passive: true });
    item.addEventListener('touchmove',  onTouchMove,  { passive: false });
    item.addEventListener('touchend',   onTouchEnd,   { passive: true });

    list.appendChild(item);
  });
}

let _dragIdx = null;
let _touchItem = null;
let _touchStartY = 0;
let _touchLastY  = 0;

function onDragStart(e) {
  _dragIdx = +e.currentTarget.dataset.index;
  e.currentTarget.classList.add('dragging');
  e.dataTransfer.effectAllowed = 'move';
}
function onDragOver(e) {
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';
  e.currentTarget.classList.add('drag-over');
}
function onDragLeave(e) { e.currentTarget.classList.remove('drag-over'); }
function onDrop(e) {
  e.preventDefault();
  e.currentTarget.classList.remove('drag-over');
  const targetIdx = +e.currentTarget.dataset.index;
  if (_dragIdx !== null && _dragIdx !== targetIdx) {
    reorderItems(_dragIdx, targetIdx);
  }
}
function onDragEnd(e) {
  e.currentTarget.classList.remove('dragging');
  document.querySelectorAll('.order-item').forEach(i => i.classList.remove('drag-over'));
  _dragIdx = null;
}

function onTouchStart(e) {
  _touchItem = e.currentTarget;
  _touchStartY = e.touches[0].clientY;
  _touchLastY  = _touchStartY;
  _dragIdx = +_touchItem.dataset.index;
  _touchItem.classList.add('dragging');
}
function onTouchMove(e) {
  e.preventDefault();
  const y = e.touches[0].clientY;
  _touchLastY = y;
  const el = document.elementFromPoint(e.touches[0].clientX, y);
  const target = el && el.closest('.order-item');
  document.querySelectorAll('.order-item').forEach(i => i.classList.remove('drag-over'));
  if (target && target !== _touchItem) target.classList.add('drag-over');
}
function onTouchEnd(e) {
  if (!_touchItem) return;
  const el = document.elementFromPoint(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
  const target = el && el.closest('.order-item');
  if (target && target !== _touchItem) {
    reorderItems(_dragIdx, +target.dataset.index);
  } else {
    _touchItem.classList.remove('dragging');
    document.querySelectorAll('.order-item').forEach(i => i.classList.remove('drag-over'));
  }
  _touchItem = null;
  _dragIdx = null;
}

function reorderItems(from, to) {
  const item = _currentOrder.splice(from, 1)[0];
  _currentOrder.splice(to, 0, item);
  renderOrderList();
  const changed = _currentOrder.some((id, i) => id !== _originalOrder[i]);
  document.getElementById('btn-save-order').disabled = !changed;
}

document.getElementById('btn-save-order').addEventListener('click', async function() {
  var btn = document.getElementById('btn-save-order');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Saving…';

  var header = "# mount_order — managed by meta-nomountfs\n"
             + "# One module ID per line. Top = lowest priority, bottom = highest.\n"
             + "# Only modules with partition folders are listed.\n"
             + "# Edit manually to reorder. metainstall.sh appends new installs here.";
  await exec("printf '%s\\n' " + JSON.stringify(header) + " > " + ORDER_FILE);

  for (var i = 0; i < _currentOrder.length; i++) {
    var id = _currentOrder[i];
    await exec("printf '%s\\n' " + JSON.stringify(id) + " >> " + ORDER_FILE);
  }

  _originalOrder = _currentOrder.slice();
  toast('✓ mount_order saved — takes effect on next boot');
  btn.innerHTML = '<span class="icon" style="font-size:18px">save</span> Save Order';
  btn.disabled = true;
});

loadHome();
