const transcriptEl = document.getElementById("transcript");
const statusEl = document.getElementById("status");
const exportBtn = document.getElementById("export");
const kindsTemplate = document.getElementById("kinds");

let fixture = null;
let fixtureName = "";
let labels = new Map();
let open = null;

const readJSON = (file) =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        resolve(JSON.parse(reader.result));
      } catch (error) {
        reject(error);
      }
    };
    reader.onerror = reject;
    reader.readAsText(file);
  });

const clock = (seconds) => {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
};

function render() {
  transcriptEl.replaceChildren();
  if (!fixture) return;
  const finals = fixture.segments.filter((segment) => segment.isFinal);
  finals.forEach((segment, index) => {
    const row = document.createElement("div");
    row.className = "utt";
    row.dataset.index = index;
    const label = labels.get(index);
    if (label) row.classList.add("marked");
    row.innerHTML = `<time>${clock(segment.start)}</time><span></span><span class="tag">${label ?? ""}</span>`;
    row.children[1].textContent = segment.text;
    row.addEventListener("click", () => toggleKinds(index, row));
    transcriptEl.append(row);
    if (open === index) {
      const kinds = kindsTemplate.content.cloneNode(true);
      kinds.querySelectorAll("button").forEach((button) =>
        button.addEventListener("click", (event) => {
          event.stopPropagation();
          labels.set(index, button.dataset.kind);
          open = null;
          render();
        }),
      );
      transcriptEl.append(kinds);
    }
  });
  exportBtn.disabled = labels.size === 0;
  statusEl.textContent = `${finals.length} utterances, ${labels.size} labeled`;
}

function toggleKinds(index) {
  if (labels.has(index)) {
    labels.delete(index);
    open = null;
  } else {
    open = open === index ? null : index;
  }
  render();
}

document.getElementById("fixture").addEventListener("change", async (event) => {
  const [file] = event.target.files;
  if (!file) return;
  fixture = await readJSON(file);
  fixtureName = file.name.replace(/\.json$/, "");
  labels = new Map();
  open = null;
  render();
});

document.getElementById("labels").addEventListener("change", async (event) => {
  const [file] = event.target.files;
  if (!file) return;
  const data = await readJSON(file);
  labels = new Map(data.labels.map((entry) => [entry.utterance, entry.kind]));
  render();
});

exportBtn.addEventListener("click", () => {
  const finals = fixture.segments.filter((segment) => segment.isFinal);
  const body = {
    fixture: fixtureName,
    labels: [...labels.entries()]
      .sort((a, b) => a[0] - b[0])
      .map(([utterance, kind]) => ({
        utterance,
        at: finals[utterance].end,
        kind,
      })),
  };
  const blob = new Blob([JSON.stringify(body, null, 2)], {
    type: "application/json",
  });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `${fixtureName}.labels.json`;
  link.click();
  URL.revokeObjectURL(link.href);
});
