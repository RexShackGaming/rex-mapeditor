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
let favorites = [];         // [{model, label}], persisted server-side, shared by all tool users
let favoriteModels = new Set();
let openKey = 'F6';         // from Config.OpenKey - also closes the menu while it's open (see keydown listener below)

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

function post(name, data) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  }).catch(() => {});
}

function renderCategoryList(container, categories, filter, remainingBudget) {
  let rendered = 0;
  for (const cat of categories) {
    if (rendered >= remainingBudget) break;
    const matching = cat.props.filter(p =>
      !filter || p.label.toLowerCase().includes(filter) || p.model.toLowerCase().includes(filter)
    );
    if (matching.length === 0) continue;

    const catDiv = document.createElement('div');
    catDiv.className = 'category';
    const h3 = document.createElement('h3');
    h3.textContent = cat.category;
    catDiv.appendChild(h3);

    for (const p of matching) {
      if (rendered >= remainingBudget) break;
      const row = document.createElement('div');
      row.className = 'propItem';
      const label = document.createElement('span');
      label.textContent = p.label;

      const isFav = favoriteModels.has(p.model);
      const favBtn = document.createElement('button');
      favBtn.className = 'favBtn' + (isFav ? ' active' : '');
      favBtn.textContent = isFav ? '★' : '☆';
      favBtn.title = isFav ? 'Remove from favorites' : 'Save as favorite';
      favBtn.onclick = () => {
        if (isFav) {
          post('unfavoriteProp', { model: p.model });
        } else {
          post('favoriteProp', { model: p.model, label: p.label });
        }
      };

      const btn = document.createElement('button');
      btn.textContent = 'Spawn';
      btn.onclick = () => post('spawnProp', { model: p.model });

      row.appendChild(label);
      row.appendChild(favBtn);
      row.appendChild(btn);
      catDiv.appendChild(row);
      rendered++;
    }
    container.appendChild(catDiv);
  }
  return rendered;
}

function renderCategories(filterText) {
  propCategories.innerHTML = '';
  const filter = (filterText || '').toLowerCase().trim();

  // Favorites always show first (unfiltered list still respects the search
  // box like everything else) so props saved from a search are easy to find
  // again without re-searching.
  let rendered = 0;
  if (favorites.length > 0) {
    const favCategory = { category: '★ Favorites', props: favorites };
    rendered += renderCategoryList(propCategories, [favCategory], filter, MAX_RENDERED_ITEMS);
  }

  // No curated/static list - everything else comes from live search across
  // the full Spooni library (14,856 props) once the user types 2+ characters.
  if (filter.length >= 2 && spooniLoaded) {
    rendered += renderCategoryList(propCategories, spooniPropList, filter, MAX_RENDERED_ITEMS - rendered);
  }

  if (filter.length >= 2 && rendered >= MAX_RENDERED_ITEMS) {
    const note = document.createElement('div');
    note.style.cssText = 'font-size:11px;opacity:0.6;margin-top:6px;';
    note.textContent = `Showing first ${MAX_RENDERED_ITEMS} matches - refine your search to narrow further.`;
    propCategories.appendChild(note);
  } else if (filter.length === 1) {
    const note = document.createElement('div');
    note.style.cssText = 'font-size:11px;opacity:0.6;margin-top:6px;';
    note.textContent = 'Keep typing (2+ characters) to search the full 14,856-prop Spooni library.';
    propCategories.appendChild(note);
  } else if (filter.length === 0 && favorites.length === 0) {
    const note = document.createElement('div');
    note.style.cssText = 'font-size:11px;opacity:0.6;margin-top:6px;';
    note.textContent = 'Search for a prop above, or star one to save it as a favorite.';
    propCategories.appendChild(note);
  }
}

function renderPlacedList() {
  placedList.innerHTML = '';
  if (currentPlaced.length === 0) {
    placedList.innerHTML = '<div style="opacity:0.5; font-size:12px;">No props placed yet.</div>';
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
    tpBtn.textContent = 'TP';
    tpBtn.onclick = () => post('teleportTo', { localId: p.localId });

    const delBtn = document.createElement('button');
    delBtn.textContent = 'Delete';
    delBtn.className = '';
    delBtn.onclick = () => post('deleteProp', { localId: p.localId });

    actions.appendChild(tpBtn);
    actions.appendChild(delBtn);
    row.appendChild(info);
    row.appendChild(actions);
    placedList.appendChild(row);
  });
}

document.getElementById('spawnCustomBtn').onclick = () => {
  const val = searchBox.value.trim();
  if (!val) return;
  post('spawnProp', { model: val });
};

document.getElementById('closeBtn').onclick = () => post('close');

document.getElementById('saveMapBtn').onclick = () => {
  post('setMapName', { mapname: mapNameInput.value.trim() || 'default' }).then(() => post('saveMap'));
};

document.getElementById('loadMapBtn').onclick = () => {
  post('loadMap', { mapname: mapNameInput.value.trim() || 'default' });
};

document.getElementById('exportBtn').onclick = () => {
  post('exportYmap', { mapname: mapNameInput.value.trim() || 'default' });
};

document.getElementById('clearBtn').onclick = () => {
  if (confirm('Delete all currently placed (unsaved changes will be lost)?')) {
    post('clearAll');
  }
};

searchBox.addEventListener('input', () => renderCategories(searchBox.value));

window.addEventListener('message', (event) => {
  const data = event.data;
  switch (data.action) {
    case 'open':
      mapNameInput.value = data.mapname;
      if (data.openKey) openKey = data.openKey;
      app.classList.remove('hidden');
      renderCategories(searchBox.value);
      loadSpooniProps().then(() => renderCategories(searchBox.value));
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
    case 'refreshList':
      currentPlaced = data.props;
      renderPlacedList();
      break;
    case 'favoritesList':
      favorites = data.favorites || [];
      favoriteModels = new Set(favorites.map(f => f.model));
      renderCategories(searchBox.value);
      break;
    case 'showPlacement':
      placementModelLabel.textContent = data.model || 'prop';
      placementPanel.classList.remove('hidden');
      break;
    case 'hidePlacement':
      placementPanel.classList.add('hidden');
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
  if (e.key === 'Escape') {
    post('close');
  }
  // The menu grabs full keyboard focus while open (SetNuiFocus(true, true)),
  // which stops the game's own RegisterKeyMapping for Config.OpenKey (F6 by
  // default) from ever firing a second time - so re-pressing it here has to
  // be handled directly in the NUI instead.
  const pressed = (e.key || '').toUpperCase();
  const bound = (openKey || '').toUpperCase();
  if (bound && (pressed === bound || e.code.toUpperCase() === bound)) {
    post('close');
  }
});
