<script setup>
import { ref, onMounted } from 'vue'
import { session, fmtTime } from '../api.js'

// 直接打 /health 與 /health/ready，顯示監控系統看到的同一份結果
const checks = ref([])
async function probe(path) {
  const started = performance.now()
  try {
    const res = await fetch(path)
    return { path, code: res.status, body: await res.text(), ms: Math.round(performance.now() - started) }
  } catch {
    return { path, code: 0, body: '連不上', ms: Math.round(performance.now() - started) }
  }
}
async function refresh() {
  checks.value = await Promise.all(['/health', '/health/ready', '/whoami'].map(probe))
}
onMounted(refresh)
</script>

<template>
  <section>
    <div class="page-head">
      <h1>系統狀態</h1>
      <button class="ghost" @click="refresh">重新檢查</button>
    </div>
    <dl class="facts" v-if="session.system">
      <dt>環境</dt><dd>{{ session.system.environment }}</dd>
      <dt>版本</dt><dd class="mono">{{ session.system.version }}</dd>
      <dt>啟動時間</dt><dd class="mono">{{ fmtTime(session.system.startedAt) }}</dd>
    </dl>
    <div class="checks">
      <div v-for="c in checks" :key="c.path" class="check" :data-ok="c.code === 200">
        <div class="check-head"><code>{{ c.path }}</code><b>{{ c.code || '—' }}</b></div>
        <pre>{{ c.body }}</pre>
        <small>{{ c.ms }} ms</small>
      </div>
    </div>
    <p class="hint"><code>/health</code> 只看資料庫連不連得上；<code>/health/ready</code> 另外檢查 Schema 是否已經 migrate 到最新版。</p>
  </section>
</template>
