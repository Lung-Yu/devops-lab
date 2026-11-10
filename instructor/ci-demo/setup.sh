#!/bin/bash
# 把本機示範 GitLab 設好：token、專案、CI 變數（含 dev／qa／poc 環境變數）、Runner，再推四個版本觸發 pipeline
#   main（綠燈、自動部署 dev）→ tag v1.0.0（產生 Release、可放行到 poc）→ main 第二版（dev 第二筆部署，可 Rollback）
#   → feature/break-test（測試失敗＝紅燈）
# 先 docker compose up -d（見 README.md），GitLab 登入頁打得開再跑：bash setup.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
API=http://localhost:8929/api/v4
TOKEN="glpat-keypasco-demo-0000000000"   # 只給拋棄式示範環境用
PROJECT=keypasco-demo

echo "[1/5] root 的 API token"
docker compose -f "$HERE/docker-compose.yml" exec -T gitlab gitlab-rails runner "
  u = User.find_by_username('root')
  u.personal_access_tokens.where(name: 'demo').delete_all
  t = u.personal_access_tokens.build(name: 'demo', scopes: [:api, :write_repository], expires_at: 30.days.from_now, organization: u.namespace.organization)
  t.set_token('$TOKEN'); t.save!
" > /dev/null
H=(-s -H "PRIVATE-TOKEN: $TOKEN")
# 關掉版本檢查：不然 GitLab 會跳「Critical patch release」視窗擋住畫面（上課投影時很干擾）
curl "${H[@]}" -X PUT "$API/application/settings?version_check_enabled=false" > /dev/null

echo "[2/5] 專案 ${PROJECT}（已存在就沿用：GitLab 刪專案是延遲刪除，同名不能馬上重建）"
PID=$(curl "${H[@]}" "$API/projects/root%2F$PROJECT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
[ -n "$PID" ] || PID=$(curl "${H[@]}" -X POST "$API/projects" --data "name=$PROJECT&visibility=private&initialize_with_readme=false" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

echo "[3/5] CI 變數：一般／Masked／Masked＋Protected／Environment scope"
for k in DEPLOY_USER DEPLOY_PASSWORD PROD_DB_PASSWORD; do curl "${H[@]}" -X DELETE "$API/projects/$PID/variables/$k" > /dev/null; done
curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=DEPLOY_USER&value=deployer" > /dev/null
curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=DEPLOY_PASSWORD&value=Dep10y-Pa55w0rd&masked=true" > /dev/null
curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=PROD_DB_PASSWORD&value=Pr0d-Db-Secret-2026&masked=true&protected=true" > /dev/null
# 部署用：三個環境共用的（scope *）＋各環境不同的（Environment scope dev／qa／poc）——GitLab 版的 .env.dev／.env.qa／.env.poc
for v in $(curl "${H[@]}" "$API/projects/$PID/variables?per_page=100" | python3 -c 'import json,sys; [print(v["key"]+"|"+v["environment_scope"]) for v in json.load(sys.stdin) if v["key"] in ("DB_HOST","DB_USER","DB_PASSWORD","DB_NAME","ASPNETCORE_ENVIRONMENT")]'); do
  curl "${H[@]}" -X DELETE "$API/projects/$PID/variables/${v%%|*}?filter%5Benvironment_scope%5D=${v#*|}" > /dev/null
done
curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=DB_HOST&value=demo-db" > /dev/null
curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=DB_USER&value=labuser" > /dev/null
curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=DB_PASSWORD&value=labpass-demo&masked=true" > /dev/null
for e in "dev labdb Development" "qa labdb_qa QA" "poc labdb_poc POC"; do
  set -- $e
  curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=DB_NAME&value=$2&environment_scope=$1" > /dev/null
  curl "${H[@]}" -X POST "$API/projects/$PID/variables" --data "key=ASPNETCORE_ENVIRONMENT&value=$3&environment_scope=$1" > /dev/null
done

echo "[4/5] Runner（docker executor，接到 ci-demo 網路）：一般用＋部署用（tag deploy）"
for r in $(curl "${H[@]}" "$API/runners/all" | python3 -c 'import json,sys; [print(r["id"]) for r in json.load(sys.stdin)]'); do curl "${H[@]}" -X DELETE "$API/runners/$r" > /dev/null; done
RTOKEN=$(curl "${H[@]}" -X POST "$API/user/runners" --data "runner_type=instance_type&description=demo-runner&run_untagged=true" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
# 部署用 Runner：只接 tags: [deploy] 的 job，掛講師電腦的 Docker socket 當「部署機」
# （真實環境是裝在部署機上的 Runner；一般 Runner 不掛 socket，docker-build 才會用自己的 dind）
DTOKEN=$(curl "${H[@]}" -X POST "$API/user/runners" --data "runner_type=instance_type&description=deploy-runner&tag_list=deploy&run_untagged=false" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
docker compose -f "$HERE/docker-compose.yml" exec -T runner sh -c "rm -f /etc/gitlab-runner/config.toml; gitlab-runner register --non-interactive \
  --url http://gitlab:8929 --clone-url http://gitlab:8929 --token $RTOKEN --executor docker \
  --docker-image alpine:3.20 --docker-privileged --docker-network-mode ci-demo --docker-volumes /certs/client \
  --docker-pull-policy if-not-present && gitlab-runner register --non-interactive \
  --url http://gitlab:8929 --clone-url http://gitlab:8929 --token $DTOKEN --executor docker \
  --docker-image docker:27 --docker-network-mode ci-demo --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
  --docker-pull-policy if-not-present" > /dev/null
docker compose -f "$HERE/docker-compose.yml" restart runner > /dev/null

echo "[5/5] 推程式碼（先清掉舊的 pipeline 和 image tag，截圖只留這次的）"
for p in $(curl "${H[@]}" "$API/projects/$PID/pipelines?per_page=100" | python3 -c 'import json,sys; [print(p["id"]) for p in json.load(sys.stdin)]'); do curl "${H[@]}" -X DELETE "$API/projects/$PID/pipelines/$p" > /dev/null; done
for r in $(curl "${H[@]}" "$API/projects/$PID/registry/repositories" | python3 -c 'import json,sys; [print(r["id"]) for r in json.load(sys.stdin)]'); do
  for t in $(curl "${H[@]}" "$API/projects/$PID/registry/repositories/$r/tags?per_page=100" | python3 -c 'import json,sys; [print(t["name"]) for t in json.load(sys.stdin)]'); do
    curl "${H[@]}" -X DELETE "$API/projects/$PID/registry/repositories/$r/tags/$t" > /dev/null
  done
done
# 上一輪部署出來的東西也清掉：容器、Environments（要先 stop 才能刪）、Release
docker rm -f deploylog-dev deploylog-qa deploylog-poc > /dev/null 2>&1 || true
for e in $(curl "${H[@]}" "$API/projects/$PID/environments?per_page=100" | python3 -c 'import json,sys; [print(e["id"]) for e in json.load(sys.stdin)]'); do
  curl "${H[@]}" -X POST "$API/projects/$PID/environments/$e/stop?force=true" > /dev/null
  curl "${H[@]}" -X DELETE "$API/projects/$PID/environments/$e" > /dev/null
done
curl "${H[@]}" -X DELETE "$API/projects/$PID/releases/v1.0.0" > /dev/null
WORK="$(mktemp -d)"
# 程式碼跟學員 M3 練習用的同一份（labs/m3-ci-pipeline/sample-repo），再加上示範用的 .gitlab-ci.yml
cp -R "$HERE/../../labs/m3-ci-pipeline/sample-repo/." "$WORK/"
cp "$HERE/.gitlab-ci.yml" "$WORK/"
cd "$WORK"
git init -q -b main
git -c user.name=Tygrus -c user.email=demo@example.com add -A
git -c user.name=Tygrus -c user.email=demo@example.com commit -q -m "API 與 CI pipeline：build → test → package → docker"
REMOTE="http://root:$TOKEN@localhost:8929/root/$PROJECT.git"
# main 是 protected branch（不能 force push）：先解除、推完再保護回來——Protected 變數的示範要靠它
curl "${H[@]}" -X DELETE "$API/projects/$PID/protected_branches/main" > /dev/null
git push -q -f "$REMOTE" main
curl "${H[@]}" -X POST "$API/projects/$PID/protected_branches" --data "name=main&push_access_level=40&merge_access_level=40" > /dev/null
sleep 20
git push -q "$REMOTE" :refs/tags/v1.0.0 2> /dev/null || true
git tag v1.0.0 && git push -q "$REMOTE" v1.0.0
sleep 20
# main 再推一版：dev 會有兩筆部署紀錄，Environments 頁面才有東西可以 Rollback
printf '# 變更紀錄\n\n## 未發版\n- 部署紀錄列表加上環境欄位\n\n## v1.0.0\n- 第一版\n' > CHANGELOG.md
git -c user.name=Tygrus -c user.email=demo@example.com add CHANGELOG.md
git -c user.name=Tygrus -c user.email=demo@example.com commit -q -m "新增 CHANGELOG（示範：main 第二版，dev 自動部署、可以 Rollback 回上一版）"
curl "${H[@]}" -X DELETE "$API/projects/$PID/protected_branches/main" > /dev/null
git push -q "$REMOTE" main
curl "${H[@]}" -X POST "$API/projects/$PID/protected_branches" --data "name=main&push_access_level=40&merge_access_level=40" > /dev/null
sleep 20
git checkout -q -b feature/break-test
sed -i '' 's/Assert.Empty(RequiredSettings.Missing(config));/Assert.Equal(["DB_NAME"], RequiredSettings.Missing(config));  \/\/ 故意寫錯的預期值/' tests/Api.Tests/RequiredSettingsTests.cs
git -c user.name=Tygrus -c user.email=demo@example.com commit -q -am "改了測試的預期值（示範：測試沒過，後面的 stage 不會跑）"
git push -q -f "$REMOTE" feature/break-test
rm -rf "$WORK"
echo "完成：http://localhost:8929/root/$PROJECT/-/pipelines（瀏覽器要把 gitlab 指到 127.0.0.1，見 README.md）"
