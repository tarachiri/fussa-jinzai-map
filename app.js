const FUSSA_CENTER = [35.7385, 139.3270];

const map = L.map("map", {
  zoomControl: false,
  gestureHandling: true,
  gestureHandlingOptions: {
    text: {
      touch: "2本の指で地図を操作してください",
      scroll: "Ctrlキーを押しながらスクロールすると地図を拡大縮小できます",
      scrollMac: "⌘キーを押しながらスクロールすると地図を拡大縮小できます"
    }
  }
}).setView(FUSSA_CENTER, 13);
L.control.zoom({ position: "topright" }).addTo(map);
L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19,
  attribution: "© OpenStreetMap contributors"
}).addTo(map);

const markers = L.markerClusterGroup({
  maxClusterRadius: 20,
  showCoverageOnHover: false,
  disableClusteringAtZoom: 16
});
map.addLayer(markers);

function escapeHtml(value) {
  const element = document.createElement("div");
  element.textContent = value == null ? "" : String(value);
  return element.innerHTML;
}

function makeIcon(needsVerification) {
  const state = needsVerification ? "unverified" : "verified";
  const label = needsVerification ? "概算・未確認の位置" : "位置確認済み";
  return L.divIcon({
    className: "",
    html: `<span class="circle-pin ${state}" role="img" aria-label="${label}"></span>`,
    iconSize: [28, 28],
    iconAnchor: [14, 28],
    popupAnchor: [0, -25]
  });
}

function popupHtml(circle) {
  const description = circle.description
    ? `<p class="description">${escapeHtml(circle.description).replaceAll("\n", "<br>")}</p>`
    : '<p class="description">活動内容は現在確認中です。</p>';
  const tags = Array.isArray(circle.categories) && circle.categories.length
    ? `<div class="tags">${circle.categories.map(tag => `<span class="tag">${escapeHtml(tag)}</span>`).join("")}</div>`
    : "";
  const notice = circle.needs_verification
    ? '<p class="notice">位置情報は概算・未確認の場合があります。</p>'
    : "";
  return `<article class="popup"><h2>${escapeHtml(circle.name)}</h2>${tags}${description}${notice}</article>`;
}

async function loadCircles() {
  const response = await fetch(`circles.json?v=${Date.now()}`);
  if (!response.ok) throw new Error(`circles.json: HTTP ${response.status}`);
  const payload = await response.json();
  const bounds = [];
  let verified = 0;
  let unverified = 0;

  payload.circles.forEach(circle => {
    if (!Number.isFinite(circle.lat) || !Number.isFinite(circle.lng)) return;
    const needsVerification = Number(circle.needs_verification) === 1;
    needsVerification ? unverified++ : verified++;
    L.marker([circle.lat, circle.lng], { icon: makeIcon(needsVerification) })
      .bindPopup(popupHtml(circle), {
        maxWidth: 300,
        maxHeight: 280,
        autoPan: true,
        autoPanPaddingTopLeft: [24, 24],
        autoPanPaddingBottomRight: [24, 24]
      })
      .addTo(markers);
    bounds.push([circle.lat, circle.lng]);
  });

  document.getElementById("visible-count").textContent = String(bounds.length);
  document.getElementById("data-summary").textContent = `確認済み ${verified}件 ／ 概算・未確認 ${unverified}件`;
  if (bounds.length) map.fitBounds(bounds, { padding: [34, 34], maxZoom: 14 });
}

loadCircles().catch(error => {
  console.error(error);
  document.getElementById("visible-count").textContent = "!";
  document.getElementById("data-summary").textContent = "データ読込失敗";
  document.getElementById("load-error").hidden = false;
});
