"""Teams 通知モックサーバー.

本番では、ビルド結果の通知は Microsoft Teams(Power Automate の
Incoming Webhook)へ Adaptive Card 形式の JSON を POST して行う。
本プロトタイプでは代わりに本サーバーが同じ形式の POST を受信し、
Teams 風のカードとしてブラウザに表示する。

本番移行時は、Jenkins 側の環境変数 TEAMS_WEBHOOK_URL を
実際の Teams の Webhook URL に差し替えるだけでよい(通知側の変更は不要)。
"""

from datetime import datetime, timedelta, timezone

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse

JST = timezone(timedelta(hours=9))
MAX_NOTIFICATIONS = 100

app = FastAPI(title="Teams通知モック")

# 受信した通知(新しい順)。プロトタイプのためメモリ保持とする
notifications: list[dict] = []


@app.post("/webhook")
async def receive_webhook(request: Request):
    """Teams Incoming Webhook 互換の受信口."""
    try:
        payload = await request.json()
    except Exception:
        payload = {"raw": (await request.body()).decode("utf-8", errors="replace")}

    notifications.insert(
        0,
        {
            "received_at": datetime.now(JST).strftime("%Y-%m-%d %H:%M:%S"),
            "payload": payload,
        },
    )
    del notifications[MAX_NOTIFICATIONS:]
    return {"status": "ok"}


@app.get("/api/notifications")
async def list_notifications():
    return notifications


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


PAGE = """<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Teams通知モック</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: "Segoe UI", "Hiragino Sans", "Meiryo", sans-serif;
         margin: 0; background: #f0f0f0; color: #242424; }
  header { background: #464775; color: #fff; padding: 14px 24px; }
  header h1 { margin: 0; font-size: 18px; }
  header .sub { color: #c7c7e0; font-size: 12px; }
  main { max-width: 720px; margin: 20px auto; padding: 0 16px; }
  .empty { text-align: center; color: #616161; margin-top: 60px; font-size: 14px; }
  .msg { display: flex; gap: 10px; margin-bottom: 18px; }
  .avatar { width: 36px; height: 36px; border-radius: 50%; background: #464775;
            color: #fff; display: flex; align-items: center; justify-content: center;
            font-weight: bold; flex-shrink: 0; }
  .bubble { background: #fff; border-radius: 6px; padding: 12px 16px;
            box-shadow: 0 1px 2px rgba(0,0,0,.15); flex-grow: 1; }
  .meta { font-size: 12px; color: #616161; margin-bottom: 6px; }
  .card-title { font-weight: 600; font-size: 15px; margin: 4px 0 10px; }
  table.facts { border-collapse: collapse; font-size: 13px; }
  table.facts td { padding: 2px 14px 2px 0; vertical-align: top; }
  table.facts td.k { color: #616161; white-space: nowrap; }
  .actions { margin-top: 12px; }
  .actions a { display: inline-block; border: 1px solid #d1d1d1; border-radius: 4px;
               padding: 6px 14px; margin-right: 8px; text-decoration: none;
               color: #5b5fc7; font-size: 13px; font-weight: 600; }
  .actions a:hover { background: #f5f5ff; }
  pre.raw { background: #f5f5f5; border-radius: 4px; padding: 8px;
            font-size: 12px; overflow-x: auto; }
</style>
</head>
<body>
<header>
  <h1>Teams通知モック — ビルド通知チャネル</h1>
  <div class="sub">本番では Microsoft Teams に届く通知を、ここで代わりに受信・表示しています(自動更新)</div>
</header>
<main id="list"><div class="empty">まだ通知はありません。ビルドを実行すると、ここに通知カードが届きます。</div></main>
<script>
function esc(s) {
  return String(s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}

function renderCard(content) {
  var html = "";
  (content.body || []).forEach(function (block) {
    if (block.type === "TextBlock") {
      html += '<div class="card-title">' + esc(block.text || "") + "</div>";
    } else if (block.type === "FactSet") {
      html += '<table class="facts">';
      (block.facts || []).forEach(function (f) {
        html += '<tr><td class="k">' + esc(f.title || "") + "</td><td>" +
                esc(f.value || "") + "</td></tr>";
      });
      html += "</table>";
    }
  });
  var actions = (content.actions || []).filter(function (a) { return a.type === "Action.OpenUrl"; });
  if (actions.length) {
    html += '<div class="actions">';
    actions.forEach(function (a) {
      html += '<a href="' + esc(a.url || "#") + '" target="_blank">' + esc(a.title || "開く") + "</a>";
    });
    html += "</div>";
  }
  return html;
}

function renderNotification(n) {
  var inner = "";
  var payload = n.payload || {};
  var attachments = payload.attachments || [];
  if (attachments.length && attachments[0].content) {
    inner = renderCard(attachments[0].content);
  } else if (payload.text) {
    // 旧形式(MessageCard / シンプルテキスト)へのフォールバック
    inner = '<div class="card-title">' + esc(payload.text) + "</div>";
  } else {
    inner = '<pre class="raw">' + esc(JSON.stringify(payload, null, 2)) + "</pre>";
  }
  return '<div class="msg"><div class="avatar">CI</div><div class="bubble">' +
         '<div class="meta">ビルド通知Bot ・ ' + esc(n.received_at) + "</div>" +
         inner + "</div></div>";
}

async function refresh() {
  try {
    var resp = await fetch("/api/notifications");
    var items = await resp.json();
    var list = document.getElementById("list");
    if (!items.length) return;
    list.innerHTML = items.map(renderNotification).join("");
  } catch (e) { /* 次回のポーリングで再試行 */ }
}

refresh();
setInterval(refresh, 3000);
</script>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
async def index():
    return PAGE
