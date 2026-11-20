// La finestra di prova della pagina: stessi testi e stesse regole di Copy8 (ricerca, numeri, puntina,
// anteprima), con contenuti inventati. "Incollare" scrive nella nota dietro la finestra.
(() => {
  "use strict";

  const demo = document.querySelector("[data-demo]");
  if (!demo) return;

  const DAYS = 7;
  const SVG = "http://www.w3.org/2000/svg";
  const now = new Date();
  const ago = (minutes) => new Date(now.getTime() - minutes * 60000);

  // Gli stessi esempi del tutorial (Sources/Copy8/Tutorial.swift, enum Sample).
  const items = [
    { id: 9, kind: "text", text: "IT60 X054 2811 1010 0000 0123 456", source: "Safari", at: ago(9), pinned: true },
    { id: 1, kind: "text", text: "Ci vediamo lunedì alle 10 in sala riunioni", source: "Mail", at: ago(2) },
    { id: 2, kind: "code", text: "git push origin main", source: "Terminale", at: ago(6) },
    { id: 7, kind: "text", text: "Ho mandato la fattura a Giulia stamattina", source: "Messaggi", at: ago(8) },
    { id: 3, kind: "link", text: "https://meet.example.com/riunione-lunedi", source: "Calendario", at: ago(11) },
    { id: 8, kind: "file", text: "/Users/me/Documenti/Fatture ottobre.xlsx", source: "Finder", at: ago(15), size: "48 KB" },
    { id: 4, kind: "color", text: "#9365FF", source: "Anteprima", at: ago(19) },
    { id: 5, kind: "text", text: "Fattura 2026-118 · 1.250,00 €", source: "Numbers", at: ago(26) },
    { id: 6, kind: "text", text: "Chiamare Giulia per il preventivo", source: "Promemoria", at: ago(34) },
  ];
  const KIND_ICON = { text: "text", code: "code", link: "link", file: "doc", image: "photo" };

  const input = demo.querySelector("[data-search]");
  const list = demo.querySelector("[data-list]");
  const preview = demo.querySelector("[data-preview]");
  const count = demo.querySelector("[data-count]");
  const clearButton = demo.querySelector("[data-clear]");
  const summary = demo.querySelector("[data-summary]");
  const pinLabel = demo.querySelector("[data-pin-label]");
  const note = demo.querySelector("[data-note]");
  const toast = demo.querySelector("[data-toast]");
  const toastText = demo.querySelector("[data-toast-text]");

  let query = "";
  let terms = [];
  let results = [];
  let selectedId = null;
  let toastTimer = 0;

  // ---------- Testi e formati, come in PanelText e DayFormat ----------

  const number = new Intl.NumberFormat("it-IT");
  const time = new Intl.DateTimeFormat("it-IT", { hour: "2-digit", minute: "2-digit" });
  const longDay = new Intl.DateTimeFormat("it-IT", { weekday: "long", day: "numeric", month: "long" });
  const weekday = new Intl.DateTimeFormat("it-IT", { weekday: "long" });
  const capitalized = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  const plural = (n, one, many) => `${number.format(n)} ${n === 1 ? one : many}`;
  const resultCount = (n) => plural(n, "risultato", "risultati");

  const dayDiff = (from, to) => {
    const start = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    return Math.round((start(to) - start(from)) / 86400000);
  };
  const dayLabel = (date) => {
    const diff = dayDiff(date, now);
    if (diff <= 0) return "Oggi";
    if (diff === 1) return "Ieri";
    return capitalized((diff < 7 ? weekday : longDay).format(date));
  };
  const until = (date) => {
    const diff = dayDiff(now, date);
    if (diff <= 0) return `oggi alle ${time.format(date)}`;
    if (diff === 1) return `domani alle ${time.format(date)}`;
    return longDay.format(date);
  };

  const titleOf = (item) => {
    if (item.kind === "link") return item.text.replace(/^https?:\/\//i, "");
    if (item.kind === "file") return item.text.split("/").pop();
    return item.text.replace(/\s+/g, " ").trim();
  };

  // ---------- Ricerca: maiuscole e accenti non contano, servono tutte le parole ----------

  // Toglie accenti e maiuscole lettera per lettera, così le posizioni restano quelle del testo originale.
  const fold = (s) => Array.from(s, (c) => {
    const f = c.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    return f.length === c.length ? f : c;
  }).join("");

  const matches = (item) => {
    const key = fold(`${item.text}\n${item.source}`);
    return terms.every((term) => key.includes(term));
  };

  // Testo con le parole cercate dentro <mark>.
  function highlighted(value) {
    const fragment = document.createDocumentFragment();
    const folded = fold(value);
    const ranges = [];
    for (const term of terms) {
      for (let at = folded.indexOf(term); at !== -1; at = folded.indexOf(term, at + term.length)) {
        ranges.push([at, at + term.length]);
      }
    }
    ranges.sort((a, b) => a[0] - b[0]);
    let cursor = 0;
    for (const [start, end] of ranges) {
      if (end <= cursor) continue;
      const from = Math.max(start, cursor);
      if (from > cursor) fragment.append(value.slice(cursor, from));
      const mark = document.createElement("mark");
      mark.textContent = value.slice(from, end);
      fragment.append(mark);
      cursor = end;
    }
    fragment.append(value.slice(cursor));
    return fragment;
  }

  // ---------- Elementi del DOM ----------

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function icon(name, className = "icon") {
    const svg = document.createElementNS(SVG, "svg");
    svg.setAttribute("class", className);
    svg.setAttribute("aria-hidden", "true");
    const use = document.createElementNS(SVG, "use");
    use.setAttribute("href", `#i-${name}`);
    svg.append(use);
    return svg;
  }

  function sectionHeader(label, pinned, first) {
    const header = el("div", `section-header${first ? " is-first" : ""}`);
    header.setAttribute("role", "presentation");
    if (pinned) header.append(icon("pin-fill"));
    header.append(el("span", "", label));
    if (pinned) header.append(el("span", "aside", `Restano anche dopo i ${DAYS} giorni`));
    return header;
  }

  function row(item, index) {
    const node = el("div", `row${item.pinned ? " is-pinned" : ""}`);
    node.id = `demo-row-${item.id}`;
    node.dataset.id = item.id;
    node.setAttribute("role", "option");

    const tile = el("span", "type-icon");
    if (item.kind === "color") {
      const swatch = el("span", "swatch");
      swatch.style.background = item.text;
      tile.append(swatch);
    } else {
      tile.append(icon(KIND_ICON[item.kind]));
    }

    const title = el("span", `row-title${item.kind === "code" || item.kind === "color" ? " mono" : ""}`);
    title.append(highlighted(titleOf(item)));

    const accessories = el("span", "row-accessories");
    const pin = el("span", "pin");
    pin.title = item.pinned ? "Togli dai fissati (⌘P)" : "Fissa: resta in cima e non viene mai cancellato (⌘P)";
    pin.append(icon(item.pinned ? "pin-fill" : "pin"));
    accessories.append(pin);
    // Il tasto della riga: "3" a ricerca vuota, "⌘3" mentre si cerca. Solo per le prime nove.
    if (index < 9) accessories.append(el("span", "key-badge", query ? `⌘${index + 1}` : String(index + 1)));

    node.append(tile, title, accessories, el("span", "row-time", time.format(item.at)));
    return node;
  }

  function emptyState() {
    const box = el("div", "empty");
    box.append(icon("search"));
    box.append(el("strong", "", `Nessun risultato per «${query.trim()}»`));
    box.append(el("span", "", "Prova con meno parole o aumenta i giorni nelle impostazioni."));
    return box;
  }

  // ---------- Disegno ----------

  function render() {
    terms = fold(query).split(/\s+/).filter(Boolean);
    const byTime = (a, b) => b.at - a.at;
    const pinned = items.filter((item) => item.pinned && matches(item)).sort(byTime);
    const others = items.filter((item) => !item.pinned && matches(item)).sort(byTime);
    results = [...pinned, ...others];

    list.replaceChildren();
    if (results.length === 0) list.append(emptyState());
    let index = 0;
    if (pinned.length) {
      list.append(sectionHeader("Fissati", true, true));
      pinned.forEach((item) => list.append(row(item, index++)));
    }
    let day = null;
    for (const item of others) {
      const label = dayLabel(item.at);
      if (label !== day) {
        list.append(sectionHeader(label, false, index === 0));
        day = label;
      }
      list.append(row(item, index++));
    }

    if (!results.some((item) => item.id === selectedId)) selectedId = results.length ? results[0].id : null;

    count.hidden = clearButton.hidden = query === "";
    count.textContent = resultCount(results.length);
    summary.textContent = terms.length
      ? `${resultCount(results.length)} · ultimi ${DAYS} giorni`
      : [`Ultimi ${DAYS} giorni`, plural(others.length, "elemento", "elementi"),
         pinned.length ? plural(pinned.length, "fissato", "fissati") : ""].filter(Boolean).join(" · ");
    updateSelection(false);
  }

  function select(id, scroll) {
    if (id === selectedId) return;
    selectedId = id;
    updateSelection(scroll);
  }

  function updateSelection(scroll) {
    for (const node of list.querySelectorAll(".row")) {
      const on = Number(node.dataset.id) === selectedId;
      node.classList.toggle("is-selected", on);
      node.setAttribute("aria-selected", String(on));
      if (on && scroll) reveal(node);
    }
    if (selectedId === null) input.removeAttribute("aria-activedescendant");
    else input.setAttribute("aria-activedescendant", `demo-row-${selectedId}`);
    const item = selected();
    pinLabel.textContent = item && item.pinned ? "Togli" : "Fissa";
    renderPreview(item);
  }

  // Scorre solo l'elenco, mai la pagina.
  function reveal(node) {
    const top = node.offsetTop;
    const bottom = top + node.offsetHeight;
    if (top < list.scrollTop + 4) list.scrollTop = top - 4;
    else if (bottom > list.scrollTop + list.clientHeight - 8) list.scrollTop = bottom - list.clientHeight + 8;
  }

  const selected = () => results.find((item) => item.id === selectedId) || null;

  function renderPreview(item) {
    preview.replaceChildren();
    if (!item) return;
    const content = el("div", "preview-content");
    switch (item.kind) {
      case "code": {
        const code = el("div", "preview-code");
        code.append(highlighted(item.text));
        content.append(code);
        break;
      }
      case "link": {
        content.append(el("div", "preview-host", new URL(item.text).host));
        const url = el("div", "preview-url");
        url.append(highlighted(item.text));
        content.append(url);
        break;
      }
      case "color": {
        const swatch = el("div", "preview-swatch");
        swatch.style.background = item.text;
        content.append(swatch, el("div", "preview-hex", item.text));
        break;
      }
      case "file": {
        const file = el("div", "preview-file");
        const label = el("div");
        label.append(el("strong", "", titleOf(item)), el("span", "", item.text.split("/").slice(0, -1).join("/").replace(/^\/Users\/[^/]+/, "~")));
        file.append(icon("doc", "icon file-icon"), label);
        content.append(file);
        break;
      }
      default: {
        const text = el("div", "preview-text");
        text.append(highlighted(item.text));
        content.append(text);
      }
    }

    const meta = el("dl", "meta");
    const add = (label, value) => meta.append(el("dt", "", label), el("dd", "", value));
    add("Origine", item.source);
    add("Copiato", `${dayLabel(item.at)} alle ${time.format(item.at)}`);
    add("Conservazione", item.pinned
      ? "Fissato, non si cancella · ⌘P per toglierlo"
      : `Fino a ${until(new Date(item.at.getTime() + DAYS * 86400000))} · ⌘P per fissarlo`);
    const characters = Array.from(item.text).length;
    if (item.kind === "text") {
      add("Contenuto", `${plural(characters, "carattere", "caratteri")} · ${plural(item.text.split(/\s+/).filter(Boolean).length, "parola", "parole")}`);
    } else if (item.kind === "code") {
      add("Contenuto", `${plural(item.text.split("\n").length, "riga", "righe")} · ${plural(characters, "carattere", "caratteri")}`);
    } else if (item.kind === "link") {
      add("Contenuto", `Link · ${new URL(item.text).host}`);
    } else if (item.kind === "color") {
      const hex = parseInt(item.text.slice(1), 16);
      add("Valori", `rgb(${hex >> 16}, ${(hex >> 8) & 255}, ${hex & 255})`);
    } else if (item.kind === "file") {
      add("File", item.size);
    }
    preview.append(content, meta);
  }

  // ---------- Azioni ----------

  function paste(item) {
    const text = el("span", "pasted is-new", item.kind === "file" ? titleOf(item) : item.text);
    const line = el("p");
    line.append(text);
    note.append(line);
    while (note.children.length > 14) note.children[1].remove();
    note.scrollTop = note.scrollHeight;
    // Il giallo si vede subito e poi sfuma, come nel tutorial.
    requestAnimationFrame(() => requestAnimationFrame(() => text.classList.remove("is-new")));
    showToast("Incollato nell’app attiva");
  }

  function togglePin(item) {
    item.pinned = !item.pinned;
    render();
    const node = list.querySelector(`#demo-row-${item.id}`);
    if (node) reveal(node);
  }

  function showToast(message) {
    toastText.textContent = message;
    toast.classList.add("is-visible");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove("is-visible"), 1600);
  }

  function setQuery(value) {
    query = value;
    render();
    list.scrollTop = 0;
  }

  input.addEventListener("input", () => setQuery(input.value));

  input.addEventListener("keydown", (event) => {
    if (event.isComposing) return;
    const index = results.findIndex((item) => item.id === selectedId);
    const plain = !event.metaKey && !event.ctrlKey && !event.altKey;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!results.length) return;
      const next = event.key === "ArrowDown" ? Math.min(index + 1, results.length - 1) : Math.max(index - 1, 0);
      select(results[next].id, true);
    } else if (event.key === "Enter") {
      event.preventDefault();
      const item = selected();
      if (item) paste(item);
    } else if (event.key === "Escape") {
      if (query) {
        event.preventDefault();
        input.value = "";
        setQuery("");
      } else {
        input.blur();
      }
    } else if (plain && query === "" && /^[1-9]$/.test(event.key)) {
      // A ricerca vuota il numero sceglie la riga e la incolla.
      event.preventDefault();
      const item = results[Number(event.key) - 1];
      if (item) {
        select(item.id, true);
        paste(item);
      }
    } else if (event.metaKey && !event.altKey && !event.shiftKey && event.key.toLowerCase() === "p") {
      event.preventDefault();
      const item = selected();
      if (item) togglePin(item);
    }
  });

  clearButton.addEventListener("click", () => {
    input.value = "";
    setQuery("");
    input.focus();
  });

  // Come nell'app, la riga sotto il mouse diventa quella scelta.
  list.addEventListener("mousemove", (event) => {
    const node = event.target.closest(".row");
    if (node) select(Number(node.dataset.id), false);
  });

  list.addEventListener("click", (event) => {
    const node = event.target.closest(".row");
    if (!node) return;
    const item = items.find((candidate) => candidate.id === Number(node.dataset.id));
    if (!item) return;
    if (event.target.closest(".pin")) togglePin(item);
    else paste(item);
  });

  render();
})();
