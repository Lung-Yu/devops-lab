<script setup>
import { ref, watch, onMounted } from 'vue'
import { api, can, statusLabel, fmtTime } from '../api.js'
import ErrorBox from './ErrorBox.vue'

const rows = ref([])
const filter = ref({ environment: '', status: '' })
const error = ref(null)
const editing = ref(null)   // null = 沒在編輯；{} = 新增；{id,...} = 修改
const formError = ref(null)
const environments = ['Dev', 'QA', 'POC', 'Production']

async function load() {
  error.value = null
  const q = new URLSearchParams(Object.entries(filter.value).filter(([, v]) => v))
  try {
    rows.value = await api(`/api/deployments?${q}`)
  } catch (e) {
    error.value = e
  }
}
onMounted(load)
watch(filter, load, { deep: true })

function toLocalInput(iso) {
  const d = iso ? new Date(iso) : new Date()
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16)
}
function openNew() {
  formError.value = null
  editing.value = { customer: '', environment: 'POC', version: '', status: 'Planned', note: '', deployedAt: toLocalInput() }
}
function openEdit(r) {
  formError.value = null
  editing.value = { ...r, deployedAt: toLocalInput(r.deployedAt) }
}
async function save() {
  formError.value = null
  const body = { ...editing.value, deployedAt: new Date(editing.value.deployedAt).toISOString() }
  try {
    if (body.id) await api(`/api/deployments/${body.id}`, { method: 'PUT', body })
    else await api('/api/deployments', { method: 'POST', body })
    editing.value = null
    await load()
  } catch (e) {
    formError.value = e
  }
}
async function remove(r) {
  if (!confirm(`確定刪除 #${r.id} ${r.customer} ${r.version}？`)) return
  try {
    await api(`/api/deployments/${r.id}`, { method: 'DELETE' })
    await load()
  } catch (e) {
    error.value = e
  }
}
</script>

<template>
  <section>
    <div class="page-head">
      <h1>部署紀錄</h1>
      <button v-if="can.edit()" @click="openNew">＋ 登錄部署</button>
    </div>
    <div class="filters">
      <select v-model="filter.environment">
        <option value="">全部環境</option>
        <option v-for="e in environments" :key="e">{{ e }}</option>
      </select>
      <select v-model="filter.status">
        <option value="">全部狀態</option>
        <option v-for="(label, s) in statusLabel" :key="s" :value="s">{{ label }}</option>
      </select>
      <span class="count">{{ rows.length }} 筆</span>
    </div>
    <ErrorBox :error="error" />
    <table v-if="rows.length">
      <thead>
        <tr><th>時間</th><th>客戶</th><th>環境</th><th>版本</th><th>狀態</th><th>備註</th><th>登錄者</th><th v-if="can.edit()"></th></tr>
      </thead>
      <tbody>
        <tr v-for="r in rows" :key="r.id">
          <td class="mono">{{ fmtTime(r.deployedAt) }}</td>
          <td>{{ r.customer }}</td>
          <td><span class="tag">{{ r.environment }}</span></td>
          <td class="mono">{{ r.version }}</td>
          <td><span class="status" :data-status="r.status">{{ statusLabel[r.status] }}</span></td>
          <td class="note">{{ r.note }}</td>
          <td>{{ r.createdBy }}</td>
          <td v-if="can.edit()" class="actions">
            <button class="ghost" @click="openEdit(r)">修改</button>
            <button v-if="can.admin()" class="ghost danger" @click="remove(r)">刪除</button>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else-if="!error" class="empty">沒有符合條件的紀錄</p>

    <div v-if="editing" class="dialog-backdrop" @click.self="editing = null">
      <form class="dialog" @submit.prevent="save">
        <h2>{{ editing.id ? `修改 #${editing.id}` : '登錄部署' }}</h2>
        <label>客戶<input v-model="editing.customer" maxlength="100" required /></label>
        <div class="row">
          <label>環境
            <select v-model="editing.environment"><option v-for="e in environments" :key="e">{{ e }}</option></select>
          </label>
          <label>版本<input v-model="editing.version" maxlength="30" required placeholder="2.4.0" /></label>
        </div>
        <div class="row">
          <label>狀態
            <select v-model="editing.status"><option v-for="(label, s) in statusLabel" :key="s" :value="s">{{ label }}</option></select>
          </label>
          <label>部署時間<input v-model="editing.deployedAt" type="datetime-local" required /></label>
        </div>
        <label>備註<textarea v-model="editing.note" maxlength="500" rows="3" /></label>
        <ErrorBox :error="formError" />
        <div class="dialog-actions">
          <button type="button" class="ghost" @click="editing = null">取消</button>
          <button>儲存</button>
        </div>
      </form>
    </div>
  </section>
</template>
