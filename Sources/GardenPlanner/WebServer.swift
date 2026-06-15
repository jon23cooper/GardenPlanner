import Foundation
import Darwin

final class WebServer: @unchecked Sendable {
    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let port: UInt16
    private weak var appData: AppData?
    private var serverFD: Int32 = -1
    private var acceptRunning = false

    init(port: UInt16, appData: AppData) {
        self.port = port
        self.appData = appData
    }

    func start() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            notify(error: "socket() failed: \(errnoString())"); return
        }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        addr.sin_addr   = in_addr(s_addr: INADDR_ANY)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            notify(error: "bind() failed on port \(port): \(errnoString()) — is another app using this port?"); return
        }
        guard listen(fd, 10) == 0 else {
            close(fd)
            notify(error: "listen() failed: \(errnoString())"); return
        }

        serverFD = fd
        acceptRunning = true
        DispatchQueue.main.async { self.onStateChange?(true) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        acceptRunning = false
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        DispatchQueue.main.async { self.onStateChange?(false) }
    }

    private func acceptLoop() {
        while acceptRunning {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    // MARK: - Request handling

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }
        var buf = [UInt8](repeating: 0, count: 32768)
        let n = read(fd, &buf, buf.count - 1)
        guard n > 0 else { return }

        let raw = String(bytes: buf.prefix(n), encoding: .utf8) ?? ""
        let parts = (raw.components(separatedBy: "\r\n").first ?? "")
            .split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return }
        let method = parts[0]
        let path = parts[1].components(separatedBy: "?").first ?? parts[1]
        let body: Data = raw.range(of: "\r\n\r\n").map { Data(raw[$0.upperBound...].utf8) } ?? Data()

        let sem = DispatchSemaphore(value: 0)
        // Use a box so Swift concurrency doesn't flag the cross-thread write
        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        DispatchQueue.main.async { [weak self] in
            defer { sem.signal() }
            guard let self, let appData = self.appData else { return }
            let (status, rb, ct) = self.dispatch(method: method, path: path, body: body, appData: appData)
            box.data = self.buildResponse(status, rb, ct)
        }
        sem.wait()
        box.data.withUnsafeBytes { ptr in _ = write(fd, ptr.baseAddress, box.data.count) }
    }

    private func buildResponse(_ status: Int, _ body: Data, _ contentType: String) -> Data {
        let phrase = [200: "OK", 400: "Bad Request", 404: "Not Found"][status] ?? "Error"
        let hdr = "HTTP/1.1 \(status) \(phrase)\r\nContent-Type: \(contentType); charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        var r = Data(hdr.utf8); r.append(body); return r
    }

    private func notify(error: String) {
        print("[WebServer] \(error)")
        DispatchQueue.main.async { self.onError?(error) }
    }

    private func errnoString() -> String { String(cString: strerror(errno)) }

    // MARK: - Dispatch (always on main thread)

    private func dispatch(method: String, path: String, body: Data, appData: AppData) -> (Int, Data, String) {
        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return (200, Data(Self.pageHTML.utf8), "text/html")
        case ("GET", "/api/data"):
            return apiData(appData)
        case ("POST", "/api/plant"):
            return apiPlant(body, appData)
        case ("POST", "/api/transplant"):
            return apiTransplant(body, appData)
        default:
            return (404, Data(#"{"error":"not found"}"#.utf8), "application/json")
        }
    }

    // MARK: - GET /api/data

    private func apiData(_ appData: AppData) -> (Int, Data, String) {
        struct Out: Encodable {
            var seeds: [SeedOut]; var beds: [BedOut]; var locations: [String]; var records: [RecordOut]
        }
        struct SeedOut: Encodable { var id, displayName, colorHex: String; var stock: Int }
        struct BedOut: Encodable { var id, name: String }
        struct RecordOut: Encodable { var id, seedName, dateSown, location: String; var quantity: Int; var transplanted: String? }

        let df = DateFormatter(); df.dateStyle = .medium
        let seeds = appData.seeds.sorted { $0.displayName < $1.displayName }
            .map { SeedOut(id: $0.id.uuidString, displayName: $0.displayName, colorHex: $0.colorHex, stock: $0.quantityPackets) }
        let beds = appData.gardenBeds.map { BedOut(id: $0.id.uuidString, name: $0.name) }
        let records = appData.plantingRecords.sorted { $0.dateSown > $1.dateSown }.prefix(100).map { r -> RecordOut in
            let loc: String
            switch r.location {
            case .bed(let id): loc = appData.gardenBeds.first { $0.id == id }?.name ?? "Unknown bed"
            case .custom(let s): loc = s
            }
            return RecordOut(id: r.id.uuidString,
                             seedName: appData.seed(id: r.seedId)?.displayName ?? "Unknown",
                             dateSown: df.string(from: r.dateSown),
                             location: loc,
                             quantity: r.quantitySown,
                             transplanted: r.dateTransplanted.map { df.string(from: $0) })
        }
        let out = Out(seeds: seeds, beds: beds, locations: appData.customLocations, records: Array(records))
        return (200, (try? JSONEncoder().encode(out)) ?? Data(), "application/json")
    }

    // MARK: - POST /api/plant

    private func apiPlant(_ body: Data, _ appData: AppData) -> (Int, Data, String) {
        struct Req: Decodable { var seedId, locationType: String; var bedId, customLocation, dateSown: String?; var quantity: Int }
        guard let req = try? JSONDecoder().decode(Req.self, from: body),
              let seedId = UUID(uuidString: req.seedId) else {
            return (400, Data(#"{"error":"invalid request"}"#.utf8), "application/json")
        }
        let location: PlantLocation
        if req.locationType == "bed", let bStr = req.bedId, let bId = UUID(uuidString: bStr) {
            location = .bed(bId)
        } else {
            location = .custom(req.customLocation ?? "Outdoors")
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let date = req.dateSown.flatMap { df.date(from: $0) } ?? Date()
        appData.addPlantingRecord(PlantingRecord(seedId: seedId, dateSown: date, location: location, quantitySown: req.quantity))
        return (200, Data(#"{"ok":true}"#.utf8), "application/json")
    }

    // MARK: - POST /api/transplant

    private func apiTransplant(_ body: Data, _ appData: AppData) -> (Int, Data, String) {
        struct Req: Decodable { var recordId: String; var date: String? }
        guard let req = try? JSONDecoder().decode(Req.self, from: body),
              let id = UUID(uuidString: req.recordId),
              let idx = appData.plantingRecords.firstIndex(where: { $0.id == id }) else {
            return (400, Data(#"{"error":"invalid request"}"#.utf8), "application/json")
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        appData.plantingRecords[idx].dateTransplanted = req.date.flatMap { df.date(from: $0) } ?? Date()
        return (200, Data(#"{"ok":true}"#.utf8), "application/json")
    }

    // MARK: - HTML

    static let pageHTML = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<meta name="mobile-web-app-capable" content="yes">
<title>Garden Planner</title>
<style>
:root{--green:#4CAF50;--green-dk:#388E3C;--green-lt:#E8F5E9;--text:#212121;--text2:#757575;--border:#E0E0E0;--bg:#F4F6F3;--card:#fff;--r:12px;--tabs:58px}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);min-height:100vh;padding-bottom:var(--tabs)}
header{background:var(--green-dk);color:#fff;padding:14px 18px;display:flex;align-items:center;gap:10px;position:sticky;top:0;z-index:10}
header h1{font-size:18px;font-weight:600}
.content{padding:14px;max-width:480px;margin:0 auto}
nav{position:fixed;bottom:0;left:0;right:0;height:var(--tabs);background:#fff;border-top:1px solid var(--border);display:flex;z-index:10}
.tab{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;border:none;background:none;font-size:11px;color:var(--text2);cursor:pointer;padding:6px}
.tab.on{color:var(--green-dk);font-weight:600}
.tab svg{width:22px;height:22px}
.panel{display:none}.panel.on{display:block}
.card{background:var(--card);border-radius:var(--r);padding:16px;margin-bottom:12px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
label{display:block;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.4px;color:var(--text2);margin-bottom:5px}
select,input[type=number],input[type=date]{width:100%;padding:12px 14px;border:1.5px solid var(--border);border-radius:8px;font-size:16px;background:#fff;color:var(--text);-webkit-appearance:none;appearance:none;margin-bottom:14px}
select:focus,input:focus{outline:none;border-color:var(--green)}
.btn{display:block;width:100%;padding:15px;background:var(--green);color:#fff;border:none;border-radius:8px;font-size:16px;font-weight:600;cursor:pointer;margin-top:4px}
.btn:active{background:var(--green-dk)}.btn:disabled{background:#ccc;cursor:not-allowed}
.btn2{background:#fff;color:var(--green-dk);border:1.5px solid var(--green);padding:10px 16px;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer}
.row{display:flex;align-items:center;padding:13px 0;border-bottom:1px solid var(--border);gap:12px}
.row:last-child{border:none}
.row-info{flex:1}
.row-info strong{display:block;font-size:15px}
.row-info span{font-size:13px;color:var(--text2)}
.chip{display:inline-block;width:11px;height:11px;border-radius:50%;flex-shrink:0}
.badge{font-size:13px;font-weight:600;padding:3px 10px;border-radius:20px;background:var(--green-lt);color:var(--green-dk)}
.badge.low{background:#FFF3E0;color:#E65100}.badge.gone{background:#FFEBEE;color:#C62828}
.sec{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:var(--text2);margin:14px 0 8px}
.empty{text-align:center;padding:40px 20px;color:var(--text2);font-size:15px}
.toast{position:fixed;bottom:calc(var(--tabs) + 14px);left:50%;transform:translateX(-50%);background:#323232;color:#fff;padding:10px 20px;border-radius:24px;font-size:14px;z-index:100;opacity:0;transition:opacity .3s;white-space:nowrap;pointer-events:none}
.toast.on{opacity:1}
</style>
</head>
<body>
<header>
  <svg viewBox="0 0 24 24" fill="white" width="22" height="22"><path d="M17 8C8 10 5.9 16.17 3.82 21H5.71C6.66 19 7.5 17.4 8.5 16C9.9 17 11.3 17.8 12.5 18C14.5 18 16 15 17 13C18 15 18.5 17.1 19 21H21C19 12 23 6 17 8Z"/></svg>
  <h1>Garden Planner</h1>
</header>

<div class="content">

  <div class="panel on" id="p-log">
    <div class="sec">Log a planting</div>
    <div class="card">
      <label for="s-seed">Seed</label>
      <select id="s-seed"></select>
      <label for="s-date">Date sown</label>
      <input type="date" id="s-date">
      <label for="s-loc">Location</label>
      <select id="s-loc"></select>
      <label for="s-qty">Quantity sown</label>
      <input type="number" id="s-qty" value="1" min="1" max="9999">
      <button class="btn" id="btn-log">Log planting</button>
    </div>
  </div>

  <div class="panel" id="p-transplant">
    <div class="sec">Record a transplant</div>
    <div id="transplant-list"></div>
  </div>

  <div class="panel" id="p-seeds">
    <div class="sec">Seed stock</div>
    <div class="card" id="seeds-list"></div>
  </div>

</div>

<nav>
  <button class="tab on" onclick="show('log',this)">
    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M19 3H5C3.9 3 3 3.9 3 5v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V5h14v14zM17 17H7v-2h10v2zm0-4H7v-2h10v2zm-3-4H7V7h7v2z"/></svg>
    Log
  </button>
  <button class="tab" onclick="show('transplant',this)">
    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3a9 9 0 0 0-9 9h3l-4 4-4-4h3a11 11 0 0 1 11-11 11 11 0 0 1 11 11 11 11 0 0 1-11 11 11 11 0 0 1-7.78-3.22l1.42-1.42A9 9 0 0 0 12 21a9 9 0 0 0 9-9 9 9 0 0 0-9-9zm1 5v5l4 2.4-1 1.73L11 14V8h2z"/></svg>
    Transplant
  </button>
  <button class="tab" onclick="show('seeds',this)">
    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M17 8C8 10 5.9 16.17 3.82 21H5.71C6.66 19 7.5 17.4 8.5 16C9.9 17 11.3 17.8 12.5 18C14.5 18 16 15 17 13C18 15 18.5 17.1 19 21H21C19 12 23 6 17 8Z"/></svg>
    Seeds
  </button>
</nav>

<div class="toast" id="toast"></div>

<script>
let D = {seeds:[],beds:[],locations:[],records:[]};

async function load() {
  try {
    const r = await fetch('/api/data');
    if (!r.ok) throw new Error();
    D = await r.json();
    render();
  } catch { toast('Could not reach Garden Planner — is the app running?'); }
}

function render() { renderLog(); renderTransplant(); renderSeeds(); }

function renderLog() {
  const ss = document.getElementById('s-seed');
  const sl = document.getElementById('s-loc');
  const prevS = ss.value, prevL = sl.value;

  ss.innerHTML = D.seeds.length
    ? D.seeds.map(s=>`<option value="${s.id}">${esc(s.displayName)} (${s.stock} in stock)</option>`).join('')
    : '<option value="">No seeds in catalogue</option>';
  if (prevS) ss.value = prevS;

  sl.innerHTML = '';
  if (D.beds.length) {
    const g = document.createElement('optgroup'); g.label='Garden Beds';
    D.beds.forEach(b=>{ const o=document.createElement('option'); o.value='bed:'+b.id; o.textContent=b.name; g.appendChild(o); });
    sl.appendChild(g);
  }
  const g2 = document.createElement('optgroup'); g2.label='Other';
  D.locations.forEach(l=>{ const o=document.createElement('option'); o.value='custom:'+l; o.textContent=l; g2.appendChild(o); });
  sl.appendChild(g2);
  if (prevL) sl.value = prevL;
}

function renderTransplant() {
  const el = document.getElementById('transplant-list');
  const pending = D.records.filter(r=>!r.transplanted);
  if (!pending.length) { el.innerHTML='<div class="empty">No plantings awaiting transplant</div>'; return; }
  el.innerHTML = pending.map(r=>`
    <div class="card row">
      <div class="row-info">
        <strong>${esc(r.seedName)}</strong>
        <span>${esc(r.dateSown)} &middot; ${esc(r.location)} &middot; qty ${r.quantity}</span>
      </div>
      <button class="btn2" onclick="doTransplant('${r.id}')">Transplant today</button>
    </div>`).join('');
}

function renderSeeds() {
  const el = document.getElementById('seeds-list');
  if (!D.seeds.length) { el.innerHTML='<div class="empty">No seeds in catalogue</div>'; return; }
  el.innerHTML = D.seeds.map(s=>{
    const cls = s.stock===0?'gone':s.stock<=5?'low':'';
    return `<div class="row">
      <span class="chip" style="background:${s.colorHex}"></span>
      <span style="flex:1;font-size:15px">${esc(s.displayName)}</span>
      <span class="badge ${cls}">${s.stock}</span>
    </div>`;
  }).join('');
}

document.getElementById('s-date').value = new Date().toISOString().slice(0,10);

document.getElementById('btn-log').addEventListener('click', async () => {
  const seedId = document.getElementById('s-seed').value;
  const locVal = document.getElementById('s-loc').value;
  const qty = parseInt(document.getElementById('s-qty').value)||1;
  const date = document.getElementById('s-date').value;
  if (!seedId||!locVal) { toast('Please select a seed and location'); return; }

  const body = {seedId, quantity:qty, dateSown:date};
  if (locVal.startsWith('bed:')) { body.locationType='bed'; body.bedId=locVal.slice(4); }
  else { body.locationType='custom'; body.customLocation=locVal.slice(7); }

  const btn = document.getElementById('btn-log');
  btn.disabled=true;
  try {
    const r = await fetch('/api/plant',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    const res = await r.json();
    if (res.ok) { toast('Planting logged ✓'); document.getElementById('s-qty').value=1; await load(); }
    else toast('Error: '+(res.error||'unknown'));
  } catch { toast('Failed to save'); }
  btn.disabled=false;
});

async function doTransplant(id) {
  try {
    const r = await fetch('/api/transplant',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({recordId:id,date:new Date().toISOString().slice(0,10)})});
    const res = await r.json();
    if (res.ok) { toast('Transplant recorded ✓'); await load(); }
    else toast('Error saving');
  } catch { toast('Failed to save'); }
}

function show(name, btn) {
  document.querySelectorAll('.panel').forEach(p=>p.classList.remove('on'));
  document.querySelectorAll('.tab').forEach(b=>b.classList.remove('on'));
  document.getElementById('p-'+name).classList.add('on');
  btn.classList.add('on');
}

let _tt;
function toast(msg) {
  const el=document.getElementById('toast');
  el.textContent=msg; el.classList.add('on');
  clearTimeout(_tt); _tt=setTimeout(()=>el.classList.remove('on'),2800);
}

function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

load();
</script>
</body>
</html>
"""#
}
