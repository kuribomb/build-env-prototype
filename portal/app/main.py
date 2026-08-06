"""ビルド依頼ポータル.

ユーザーがアプリのコミットとプラットフォームのバージョンを指定し、
Jenkins のビルドジョブを発火させる Web サーバー。

- コミット一覧 / バージョン一覧は GitLab API から取得してプルダウン表示する
- ビルド実行は Jenkins REST API (buildWithParameters) を CSRF crumb 付きで呼ぶ
"""

import os
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

GITLAB_URL = os.environ.get("GITLAB_URL", "http://gitlab:8929")
GITLAB_TOKEN = os.environ.get("GITLAB_TOKEN", "")
APP_PROJECT = os.environ.get("GITLAB_APP_PROJECT", "root/app-repo")
PLATFORM_PROJECT = os.environ.get("GITLAB_PLATFORM_PROJECT", "root/platform-repo")

JENKINS_URL = os.environ.get("JENKINS_URL", "http://jenkins:8080")
JENKINS_USER = os.environ.get("JENKINS_USER", "admin")
JENKINS_PASSWORD = os.environ.get("JENKINS_PASSWORD", "")
JENKINS_JOB = os.environ.get("JENKINS_JOB", "platform-build")

# 利用者のブラウザから見える各サービスのURL(画面上のリンクに使用)
PUBLIC_JENKINS_URL = os.environ.get("PUBLIC_JENKINS_URL", "http://localhost:8080")
PUBLIC_GITLAB_URL = os.environ.get("PUBLIC_GITLAB_URL", "http://localhost:8929")
PUBLIC_NAS_URL = os.environ.get("PUBLIC_NAS_URL", "http://localhost:8081")
PUBLIC_TEAMS_URL = os.environ.get("PUBLIC_TEAMS_URL", "http://localhost:8082")

app = FastAPI(title="ビルド依頼ポータル")
templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))


def _project_id(project: str) -> str:
    """GitLab API 用に "group/name" をURLエンコードする."""
    return project.replace("/", "%2F")


async def _gitlab_get(client: httpx.AsyncClient, path: str, params: dict | None = None):
    resp = await client.get(
        f"{GITLAB_URL}/api/v4{path}",
        params=params,
        headers={"PRIVATE-TOKEN": GITLAB_TOKEN},
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    commits: list[dict] = []
    tags: list[dict] = []
    gitlab_error = None
    try:
        async with httpx.AsyncClient() as client:
            commits = await _gitlab_get(
                client,
                f"/projects/{_project_id(APP_PROJECT)}/repository/commits",
                {"per_page": 20},
            )
            tags = await _gitlab_get(
                client, f"/projects/{_project_id(PLATFORM_PROJECT)}/repository/tags"
            )
    except Exception as exc:  # GitLab 停止中でも手入力でビルドできるようにする
        gitlab_error = f"GitLab からの一覧取得に失敗しました: {exc}"

    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "commits": commits,
            "tags": tags,
            "gitlab_error": gitlab_error,
            "app_project": APP_PROJECT,
            "platform_project": PLATFORM_PROJECT,
            "jenkins_url": PUBLIC_JENKINS_URL,
            "gitlab_url": PUBLIC_GITLAB_URL,
            "nas_url": PUBLIC_NAS_URL,
            "teams_url": PUBLIC_TEAMS_URL,
            "job_name": JENKINS_JOB,
        },
    )


class BuildRequest(BaseModel):
    app_commit: str
    platform_version: str


@app.post("/api/build")
async def trigger_build(req: BuildRequest):
    """Jenkins のビルドジョブをパラメータ付きで発火する."""
    if not req.app_commit or not req.platform_version:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "error": "コミットとバージョンを指定してください"},
        )

    async with httpx.AsyncClient(
        auth=(JENKINS_USER, JENKINS_PASSWORD), timeout=15
    ) as client:
        # CSRF crumb を取得(セッションクッキーは client が保持する)
        headers = {}
        crumb_resp = await client.get(f"{JENKINS_URL}/crumbIssuer/api/json")
        if crumb_resp.status_code == 200:
            crumb = crumb_resp.json()
            headers[crumb["crumbRequestField"]] = crumb["crumb"]

        resp = await client.post(
            f"{JENKINS_URL}/job/{JENKINS_JOB}/buildWithParameters",
            params={
                "APP_COMMIT": req.app_commit,
                "PLATFORM_VERSION": req.platform_version,
            },
            headers=headers,
        )

    if resp.status_code not in (200, 201):
        return JSONResponse(
            status_code=502,
            content={
                "ok": False,
                "error": f"Jenkins へのジョブ発火に失敗しました (HTTP {resp.status_code})",
            },
        )

    return {
        "ok": True,
        "message": f"ビルドジョブ {JENKINS_JOB} を発火しました",
        "job_url": f"{PUBLIC_JENKINS_URL}/job/{JENKINS_JOB}/",
    }


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}
