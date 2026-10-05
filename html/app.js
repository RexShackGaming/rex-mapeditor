const app = document.getElementById('app');
const propCategories = document.getElementById('propCategories');
const searchBox = document.getElementById('searchBox');
const placedList = document.getElementById('placedList');
const mapNameInput = document.getElementById('mapNameInput');
const placementPanel = document.getElementById('placementPanel');
const placementHeader = document.getElementById('placementHeader');
const placementModelLabel = document.getElementById('placementModelLabel');
const fastToggle = document.getElementById('fastToggle');

let spooniPropList = [];    // from spooni_props.json (huge, only searched)
let spooniLoaded = false;
let currentPlaced = [];
let currentRemovals = []; // world props removed for the current map [{model(hash), x, y, z}]
let favorites = [];         // [{model, label}], persisted server-side, shared by all tool users
let favoriteModels = new Set();
let customAdditions = [];   // [{model, label, category}], user-added library props, persisted server-side, shared by all tool users
let customModelsSet = new Set(); // models of the entries in customAdditions - lets a row know it's user-added (label+category directly editable) vs bundled (label-only override)
let customRemovals = new Set(); // models blacklisted from the library (hides them from the bundled list or from customAdditions)
let customOverrides = {};   // { [model]: {label} }, label overrides for bundled (non-custom) props, persisted server-side, shared by all tool users
let editingKey = null;      // origModel of the row currently shown in inline edit mode in the Prop Library, if any
let openKey = 'F6';         // from Config.OpenKey - also closes the menu while it's open (see keydown listener below)

// ---------------------------------------------------------------------
// Localisation: strings come from locales/<lang>.json (ui_* keys) via the
// client 'locales' message. The English text in index.html is the fallback.
// ---------------------------------------------------------------------
let i18n = {};

function t(key, ...args) {
  let str = i18n[key];
  if (typeof str !== 'string') return key;
  for (const a of args) str = str.replace('%s', a);
  return str;
}

function applyLocales() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    if (i18n[el.dataset.i18n]) el.textContent = i18n[el.dataset.i18n];
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    if (i18n[el.dataset.i18nPlaceholder]) el.placeholder = i18n[el.dataset.i18nPlaceholder];
  });
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    if (i18n[el.dataset.i18nTitle]) el.title = i18n[el.dataset.i18nTitle];
  });
  document.getElementById('closeBtn').textContent = t('ui_close', openKey);
}

const MAX_RENDERED_ITEMS = 250; // cap DOM nodes when searching the full Spooni library

async function loadSpooniProps() {
  if (spooniLoaded) return;
  try {
    const res = await fetch('props.json');
    spooniPropList = await res.json();
  } catch (e) {
    spooniPropList = [];
  }
  spooniLoaded = true;
}

// Custom confirm modal - window.confirm() can hang/lock the CEF NUI
// browser, so anything needing an "are you sure?" prompt uses this
// promise-based modal instead. Resolves true/false.
const confirmOverlay = document.getElementById('confirmOverlay');
const confirmMessage = document.getElementById('confirmMessage');
const confirmOkBtn = document.getElementById('confirmOkBtn');
const confirmCancelBtn = document.getElementById('confirmCancelBtn');
let confirmResolve = null;

function showConfirm(message) {
  confirmMessage.textContent = message;
  confirmOverlay.classList.remove('hidden');
  return new Promise((resolve) => {
    confirmResolve = resolve;
  });
}

function closeConfirm(result) {
  confirmOverlay.classList.add('hidden');
  if (confirmResolve) {
    const resolve = confirmResolve;
    confirmResolve = null;
    resolve(result);
  }
}

confirmOkBtn.onclick = () => closeConfirm(true);
confirmCancelBtn.onclick = () => closeConfirm(false);
confirmOverlay.addEventListener('click', (e) => {
  if (e.target === confirmOverlay) closeConfirm(false);
});

function post(name, data) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).catch(() => {});
}

// Every row is rendered from a resolved entry shape, computed upstream by
// the build*Entries() functions below:
//   { model, label, category, origModel, isCustom }
// - model/label/category are what's actually shown/spawned (after any
//   override or direct edit has been applied).
// - origModel is the STABLE identity used to target edits/removals/favorites
//   server-side: for a custom addition it's just its own model; for a
//   bundled (Spooni) prop it's the model as it appears in props.json, even
//   after the display model has been renamed via an override, so repeated
//   edits keep landing on the same saved override slot instead of creating
//   new ones.

// Inline edit form shown in place of a row's label/buttons while it's being
// edited. Model, label, and category are all editable and all saveable
// blank - nothing here is required to submit.
// Small persistent label above an edit-form input, since the input's
// placeholder text disappears as soon as it has a value (which every field
// here starts pre-filled with).
function addFieldLabel(container, text) {
  const el = document.createElement('label');
  el.className = 'fieldLabel';
  el.textContent = text;
  container.appendChild(el);
}

function buildEditForm(entry) {
  const wrap = document.createElement('div');
  wrap.className = 'editForm';

  addFieldLabel(wrap, t('ui_field_model'));
  const modelInput = document.createElement('input');
  modelInput.type = 'text';
  modelInput.value = entry.model;
  modelInput.placeholder = t('ui_field_model');
  wrap.appendChild(modelInput);

  addFieldLabel(wrap, t('ui_field_label'));
  const labelInput = document.createElement('input');
  labelInput.type = 'text';
  labelInput.value = entry.label;
  labelInput.placeholder = t('ui_field_label');
  wrap.appendChild(labelInput);

  addFieldLabel(wrap, t('ui_field_category'));
  const categoryInput = document.createElement('input');
  categoryInput.type = 'text';
  categoryInput.value = entry.category;
  categoryInput.placeholder = t('ui_field_category');
  wrap.appendChild(categoryInput);

  const actions = document.createElement('div');
  actions.className = 'editFormActions';

  const saveBtn = document.createElement('button');
  saveBtn.className = 'success';
  saveBtn.textContent = t('ui_save');
  saveBtn.onclick = () => {
    post('editLibraryProp', {
      model: entry.origModel,
      newModel: modelInput.value.trim(),
      label: labelInput.value.trim(),
      category: categoryInput.value.trim()
    });
    editingKey = null;
    renderCategories(searchBox.value);
  };

  const cancelBtn = document.createElement('button');
  cancelBtn.textContent = t('ui_cancel');
  cancelBtn.onclick = () => {
    editingKey = null;
    renderCategories(searchBox.value);
  };

  actions.appendChild(saveBtn);
  actions.appendChild(cancelBtn);
  wrap.appendChild(actions);
  return wrap;
}

function renderCategoryList(container, categories, remainingBudget) {
  let rendered = 0;
  for (const cat of categories) {
    if (rendered >= remainingBudget) break;
    if (cat.props.length === 0) continue;

    const catDiv = document.createElement('div');
    catDiv.className = 'category';
    const h3 = document.createElement('h3');
    h3.textContent = cat.category;
    catDiv.appendChild(h3);

    for (const entry of cat.props) {
      if (rendered >= remainingBudget) break;
      const row = document.createElement('div');
      row.className = 'propItem';

      if (editingKey === entry.origModel) {
        row.appendChild(buildEditForm(entry));
        catDiv.appendChild(row);
        rendered++;
        continue;
      }

      const label = document.createElement('span');
      label.textContent = entry.label;

      const isFav = favoriteModels.has(entry.origModel);
      const favBtn = document.createElement('button');
      favBtn.className = 'favBtn' + (isFav ? ' active' : '');
      favBtn.textContent = isFav ? '★' : '☆';
      favBtn.title = t(isFav ? 'ui_unfavorite' : 'ui_favorite');
      favBtn.onclick = () => {
        if (isFav) {
          post('unfavoriteProp', { model: entry.origModel });
        } else {
          post('favoriteProp', { model: entry.origModel, label: entry.label });
        }
      };

      const btn = document.createElement('button');
      btn.textContent = t('ui_spawn');
      btn.onclick = () => post('spawnProp', { model: entry.model });

      const editBtn = document.createElement('button');
      editBtn.className = 'editBtn';
      editBtn.textContent = '✎';
      editBtn.title = t('ui_edit_entry');
      editBtn.onclick = () => {
        editingKey = entry.origModel;
        renderCategories(searchBox.value);
      };

      const removeBtn = document.createElement('button');
      removeBtn.className = 'removeBtn';
      removeBtn.textContent = '✕';
      removeBtn.title = t('ui_remove_entry');
      removeBtn.onclick = () => {
        showConfirm(t('ui_confirm_remove_entry', entry.label)).then((ok) => {
          if (!ok) return;
          if (isFav) post('unfavoriteProp', { model: entry.origModel });
          post('removeLibraryProp', { model: entry.origModel });
        });
      };

      row.appendChild(label);
      row.appendChild(favBtn);
      row.appendChild(btn);
      row.appendChild(editBtn);
      row.appendChild(removeBtn);
      catDiv.appendChild(row);
      rendered++;
    }
    container.appendChild(catDiv);
  }
  return rendered;
}

function buildFavoriteEntries(filter) {
  const props = favorites
    .filter(f => !filter || f.label.toLowerCase().includes(filter) || f.model.toLowerCase().includes(filter))
    .map(f => ({ model: f.model, label: f.label, category: '★ ' + t('ui_favorites'), origModel: f.model, isCustom: customModelsSet.has(f.model) }));
  return props.length ? [{ category: '★ ' + t('ui_favorites'), props }] : [];
}

// Custom props added via the "+ Add to Library" form (or later edited),
// grouped by whatever category they currently have - blank falls under
// "Uncategorized" for display only, the stored category stays blank.
function buildCustomEntries(filter) {
  const byCategory = new Map();
  for (const p of customAdditions) {
    if (filter && !(p.label.toLowerCase().includes(filter) || p.model.toLowerCase().includes(filter))) continue;
    const cat = p.category || t('ui_uncategorized');
    if (!byCategory.has(cat)) byCategory.set(cat, []);
    byCategory.get(cat).push({ model: p.model, label: p.label, category: p.category || '', origModel: p.model, isCustom: true });
  }
  return Array.from(byCategory.entries()).map(([category, props]) => ({ category, props }));
}

// The bundled Spooni library, with any saved edits (model/label/category
// overrides) applied on top - including moving an entry into a different
// category if its category override says so. Only computed once the user
// has typed 2+ characters, same as before.
function buildBundledEntries(filter) {
  const byCategory = new Map();
  for (const cat of spooniPropList) {
    for (const p of cat.props) {
      if (customRemovals.has(p.model) || customModelsSet.has(p.model)) continue;
      const ov = customOverrides[p.model];
      // ov.model === '' means "no rename requested" (a blank model can't be
      // spawned, so it isn't treated as an override). ov.label/ov.category
      // can genuinely be saved blank once an override exists at all - a
      // blank category groups the prop under "Uncategorized".
      const model = (ov && ov.model) ? ov.model : p.model;
      const label = ov ? ov.label : p.label;
      const category = ov ? (ov.category || t('ui_uncategorized')) : cat.category;
      if (filter && !(label.toLowerCase().includes(filter) || model.toLowerCase().includes(filter))) continue;
      if (!byCategory.has(category)) byCategory.set(category, []);
      byCategory.get(category).push({ model, label, category, origModel: p.model, isCustom: false });
    }
  }
  return Array.from(byCategory.entries()).map(([category, props]) => ({ category, props }));
}

function renderCategories(filterText) {
  propCategories.innerHTML = '';
  const filter = (filterText || '').toLowerCase().trim();

  // Favorites always show first (unfiltered list still respects the search
  // box like everything else) so props saved from a search are easy to find
  // again without re-searching.
  let rendered = 0;
  rendered += renderCategoryList(propCategories, buildFavoriteEntries(filter), MAX_RENDERED_ITEMS - rendered);

  // Custom props are always shown too, same as favorites, so they don't
  // need to be re-searched either.
  rendered += renderCategoryList(propCategories, buildCustomEntries(filter), MAX_RENDERED_ITEMS - rendered);

  // No curated/static list - everything else comes from live search across
  // the full Spooni library (14,856 props) once the user types 2+ characters.
  if (filter.length >= 2 && spooniLoaded) {
    rendered += renderCategoryList(propCategories, buildBundledEntries(filter), MAX_RENDERED_ITEMS - rendered);
  }

  if (filter.length >= 2 && rendered >= MAX_RENDERED_ITEMS) {
    const note = document.createElement('div');
    note.style.cssText = 'font-size:11px;opacity:0.6;margin-top:6px;';
    note.textContent = t('ui_results_capped', MAX_RENDERED_ITEMS);
    propCategories.appendChild(note);
  } else if (filter.length === 1) {
    const note = document.createElement('div');
    note.style.cssText = 'font-size:11px;opacity:0.6;margin-top:6px;';
    note.textContent = t('ui_keep_typing');
    propCategories.appendChild(note);
  } else if (filter.length === 0 && favorites.length === 0 && customAdditions.length === 0) {
    const note = document.createElement('div');
    note.style.cssText = 'font-size:11px;opacity:0.6;margin-top:6px;';
    note.textContent = t('ui_library_empty');
    propCategories.appendChild(note);
  }
}

function renderPlacedList() {
  placedList.innerHTML = '';
  if (currentPlaced.length === 0) {
    const empty = document.createElement('div');
    empty.style.cssText = 'opacity:0.5; font-size:12px;';
    empty.textContent = t('ui_no_props');
    placedList.appendChild(empty);
    return;
  }
  currentPlaced.forEach(p => {
    const row = document.createElement('div');
    row.className = 'placedItem';
    const info = document.createElement('div');
    info.className = 'info';
    info.textContent = `${p.model}  (${p.x.toFixed(2)}, ${p.y.toFixed(2)}, ${p.z.toFixed(2)})`;
    const actions = document.createElement('div');
    actions.className = 'actions';

    const tpBtn = document.createElement('button');
    tpBtn.textContent = t('ui_teleport');
    tpBtn.onclick = () => post('teleportTo', { localId: p.localId });

    const delBtn = document.createElement('button');
    delBtn.textContent = t('ui_delete');
    delBtn.className = 'danger';
    delBtn.onclick = () => post('deleteProp', { localId: p.localId });

    actions.appendChild(tpBtn);
    actions.appendChild(delBtn);
    row.appendChild(info);
    row.appendChild(actions);
    placedList.appendChild(row);
  });
}

const removedList = document.getElementById('removedList');
const toggleRemovedBtn = document.getElementById('toggleRemovedBtn');

function renderRemovedList() {
  document.getElementById('removedCount').textContent = currentRemovals.length;
  toggleRemovedBtn.textContent = t(removedList.classList.contains('hidden') ? 'ui_show' : 'ui_hide');
  removedList.innerHTML = '';
  if (currentRemovals.length === 0) {
    const empty = document.createElement('div');
    empty.style.cssText = 'opacity:0.5; font-size:12px;';
    empty.textContent = t('ui_no_removed');
    removedList.appendChild(empty);
    return;
  }
  currentRemovals.forEach((r, i) => {
    const unsigned = (r.model >>> 0);
    const name = (hashNameMap && hashNameMap.get(unsigned)) || `0x${unsigned.toString(16).toUpperCase()}`;
    const row = document.createElement('div');
    row.className = 'placedItem';
    const info = document.createElement('div');
    info.className = 'info';
    info.textContent = `${name}  (${r.x.toFixed(2)}, ${r.y.toFixed(2)}, ${r.z.toFixed(2)})`;
    info.title = `${r.model}`;
    const actions = document.createElement('div');
    actions.className = 'actions';

    // Lua arrays are 1-based
    const tpBtn = document.createElement('button');
    tpBtn.textContent = t('ui_teleport');
    tpBtn.onclick = () => post('teleportToRemoval', { index: i + 1 });

    const restoreBtn = document.createElement('button');
    restoreBtn.textContent = t('ui_restore');
    restoreBtn.className = 'success';
    restoreBtn.onclick = () => {
      showConfirm(t('ui_confirm_restore', name)).then((ok) => {
        if (ok) post('restoreRemoval', { index: i + 1 });
      });
    };

    actions.appendChild(tpBtn);
    actions.appendChild(restoreBtn);
    row.appendChild(info);
    row.appendChild(actions);
    removedList.appendChild(row);
  });
}

toggleRemovedBtn.onclick = () => {
  removedList.classList.toggle('hidden');
  if (!removedList.classList.contains('hidden')) ensureHashMap().then(renderRemovedList);
  else renderRemovedList();
};

document.getElementById('spawnCustomBtn').onclick = () => {
  const val = searchBox.value.trim();
  if (!val) return;
  post('spawnProp', { model: val });
};

document.getElementById('closeBtn').onclick = () => post('close');

document.getElementById('addPropBtn').onclick = () => {
  const modelInput = document.getElementById('addPropModel');
  const labelInput = document.getElementById('addPropLabel');
  const categoryInput = document.getElementById('addPropCategory');
  const model = modelInput.value.trim();
  if (!model) return;
  post('addLibraryProp', {
    model,
    label: labelInput.value.trim(),
    category: categoryInput.value.trim()
  });
  modelInput.value = '';
  labelInput.value = '';
  categoryInput.value = '';
};

// Mirror the server's sanitizer so the name shown is the name used.
function currentMapName() {
  const clean = mapNameInput.value.trim().replace(/[^\w-]/g, '').slice(0, 48) || 'default';
  mapNameInput.value = clean;
  return clean;
}

document.getElementById('saveMapBtn').onclick = () => {
  post('saveMap', { mapname: currentMapName() });
};

document.getElementById('loadMapBtn').onclick = () => {
  post('loadMap', { mapname: currentMapName() });
};

document.getElementById('exportBtn').onclick = () => {
  post('exportYmap', { mapname: currentMapName() });
};

document.getElementById('clearBtn').onclick = () => {
  showConfirm(t('ui_confirm_clear_all')).then((ok) => {
    if (ok) post('clearAll');
  });
};

// Debounced so typing doesn't rebuild the 14k-prop search on every key.
let searchTimer = null;
searchBox.addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => renderCategories(searchBox.value), 150);
});

window.addEventListener('message', (event) => {
  const data = event.data;
  switch (data.action) {
    case 'open':
      mapNameInput.value = data.mapname;
      if (data.openKey) {
        openKey = data.openKey;
        applyLocales();
      }
      app.classList.remove('hidden');
      renderCategories(searchBox.value);
      loadSpooniProps().then(() => renderCategories(searchBox.value));
      break;
    case 'locales':
      i18n = data.locales || {};
      applyLocales();
      renderCategories(searchBox.value);
      renderPlacedList();
      renderRemovedList();
      break;
    case 'close':
      app.classList.add('hidden');
      break;
    case 'hide':
      app.classList.add('hidden');
      break;
    case 'show':
      app.classList.remove('hidden');
      break;
    case 'removedList':
      currentRemovals = data.removals || [];
      renderRemovedList();
      break;
    case 'refreshList':
      currentPlaced = data.props;
      renderPlacedList();
      break;
    case 'favoritesList':
      favorites = data.favorites || [];
      favoriteModels = new Set(favorites.map(f => f.model));
      renderCategories(searchBox.value);
      break;
    case 'customPropsList':
      customAdditions = (data.customProps && data.customProps.additions) || [];
      customModelsSet = new Set(customAdditions.map(p => p.model));
      customRemovals = new Set((data.customProps && data.customProps.removals) || []);
      customOverrides = (data.customProps && data.customProps.overrides) || {};
      renderCategories(searchBox.value);
      break;
    case 'showPlacement':
      placementModelLabel.textContent = data.model || t('ui_prop');
      placementPanel.classList.remove('hidden');
      break;
    case 'hidePlacement':
      placementPanel.classList.add('hidden');
      break;
    case 'showInspector':
      showInspector(data);
      break;
    case 'hideInspector':
      document.getElementById('inspector').classList.add('hidden');
      break;
  }
});

// ---------------------------------------------------------------------
// Placement Panel: dragging + click/hold-to-repeat buttons
// ---------------------------------------------------------------------

(function initPlacementPanel() {
  // Dragging - grab anywhere on the header, release anywhere.
  let dragOffset = null;

  placementHeader.addEventListener('mousedown', (e) => {
    dragOffset = { x: e.clientX - placementPanel.offsetLeft, y: e.clientY - placementPanel.offsetTop };
    e.preventDefault();
  });

  document.addEventListener('mousemove', (e) => {
    if (!dragOffset) return;
    let x = e.clientX - dragOffset.x;
    let y = e.clientY - dragOffset.y;
    x = Math.max(0, Math.min(window.innerWidth - placementPanel.offsetWidth, x));
    y = Math.max(0, Math.min(window.innerHeight - placementPanel.offsetHeight, y));
    placementPanel.style.left = x + 'px';
    placementPanel.style.top = y + 'px';
    placementPanel.style.right = 'auto';
  });

  document.addEventListener('mouseup', () => { dragOffset = null; });

  // A single click nudges once; holding the button repeats it, same as
  // holding the equivalent key would. 350ms delay before repeat kicks in
  // avoids a double-step on a normal click.
  function bindHold(el, fire) {
    if (!el) return;
    let interval = null;
    let delay = null;
    const start = (e) => {
      e.preventDefault();
      fire();
      delay = setTimeout(() => {
        interval = setInterval(fire, 60);
      }, 350);
    };
    const stop = () => {
      clearTimeout(delay);
      clearInterval(interval);
      delay = null;
      interval = null;
    };
    el.addEventListener('mousedown', start);
    el.addEventListener('mouseup', stop);
    el.addEventListener('mouseleave', stop);
  }

  document.querySelectorAll('[data-move]').forEach(btn => {
    bindHold(btn, () => post('placementMove', { dir: btn.dataset.move, fast: fastToggle.checked }));
  });
  document.querySelectorAll('[data-height]').forEach(btn => {
    bindHold(btn, () => post('placementHeight', { dir: btn.dataset.height, fast: fastToggle.checked }));
  });
  document.querySelectorAll('[data-rotate]').forEach(btn => {
    bindHold(btn, () => post('placementRotate', { dir: btn.dataset.rotate, fast: fastToggle.checked }));
  });
  document.querySelectorAll('[data-pitch]').forEach(btn => {
    bindHold(btn, () => post('placementPitch', { dir: btn.dataset.pitch, fast: fastToggle.checked }));
  });

  document.getElementById('placementConfirmBtn').onclick = () => post('placementConfirm');
  document.getElementById('placementCancelBtn').onclick = () => post('placementCancel');
})();

document.addEventListener('keydown', (e) => {
  // Escape: close the confirm modal first, cancel placement if placing,
  // otherwise close the menu.
  if (e.key === 'Escape') {
    if (!confirmOverlay.classList.contains('hidden')) closeConfirm(false);
    else if (!placementPanel.classList.contains('hidden')) post('placementCancel');
    else post('close');
    return;
  }
  // Ignore the open key while typing in an input.
  if (e.target && e.target.tagName === 'INPUT' && (e.key || '').length === 1) return;
  // The menu grabs full keyboard focus while open (SetNuiFocus(true, true)),
  // which stops the game's own RegisterKeyMapping for Config.OpenKey (F6 by
  // default) from ever firing a second time - so re-pressing it here has to
  // be handled directly in the NUI instead.
  const pressed = (e.key || '').toUpperCase();
  if (!placementPanel.classList.contains('hidden')) return;
  const bound = (openKey || '').toUpperCase();
  if (bound && (pressed === bound || e.code.toUpperCase() === bound)) {
    post('close');
  }
});


// ---------------------------------------------------------------------
// Aim inspector (top-left info card)
// ---------------------------------------------------------------------
function joaat(str) {
  str = str.toLowerCase();
  let h = 0;
  for (let i = 0; i < str.length; i++) {
    h = (h + str.charCodeAt(i)) >>> 0;
    h = (h + (h << 10)) >>> 0;
    h = (h ^ (h >>> 6)) >>> 0;
  }
  h = (h + (h << 3)) >>> 0;
  h = (h ^ (h >>> 11)) >>> 0;
  h = (h + (h << 15)) >>> 0;
  return h;
}

let hashNameMap = null;
let hashMapBuilding = false;
async function ensureHashMap() {
  if (hashNameMap || hashMapBuilding) return;
  hashMapBuilding = true;
  await loadSpooniProps();
  const m = new Map();
  const add = (model) => { if (model) m.set(joaat(model), model); };
  for (const cat of spooniPropList || []) {
    if (cat && Array.isArray(cat.props)) cat.props.forEach(p => add(p.model));
    else if (cat && cat.model) add(cat.model);
  }
  (customAdditions || []).forEach(p => add(p.model));
  hashNameMap = m;
  hashMapBuilding = false;
}

function showInspector(d) {
  ensureHashMap();
  const el = document.getElementById('inspector');
  const unsigned = (d.hash >>> 0);
  const name = hashNameMap && hashNameMap.get(unsigned);
  const f = (n) => Number(n).toFixed(2);
  document.getElementById('inspModel').textContent = name || t('ui_insp_unknown_model');
  document.getElementById('inspHash').textContent = `${d.hash}  (0x${unsigned.toString(16).toUpperCase()})`;
  document.getElementById('inspType').textContent = t('ui_type_' + d.type);
  document.getElementById('inspCoords').textContent = `${f(d.x)}, ${f(d.y)}, ${f(d.z)}`;
  document.getElementById('inspRot').textContent = `${f(d.rx)}, ${f(d.ry)}, ${f(d.rz)}`;
  document.getElementById('inspDist').textContent = `${f(d.distance)} m`;
  document.getElementById('inspSource').textContent = d.placed ? t('ui_insp_placed', d.map) : t('ui_insp_world_prop');
  const flags = [];
  if (d.mission) flags.push(t('ui_flag_mission'));
  if (d.networked) flags.push(t('ui_flag_networked'));
  document.getElementById('inspFlags').textContent = flags.length ? flags.join(' · ') : t('ui_flag_none');

  const pill = document.getElementById('inspStatus');
  const note = document.getElementById('inspNote');
  pill.classList.remove('ok', 'bad', 'warn');
  if (!d.deletable) {
    pill.textContent = t('ui_status_no_delete'); pill.classList.add('bad');
    note.textContent = t('ui_note_no_delete');
  } else if (d.type === 'map' && !d.placed) {
    pill.textContent = t('ui_status_hide'); pill.classList.add('warn');
    note.textContent = t('ui_note_hide');
  } else if (d.networked && !d.placed) {
    pill.textContent = t('ui_status_maybe'); pill.classList.add('warn');
    note.textContent = t('ui_note_networked');
  } else {
    pill.textContent = t('ui_status_deletable'); pill.classList.add('ok');
    note.textContent = '';
  }
  note.style.display = note.textContent ? 'block' : 'none';
  el.classList.remove('hidden');
}
