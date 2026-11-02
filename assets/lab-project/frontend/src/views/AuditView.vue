<script setup>
import { ref, onMounted } from 'vue'
import { api, fmtTime } from '../api.js'
import ErrorBox from './ErrorBox.vue'

const rows = ref([])
const error = ref(null)
onMounted(async () => {
  try {
    rows.value = await api('/api/audit')
  } catch (e) {
    error.value = e
  }
})
</script>

<template>
  <section>
    <h1>稽核紀錄 <small>最近 100 筆</small></h1>
    <ErrorBox :error="error" />
    <table v-if="rows.length">
      <thead><tr><th>時間</th><th>使用者</th><th>動作</th><th>對象</th><th>追蹤編號</th></tr></thead>
      <tbody>
        <tr v-for="r in rows" :key="r.id" :class="{ warn: r.action === 'login.failed' }">
          <td class="mono">{{ fmtTime(r.at) }}</td>
          <td>{{ r.userName }}</td>
          <td class="mono">{{ r.action }}</td>
          <td>{{ r.target }}</td>
          <td class="mono trace">{{ r.traceId }}</td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
