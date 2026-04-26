const form = document.getElementById("post-form");
const textarea = document.getElementById("text");
const charCount = document.getElementById("char-count");
const submitBtn = document.getElementById("submit");
const resultsBox = document.getElementById("results");
const resultsList = document.getElementById("results-list");
const limits = { twitter: 280, bluesky: 300 };

function updateChars() {
  const len = textarea.value.length;
  charCount.textContent = len;
  document.querySelectorAll(".limit").forEach((el) => {
    const cap = limits[el.dataset.platform];
    el.classList.toggle("over", len > cap);
  });
}
textarea.addEventListener("input", updateChars);
updateChars();

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  resultsBox.hidden = true;
  resultsList.innerHTML = "";
  submitBtn.disabled = true;
  submitBtn.textContent = "Posting…";

  const data = new FormData(form);

  try {
    const resp = await fetch("/api/post", { method: "POST", body: data });
    const payload = await resp.json();

    if (!resp.ok) {
      renderError(payload.error || `HTTP ${resp.status}`);
      return;
    }

    renderResults(payload.results || []);
  } catch (err) {
    renderError(err.message || String(err));
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = "Post";
  }
});

function renderError(message) {
  resultsBox.hidden = false;
  const li = document.createElement("li");
  li.innerHTML = `<span class="fail">Error</span><span>${escapeHtml(message)}</span>`;
  resultsList.appendChild(li);
}

function renderResults(results) {
  resultsBox.hidden = false;
  for (const r of results) {
    const li = document.createElement("li");
    const status = r.ok
      ? `<span class="ok">✓</span>`
      : `<span class="fail">✗</span>`;
    const link = r.url
      ? ` <a href="${escapeAttr(r.url)}" target="_blank" rel="noreferrer">view</a>`
      : "";
    li.innerHTML = `${status}<span class="platform-name">${escapeHtml(r.platform)}</span><span>${escapeHtml(r.message)}</span>${link}`;
    resultsList.appendChild(li);
  }
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
function escapeAttr(s) {
  return escapeHtml(s).replaceAll("'", "&#39;");
}
