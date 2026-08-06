// =====================================================================
// ビルドジョブ定義 (Job DSL)
//
// JCasC (casc/jenkins.yaml の jobs: セクション) から読み込まれ、
// Jenkins 起動時にジョブ「platform-build」を自動作成する。
// ジョブの中身 (Pipeline) もこのファイル内に定義しており、
// ジョブ設定の一切を手作業なしのコード管理とする。
// =====================================================================
pipelineJob('platform-build') {
    displayName('プラットフォームビルド')
    description('''アプリのコミットとプラットフォームのバージョン(タグ)を指定してビルドする。
通常はビルド依頼ポータル(portal)から発火される。
成果物はNASへ保管され、結果はTeams(モック)へ通知される。''')

    parameters {
        stringParam('APP_COMMIT', 'main', 'アプリリポジトリのコミットSHA(またはブランチ名)')
        stringParam('PLATFORM_VERSION', 'v1.0.0', 'プラットフォームのバージョン(gitタグ)')
    }

    definition {
        cps {
            sandbox(true)
            script('''
// ビルド結果を Teams(モック)へ Adaptive Card 形式で通知する。
// 本番移行時は TEAMS_WEBHOOK_URL を実際の Teams(Power Automate)の
// Webhook URL に差し替えるだけで、この通知処理はそのまま使える。
def notifyTeams(boolean success) {
    def statusText = success ? "成功" : "失敗"
    def icon = success ? "✅" : "❌"

    def actionList = [
        [type: "Action.OpenUrl", title: "ビルドログ (Jenkins)", url: env.BUILD_URL]
    ]
    if (success && env.ARTIFACT_URL) {
        actionList = [
            [type: "Action.OpenUrl", title: "成果物を開く (NAS)", url: env.ARTIFACT_URL],
            [type: "Action.OpenUrl", title: "ビルドログ (Jenkins)", url: env.BUILD_URL]
        ]
    }

    def card = [
        type: "message",
        attachments: [[
            contentType: "application/vnd.microsoft.card.adaptive",
            content: [
                '$schema': "http://adaptivecards.io/schemas/adaptive-card.json",
                type: "AdaptiveCard",
                version: "1.4",
                body: [
                    [type: "TextBlock", size: "Medium", weight: "Bolder",
                     text: icon + " ビルド" + statusText + ": " + env.JOB_NAME + " #" + env.BUILD_NUMBER],
                    [type: "FactSet", facts: [
                        [title: "アプリコミット", value: (env.APP_SHA ?: params.APP_COMMIT)],
                        [title: "プラットフォーム", value: params.PLATFORM_VERSION],
                        [title: "結果", value: statusText],
                        [title: "成果物", value: (env.ARTIFACT_URL ?: "なし")]
                    ]]
                ],
                actions: actionList
            ]
        ]]
    ]

    writeFile file: 'teams_payload.json', text: groovy.json.JsonOutput.toJson(card)
    sh 'curl -fsS -X POST -H "Content-Type: application/json" --data @teams_payload.json "$TEAMS_WEBHOOK_URL"'
}

pipeline {
    agent { label 'linux-build' }

    stages {
        stage('アプリ取得(指定コミット)') {
            steps {
                dir('app') {
                    checkout([$class: 'GitSCM',
                        branches: [[name: params.APP_COMMIT]],
                        userRemoteConfigs: [[url: env.APP_REPO_URL, credentialsId: 'gitlab-pat']]])
                }
                script {
                    env.APP_SHA = sh(script: 'git -C app rev-parse --short HEAD', returnStdout: true).trim()
                }
            }
        }

        stage('プラットフォーム取得(指定バージョン)') {
            steps {
                dir('platform') {
                    checkout([$class: 'GitSCM',
                        branches: [[name: 'refs/tags/' + params.PLATFORM_VERSION]],
                        userRemoteConfigs: [[url: env.PLATFORM_REPO_URL, credentialsId: 'gitlab-pat']]])
                }
            }
        }

        stage('ビルド(ビルドバッチ実行)') {
            steps {
                sh 'chmod +x app/build.sh && app/build.sh platform out'
            }
        }

        stage('成果物をNASへ保管') {
            steps {
                script {
                    env.NAS_SUBDIR = "builds/" + env.JOB_NAME + "/" +
                        env.BUILD_NUMBER + "_" + env.APP_SHA + "_" + params.PLATFORM_VERSION
                    env.ARTIFACT_URL = env.PUBLIC_NAS_URL + "/" + env.NAS_SUBDIR + "/"
                }
                sh 'mkdir -p "$NAS_DIR/$NAS_SUBDIR" && cp -r out/. "$NAS_DIR/$NAS_SUBDIR/"'
            }
        }
    }

    post {
        success {
            script { notifyTeams(true) }
        }
        failure {
            script { notifyTeams(false) }
        }
    }
}
''')
        }
    }
}
