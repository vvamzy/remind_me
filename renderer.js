(() => {
  const $ = (sel, el = document) => el.querySelector(sel);
  const $$ = (sel, el = document) => Array.from(el.querySelectorAll(sel));

  const state = {
    todos: [],
    filter: 'all',
    tickHandle: null
  };

  const storageKey = 'todo-timer-items';

  function load() {
    try {
      const raw = localStorage.getItem(storageKey);
      state.todos = raw ? JSON.parse(raw) : [];
    } catch {
      state.todos = [];
    }
  }
  function save() {
    localStorage.setItem(storageKey, JSON.stringify(state.todos));
  }

  function uid() {
    return Math.random().toString(36).slice(2) + Date.now().toString(36);
  }

  function formatHMS(ms) {
    const neg = ms < 0;
    ms = Math.abs(ms);
    const s = Math.floor(ms / 1000);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    const part = [
      h > 0 ? String(h).padStart(2, '0') : '00',
      String(m).padStart(2, '0'),
      String(sec).padStart(2, '0')
    ].join(':');
    return (neg ? '-' : '') + part;
  }

  function hueForFraction(f) {
    f = Math.max(0, Math.min(1, f));
    const hue = 120 * (1 - f); // 0 = red, 1 = green; we want green->red as f increases
    return `hsl(${hue} 70% 45%)`;
  }

  function computeProgress(todo, now) {
    const total = todo.totalMs;
    const elapsed = Math.max(0, Math.min(total, now - todo.createdAt));
    const frac = total === 0 ? 1 : elapsed / total;
    const remaining = todo.dueAt - now;
    return { total, elapsed, frac, remaining };
  }

  function render() {
    const list = $('#todo-list');
    list.innerHTML = '';

    const all = state.todos.slice().sort((a, b) => {
      // Active first, then due soonest, then created
      if (a.done !== b.done) return a.done ? 1 : -1;
      return a.dueAt - b.dueAt || a.createdAt - b.createdAt;
    });

    const items = all.filter(t => {
      if (state.filter === 'all') return true;
      if (state.filter === 'active') return !t.done;
      if (state.filter === 'done') return !!t.done;
      return true;
    });

    if (items.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = 'No todos yet. Add your first above.';
      list.appendChild(empty);
      return;
    }

    const tpl = $('#todo-item-template');
    const now = Date.now();

    for (const t of items) {
      const node = tpl.content.firstElementChild.cloneNode(true);
      node.dataset.id = t.id;
      if (t.done) node.classList.add('done');

      const toggle = $('.toggle', node);
      const title = $('.title', node);
      const due = $('.badge.due', node);
      const delBtn = $('.delete', node);
      const editBtn = $('.edit', node);
      const barFill = $('.bar .fill', node);
      const timeText = $('.time-text', node);

      toggle.checked = !!t.done;
      title.textContent = t.title;

      const dueDate = new Date(t.dueAt);
      const hh = String(dueDate.getHours()).padStart(2, '0');
      const mm = String(dueDate.getMinutes()).padStart(2, '0');
      due.textContent = `due ${hh}:${mm}`;

      const { frac, remaining } = computeProgress(t, now);
      const pct = Math.round(frac * 100);
      barFill.style.width = `${pct}%`;
      barFill.style.backgroundColor = hueForFraction(frac);
      timeText.textContent = t.done
        ? 'Completed'
        : remaining >= 0
          ? `${formatHMS(remaining)} remaining`
          : `${formatHMS(remaining)} overdue`;

      toggle.addEventListener('change', () => {
        t.done = toggle.checked;
        t.doneAt = t.done ? Date.now() : null;
        save();
        render();
      });
      delBtn.addEventListener('click', () => {
        state.todos = state.todos.filter(x => x.id !== t.id);
        save();
        render();
      });
      editBtn.addEventListener('click', () => {
        const newTitle = prompt('Edit title:', t.title);
        if (newTitle == null) return;
        const newMinsStr = prompt('Set minutes (leave blank to keep):', '');
        const newSecsStr = prompt('Set seconds (leave blank to keep):', '');
        if (newTitle.trim()) t.title = newTitle.trim();
        let total = t.totalMs;
        if (newMinsStr?.trim() || newSecsStr?.trim()) {
          const mins = parseInt(newMinsStr || '0', 10) || 0;
          const secs = parseInt(newSecsStr || '0', 10) || 0;
          total = Math.max(0, (mins * 60 + secs) * 1000);
          const elapsed = Date.now() - t.createdAt;
          const remaining = Math.max(0, total - Math.max(0, elapsed));
          t.totalMs = total;
          t.dueAt = Date.now() + remaining;
          t.createdAt = Date.now() - (total - remaining);
        }
        save();
        render();
      });

      list.appendChild(node);
    }
  }

  function startTicker() {
    if (state.tickHandle) clearInterval(state.tickHandle);
    state.tickHandle = setInterval(() => {
      const now = Date.now();
      // Update visible items efficiently
      $$('#todo-list .todo-item').forEach(node => {
        const id = node.dataset.id;
        const t = state.todos.find(x => x.id === id);
        if (!t) return;
        const fill = $('.bar .fill', node);
        const timeText = $('.time-text', node);
        if (t.done) {
          fill.style.width = '100%';
          timeText.textContent = 'Completed';
          return;
        }
        const { frac, remaining } = computeProgress(t, now);
        fill.style.width = `${Math.round(frac * 100)}%`;
        fill.style.backgroundColor = hueForFraction(frac);
        timeText.textContent = remaining >= 0
          ? `${formatHMS(remaining)} remaining`
          : `${formatHMS(remaining)} overdue`;
      });
    }, 250);
  }

  function addTodo(title, mins, secs) {
    const totalMs = Math.max(0, (mins * 60 + secs) * 1000);
    const now = Date.now();
    const t = {
      id: uid(),
      title: title.trim(),
      totalMs,
      createdAt: now,
      dueAt: now + totalMs,
      done: false,
      doneAt: null
    };
    state.todos.push(t);
    save();
    render();
  }

  function wireUI() {
    // Version
    const v = (window.todoApp && window.todoApp.version) || '';
    const verNode = $('#app-version');
    verNode.textContent = v ? `v${v}` : '';

    // Add
    const title = $('#todo-title');
    const mins = $('#todo-mins');
    const secs = $('#todo-secs');
    const addBtn = $('#add-btn');
    function onAdd() {
      const t = title.value.trim();
      const m = parseInt(mins.value || '0', 10) || 0;
      const s = parseInt(secs.value || '0', 10) || 0;
      if (!t) return;
      addTodo(t, Math.max(0, m), Math.max(0, Math.min(59, s)));
      title.value = '';
    }
    addBtn.addEventListener('click', onAdd);
    title.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') onAdd();
    });

    // Filters
    $$('.filters .chip').forEach(btn => {
      btn.addEventListener('click', () => {
        const f = btn.dataset.filter;
        if (f) {
          state.filter = f;
          $$('.filters .chip').forEach(b => b.classList.toggle('active', b === btn));
          render();
        }
      });
    });

    $('#clear-done').addEventListener('click', () => {
      state.todos = state.todos.filter(t => !t.done);
      save();
      render();
    });
  }

  // Initialize
  load();
  wireUI();
  render();
  startTicker();
})();
