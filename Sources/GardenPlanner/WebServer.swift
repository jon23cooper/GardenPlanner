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
        case ("POST", "/api/bed-data"):
            return apiBedData(body, appData)
        case ("POST", "/api/bed-plant"):
            return apiBedPlant(body, appData)
        case ("POST", "/api/bed-clear"):
            return apiBedClear(body, appData)
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

    // MARK: - POST /api/bed-data

    private func apiBedData(_ body: Data, _ appData: AppData) -> (Int, Data, String) {
        struct Req: Decodable { var bedId: String; var year: Int }
        struct CellOut: Encodable { var row, col: Int; var seedId: String?; var seedName: String?; var colorHex: String? }
        struct Out: Encodable { var rows, columns: Int; var cells: [CellOut] }
        guard let req = try? JSONDecoder().decode(Req.self, from: body),
              let bed = appData.gardenBeds.first(where: { $0.id.uuidString == req.bedId }) else {
            return (400, Data(#"{"error":"bed not found"}"#.utf8), "application/json")
        }
        var cells: [CellOut] = []
        for row in 0..<bed.rows {
            for col in 0..<bed.columns {
                let bedCell = bed.cells.first { $0.row == row && $0.column == col && $0.year == req.year }
                let seed = bedCell.flatMap { appData.seed(id: $0.seedId) }
                cells.append(CellOut(row: row, col: col, seedId: seed?.id.uuidString, seedName: seed?.displayName, colorHex: seed?.colorHex))
            }
        }
        let out = Out(rows: bed.rows, columns: bed.columns, cells: cells)
        return (200, (try? JSONEncoder().encode(out)) ?? Data(), "application/json")
    }

    // MARK: - POST /api/bed-plant

    private func apiBedPlant(_ body: Data, _ appData: AppData) -> (Int, Data, String) {
        struct Req: Decodable { var bedId, seedId: String; var row, col, year: Int }
        guard let req = try? JSONDecoder().decode(Req.self, from: body),
              let bedId = UUID(uuidString: req.bedId),
              let seedId = UUID(uuidString: req.seedId) else {
            return (400, Data(#"{"error":"invalid"}"#.utf8), "application/json")
        }
        appData.plantSeed(seedId, in: bedId, at: GridPosition(row: req.row, column: req.col), year: req.year)
        return (200, Data(#"{"ok":true}"#.utf8), "application/json")
    }

    // MARK: - POST /api/bed-clear

    private func apiBedClear(_ body: Data, _ appData: AppData) -> (Int, Data, String) {
        struct Req: Decodable { var bedId: String; var row, col, year: Int }
        guard let req = try? JSONDecoder().decode(Req.self, from: body),
              let bedId = UUID(uuidString: req.bedId) else {
            return (400, Data(#"{"error":"invalid"}"#.utf8), "application/json")
        }
        appData.clearCell(in: bedId, at: GridPosition(row: req.row, column: req.col), year: req.year)
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
#p-beds{padding:14px}
.empty{text-align:center;padding:40px 20px;color:var(--text2);font-size:15px}
.cell{width:52px;height:52px;border:1px solid var(--border);border-radius:6px;display:flex;flex-direction:column;align-items:center;justify-content:center;font-size:8px;text-align:center;padding:3px;cursor:pointer;flex-shrink:0;-webkit-tap-highlight-color:transparent}
.cell.planted{border-width:2px}
.cell:active{opacity:.7}
.grid-row{display:flex;gap:3px;margin-bottom:3px}
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

<div class="panel" id="p-beds">
  <div class="sec" style="padding:0 14px">Garden beds</div>
  <div class="card" style="margin:0 14px 10px">
    <label for="bed-sel">Bed</label>
    <select id="bed-sel" onchange="loadBed()"></select>
    <label for="bed-year">Year</label>
    <select id="bed-year" onchange="loadBed()"></select>
  </div>
  <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;padding:0 14px">
    <span style="font-size:12px;color:#999">Pinch or use buttons to zoom</span>
    <div style="display:flex;gap:6px">
      <button class="btn2" onclick="adjustZoom(-0.2)" style="padding:6px 14px;font-size:18px;line-height:1">−</button>
      <button class="btn2" onclick="adjustZoom(0)" style="padding:6px 10px;font-size:12px">Reset</button>
      <button class="btn2" onclick="adjustZoom(0.2)" style="padding:6px 14px;font-size:18px;line-height:1">+</button>
    </div>
  </div>
  <div id="bed-grid-wrap" style="overflow:auto;-webkit-overflow-scrolling:touch;padding:0 14px">
    <div id="bed-grid-inner" style="transform-origin:top left;display:inline-block"></div>
  </div>
</div>

<!-- Seed picker overlay for bed planting -->
<div id="picker-overlay" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:50;align-items:flex-end" onclick="if(event.target===this)closePicker()">
  <div style="background:#fff;border-radius:16px 16px 0 0;width:100%;max-height:70vh;overflow-y:auto;padding:16px">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
      <strong style="font-size:16px">Plant a seed</strong>
      <button onclick="closePicker()" style="background:none;border:none;font-size:22px;color:#666;cursor:pointer">×</button>
    </div>
    <div id="picker-list"></div>
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
  <button class="tab" onclick="show('beds',this);loadBed()">
    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 3h18v2H3zm0 4h18v2H3zm0 4h18v2H3zm0 4h18v2H3zm0 4h18v2H3z"/></svg>
    Beds
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

function render() { renderLog(); renderTransplant(); renderSeeds(); renderBedSelectors(); }

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

// ---- Beds ----

let bedData = null;
let pickerCell = null; // {bedId, row, col, year}

function renderBedSelectors() {
  const bs = document.getElementById('bed-sel');
  const prev = bs.value;
  bs.innerHTML = D.beds.length
    ? D.beds.map(b=>`<option value="${b.id}">${esc(b.name)}</option>`).join('')
    : '<option value="">No beds</option>';
  if (prev) bs.value = prev;

  const ys = document.getElementById('bed-year');
  const yr = new Date().getFullYear();
  const prevY = ys.value || String(yr);
  ys.innerHTML = [yr-1,yr,yr+1].map(y=>`<option value="${y}">${y}</option>`).join('');
  ys.value = prevY;
}

async function loadBed() {
  const bedId = document.getElementById('bed-sel').value;
  const year = parseInt(document.getElementById('bed-year').value);
  if (!bedId) return;
  try {
    const r = await fetch('/api/bed-data',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({bedId,year})});
    bedData = await r.json();
    bedData._bedId = bedId; bedData._year = year;
    renderBedGrid();
  } catch { toast('Could not load bed data'); }
}

function renderBedGrid() {
  const wrap = document.getElementById('bed-grid-inner');
  if (!bedData || bedData.rows === undefined) { wrap.innerHTML='<div class="empty">Select a bed above</div>'; return; }

  // Index cells by row,col
  const cellMap = {};
  (bedData.cells||[]).forEach(c=>{ cellMap[c.row+','+c.col]=c; });

  let html = '<div style="display:inline-block;min-width:100%">';
  // Column numbers
  html += '<div style="display:flex;gap:3px;margin-bottom:3px;padding-left:22px">';
  for(let c=0;c<bedData.columns;c++) html+=`<div style="width:52px;text-align:center;font-size:10px;color:#999">${c+1}</div>`;
  html += '</div>';
  for(let r=0;r<bedData.rows;r++){
    html+=`<div style="display:flex;align-items:center;gap:3px;margin-bottom:3px">`;
    html+=`<div style="width:18px;font-size:10px;color:#999;text-align:right;flex-shrink:0">${r+1}</div>`;
    for(let c=0;c<bedData.columns;c++){
      const cell = cellMap[r+','+c];
      if(cell && cell.seedName){
        const bg = cell.colorHex||'#4CAF50';
        html+=`<div class="cell planted" style="background:${bg}22;border-color:${bg}" onclick="tapPlanted('${bedData._bedId}',${r},${c},${bedData._year},'${esc(cell.seedName||'')}')">
          <span class="chip" style="background:${bg};width:8px;height:8px;border-radius:50%;display:block;margin-bottom:2px"></span>
          <span style="color:#333;line-height:1.1">${esc(cell.seedName)}</span>
        </div>`;
      } else {
        html+=`<div class="cell" style="background:#f8f8f8" onclick="tapEmpty('${bedData._bedId}',${r},${c},${bedData._year})">
          <span style="color:#ccc;font-size:18px">+</span>
        </div>`;
      }
    }
    html+='</div>';
  }
  html+='</div>';
  wrap.innerHTML = html;
}

function tapEmpty(bedId, row, col, year) {
  pickerCell = {bedId, row, col, year};
  const list = document.getElementById('picker-list');
  list.innerHTML = D.seeds.map(s=>`
    <div class="row" onclick="plantInBed('${s.id}')" style="cursor:pointer">
      <span class="chip" style="background:${s.colorHex}"></span>
      <span style="flex:1;font-size:15px">${esc(s.displayName)}</span>
      <span class="badge ${s.stock===0?'gone':s.stock<=5?'low':''}">${s.stock}</span>
    </div>`).join('');
  const ov = document.getElementById('picker-overlay');
  ov.style.display='flex';
}

function tapPlanted(bedId, row, col, year, seedName) {
  if(confirm('Clear '+seedName+' from this cell?')) clearBedCell(bedId, row, col, year);
}

function closePicker() {
  document.getElementById('picker-overlay').style.display='none';
  pickerCell=null;
}

async function plantInBed(seedId) {
  if(!pickerCell) return;
  const {bedId,row,col,year}=pickerCell;
  closePicker();
  try {
    const r = await fetch('/api/bed-plant',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({bedId,seedId,row,col,year})});
    const res = await r.json();
    if(res.ok){ toast('Planted ✓'); await load(); await loadBed(); }
    else toast('Error planting');
  } catch { toast('Failed to save'); }
}

async function clearBedCell(bedId, row, col, year) {
  try {
    const r = await fetch('/api/bed-clear',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({bedId,row,col,year})});
    const res = await r.json();
    if(res.ok){ toast('Cell cleared'); await loadBed(); }
    else toast('Error clearing');
  } catch { toast('Failed to save'); }
}

// ---- Bed grid zoom ----

let bedScale = 1.0;

function applyScale() {
  const inner = document.getElementById('bed-grid-inner');
  if (inner) {
    inner.style.transform = `scale(${bedScale})`;
    // Shrink wrapper height to match scaled content so page doesn't leave dead space
    const wrap = document.getElementById('bed-grid-wrap');
    if (wrap) wrap.style.height = (inner.scrollHeight * bedScale + 16) + 'px';
  }
}

function adjustZoom(delta) {
  if (delta === 0) { bedScale = 1.0; }
  else { bedScale = Math.min(3, Math.max(0.2, bedScale + delta)); }
  applyScale();
}

(function(){
  let startDist = 0, startScale = 1;
  function dist(t){ const dx=t[0].clientX-t[1].clientX,dy=t[0].clientY-t[1].clientY; return Math.sqrt(dx*dx+dy*dy); }
  const inGrid = e => { const w=document.getElementById('bed-grid-wrap'); return w&&w.contains(e.target); };
  window.addEventListener('resize', () => { if (bedData) { renderBedGrid(); applyScale(); } });

  document.addEventListener('touchstart', e=>{
    if(!inGrid(e)||e.touches.length!==2) return;
    startDist=dist(e.touches); startScale=bedScale; e.preventDefault();
  },{passive:false});
  document.addEventListener('touchmove', e=>{
    if(!inGrid(e)||e.touches.length!==2) return;
    e.preventDefault();
    bedScale=Math.min(3,Math.max(0.2,startScale*dist(e.touches)/startDist));
    applyScale();
  },{passive:false});
})();

load();
</script>
</body>
</html>
"""#
}
